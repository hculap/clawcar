import 'dart:async';
import 'dart:typed_data';

import 'package:vad/vad.dart';

import '../../shared/models/vad_event.dart' as app;
import 'vad_config.dart';

/// Current state of the VAD pipeline.
enum VadState { idle, listening, speechDetected, speechEnded }

/// Voice Activity Detection service wrapping the Silero VAD model.
///
/// Manages a [VadHandler] lifecycle and translates low-level VAD callbacks
/// into typed [VadEvent] and [VadState] streams consumed by the UI and
/// gateway layers.
///
/// The handler owns its own [AudioRecorder] — this service does not depend
/// on [AudioRecorderService] (which feeds raw PCM to the gateway).
class VadService {
  VadService({VadConfig config = const VadConfig()}) : _config = config;

  final VadConfig _config;
  VadHandler? _handler;

  final _stateController = StreamController<VadState>.broadcast();
  final _eventController = StreamController<app.VadEvent>.broadcast();

  VadState _state = VadState.idle;
  DateTime? _speechStartedAt;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Stream of state transitions (idle → listening → speechDetected → …).
  Stream<VadState> get stateChanges => _stateController.stream;

  /// Stream of structured speech events (start / end with audio).
  Stream<app.VadEvent> get events => _eventController.stream;

  /// Current VAD state.
  VadState get state => _state;

  /// Active configuration snapshot.
  VadConfig get config => _config;

  /// Create the underlying Silero handler. Call once before [startListening].
  Future<void> initialize() async {
    _handler = VadHandler.create();
    _subscribeToHandler();
  }

  /// Begin listening for voice activity using configured thresholds.
  ///
  /// Optionally pass [audioStream] to feed audio from an external source
  /// (e.g. for testing) instead of the built-in microphone recorder.
  Future<void> startListening({Stream<Uint8List>? audioStream}) async {
    final handler = _requireHandler();

    await handler.startListening(
      positiveSpeechThreshold: _config.positiveSpeechThreshold,
      negativeSpeechThreshold: _config.negativeSpeechThreshold,
      minSpeechFrames: _config.minSpeechFrames,
      redemptionFrames: _config.redemptionFrames,
      preSpeechPadFrames: _config.preSpeechPadFrames,
      audioStream: audioStream,
    );

    _setState(VadState.listening);
  }

  /// Stop listening and release audio resources.
  Future<void> stopListening() async {
    await _handler?.stopListening();
    _speechStartedAt = null;
    _setState(VadState.idle);
  }

  /// Release all resources. The service cannot be reused after this call.
  void dispose() {
    _handler?.dispose();
    _handler = null;
    _speechStartedAt = null;
    _stateController.close();
    _eventController.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  VadHandler _requireHandler() {
    final handler = _handler;
    if (handler == null) {
      throw StateError(
        'VadService not initialized — call initialize() first',
      );
    }
    return handler;
  }

  void _subscribeToHandler() {
    final handler = _requireHandler();

    handler.onRealSpeechStart.listen((_) {
      final now = DateTime.now();
      _speechStartedAt = now;
      _eventController.add(app.VadEvent.speechStart(timestamp: now));
      _setState(VadState.speechDetected);
    });

    handler.onSpeechEnd.listen((audioData) {
      final now = DateTime.now();
      final duration = _speechStartedAt != null
          ? now.difference(_speechStartedAt!)
          : Duration.zero;

      _eventController.add(
        app.VadEvent.speechEnd(
          timestamp: now,
          audioData: audioData,
          speechDuration: duration,
        ),
      );
      _speechStartedAt = null;
      _setState(VadState.speechEnded);

      // Auto-transition back to listening so the next utterance is caught.
      _setState(VadState.listening);
    });

    handler.onVADMisfire.listen((_) {
      // False positive — revert to listening without emitting a speech event.
      if (_state == VadState.speechDetected) {
        _speechStartedAt = null;
        _setState(VadState.listening);
      }
    });

    handler.onError.listen((error) {
      _speechStartedAt = null;
      _setState(VadState.idle);
    });
  }

  void _setState(VadState next) {
    if (_state == next) return;
    _state = next;
    _stateController.add(next);
  }
}
