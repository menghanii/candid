import UIKit
import Capacitor

// iOS 27 부터 필수인 화면(Scene) 방식. 화면은 Main.storyboard 로 만들어지고,
// candid:// 링크·유니버설 링크로 열릴 때는 Capacitor(앱 플러그인)에 그대로 넘김
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let ctx = connectionOptions.urlContexts.first { open(ctx.url) }
        if let ua = connectionOptions.userActivities.first { cont(ua) }
    }
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        URLContexts.forEach { open($0.url) }
    }
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) { cont(userActivity) }

    private func open(_ url: URL) {
        _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, open: url, options: [:])
    }
    private func cont(_ ua: NSUserActivity) {
        _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, continue: ua, restorationHandler: { _ in })
    }
}
