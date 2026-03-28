import CarPlay
import Foundation

/// Voice state identifiers matching Flutter's PipelineState.
enum VoiceState: String {
    case idle
    case listening
    case processing
    case speaking
    case error
}

/// Agent descriptor received from Flutter.
struct CarPlayAgent {
    let id: String
    let name: String
    let isDefault: Bool
}

/// Manages the CPVoiceControlTemplate and its voice control states.
///
/// Translates between Flutter's PipelineState and CarPlay's voice control
/// states. Provides action buttons for start/stop listening and agent switching.
final class CarPlayVoiceController {

    private weak var channelHandler: CarPlayChannelHandler?
    private var voiceTemplate: CPVoiceControlTemplate?

    /// Called when the voice template is rebuilt and must be re-set as root.
    var onTemplateRebuild: ((CPVoiceControlTemplate) -> Void)?

    private(set) var currentState: VoiceState = .idle
    private var agents: [CarPlayAgent] = []
    private var selectedAgentId: String?
    private var statusText: String = "Ready"

    init(channelHandler: CarPlayChannelHandler) {
        self.channelHandler = channelHandler
    }

    // MARK: - Template creation

    /// Creates and returns the CPVoiceControlTemplate for the CarPlay interface.
    ///
    /// Attaches mic (start/stop/cancel) and agent-switch bar buttons to the
    /// template. These are re-attached on every rebuild via `rebuildStates()`.
    func createTemplate() -> CPVoiceControlTemplate {
        let template = buildTemplate()
        activateState(.idle)
        return template
    }

    // MARK: - State management (called from Flutter via channel handler)

    func updateFromFlutter(stateString: String) {
        guard let state = VoiceState(rawValue: stateString) else { return }
        currentState = state
        activateState(state)
    }

    func updateStatusText(_ text: String) {
        statusText = text
        // Rebuild template states to reflect new status text
        rebuildStates()
    }

    func setAgents(_ agentDicts: [[String: Any]]) {
        agents = agentDicts.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let name = dict["name"] as? String
            else { return nil }
            let isDefault = dict["isDefault"] as? Bool ?? false
            return CarPlayAgent(id: id, name: name, isDefault: isDefault)
        }
    }

    func setSelectedAgent(agentId: String) {
        selectedAgentId = agentId
    }

    // MARK: - Voice control states

    private func buildVoiceControlStates() -> [CPVoiceControlState] {
        return [
            buildIdleState(),
            buildListeningState(),
            buildProcessingState(),
            buildSpeakingState(),
            buildErrorState(),
        ]
    }

    private func buildIdleState() -> CPVoiceControlState {
        let agentName = currentAgentName()
        return CPVoiceControlState(
            identifier: VoiceState.idle.rawValue,
            titleVariants: [agentName.map { "Ask \($0)" } ?? "Tap to speak"],
            image: nil,
            repeats: false
        )
    }

    private func buildListeningState() -> CPVoiceControlState {
        return CPVoiceControlState(
            identifier: VoiceState.listening.rawValue,
            titleVariants: ["Listening..."],
            image: nil,
            repeats: true
        )
    }

    private func buildProcessingState() -> CPVoiceControlState {
        return CPVoiceControlState(
            identifier: VoiceState.processing.rawValue,
            titleVariants: ["Thinking..."],
            image: nil,
            repeats: true
        )
    }

    private func buildSpeakingState() -> CPVoiceControlState {
        return CPVoiceControlState(
            identifier: VoiceState.speaking.rawValue,
            titleVariants: ["Speaking..."],
            image: nil,
            repeats: true
        )
    }

    private func buildErrorState() -> CPVoiceControlState {
        return CPVoiceControlState(
            identifier: VoiceState.error.rawValue,
            titleVariants: [statusText],
            image: nil,
            repeats: false
        )
    }

    private func activateState(_ state: VoiceState) {
        voiceTemplate?.activateVoiceControlState(
            withIdentifier: state.rawValue
        )
    }

    private func rebuildStates() {
        // CPVoiceControlTemplate doesn't support live state updates,
        // so we recreate and push it as root via the callback.
        guard voiceTemplate != nil else { return }
        let template = buildTemplate()
        activateState(currentState)
        onTemplateRebuild?(template)
    }

    /// Builds a new CPVoiceControlTemplate with bar buttons attached.
    private func buildTemplate() -> CPVoiceControlTemplate {
        let template = CPVoiceControlTemplate(
            voiceControlStates: buildVoiceControlStates()
        )
        voiceTemplate = template

        let micButton = CPBarButton(title: "Listen") { [weak self] _ in
            guard let self else { return }
            switch self.currentState {
            case .idle, .error:
                self.handleStartListening()
            case .listening:
                self.handleStopListening()
            case .processing, .speaking:
                self.handleCancel()
            }
        }

        let agentButton = CPBarButton(title: "Agent") { [weak self] _ in
            self?.handleSwitchAgent()
        }

        template.leadingNavigationBarButtons = [micButton]
        template.trailingNavigationBarButtons = [agentButton]

        return template
    }

    // MARK: - User actions (CarPlay -> Flutter)

    /// Called when the user taps the voice control template to start listening.
    func handleStartListening() {
        guard currentState == .idle || currentState == .error else { return }
        channelHandler?.sendEvent(type: "startListening")
    }

    /// Called when the user taps during listening to stop.
    func handleStopListening() {
        guard currentState == .listening else { return }
        channelHandler?.sendEvent(type: "stopListening")
    }

    /// Called when the user taps during speaking/processing to cancel.
    func handleCancel() {
        guard currentState == .processing || currentState == .speaking else {
            return
        }
        channelHandler?.sendEvent(type: "cancel")
    }

    /// Cycles to the next agent and notifies Flutter.
    func handleSwitchAgent() {
        guard !agents.isEmpty else { return }

        let currentIndex = agents.firstIndex(where: {
            $0.id == selectedAgentId
        }) ?? -1
        let nextIndex = (currentIndex + 1) % agents.count
        let nextAgent = agents[nextIndex]

        selectedAgentId = nextAgent.id
        channelHandler?.sendEvent(
            type: "switchAgent",
            data: ["agentId": nextAgent.id, "agentName": nextAgent.name]
        )
    }

    // MARK: - Helpers

    private func currentAgentName() -> String? {
        if let id = selectedAgentId {
            return agents.first(where: { $0.id == id })?.name
        }
        return agents.first(where: { $0.isDefault })?.name
    }
}
