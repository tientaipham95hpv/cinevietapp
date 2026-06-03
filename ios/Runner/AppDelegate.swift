import AVFoundation
import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
  private weak var volumeSlider: UISlider?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    DispatchQueue.main.async { [weak self] in
      self?.setupPlayerControlChannel()
    }

    return ok
  }

  private func setupPlayerControlChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }

    if volumeView.superview == nil {
      volumeView.alpha = 0.01
      volumeView.isUserInteractionEnabled = false
      controller.view.addSubview(volumeView)
      volumeSlider = volumeView.subviews.compactMap { $0 as? UISlider }.first
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
        self?.volumeSlider = self?.volumeView.subviews.compactMap { $0 as? UISlider }.first
      }
    }

    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
    try? AVAudioSession.sharedInstance().setActive(true)

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
          result(Double(UIScreen.main.brightness))
        case "getVolume":
          result(Double(AVAudioSession.sharedInstance().outputVolume))
        case "setVolume":
          let value = self?.doubleArg(call.arguments, key: "value", fallback: 1.0) ?? 1.0
          self?.setSystemVolume(value)
          result(Double(AVAudioSession.sharedInstance().outputVolume))
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
    if volumeSlider == nil {
      volumeView.layoutIfNeeded()
      volumeSlider = volumeView.subviews.compactMap { $0 as? UISlider }.first
    }
    volumeSlider?.value = clamped
    volumeSlider?.sendActions(for: .valueChanged)
  }
}
