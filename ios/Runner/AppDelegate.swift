import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let carPlayChannelHandler = CarPlayChannelHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    carPlayChannelHandler.register(with: controller.binaryMessenger)
    CarPlaySceneDelegate.channelHandler = carPlayChannelHandler
  }
}
