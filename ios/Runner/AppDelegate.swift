import AVFoundation
import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "live.cineviet/brightness", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "get":
          result(Double(UIScreen.main.brightness))
        case "set":
          if let args = call.arguments as? [String: Any], let value = args["value"] as? Double {
            UIScreen.main.brightness = CGFloat(min(max(value, 0.0), 1.0))
          }
          result(nil)
        case "getVolume":
          let session = AVAudioSession.sharedInstance()
          result(Double(session.outputVolume))
        case "setVolume":
          // iOS does not allow programmatic system-volume changes through public API.
          // Flutter still adjusts player volume on the Dart side; this keeps the method safe.
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
