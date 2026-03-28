import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../shared/models/vad_event.dart';
import 'audio_recorder.dart';
import 'energy_vad_config.dart';
import 'vad_service.dart' show VadState;
import 'vad_service_base.dart';

/// Energy-based voice activity detection for desktop platforms.
///
/// The Silero VAD (`vad` package) does not reliably fire speechEnd on macOS.
/// This service uses RMS energy of PCM16 audio frames to detect speech
/// boundaries, with a hard [maxRecordingDuration] safety timeout.
///
/// Audio is captured via [AudioRecorderService] (PCM16, 16 kHz, mono).
/// Accumulated float samples are delivered in [VadEvent.speechEnd] so the
/// downstream [VoicePipeline] can convert them identically to Silero output.
class EnergyVadService implements VadServiceBase {
  EnergyVadService({
    required AudioRecorderService recorder,
    EnergyVadConfig config = const EnergyVadConfig(),
  })  : _recorder = recorder,
        _config = config;

  final AudioRecorderService _recorder;
  final EnergyVadConfig _config;

  final _stateController = StreamController<VadState>.broadcast();
  final _eventController = StreamController<VadEvent>.broadcast();

  VadState _state = VadState.idle;
  bool _initialized = false;

  // Listening session state — rebuilt on each startListening call.
  StreamSubscription<Uint8List>? _audioSub;
  Timer? _maxDurationTimer;
  List<List<double>> _preSpeechBuffer = [];
  List<double> _speechBuffer = [];
  int _consecutiveSpeechFrames = 0;
  int _consecutiveSilenceFrames = 0;
  DateTime? _speechStartedAt;

  @override
  Stream<VadState> get stateChanges => _stateController.stream;

  @override
  Stream<VadEvent> get events => _eventController.stream;

  @override
  VadState get state => _state;

  /// Active configuration snapshot.
  EnergyVadConfig get config => _config;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> startListening({Stream<Uint8List>? audioStream}) async {
    if (!_initialized) {
      throw StateError(
        'EnergyVadService not initialized — call initialize() first',
      );
    }

    await _stopAudioCapture();
    _resetSessionState();

    final source = audioStream ?? _recorder.audioStream;

    if (audioStream == null) {
      await _recorder.startRecording();
    }

    _audioSub = source.listen(
      _onAudioChunk,
      onError: (Object error) {
        _eventController.add(
          VadEvent.error(timestamp: DateTime.now(), message: '$error'),
        );
        _setState(VadState.idle);
      },
    );

    _maxDurationTimer = Timer(_config.maxRecordingDuration, _forceEnd);
    _setState(VadState.listening);
  }

  @override
  Future<void> stopListening() async {
    await _stopAudioCapture();
    _speechStartedAt = null;
    _setState(VadState.idle);
  }

  @override
  void dispose() {
    _audioSub?.cancel();
    _maxDurationTimer?.cancel();
    _recorder.stopRecording();
    _stateController.close();
    _eventController.close();
  }

  // ---------------------------------------------------------------------------
  // Audio processing
  // ---------------------------------------------------------------------------

  void _onAudioChunk(Uint8List pcm16Bytes) {
    final samples = _pcm16ToFloat(pcm16Bytes);
    final energy = _rmsEnergy(samples);
    final isSpeech = energy >= _config.energyThreshold;

    if (_state == VadState.listening) {
      // Pre-speech: maintain a rolling buffer of recent frames.
      _preSpeechBuffer = [
        ..._preSpeechBuffer,
        samples,
      ];
      if (_preSpeechBuffer.length > _config.preSpeechPadFrames) {
        _preSpeechBuffer = _preSpeechBuffer
            .sublist(_preSpeechBuffer.length - _config.preSpeechPadFrames);
      }

      if (isSpeech) {
        _consecutiveSpeechFrames++;
        if (_consecutiveSpeechFrames >= _config.speechStartFrames) {
          _onSpeechStart(samples);
        }
      } else {
        _consecutiveSpeechFrames = 0;
      }
    } else if (_state == VadState.speechDetected) {
      _speechBuffer = [..._speechBuffer, ...samples];

      if (!isSpeech) {
        _consecutiveSilenceFrames++;
        if (_consecutiveSilenceFrames >= _config.silenceFrames) {
          _emitSpeechEnd();
        }
      } else {
        _consecutiveSilenceFrames = 0;
      }
    }
  }

  void _onSpeechStart(List<double> currentFrame) {
    _speechStartedAt = DateTime.now();

    // Prepend the pre-speech pad so the utterance beginning isn't clipped.
    final padSamples = _preSpeechBuffer.expand((f) => f).toList();
    _speechBuffer = [...padSamples, ...currentFrame];
    _preSpeechBuffer = [];

    _eventController.add(VadEvent.speechStart(timestamp: _speechStartedAt!));
    _setState(VadState.speechDetected);
  }

  void _emitSpeechEnd() {
    final now = DateTime.now();
    final duration = _speechStartedAt != null
        ? now.difference(_speechStartedAt!)
        : Duration.zero;

    _eventController.add(
      VadEvent.speechEnd(
        timestamp: now,
        audioData: List<double>.unmodifiable(_speechBuffer),
        speechDuration: duration,
      ),
    );
    _speechStartedAt = null;
    _setState(VadState.speechEnded);
  }

  /// Hard timeout: emit whatever audio we have so the pipeline isn't stuck.
  void _forceEnd() {
    if (_state == VadState.speechDetected) {
      _emitSpeechEnd();
    } else if (_state == VadState.listening) {
      // No speech detected at all within the timeout — emit error.
      _eventController.add(
        VadEvent.error(
          timestamp: DateTime.now(),
          message: 'Max recording duration reached with no speech detected',
        ),
      );
      _setState(VadState.idle);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _resetSessionState() {
    _preSpeechBuffer = [];
    _speechBuffer = [];
    _consecutiveSpeechFrames = 0;
    _consecutiveSilenceFrames = 0;
    _speechStartedAt = null;
  }

  Future<void> _stopAudioCapture() async {
    _audioSub?.cancel();
    _audioSub = null;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    await _recorder.stopRecording();
  }

  void _setState(VadState next) {
    if (_state == next) return;
    _state = next;
    _stateController.add(next);
  }
}

/// Convert PCM16 little-endian bytes to normalized float samples [-1.0, 1.0].
List<double> _pcm16ToFloat(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final sampleCount = bytes.length ~/ 2;
  final samples = List<double>.filled(sampleCount, 0.0);
  for (var i = 0; i < sampleCount; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}

/// Root mean square energy of a frame of float samples.
double _rmsEnergy(List<double> samples) {
  if (samples.isEmpty) return 0.0;
  var sumSquares = 0.0;
  for (final s in samples) {
    sumSquares += s * s;
  }
  return math.sqrt(sumSquares / samples.length);
}
