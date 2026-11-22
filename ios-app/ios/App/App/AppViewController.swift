import UIKit
import Capacitor

// 앱 화면(웹)을 담는 화면. 앱 안에서 직접 만든 iPhone 기능(플러그인)을 여기서 등록
class AppViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(AuthSessionPlugin())
        bridge?.registerPluginInstance(MediaPickerPlugin())
        bridge?.registerPluginInstance(AppleSignInPlugin())
        bridge?.registerPluginInstance(NativeAdsPlugin())
        if let scroll = webView?.scrollView {
            scroll.pinchGestureRecognizer?.isEnabled = false
        }
        webView?.allowsLinkPreview = false // 링크를 길게 눌러도 미리보기 창이 뜨지 않게
    }
}
