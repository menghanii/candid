import Foundation
import Capacitor
import AuthenticationServices

// iPhone 기본 Apple 로그인 창(Face ID). 웹에서 만든 nonce 의 해시를 받아 요청하고,
// Apple 이 준 identity token(과 처음 한 번만 오는 이름·이메일)을 웹에 돌려줌 → 웹이 Supabase 에 로그인
@objc(AppleSignInPlugin)
public class AppleSignInPlugin: CAPPlugin, CAPBridgedPlugin, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    public let identifier = "AppleSignInPlugin"
    public let jsName = "AppleSignIn"
    public let pluginMethods: [CAPPluginMethod] = [CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise)]
    private var pending: CAPPluginCall?

    @objc func start(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let req = ASAuthorizationAppleIDProvider().createRequest()
            req.requestedScopes = [.fullName, .email]
            req.nonce = call.getString("nonce")
            let c = ASAuthorizationController(authorizationRequests: [req])
            c.delegate = self
            c.presentationContextProvider = self
            self.pending = call
            c.performRequests()
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let call = pending else { return }
        pending = nil
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = cred.identityToken, let token = String(data: data, encoding: .utf8) else {
            call.reject("no_token"); return
        }
        let name = [cred.fullName?.familyName, cred.fullName?.givenName].compactMap { $0 }.joined()
        call.resolve(["identityToken": token, "name": name, "email": cred.email ?? ""])
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard let call = pending else { return }
        pending = nil
        if (error as? ASAuthorizationError)?.code == .canceled { call.reject("canceled", "canceled") }
        else { call.reject(error.localizedDescription) }
    }

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return self.bridge?.webView?.window ?? ASPresentationAnchor()
    }
}
