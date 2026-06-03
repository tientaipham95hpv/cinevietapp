import AVFoundation
import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
  private weak var volumeSlider: UISlider?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setupPlayerControlChannel()
    return ok
  }

  private func setupPlayerControlChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }

    if volumeView.superview == nil {
      volumeView.alpha = 0.01
      controller.view.addSubview(volumeView)
      volumeSlider = volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    let channel = FlutterMethodChannel(
      name: "live.cineviet/brightness",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      DispatchQueue.main.async {
        switch call.method {
        case "get":
          result(Double(UIScreen.main.brightness))
        case "set":
          let value = self?.doubleArg(call.arguments, key: "value", fallback: 0.5) ?? 0.5
          UIScreen.main.brightness = CGFloat(min(max(value, 0.0), 1.0))
          result(nil)
        case "getVolume":
          result(Double(AVAudioSession.sharedInstance().outputVolume))
        case "setVolume":
          let value = self?.doubleArg(call.arguments, key: "value", fallback: 1.0) ?? 1.0
          self?.setSystemVolume(value)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private func doubleArg(_ arguments: Any?, key: String, fallback: Double) -> Double {
    guard let args = arguments as? [String: Any] else { return fallback }
    if let value = args[key] as? Double { return value }
    if let value = args[key] as? NSNumber { return value.doubleValue }
    return fallback
  }

  private func setSystemVolume(_ value: Double) {
    let clamped = Float(min(max(value, 0.0), 1.0))
    if volumeSlider == nil {
      volumeSlider = volumeView.subviews.compactMap { $0 as? UISlider }.first
    }
    volumeSlider?.setValue(clamped, animated: false)
    volumeSlider?.sendActions(for: .valueChanged)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
