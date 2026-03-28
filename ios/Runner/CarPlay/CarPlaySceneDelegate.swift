import CarPlay
import Flutter
import UIKit

/// CarPlay scene delegate that manages the CarPlay window lifecycle.
///
/// Handles:
/// - CarPlay connect/disconnect events
/// - CPVoiceControlTemplate as root template
/// - AVAudioSession activation for car audio routing
/// - Platform channel registration for Flutter communication
///
/// Registered in Info.plist under CPTemplateApplicationSceneSessionRoleApplication.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    /// Tracks whether a CarPlay session is currently active.
    static private(set) var isCarPlayConnected = false

    private var interfaceController: CPInterfaceController?
    private var voiceController: CarPlayVoiceController?

    // Shared channel handler registered by AppDelegate with the Flutter engine.
    static var channelHandler: CarPlayChannelHandler?

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        Self.isCarPlayConnected = true

        configureAudioSession()
        setupVoiceTemplate(with: interfaceController)

        Self.channelHandler?.sendEvent(type: "carplayConnected")
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        voiceController = nil
        Self.isCarPlayConnected = false

        CarPlayAudioSession.deactivate()
        Self.channelHandler?.sendEvent(type: "carplayDisconnected")
    }

    // MARK: - Setup

    private func configureAudioSession() {
        do {
            try CarPlayAudioSession.activateForCarPlay()
        } catch {
            Self.channelHandler?.sendEvent(
                type: "error",
                data: [
                    "code": "audio_session_failed",
                    "message": "Failed to configure car audio: \(error.localizedDescription)",
                ]
            )
        }
    }

    private func setupVoiceTemplate(with controller: CPInterfaceController) {
        guard let channelHandler = Self.channelHandler else { return }

        let voice = CarPlayVoiceController(channelHandler: channelHandler)
        channelHandler.setVoiceController(voice)
        voiceController = voice

        voice.onTemplateRebuild = { [weak controller] newTemplate in
            controller?.setRootTemplate(newTemplate, animated: true, completion: nil)
        }

        let template = voice.createTemplate()
        controller.setRootTemplate(template, animated: false, completion: nil)
    }
}

