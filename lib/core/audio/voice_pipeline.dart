import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../shared/models/vad_event.dart';
import '../gateway/gateway_client.dart';
import '../gateway/gateway_protocol.dart';
import 'audio_player_service.dart';
import 'audio_recorder.dart';
import 'vad_service.dart' show VadState;
import 'vad_service_base.dart';

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
  final VadServiceBase _vad;
  final AudioPlayerBase _player;
  final AudioRecorderBase _recorder;

  final _stateController = StreamController<PipelineState>.broadcast();
  final _errorController = StreamController<VoicePipelineError>.broadcast();

  PipelineState _state = PipelineState.idle;
  StreamSubscription<VadSpeechEnd>? _speechSub;
  StreamSubscription<GatewayEvent>? _eventSub;
  StreamSubscription<dynamic>? _playerSub;
  StreamSubscription<Uint8List>? _audioBufferSub;
  final List<Uint8List> _audioBuffer = [];
  bool _disposed = false;

  VoicePipeline({
    required GatewayClient gateway,
    required VadServiceBase vad,
    required AudioPlayerBase player,
    required AudioRecorderBase recorder,
  })  : _gateway = gateway,
        _vad = vad,
        _player = player,
        _recorder = recorder;

  PipelineState get state => _state;
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

    _audioBuffer.clear();
    _audioBufferSub?.cancel();

    _speechSub?.cancel();
    _speechSub = _vad.events
        .where((e) => e is VadSpeechEnd)
        .cast<VadSpeechEnd>()
        .listen((event) => _onSpeechEnd(event.audioData));

    _audioBufferSub = _recorder.audioStream.listen(
      (chunk) => _audioBuffer.add(chunk),
    );

    await _recorder.startRecording();
    await _vad.startListening(audioStream: _recorder.audioStream);
    _setState(PipelineState.listening);
  }

  Future<void> stopListening() async {
    _audioBufferSub?.cancel();
    _audioBufferSub = null;

    await _vad.stopListening();
    await _recorder.stopRecording();

    _speechSub?.cancel();
    _speechSub = null;

    if (_state == PipelineState.listening) {
      final bufferedAudio = _drainAudioBuffer();
      if (bufferedAudio.isNotEmpty) {
        _setState(PipelineState.processing);
        try {
          await _gateway.sendAudio(bufferedAudio);
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
      } else {
        _setState(PipelineState.idle);
      }
    }
  }

  Uint8List _drainAudioBuffer() {
    if (_audioBuffer.isEmpty) return Uint8List(0);

    final totalLength =
        _audioBuffer.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final combined = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in _audioBuffer) {
      combined.setAll(offset, chunk);
      offset += chunk.length;
    }
    _audioBuffer.clear();
    return combined;
  }

  Future<void> cancel() async {
    _audioBufferSub?.cancel();
    _audioBufferSub = null;
    _audioBuffer.clear();

    await _player.stop();
    await _vad.stopListening();
    await _recorder.stopRecording();

    _speechSub?.cancel();
    _speechSub = null;
    _setState(PipelineState.idle);
  }

  void _listenToGatewayEvents() {
    _eventSub = _gateway.events.listen(_onGatewayEvent);
  }

  void _listenToPlayerState() {
    _playerSub = _player.playerState.listen((playerState) {
      if (_state == PipelineState.speaking && !_player.isPlaying) {
        _setState(PipelineState.idle);
      }
    });
  }

  Future<void> _onSpeechEnd(List<double> floatSamples) async {
    if (_disposed) return;

    _audioBufferSub?.cancel();
    _audioBufferSub = null;
    _audioBuffer.clear();

    await _vad.stopListening();
    await _recorder.stopRecording();
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
        _setState(PipelineState.idle);
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
    _audioBufferSub?.cancel();
    _audioBuffer.clear();
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
