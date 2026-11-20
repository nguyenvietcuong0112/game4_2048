import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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
