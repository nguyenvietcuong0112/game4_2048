import Flutter
import UIKit
import AdSupport

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Tự động nhận diện bản TestFlight (sandboxReceipt) hoặc bản Debug trong Xcode
    let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    #if DEBUG
    let isDebug = true
    #else
    let isDebug = false
    #endif

    // Chỉ bật DebugView trên TestFlight/Debug; bản App Store thật sẽ xóa sạch cờ debug
    if isTestFlight || isDebug {
      UserDefaults.standard.set(true, forKey: "/google/firebase/debug_mode")
      UserDefaults.standard.set(true, forKey: "/google/measurement/debug_mode")
      UserDefaults.standard.synchronize()
      print("[AppDelegate] Firebase Analytics DebugView is ENABLED for TestFlight/Debug.")

      let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
      let idfv = UIDevice.current.identifierForVendor?.uuidString ?? "N/A"
      print("[AppDelegate] Test Device Info -> IDFA: \(idfa), IDFV: \(idfv)")
    } else {
      UserDefaults.standard.removeObject(forKey: "/google/firebase/debug_mode")
      UserDefaults.standard.removeObject(forKey: "/google/measurement/debug_mode")
      UserDefaults.standard.synchronize()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let appInfoChannel = FlutterMethodChannel(
      name: "com.fw.water.block.number.merge/app_info",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    appInfoChannel.setMethodCallHandler { call, result in
      if call.method == "getAppVersion" {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        result(version)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
