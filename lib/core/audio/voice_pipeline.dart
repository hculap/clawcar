import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../shared/models/vad_event.dart';
import '../gateway/gateway_client.dart';
import 'audio_player_service.dart';
import 'audio_recorder.dart';
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

/// Voice pipeline: record → STT (via gateway chat) → TTS → playback.
///
/// Flow:
/// 1. Record audio, detect speech end via VAD
/// 2. Send recorded audio as PCM16 text to gateway via `chat.send`
///    (gateway handles STT internally if configured, otherwise we send
///    the audio data for processing)
/// 3. Receive assistant response text via streaming chat events
/// 4. Convert response to speech via `tts.convert`
/// 5. Play the TTS audio file
class VoicePipeline {
  final GatewayClient _gateway;
  final VadServiceBase _vad;
  final AudioPlayerBase _player;
  final AudioRecorderBase _recorder;

  final _stateController = StreamController<PipelineState>.broadcast();
  final _errorController = StreamController<VoicePipelineError>.broadcast();

  PipelineState _state = PipelineState.idle;
  bool continuousMode = false;
  StreamSubscription<VadSpeechEnd>? _speechSub;
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
  }

  Future<void> startListening() async {
    if (_state == PipelineState.processing ||
        _state == PipelineState.speaking) {
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
      (chunk) {
        _audioBuffer.add(chunk);
      },
      onError: (Object e) {
        _emitError(VoicePipelineError(
          code: 'recorder_error',
          message: 'Audio recording error: $e',
        ));
      },
    );

    await _recorder.startRecording();
    await _vad.startListening(audioStream: _recorder.audioStream);
    _setState(PipelineState.listening);
  }

  Future<void> stopListening() async {
    if (_state != PipelineState.listening) return;

    _audioBufferSub?.cancel();
    _audioBufferSub = null;

    await _vad.stopListening();
    await _recorder.stopRecording();

    _speechSub?.cancel();
    _speechSub = null;

    if (_state == PipelineState.listening) {
      final bufferedAudio = _drainAudioBuffer();
      if (bufferedAudio.length >= 16000) {
        await _processAudio(bufferedAudio);
      } else if (bufferedAudio.isEmpty) {
        _emitError(const VoicePipelineError(
          code: 'no_audio',
          message: 'No audio captured. Check microphone permissions.',
        ));
        _setState(PipelineState.idle);
      } else {
        _emitError(const VoicePipelineError(
          code: 'too_short',
          message: 'Recording too short. Hold longer while speaking.',
        ));
        _setState(PipelineState.idle);
      }
    }
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

  Future<void> _onSpeechEnd(List<double> floatSamples) async {
    if (_disposed) return;

    _audioBufferSub?.cancel();
    _audioBufferSub = null;
    _audioBuffer.clear();

    await _vad.stopListening();
    await _recorder.stopRecording();

    final pcmBytes = floatToPcm16(floatSamples);
    await _processAudio(pcmBytes);
  }

  /// Core processing: send text via chat → get response → TTS → play.
  ///
  /// For now, sends a placeholder text message since the gateway
  /// doesn't have a direct STT endpoint. The recorded audio is
  /// available for future STT integration.
  Future<void> _processAudio(Uint8List audioData) async {
    _setState(PipelineState.processing);

    try {
      // Send chat message to get agent response
      // TODO: Integrate client-side STT (e.g., Whisper) to transcribe
      // audioData before sending. For now, send audio length as context.
      final durationSecs = (audioData.length / 32000).toStringAsFixed(1);
      final responseText = await _gateway.sendChat(
        '[Voice message: ${durationSecs}s of audio received]',
      );

      if (_disposed || responseText.isEmpty) {
        _setState(PipelineState.idle);
        return;
      }

      // Convert response to speech
      final audioPath = await _gateway.convertTts(responseText);

      if (_disposed) return;

      // Read and play the TTS audio file
      final audioFile = File(audioPath);
      if (!audioFile.existsSync()) {
        _emitError(const VoicePipelineError(
          code: 'tts_file_missing',
          message: 'TTS audio file not found',
        ));
        _setState(PipelineState.idle);
        return;
      }

      final audioBytes = await audioFile.readAsBytes();
      _setState(PipelineState.speaking);
      await _player.playAudioBytes(audioBytes, mimeType: 'audio/mpeg');

      if (!_disposed) {
        if (continuousMode) {
          await startListening();
        } else {
          _setState(PipelineState.idle);
        }
      }
    } catch (e) {
      _emitError(VoicePipelineError(
        code: 'pipeline_error',
        message: 'Voice processing failed: $e',
        retryable: true,
      ));
      _setState(PipelineState.error);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!_disposed) {
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
