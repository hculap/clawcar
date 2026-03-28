import 'dart:async';

import '../../core/audio/voice_pipeline.dart';
import '../../shared/models/agent.dart';
import 'carplay_service.dart';

/// Bridges CarPlay events to the voice pipeline and keeps
/// the native CarPlay UI in sync with pipeline state.
class CarPlayController {
  CarPlayController({
    required CarPlayService service,
    required VoicePipeline Function() pipelineGetter,
    required void Function(String agentId) onAgentSwitch,
  })  : _service = service,
        _pipelineGetter = pipelineGetter,
        _onAgentSwitch = onAgentSwitch;

  final CarPlayService _service;
  final VoicePipeline Function() _pipelineGetter;
  final void Function(String agentId) _onAgentSwitch;

  StreamSubscription<CarPlayEvent>? _eventSub;
  StreamSubscription<PipelineState>? _stateSub;
  bool _disposed = false;

  /// Starts listening to CarPlay events and pipeline state changes.
  void start() {
    _eventSub = _service.events.listen(_handleCarPlayEvent);
  }

  /// Syncs the CarPlay UI when a voice pipeline becomes available.
  void attachPipeline(VoicePipeline pipeline) {
    _stateSub?.cancel();
    _stateSub = pipeline.stateChanges.listen(_syncState);
    _syncState(pipeline.state);
  }

  /// Sends the current agent list to CarPlay.
  Future<void> syncAgents(List<Agent> agents, String? selectedAgentId) async {
    if (_disposed) return;
    await _service.setAgents(agents);
    if (selectedAgentId != null) {
      await _service.setSelectedAgent(selectedAgentId);
    }
  }

  Future<void> _handleCarPlayEvent(CarPlayEvent event) async {
    if (_disposed) return;

    try {
      switch (event.type) {
        case 'startListening':
          await _pipelineGetter().startListening();
        case 'stopListening':
          await _pipelineGetter().stopListening();
        case 'cancel':
          await _pipelineGetter().cancel();
        case 'switchAgent':
          final agentId = event.data?['agentId'] as String?;
          if (agentId != null) {
            _onAgentSwitch(agentId);
          }
        case 'carplayConnected':
          await _syncState(_pipelineGetter().state);
        case 'carplayDisconnected':
          await _stateSub?.cancel();
          _stateSub = null;
      }
    } catch (e) {
      if (_disposed) return;
      await _service.updateStatusText('Error: $e');
      await _service.updateState('error');
    }
  }

  Future<void> _syncState(PipelineState state) async {
    if (_disposed) return;
    await _service.updateState(state.name);
  }

  void dispose() {
    _disposed = true;
    _eventSub?.cancel();
    _stateSub?.cancel();
  }
}
