import UIKit
import Capacitor

// 앱 화면(웹)을 담는 화면. 앱 안에서 직접 만든 iPhone 기능(플러그인)을 여기서 등록
class AppViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(AuthSessionPlugin())
        bridge?.registerPluginInstance(MediaPickerPlugin())
        bridge?.registerPluginInstance(AppleSignInPlugin())
        bridge?.registerPluginInstance(NativeAdsPlugin())
    }
}
