import Foundation
import UIKit
import Capacitor
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

// 사진·영상 고르기와 준비를 iPhone 기능으로(웹보다 빠르고 안정적)
//  · pick: iPhone 사진 선택창(여러 장, 고른 순서대로) → 사진은 1080px 본문 + 480px 썸네일(JPEG)로 줄이고, 영상은 원본 복사 + 대표 이미지
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
        CAPPluginMethod(name: "libThumbs", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "libExport", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "libManage", returnType: CAPPluginReturnPromise)
    ]
    private var pending: CAPPluginCall?
    private var camCall: CAPPluginCall?

    private lazy var dir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("candid-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private func newFile(_ ext: String) -> URL { dir.appendingPathComponent(UUID().uuidString + "." + ext) }

    // ---------- 고르기 ----------
    @objc func pick(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            // 지난번 임시 파일 정리
            if let old = try? FileManager.default.contentsOfDirectory(at: self.dir, includingPropertiesForKeys: nil) {
                old.forEach { try? FileManager.default.removeItem(at: $0) }
            }
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
            } else if p.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                p.loadObject(ofClass: UIImage.self) { obj, _ in
                    defer { group.leave() }
                    guard let img = obj as? UIImage else { return }
                    let main = Self.resize(img, maxSide: 1080), thumb = Self.resize(main, maxSide: 480)
                    guard let mp = self.saveJPEG(main, 0.82), let tp = self.saveJPEG(thumb, 0.7) else { return }
                    put(i, ["kind": "image", "path": mp, "thumbPath": tp,
                            "width": Int(main.size.width), "height": Int(main.size.height)])
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
        gen.maximumSize = CGSize(width: 720, height: 720)
        var thumbPath = ""
        if let cg = try? gen.copyCGImage(at: CMTime(seconds: min(0.15, dur / 2), preferredTimescale: 600), actualTime: nil),
           let tp = saveJPEG(UIImage(cgImage: cg), 0.72) { thumbPath = tp }
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
            }) { ok, err in ok ? call.resolve() : call.reject(err?.localizedDescription ?? "save_failed") }
        }
    }

    // ---------- 카메라로 바로 찍기 ----------
    // 사진 또는 영상(최대 10초)을 찍으면 고르기와 같은 모양(items)으로 돌려줌
    @objc func camera(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else { call.reject("no_camera", "no_camera"); return }
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
                guard let mp = self.saveJPEG(main, 0.82), let tp = self.saveJPEG(thumb, 0.7) else { call.reject("image_failed"); return }
                call.resolve(["items": [["kind": "image", "path": mp, "thumbPath": tp, "width": Int(main.size.width), "height": Int(main.size.height)]], "skipped": 0])
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
        DispatchQueue.global(qos: .userInitiated).async {
            let o = PHFetchOptions()
            o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            o.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            let r = PHAsset.fetchAssets(with: o)
            var ids = [String](), ts = [Int](), dur = [Double](), map = [String: PHAsset]()
            ids.reserveCapacity(r.count); ts.reserveCapacity(r.count); dur.reserveCapacity(r.count)
            r.enumerateObjects { a, _, _ in
                ids.append(a.localIdentifier); ts.append(Int(a.creationDate?.timeIntervalSince1970 ?? 0))
                dur.append(a.mediaType == .video ? (a.duration * 10).rounded() / 10 : 0); map[a.localIdentifier] = a
            }
            DispatchQueue.main.async { self.fetch = r; self.byId = map; call.resolve(["ids": ids, "ts": ts, "dur": dur]) }
        }
    }
    @objc func libThumbs(_ call: CAPPluginCall) {
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
        let ids = call.getArray("ids", String.self) ?? []
        if let old = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) { old.forEach { try? FileManager.default.removeItem(at: $0) } }
        let g = DispatchGroup(), lock = NSLock(); var out = [Int: [String: Any]]()
        let put = { (i: Int, v: [String: Any]) in lock.lock(); out[i] = v; lock.unlock() }
        for (i, id) in ids.enumerated() {
            guard let a = byId[id] else { continue }
            g.enter()
            if a.mediaType == .video {
                let vo = PHVideoRequestOptions(); vo.isNetworkAccessAllowed = true; vo.deliveryMode = .highQualityFormat; vo.version = .current
                PHImageManager.default().requestAVAsset(forVideo: a, options: vo) { av, _, _ in
                    if let u = (av as? AVURLAsset)?.url {
                        let dst = self.newFile(u.pathExtension.isEmpty ? "mov" : u.pathExtension.lowercased())
                        if (try? FileManager.default.copyItem(at: u, to: dst)) != nil, let v = self.videoInfo(dst) { put(i, v) }
                        g.leave()
                    } else if let av = av, let ex = AVAssetExportSession(asset: av, presetName: AVAssetExportPresetHighestQuality) { // 슬로모 등
                        let dst = self.newFile("mp4"); ex.outputURL = dst; ex.outputFileType = .mp4
                        ex.exportAsynchronously { if ex.status == .completed, let v = self.videoInfo(dst) { put(i, v) }; g.leave() }
                    } else { g.leave() }
                }
            } else {
                let io = PHImageRequestOptions(); io.isNetworkAccessAllowed = true; io.deliveryMode = .highQualityFormat; io.resizeMode = .exact; io.version = .current
                PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 1080, height: 1080), contentMode: .aspectFit, options: io) { img, _ in
                    defer { g.leave() }
                    guard let img = img else { return }
                    let main = Self.resize(img, maxSide: 1080), thumb = Self.resize(main, maxSide: 480)
                    guard let mp = self.saveJPEG(main, 0.82), let tp = self.saveJPEG(thumb, 0.7) else { return }
                    put(i, ["kind": "image", "path": mp, "thumbPath": tp, "width": Int(main.size.width), "height": Int(main.size.height)])
                }
            }
        }
        g.notify(queue: .main) {
            let items = (0..<ids.count).compactMap { out[$0] }
            call.resolve(["items": items, "skipped": ids.count - items.count])
        }
    }
    @objc func libManage(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else { call.reject("no_vc"); return }
            if #available(iOS 15.0, *) { PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: vc) { _ in call.resolve() } }
            else { PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: vc); call.resolve() }
        }
    }

    // ---------- 도구 ----------
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
