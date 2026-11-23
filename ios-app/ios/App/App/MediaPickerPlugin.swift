import Foundation
import UIKit
import Capacitor
import PhotosUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// 사진·영상 고르기와 준비를 iPhone 기능으로(웹보다 빠르고 안정적)
//  · pick: iPhone 사진 선택창(여러 장, 고른 순서대로) → 사진은 1080px 본문 + 480px 썸네일 + 3024px 편집용(JPEG), 영상은 원본 복사 + 대표 이미지
//  · libExport(앱 안 사진첩): 사진은 3024px 로만 요청, 영상은 원본을 복사 없이 그대로, iCloud 면 진행률(libProgress) 알림
//    (사진첩 전체 접근 권한을 묻지 않음 — 사용자가 고른 것만 받음)
//  · exportVideo: 영상의 고른 구간만 잘라 720p MP4 로(파일이 9MB 를 넘으면 540p 로 한 번 더)
//  결과 파일은 앱 임시 폴더에 쓰고, 경로를 웹에 돌려줌 → 웹이 읽어서 Supabase 에 올림
@objc(MediaPickerPlugin)
public class MediaPickerPlugin: CAPPlugin, CAPBridgedPlugin, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public let identifier = "MediaPickerPlugin"
    public let jsName = "MediaPicker"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "pick", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "exportVideo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveToPhotos", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "camera", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "libAuth", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "libList", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "libAlbums", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "libThumbs", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "libExport", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "libManage", returnType: CAPPluginReturnPromise)
    ]
    private var pending: CAPPluginCall?
    private var camCall: CAPPluginCall?

    private let dir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("candid-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private func newFile(_ ext: String) -> URL { dir.appendingPathComponent(UUID().uuidString + "." + ext) }

    // ---------- 고르기 ----------
    @objc func pick(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.cleanOld() // 지난번 임시 파일 정리(1시간 지난 것만 — 지금 올리는 중인 파일은 그대로)
            self.pending?.reject("replaced", "replaced") // 앞 호출이 남아 있으면 끝내 줌(웹이 영원히 기다리지 않게)
            var cfg = PHPickerConfiguration()
            cfg.selectionLimit = max(1, min(10, call.getInt("max") ?? 10))
            cfg.filter = .any(of: [.images, .videos])
            if #available(iOS 15.0, *) { cfg.selection = .ordered }
            cfg.preferredAssetRepresentationMode = .current
            let vc = PHPickerViewController(configuration: cfg)
            vc.delegate = self
            self.pending = call
            self.bridge?.viewController?.present(vc, animated: true)
        }
    }

    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let call = pending else { return }
        pending = nil
        if results.isEmpty { call.reject("canceled", "canceled"); return }

        let group = DispatchGroup(), lock = NSLock()
        var out = [Int: [String: Any]]()
        let put = { (i: Int, v: [String: Any]) in lock.lock(); out[i] = v; lock.unlock() }

        for (i, r) in results.enumerated() {
            let p = r.itemProvider
            if p.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                group.enter()
                p.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                    defer { group.leave() }
                    guard let url = url else { return }
                    let dst = self.newFile(url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased())
                    do { try FileManager.default.copyItem(at: url, to: dst) } catch { return }
                    if let v = self.videoInfo(dst) { put(i, v) }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                // 파일에서 3024px 로 바로 줄여 읽기(4800만 화소 원본 전체를 풀지 않음). 안 되면 예전처럼 통째로
                p.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                    if let url = url, let img = Self.downsample(url, maxSide: 3024), let v = self.imageItem(img) { put(i, v); group.leave(); return }
                    guard p.canLoadObject(ofClass: UIImage.self) else { group.leave(); return }
                    p.loadObject(ofClass: UIImage.self) { obj, _ in
                        defer { group.leave() }
                        if let img = obj as? UIImage, let v = self.imageItem(img) { put(i, v) }
                    }
                }
            }
        }
        group.notify(queue: .main) {
            let items = (0..<results.count).compactMap { out[$0] }
            call.resolve(["items": items, "skipped": results.count - items.count])
        }
    }

    private func videoInfo(_ url: URL) -> [String: Any]? {
        let asset = AVURLAsset(url: url)
        let dur = CMTimeGetSeconds(asset.duration)
        guard dur.isFinite, dur > 0 else { return nil }
        var w = 0, h = 0
        if let track = asset.tracks(withMediaType: .video).first {
            let s = track.naturalSize.applying(track.preferredTransform)
            w = Int(abs(s.width)); h = Int(abs(s.height))
        }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480) // 영상 썸네일도 격자용 크기(480px)
        var thumbPath = ""
        if let cg = try? gen.copyCGImage(at: CMTime(seconds: min(0.15, dur / 2), preferredTimescale: 600), actualTime: nil),
           let tp = saveJPEG(UIImage(cgImage: cg), 0.6) { thumbPath = tp }
        return ["kind": "video", "path": url.path, "thumbPath": thumbPath, "duration": dur, "width": w, "height": h]
    }

    // ---------- 영상 자르기·줄이기 ----------
    // 구간만 잘라 720p·약 2.5Mbps H.264 + AAC 로 다시 만듦(10초 ≈ 3MB). 9MB 를 넘으면 540p·1.5Mbps 로 한 번 더
    @objc func exportVideo(_ call: CAPPluginCall) {
        guard let path = call.getString("path") else { call.reject("bad_args"); return }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let dur = CMTimeGetSeconds(asset.duration)
        let start = max(0, call.getDouble("start") ?? 0)
        let end = min(dur, call.getDouble("end") ?? dur, start + 10)
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                end: CMTime(seconds: max(end, start + 0.5), preferredTimescale: 600))
        let out1 = newFile("mp4")
        transcode(asset, range, to: out1) { ok in
            let size = (try? FileManager.default.attributesOfItem(atPath: out1.path)[.size] as? Int) ?? 0
            if ok && size <= 9 * 1024 * 1024 { call.resolve(["path": out1.path]); return }
            try? FileManager.default.removeItem(at: out1) // 너무 커서 안 쓰는 첫 결과
            let out2 = self.newFile("mp4")
            self.transcode(asset, range, to: out2, maxSide: 960, bitrate: 1_500_000) { ok2 in
                ok2 ? call.resolve(["path": out2.path]) : call.reject("export_failed")
            }
        }
    }

    private func transcode(_ asset: AVAsset, _ range: CMTimeRange, to out: URL, maxSide: CGFloat = 1280, bitrate: Int = 2_500_000, done: @escaping (Bool) -> Void) {
        guard let vtrack = asset.tracks(withMediaType: .video).first else { done(false); return }
        let atrack = asset.tracks(withMediaType: .audio).first
        do {
            let reader = try AVAssetReader(asset: asset); reader.timeRange = range
            let writer = try AVAssetWriter(outputURL: out, fileType: .mp4); writer.shouldOptimizeForNetworkUse = true
            let nat = vtrack.naturalSize, k = min(1, maxSide / max(nat.width, nat.height))
            let w = Int(nat.width * k / 2) * 2, h = Int(nat.height * k / 2) * 2
            let vOut = AVAssetReaderTrackOutput(track: vtrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
            vOut.alwaysCopiesSampleData = false; reader.add(vOut)
            let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: 60]])
            vIn.transform = vtrack.preferredTransform; vIn.expectsMediaDataInRealTime = false; writer.add(vIn)
            var aPair: (AVAssetWriterInput, AVAssetReaderTrackOutput)?
            if let at = atrack {
                var ch = 2, rate = 44100.0
                if let fd = at.formatDescriptions.first, let d = CMAudioFormatDescriptionGetStreamBasicDescription(fd as! CMAudioFormatDescription)?.pointee {
                    ch = max(1, min(2, Int(d.mChannelsPerFrame))); rate = d.mSampleRate > 0 ? min(48000, d.mSampleRate) : 44100
                }
                let o = AVAssetReaderTrackOutput(track: at, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVNumberOfChannelsKey: ch, AVSampleRateKey: rate])
                reader.add(o)
                let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: ch, AVSampleRateKey: rate, AVEncoderBitRateKey: 128_000])
                i.expectsMediaDataInRealTime = false; writer.add(i); aPair = (i, o)
            }
            guard reader.startReading(), writer.startWriting() else { done(false); return }
            writer.startSession(atSourceTime: range.start)
            let g = DispatchGroup()
            func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderTrackOutput, _ q: DispatchQueue) {
                g.enter(); var finished = false
                input.requestMediaDataWhenReady(on: q) {
                    while input.isReadyForMoreMediaData && !finished {
                        if let b = output.copyNextSampleBuffer() { if !input.append(b) { finished = true; input.markAsFinished(); g.leave() } }
                        else { finished = true; input.markAsFinished(); g.leave() }
                    }
                }
            }
            pump(vIn, vOut, DispatchQueue(label: "candid.v"))
            if let (ai, ao) = aPair { pump(ai, ao, DispatchQueue(label: "candid.a")) }
            g.notify(queue: .global()) {
                if reader.status == .failed { writer.cancelWriting(); done(false); return }
                writer.finishWriting { done(writer.status == .completed) }
            }
        } catch { done(false) }
    }

    // ---------- 사진첩에 저장 ----------
    // 웹이 base64(사진·영상)로 넘기면 임시 파일로 쓰고 사진첩에 추가(추가 전용 권한만 물음)
    @objc func saveToPhotos(_ call: CAPPluginCall) {
        guard let b64 = call.getString("data"), let data = Data(base64Encoded: b64) else { call.reject("bad_args"); return }
        let isVideo = (call.getString("type") ?? "").hasPrefix("video")
        let url = newFile(isVideo ? "mp4" : "jpg")
        do { try data.write(to: url) } catch { call.reject("write_failed"); return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { st in
            guard st == .authorized || st == .limited else { call.reject("denied", "denied"); return }
            PHPhotoLibrary.shared().performChanges({
                if isVideo { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
                else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
            }) { ok, err in try? FileManager.default.removeItem(at: url); ok ? call.resolve() : call.reject(err?.localizedDescription ?? "save_failed") }
        }
    }

    // ---------- 카메라로 바로 찍기 ----------
    // 사진 또는 영상(최대 10초)을 찍으면 고르기와 같은 모양(items)으로 돌려줌
    @objc func camera(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else { call.reject("no_camera", "no_camera"); return }
            self.camCall?.reject("replaced", "replaced")
            let vc = UIImagePickerController()
            vc.sourceType = .camera
            vc.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            vc.videoMaximumDuration = 10
            vc.videoQuality = .typeHigh
            vc.delegate = self
            self.camCall = call
            self.bridge?.viewController?.present(vc, animated: true)
        }
    }
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        camCall?.reject("canceled", "canceled"); camCall = nil
    }
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let call = camCall else { return }
        camCall = nil
        DispatchQueue.global(qos: .userInitiated).async {
            if let url = info[.mediaURL] as? URL {
                let dst = self.newFile(url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased())
                try? FileManager.default.copyItem(at: url, to: dst)
                if let v = self.videoInfo(dst) { call.resolve(["items": [v], "skipped": 0]) } else { call.reject("video_failed") }
            } else if let img = info[.originalImage] as? UIImage {
                let main = Self.resize(img, maxSide: 1080), thumb = Self.resize(main, maxSide: 480)
                let edit = Self.resize(img, maxSide: 3024)
                guard let mp = self.saveJPEG(main, 0.82), let tp = self.saveJPEG(thumb, 0.6), let ep = self.saveJPEG(edit, 0.9) else { call.reject("image_failed"); return }
                call.resolve(["items": [["kind": "image", "path": mp, "thumbPath": tp, "editPath": ep, "width": Int(main.size.width), "height": Int(main.size.height)]], "skipped": 0])
            } else { call.reject("no_media") }
        }
    }

    // ---------- 앱 안 사진첩(아래에서 올라오는 시트) ----------
    //  · libAuth: 권한 상태(request: true 면 물어봄) → authorized | limited | denied | notDetermined
    //  · libList: 사진·영상 전체(최신순) id·찍은 시각(초)·영상 길이
    //  · libThumbs: 보이는 칸의 작은 사진을 캐시 폴더에 jpg 로 → 경로
    //  · libExport: 고른 것들을 pick 과 같은 모양(items)으로 준비(iCloud 에만 있으면 받아 옴)
    //  · libManage: '선택한 사진만 허용'일 때 허용 사진 고치기
    private var fetch: PHFetchResult<PHAsset>?
    private var byId: [String: PHAsset] = [:]
    private let imgr = PHCachingImageManager()
    private lazy var thumbDir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("lib-thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private func authName(_ s: PHAuthorizationStatus) -> String {
        switch s { case .authorized: return "authorized"; case .limited: return "limited"; case .notDetermined: return "notDetermined"; default: return "denied" }
    }
    @objc func libAuth(_ call: CAPPluginCall) {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if s == .notDetermined && (call.getBool("request") ?? false) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { ns in call.resolve(["status": self.authName(ns)]) }
        } else { call.resolve(["status": authName(s)]) }
    }
    @objc func libList(_ call: CAPPluginCall) {
        DispatchQueue.global(qos: .utility).async { self.cleanOld(self.thumbDir, maxAge: 14 * 86400) }
        let albumId = call.getString("albumId")
        let albumSub = call.getInt("albumSubtype")
        DispatchQueue.global(qos: .userInitiated).async {
            let albumOpts = PHFetchOptions()
            albumOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let allOpts = PHFetchOptions()
            allOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            allOpts.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            var albums: [PHAssetCollection] = []
            if let raw = albumSub, let sub = PHAssetCollectionSubtype(rawValue: raw),
               let c = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: sub, options: nil).firstObject {
                albums.append(c)
            }
            if let aid = albumId, !aid.isEmpty,
               let c = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [aid], options: nil).firstObject,
               !albums.contains(where: { $0.localIdentifier == c.localIdentifier }) {
                albums.append(c)
            }
            var picked: PHFetchResult<PHAsset>? = nil
            for c in albums { // 앨범은 mediaType 필터 없이(비디오 앨범이 비지 않게) 먼저 시도
                let q = PHAsset.fetchAssets(in: c, options: albumOpts)
                if q.count > 0 { picked = q; break }
            }
            let r = picked ?? PHAsset.fetchAssets(with: allOpts)
            var ids = [String](), ts = [Int](), dur = [Double](), map = [String: PHAsset]()
            ids.reserveCapacity(r.count); ts.reserveCapacity(r.count); dur.reserveCapacity(r.count)
            r.enumerateObjects { a, _, _ in
                ids.append(a.localIdentifier); ts.append(Int(a.creationDate?.timeIntervalSince1970 ?? 0))
                dur.append(a.mediaType == .video ? (a.duration * 10).rounded() / 10 : 0); map[a.localIdentifier] = a
            }
            DispatchQueue.main.async { self.fetch = r; self.byId = map; call.resolve(["ids": ids, "ts": ts, "dur": dur]) }
        }
    }
    @objc func libAlbums(_ call: CAPPluginCall) {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard s == .authorized || s == .limited else { call.resolve(["albums": []]); return }
        DispatchQueue.global(qos: .userInitiated).async {
            // 사진 앱의 '모음'(스마트 앨범): 즐겨찾기·비디오·셀피·라이브 포토 등
            let rank: [PHAssetCollectionSubtype: Int] = [
                .smartAlbumFavorites: 0, .smartAlbumVideos: 1, .smartAlbumSelfPortraits: 2,
                .smartAlbumLivePhotos: 3, .smartAlbumDepthEffect: 4, .smartAlbumPanoramas: 5,
                .smartAlbumScreenshots: 6, .smartAlbumRecentlyAdded: 7, .smartAlbumSlomoVideos: 8,
                .smartAlbumTimelapses: 9, .smartAlbumBursts: 10, .smartAlbumAnimated: 11,
                .smartAlbumLongExposures: 12
            ]
            var out: [(Int, [String: Any])] = []
            let all = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
            all.enumerateObjects { c, _, _ in
                if c.assetCollectionSubtype == .smartAlbumUserLibrary { return } // '최근 항목'은 전체라 중복 제외
                let count = PHAsset.fetchAssets(in: c, options: nil).count
                if count == 0 { return }
                let name = c.localizedTitle ?? "Collection"
                out.append((rank[c.assetCollectionSubtype] ?? 99, ["id": c.localIdentifier, "name": name, "count": count, "subtype": Int(c.assetCollectionSubtype.rawValue)]))
            }
            let albums = out.sorted { $0.0 < $1.0 }.map { $0.1 }
            DispatchQueue.main.async { call.resolve(["albums": albums]) }
        }
    }
    @objc func libThumbs(_ call: CAPPluginCall) {
        DispatchQueue.main.async { self.libThumbsMain(call) } // byId 는 main 에서만 만짐(동시 접근으로 튕기지 않게)
    }
    private func libThumbsMain(_ call: CAPPluginCall) {
        let ids = call.getArray("ids", String.self) ?? []
        let px = CGFloat(call.getInt("size") ?? 240)
        var out = [String: String](), lock = NSLock(); let g = DispatchGroup()
        let opt = PHImageRequestOptions(); opt.deliveryMode = .highQualityFormat; opt.resizeMode = .fast; opt.isNetworkAccessAllowed = true; opt.isSynchronous = false
        for id in ids {
            let safe = id.replacingOccurrences(of: "/", with: "_")
            let f = thumbDir.appendingPathComponent("\(safe)-\(Int(px)).jpg")
            if FileManager.default.fileExists(atPath: f.path) { out[id] = f.path; continue }
            guard let a = byId[id] else { continue }
            g.enter()
            imgr.requestImage(for: a, targetSize: CGSize(width: px, height: px), contentMode: .aspectFill, options: opt) { img, _ in
                if let img = img, let d = img.jpegData(compressionQuality: 0.72), (try? d.write(to: f)) != nil { lock.lock(); out[id] = f.path; lock.unlock() }
                g.leave()
            }
        }
        g.notify(queue: .main) { call.resolve(["paths": out]) }
    }
    @objc func libExport(_ call: CAPPluginCall) {
        DispatchQueue.main.async { self.libExportMain(call) }
    }
    private func libExportMain(_ call: CAPPluginCall) {
        let ids = call.getArray("ids", String.self) ?? []
        cleanOld()
        let g = DispatchGroup(), lock = NSLock(); var out = [Int: [String: Any]]()
        let put = { (i: Int, v: [String: Any]?) in if let v = v { lock.lock(); out[i] = v; lock.unlock() } }
        // iCloud 에서 받는 중이면 진행률을 웹에 알림(받는 항목들의 평균, 0.2초에 한 번까지)
        var prog = [Int: Double](), lastSent = Date.distantPast
        let progress = { (i: Int, p: Double) in
            lock.lock(); prog[i] = p; let avg = prog.values.reduce(0, +) / Double(prog.count), n = prog.count
            let now = Date(), send = now.timeIntervalSince(lastSent) > 0.2 || p >= 1; if send { lastSent = now }; lock.unlock()
            if send { self.notifyListeners("libProgress", data: ["p": avg, "n": n]) }
        }
        for (i, id) in ids.enumerated() {
            guard let a = byId[id] else { continue }
            g.enter()
            if a.mediaType == .video { loadVideo(a, progress: { progress(i, $0) }) { put(i, $0); g.leave() } }
            else { loadImage(a, progress: { progress(i, $0) }) { put(i, $0); g.leave() } }
        }
        g.notify(queue: .main) {
            let items = (0..<ids.count).compactMap { out[$0] }
            call.resolve(["items": items, "skipped": ids.count - items.count])
        }
    }

    // 사진: 쓸 크기(최대 3024px)로만 요청 — 4800만 화소 원본 전체를 풀지 않아 빠르고 메모리도 적게 씀
    //  먼저 기기에 있는 것으로, 없으면(iCloud) 받아 오면서 진행률 알림
    private func loadImage(_ a: PHAsset, progress: @escaping (Double) -> Void, done: @escaping ([String: Any]?) -> Void) {
        let k = min(1, 3024 / CGFloat(max(1, max(a.pixelWidth, a.pixelHeight))))
        let target = CGSize(width: (CGFloat(a.pixelWidth) * k).rounded(), height: (CGFloat(a.pixelHeight) * k).rounded())
        let req = { (net: Bool, then: @escaping (UIImage?) -> Void) in
            let o = PHImageRequestOptions(); o.isNetworkAccessAllowed = net; o.deliveryMode = .highQualityFormat; o.resizeMode = .exact; o.version = .current
            if net { o.progressHandler = { p, _, _, _ in progress(p) } }
            PHImageManager.default().requestImage(for: a, targetSize: target, contentMode: .aspectFit, options: o) { img, info in
                then((info?[PHImageResultIsDegradedKey] as? Bool) == true ? nil : img)
            }
        }
        req(false) { img in
            if let img = img { DispatchQueue.global(qos: .userInitiated).async { done(self.imageItem(img)) }; return }
            req(true) { img2 in
                guard let img2 = img2 else { done(nil); return }
                progress(1); DispatchQueue.global(qos: .userInitiated).async { done(self.imageItem(img2)) }
            }
        }
    }
    private func imageItem(_ img: UIImage) -> [String: Any]? {
        let main = Self.resize(img, maxSide: 1080), thumb = Self.resize(main, maxSide: 480)
        let edit = Self.resize(img, maxSide: 3024)
        guard let mp = saveJPEG(main, 0.82), let tp = saveJPEG(thumb, 0.6), let ep = saveJPEG(edit, 0.9) else { return nil }
        return ["kind": "image", "path": mp, "thumbPath": tp, "editPath": ep, "width": Int(main.size.width), "height": Int(main.size.height)]
    }

    // 영상: 기기에 있으면 원본을 복사하지 않고 그대로 씀(올릴 때 고른 10초만 잘라 720p 로 만듦)
    //  iCloud 에만 있으면 720p 판으로 받음(원본 전체를 받지 않음 — 어차피 720p 로 올림) + 진행률 알림
    private var keepAssets = [String: AVAsset]() // 원본 파일을 계속 읽을 수 있게 붙잡아 둠
    private let keepLock = NSLock()
    private func loadVideo(_ a: PHAsset, progress: @escaping (Double) -> Void, done: @escaping ([String: Any]?) -> Void) {
        let local = PHVideoRequestOptions(); local.isNetworkAccessAllowed = false; local.deliveryMode = .highQualityFormat; local.version = .current
        PHImageManager.default().requestAVAsset(forVideo: a, options: local) { av, _, _ in
            if let av = av { self.useVideo(av, done); return }
            let net = PHVideoRequestOptions(); net.isNetworkAccessAllowed = true; net.deliveryMode = .mediumQualityFormat; net.version = .current
            net.progressHandler = { p, _, _, _ in progress(p) }
            PHImageManager.default().requestAVAsset(forVideo: a, options: net) { av2, _, _ in
                guard let av2 = av2 else { done(nil); return }
                progress(1); self.useVideo(av2, done)
            }
        }
    }
    private func useVideo(_ av: AVAsset, _ done: @escaping ([String: Any]?) -> Void) {
        if let u = (av as? AVURLAsset)?.url {
            if Self.readable(u) { keepLock.lock(); keepAssets[u.path] = av; keepLock.unlock(); done(videoInfo(u)); return }
            let dst = newFile(u.pathExtension.isEmpty ? "mov" : u.pathExtension.lowercased()) // 읽을 수 없으면 예전처럼 복사
            done((try? FileManager.default.copyItem(at: u, to: dst)) != nil ? videoInfo(dst) : nil)
            return
        }
        // 슬로모 등(여러 조각을 이어 붙인 영상): 720p 로 한 번 만들어 씀(최고 화질 전체 변환보다 훨씬 빠름. 어차피 720p 로 올림)
        guard let ex = AVAssetExportSession(asset: av, presetName: AVAssetExportPreset1280x720) else { done(nil); return }
        let dst = newFile("mp4"); ex.outputURL = dst; ex.outputFileType = .mp4; ex.shouldOptimizeForNetworkUse = false
        ex.exportAsynchronously { done(ex.status == .completed ? self.videoInfo(dst) : nil) }
    }
    static func readable(_ u: URL) -> Bool { // 앱이 실제로 열 수 있는지 1바이트 읽어 봄(권한 확인)
        guard let h = try? FileHandle(forReadingFrom: u) else { return false }
        defer { try? h.close() }
        return ((try? h.read(upToCount: 1)) ?? nil)?.count == 1
    }
    @objc func libManage(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else { call.reject("no_vc"); return }
            if #available(iOS 15.0, *) { PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: vc) { _ in call.resolve() } }
            else { PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: vc); call.resolve() }
        }
    }

    // ---------- 도구 ----------
    private func cleanOld(_ d: URL? = nil, maxAge: TimeInterval = 3600) {
        let folder = d ?? dir
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let limit = Date().addingTimeInterval(-maxAge)
        for u in items {
            let m = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if m < limit { try? FileManager.default.removeItem(at: u) }
        }
    }
    static func downsample(_ url: URL, maxSide: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxSide, kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
    static func resize(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let s = img.size, k = min(1, maxSide / max(s.width, s.height))
        let size = CGSize(width: (s.width * k).rounded(), height: (s.height * k).rounded())
        let fmt = UIGraphicsImageRendererFormat.default(); fmt.scale = 1; fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) } // 회전 정보 반영
    }
    private func saveJPEG(_ img: UIImage, _ q: CGFloat) -> String? {
        guard let data = img.jpegData(compressionQuality: q) else { return nil }
        let url = newFile("jpg")
        do { try data.write(to: url) } catch { return nil }
        return url.path
    }
}
