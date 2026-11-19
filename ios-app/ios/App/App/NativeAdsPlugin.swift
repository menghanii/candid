import UIKit
import Capacitor
import GoogleMobileAds

// Candids 피드 사이의 Google 네이티브 광고(사진처럼 보이는 광고).
// 웹 화면에 '광고 자리'가 있고, 그 자리가 화면에 오면 여기서 Google 광고 보기(NativeAdView)를 정확히 그 위에 겹쳐 그림.
//  · load: 광고를 몇 개 미리 받아 두고 id 목록을 돌려줌
//  · show: 받아 둔 광고 하나를 웹이 알려준 위치(rect)에 그림 / hide: 치움 / discard: 다 쓴 광고 버림
//  · 광고 위에서 위아래로 밀면 'swipe' 이벤트(dir: 1 다음, -1 이전)를 웹에 보내 웹이 앞뒤 사진으로 넘김
@objc(NativeAdsPlugin)
public class NativeAdsPlugin: CAPPlugin, CAPBridgedPlugin, NativeAdLoaderDelegate, NativeAdDelegate {
    public let identifier = "NativeAdsPlugin"
    public let jsName = "NativeAds"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "load", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "show", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hide", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "discard", returnType: CAPPluginReturnPromise),
    ]
    private var loader: AdLoader?
    private var loadCall: CAPPluginCall?
    private var got: [String] = []
    private var ads: [String: NativeAd] = [:]
    private var adView: NativeAdView?
    private var shownId: String?
    static let testUnit = "ca-app-pub-3940256099942544/3986624511" // Google 시험용 네이티브 광고

    // ---------- 받기 ----------
    @objc func load(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.loadCall != nil { call.reject("busy"); return }
            let unit = (call.getBool("testing") ?? false) ? Self.testUnit : (call.getString("adId") ?? "")
            if unit.isEmpty { call.reject("no_unit"); return }
            let multi = MultipleAdsAdLoaderOptions()
            multi.numberOfAds = max(1, min(5, call.getInt("count") ?? 3))
            let l = AdLoader(adUnitID: unit, rootViewController: self.bridge?.viewController, adTypes: [.native], options: [multi])
            l.delegate = self
            self.loader = l; self.got = []; self.loadCall = call
            let req = Request()
            if call.getBool("npa") ?? true { let e = Extras(); e.additionalParameters = ["npa": "1"]; req.register(e) } // 추적 미허용: 비맞춤 광고
            l.load(req)
        }
    }
    public func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        let id = UUID().uuidString
        nativeAd.delegate = self
        ads[id] = nativeAd; got.append(id)
    }
    public func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        guard let call = loadCall else { return }
        loadCall = nil
        if got.isEmpty { call.reject(error.localizedDescription) } else { call.resolve(["ids": got]) }
    }
    public func adLoaderDidFinishLoading(_ adLoader: AdLoader) {
        loadCall?.resolve(["ids": got]); loadCall = nil
    }

    // ---------- 보이기·치우기 ----------
    @objc func show(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let id = call.getString("id"), let ad = self.ads[id], let web = self.bridge?.webView, let host = web.superview else { call.reject("no_ad"); return }
            let r = CGRect(x: call.getDouble("x") ?? 0, y: call.getDouble("y") ?? 0, width: call.getDouble("w") ?? Double(web.bounds.width), height: call.getDouble("h") ?? Double(web.bounds.height))
            if self.shownId == id, let v = self.adView, v.superview != nil { v.frame = r.offsetBy(dx: web.frame.minX, dy: web.frame.minY); call.resolve(); return }
            self.adView?.removeFromSuperview()
            let v = self.buildView(ad, size: r.size, label: call.getString("label") ?? "광고")
            v.frame = r.offsetBy(dx: web.frame.minX, dy: web.frame.minY)
            v.alpha = 0
            host.addSubview(v)
            UIView.animate(withDuration: 0.15) { v.alpha = 1 }
            self.adView = v; self.shownId = id
            call.resolve()
        }
    }
    @objc func hide(_ call: CAPPluginCall) {
        DispatchQueue.main.async { self.adView?.removeFromSuperview(); self.adView = nil; self.shownId = nil; call.resolve() }
    }
    @objc func discard(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if let id = call.getString("id") { if self.shownId == id { self.adView?.removeFromSuperview(); self.adView = nil; self.shownId = nil }; self.ads.removeValue(forKey: id) }
            call.resolve()
        }
    }

    // 광고 위에서 위아래로 밀기 → 웹이 앞뒤로 넘김(광고는 바로 치움)
    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard g.state == .ended, let v = g.view else { return }
        let dy = g.translation(in: v).y, vy = g.velocity(in: v).y
        guard abs(dy) > 36 || abs(vy) > 500 else { return }
        adView?.removeFromSuperview(); adView = nil; shownId = nil
        notifyListeners("swipe", data: ["dir": dy < 0 ? 1 : -1])
    }

    // ---------- 광고 보기 만들기: Candids 한 칸과 같은 모양(가운데 사진, 아래에 광고주 사진·이름·광고 표시·제목·버튼) ----------
    private func buildView(_ ad: NativeAd, size: CGSize, label: String) -> NativeAdView {
        let v = NativeAdView(frame: CGRect(origin: .zero, size: size))
        v.backgroundColor = .clear
        let W = size.width, H = size.height, pad: CGFloat = 16
        let bottomPad: CGFloat = 26, ctaH: CGFloat = 38
        let hasBody = !(ad.body ?? "").isEmpty
        let infoH: CGFloat = 46 + 26 + (hasBody ? 40 : 0) + (ad.callToAction != nil ? ctaH + 12 : 0)
        let mediaH = max(120, min(W * 1.25, H - infoH - bottomPad - 24))
        let mediaY = max(0, (H - infoH - bottomPad - mediaH) / 2)

        let media = MediaView(frame: CGRect(x: 0, y: mediaY, width: W, height: mediaH))
        media.contentMode = .scaleAspectFill
        media.clipsToBounds = true
        media.mediaContent = ad.mediaContent
        v.addSubview(media); v.mediaView = media

        var y = H - bottomPad - infoH
        // 광고주: Candids 의 '피드 주인' 자리처럼 동그란 사진 + 이름
        let iv = UIImageView(frame: CGRect(x: pad, y: y, width: 40, height: 40))
        iv.image = ad.icon?.image; iv.backgroundColor = UIColor(white: 1, alpha: 0.15)
        iv.layer.cornerRadius = 20; iv.clipsToBounds = true; iv.contentMode = .scaleAspectFill
        iv.layer.borderWidth = 1.5; iv.layer.borderColor = UIColor(white: 1, alpha: 0.9).cgColor
        v.addSubview(iv); v.iconView = iv
        let adv = UILabel(frame: CGRect(x: pad + 50, y: y + 10, width: W - pad * 2 - 50, height: 20))
        adv.text = ad.advertiser ?? ad.headline; adv.font = .systemFont(ofSize: 14, weight: .bold); adv.textColor = .white
        v.addSubview(adv); v.advertiserView = adv
        y += 46
        // '광고' 표시 + 제목 (Candids 의 from. 줄 자리)
        let tag = UILabel()
        tag.text = "  \(label)  "; tag.font = .systemFont(ofSize: 11, weight: .bold); tag.textColor = .white
        tag.backgroundColor = UIColor(white: 1, alpha: 0.18); tag.layer.cornerRadius = 9; tag.clipsToBounds = true
        tag.sizeToFit(); tag.frame = CGRect(x: pad, y: y + 2, width: tag.frame.width, height: 18)
        v.addSubview(tag)
        let head = UILabel(frame: CGRect(x: pad + tag.frame.width + 8, y: y, width: W - pad * 2 - tag.frame.width - 8, height: 22))
        head.text = ad.headline; head.font = .systemFont(ofSize: 16, weight: .bold); head.textColor = .white
        v.addSubview(head); v.headlineView = head
        y += 26
        if hasBody {
            let body = UILabel(frame: CGRect(x: pad, y: y, width: W - pad * 2, height: 36))
            body.text = ad.body; body.font = .systemFont(ofSize: 13); body.textColor = UIColor(white: 1, alpha: 0.72); body.numberOfLines = 2
            v.addSubview(body); v.bodyView = body
            y += 40
        }
        if let cta = ad.callToAction {
            let btn = UIButton(type: .system)
            btn.setTitle(cta, for: .normal); btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            btn.backgroundColor = UIColor(red: 0.36, green: 0.49, blue: 1, alpha: 1); btn.setTitleColor(.white, for: .normal)
            btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
            btn.sizeToFit()
            btn.frame = CGRect(x: pad, y: y + 8, width: min(W - pad * 2, max(120, btn.frame.width)), height: ctaH)
            btn.layer.cornerRadius = ctaH / 2; btn.isUserInteractionEnabled = false // 클릭은 Google 광고 보기가 처리
            v.addSubview(btn); v.callToActionView = btn
        }
        v.nativeAd = ad
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.cancelsTouchesInView = false
        v.addGestureRecognizer(pan)
        return v
    }
}
