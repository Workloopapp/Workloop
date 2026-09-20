import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var stripeTerminalBridge: WorkloopStripeTerminalBridge?
  private var notificationSettingsChannel: FlutterMethodChannel?
  private var receiptTextBridge: WorkloopReceiptTextBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    stripeTerminalBridge = WorkloopStripeTerminalBridge(messenger: messenger)
    receiptTextBridge = WorkloopReceiptTextBridge(messenger: messenger)
    let channel = FlutterMethodChannel(
      name: "workloop/notifications",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "openSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let settingsURL: String
      if #available(iOS 16.0, *) {
        settingsURL = UIApplication.openNotificationSettingsURLString
      } else {
        settingsURL = UIApplication.openSettingsURLString
      }
      guard let url = URL(string: settingsURL) else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        result(opened)
      }
    }
    notificationSettingsChannel = channel
  }
}
