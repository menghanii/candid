import Foundation
import Capacitor
import AuthenticationServices

// 로그인 전용 창(ASWebAuthenticationSession): 카카오·Google·Apple 로그인 페이지를 iPhone 의 안전한 창으로 열고,
// candid:// 로 돌아오는 순간 창을 닫고 그 주소를 웹(앱 화면)에 돌려줌. "열겠습니까?" 확인 창이 뜨지 않음
@objc(AuthSessionPlugin)
public class AuthSessionPlugin: CAPPlugin, CAPBridgedPlugin, ASWebAuthenticationPresentationContextProviding {
    public let identifier = "AuthSessionPlugin"
    public let jsName = "AuthSession"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise)
    ]
    private var session: ASWebAuthenticationSession?

    @objc func start(_ call: CAPPluginCall) {
        guard let raw = call.getString("url"), let url = URL(string: raw),
              let scheme = call.getString("scheme") else {
            call.reject("bad_args")
            return
        }
        DispatchQueue.main.async {
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
                defer { self?.session = nil }
                if let callback = callback {
                    call.resolve(["url": callback.absoluteString])
                } else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    call.reject("canceled", "canceled")
                } else {
                    call.reject(error?.localizedDescription ?? "failed")
                }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false // Safari 에 이미 로그인돼 있으면(카카오 등) 다시 입력하지 않게
            self.session = s
            if !s.start() { call.reject("start_failed") }
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return self.bridge?.webView?.window ?? ASPresentationAnchor()
    }
}
