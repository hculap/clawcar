import Flutter
import Foundation

/// Handles platform channel communication between Flutter and native CarPlay.
///
/// MethodChannel (`com.clawcar/carplay`): Flutter -> Native calls
/// EventChannel (`com.clawcar/carplay_events`): Native -> Flutter event stream
final class CarPlayChannelHandler: NSObject {
    static let methodChannelName = "com.clawcar/carplay"
    static let eventChannelName = "com.clawcar/carplay_events"

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    private weak var voiceController: CarPlayVoiceController?

    func register(with messenger: FlutterBinaryMessenger) {
        let method = FlutterMethodChannel(
            name: Self.methodChannelName,
            binaryMessenger: messenger
        )
        method.setMethodCallHandler(handleMethodCall)
        methodChannel = method

        let event = FlutterEventChannel(
            name: Self.eventChannelName,
            binaryMessenger: messenger
        )
        event.setStreamHandler(self)
        eventChannel = event
    }

    func setVoiceController(_ controller: CarPlayVoiceController) {
        voiceController = controller
    }

    // MARK: - Native -> Flutter events

    func sendEvent(type: String, data: [String: Any]? = nil) {
        DispatchQueue.main.async { [weak self] in
            var payload: [String: Any] = ["type": type]
            if let data {
                payload["data"] = data
            }
            self?.eventSink?(payload)
        }
    }

    // MARK: - Flutter -> Native method calls

    private func handleMethodCall(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "isAvailable":
            result(CarPlaySceneDelegate.isCarPlayConnected)

        case "updateState":
            guard let args = call.arguments as? [String: Any],
                  let stateString = args["state"] as? String
            else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "Missing 'state' argument",
                    details: nil
                ))
                return
            }
            voiceController?.updateFromFlutter(stateString: stateString)
            result(nil)

        case "updateStatusText":
            guard let args = call.arguments as? [String: Any],
                  let text = args["text"] as? String
            else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "Missing 'text' argument",
                    details: nil
                ))
                return
            }
            voiceController?.updateStatusText(text)
            result(nil)

        case "setAgents":
            guard let args = call.arguments as? [String: Any],
                  let agents = args["agents"] as? [[String: Any]]
            else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "Missing 'agents' argument",
                    details: nil
                ))
                return
            }
            voiceController?.setAgents(agents)
            result(nil)

        case "setSelectedAgent":
            guard let args = call.arguments as? [String: Any],
                  let agentId = args["agentId"] as? String
            else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "Missing 'agentId' argument",
                    details: nil
                ))
                return
            }
            voiceController?.setSelectedAgent(agentId: agentId)
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func dispose() {
        methodChannel?.setMethodCallHandler(nil)
        methodChannel = nil
        eventChannel?.setStreamHandler(nil)
        eventChannel = nil
        eventSink = nil
    }
}

// MARK: - FlutterStreamHandler

extension CarPlayChannelHandler: FlutterStreamHandler {
    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
