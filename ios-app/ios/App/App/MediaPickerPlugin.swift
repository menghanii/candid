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
public class MediaPickerPlugin: CAPPlugin, CAPBridgedPlugin, PHPickerViewControllerDelegate {
    public let identifier = "MediaPickerPlugin"
    public let jsName = "MediaPicker"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "pick", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "exportVideo", returnType: CAPPluginReturnPromise)
    ]
    private var pending: CAPPluginCall?

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
