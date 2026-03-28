import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../gateway/gateway_client.dart';
import '../gateway/gateway_protocol.dart';
import 'audio_player_service.dart';
import 'vad_service.dart';

enum PipelineState { idle, listening, processing, speaking, error }

class VoicePipelineError {
  final String code;
  final String message;
  final bool retryable;

  const VoicePipelineError({
    required this.code,
    required this.message,
    this.retryable = false,
  });
}

class VoicePipeline {
  final GatewayClient _gateway;
  final VadService _vad;
  final AudioPlayerBase _player;

  final _stateController = StreamController<PipelineState>.broadcast();
  final _errorController = StreamController<VoicePipelineError>.broadcast();

  PipelineState _state = PipelineState.idle;
  StreamSubscription<List<double>>? _speechSub;
  StreamSubscription<GatewayEvent>? _eventSub;
  StreamSubscription<dynamic>? _playerSub;
  bool _disposed = false;

  VoicePipeline({
    required GatewayClient gateway,
    required VadService vad,
    required AudioPlayerBase player,
  })  : _gateway = gateway,
        _vad = vad,
        _player = player;

  PipelineState get state => _state;
  bool continuousMode = false;
  Stream<PipelineState> get stateChanges => _stateController.stream;
  Stream<VoicePipelineError> get errors => _errorController.stream;

  Future<void> initialize() async {
    await _vad.initialize();
    _listenToGatewayEvents();
    _listenToPlayerState();
  }

  Future<void> startListening() async {
    if (_state == PipelineState.processing || _state == PipelineState.speaking) {
      return;
    }

    _speechSub?.cancel();
    _speechSub = _vad.speechFrames.listen(_onSpeechEnd);

    await _vad.startListening();
    _setState(PipelineState.listening);
  }

  Future<void> stopListening() async {
    await _vad.stopListening();
    _speechSub?.cancel();
    _speechSub = null;

    if (_state == PipelineState.listening) {
      _setState(PipelineState.idle);
    }
  }

  Future<void> cancel() async {
    continuousMode = false;
    await _player.stop();
    await stopListening();
    _setState(PipelineState.idle);
  }

  void _listenToGatewayEvents() {
    _eventSub = _gateway.events.listen(_onGatewayEvent);
  }

  void _listenToPlayerState() {
    _playerSub = _player.playerState.listen((playerState) {
      if (_state == PipelineState.speaking && !_player.isPlaying) {
        _onPlaybackComplete();
      }
    });
  }

  Future<void> _onSpeechEnd(List<double> floatSamples) async {
    if (_disposed) return;

    await _vad.stopListening();
    _setState(PipelineState.processing);

    try {
      final pcmBytes = floatToPcm16(floatSamples);
      await _gateway.sendAudio(pcmBytes);
    } catch (e) {
      _emitError(
        VoicePipelineError(
          code: 'send_failed',
          message: 'Failed to send audio: $e',
          retryable: true,
        ),
      );
      _setState(PipelineState.error);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!_disposed) {
        _setState(PipelineState.idle);
      }
    }
  }

  Future<void> _onGatewayEvent(GatewayEvent event) async {
    if (_disposed) return;

    switch (event.event) {
      case 'voice.audio':
        await _handleAudioResponse(event.payload);
      case 'voice.error':
        _handleVoiceError(event.payload);
      case _:
        break;
    }
  }

  Future<void> _handleAudioResponse(Map<String, dynamic> payload) async {
    final audioBase64 = payload['audio'] as String?;
    if (audioBase64 == null) {
      _emitError(
        const VoicePipelineError(
          code: 'invalid_response',
          message: 'Gateway response missing audio data',
        ),
      );
      _setState(PipelineState.idle);
      return;
    }

    final audioBytes = Uint8List.fromList(base64Decode(audioBase64));
    final format = payload['format'] as String? ?? 'mp3';
    final mimeType = switch (format) {
      'opus' => 'audio/opus',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      _ => 'audio/mpeg',
    };

    _setState(PipelineState.speaking);

    try {
      await _player.playAudioBytes(audioBytes, mimeType: mimeType);
      if (!_disposed) {
        await _onPlaybackComplete();
      }
    } catch (e) {
      _emitError(
        VoicePipelineError(
          code: 'playback_failed',
          message: 'Failed to play response: $e',
          retryable: true,
        ),
      );
      _setState(PipelineState.error);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!_disposed) {
        _setState(PipelineState.idle);
      }
    }
  }

  Future<void> _onPlaybackComplete() async {
    if (_disposed) return;

    if (continuousMode) {
      try {
        await startListening();
      } catch (e) {
        _emitError(
          VoicePipelineError(
            code: 'continuous_restart_failed',
            message: 'Failed to restart listening: $e',
            retryable: true,
          ),
        );
        continuousMode = false;
        _setState(PipelineState.idle);
      }
      return;
    }

    _setState(PipelineState.idle);
  }

  void _handleVoiceError(Map<String, dynamic> payload) {
    final code = payload['code'] as String? ?? 'unknown';
    final message = payload['message'] as String? ?? 'Unknown voice error';
    final retryable = payload['retryable'] as bool? ?? false;

    _emitError(
      VoicePipelineError(code: code, message: message, retryable: retryable),
    );
    _setState(PipelineState.error);
  }

  void _setState(PipelineState newState) {
    if (_disposed) return;
    _state = newState;
    _stateController.add(newState);
  }

  void _emitError(VoicePipelineError error) {
    if (_disposed) return;
    _errorController.add(error);
  }

  void dispose() {
    _disposed = true;
    _speechSub?.cancel();
    _eventSub?.cancel();
    _playerSub?.cancel();
    _stateController.close();
    _errorController.close();
  }
}

Uint8List floatToPcm16(List<double> samples) {
  final bytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    final intSample = (clamped * 32767).round();
    bytes.setInt16(i * 2, intSample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
