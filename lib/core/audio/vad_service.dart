import 'dart:async';
import 'dart:typed_data';

import 'package:vad/vad.dart';

import '../../shared/models/vad_event.dart' as app;
import 'vad_config.dart';
import 'vad_service_base.dart';

/// Current state of the VAD pipeline.
enum VadState { idle, listening, speechDetected, speechEnded }

/// Voice Activity Detection service wrapping the Silero VAD model.
///
/// Manages a [VadHandler] lifecycle and translates low-level VAD callbacks
/// into typed [VadEvent] and [VadState] streams consumed by the UI and
/// gateway layers.
///
/// The [VadHandler] owns its own [AudioRecorder] internally — this service
/// does not depend on [AudioRecorderService].

class VadService implements VadServiceBase {
  VadService({VadConfig config = const VadConfig()}) : _config = config;

  final VadConfig _config;
  VadHandler? _handler;
  final List<StreamSubscription<dynamic>> _handlerSubscriptions = [];

  final _stateController = StreamController<VadState>.broadcast();
  final _eventController = StreamController<app.VadEvent>.broadcast();

  VadState _state = VadState.idle;
  DateTime? _speechStartedAt;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Stream of state transitions (idle → listening → speechDetected → …).
  Stream<VadState> get stateChanges => _stateController.stream;

  /// Stream of structured speech events (start / end / error).
  Stream<app.VadEvent> get events => _eventController.stream;

  /// Stream of completed speech audio frames (emitted on each speech-end).
  Stream<List<double>> get speechFrames => _eventController.stream
      .where((e) => e is app.VadSpeechEnd)
      .map((e) => (e as app.VadSpeechEnd).audioData);

  /// Current VAD state.
  VadState get state => _state;

  /// Active configuration snapshot.
  VadConfig get config => _config;

  /// Create the underlying Silero handler. Safe to call multiple times —
  /// subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_handler != null) return;

    _handler = VadHandler.create();
    _subscribeToHandler();
  }

  /// Begin listening for voice activity using configured thresholds.
  ///
  /// Optionally pass [audioStream] to feed audio from an external source
  /// (e.g. for testing) instead of the [VadHandler]'s internal recorder.
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
    _cancelHandlerSubscriptions();
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

  void _cancelHandlerSubscriptions() {
    for (final sub in _handlerSubscriptions) {
      sub.cancel();
    }
    _handlerSubscriptions.clear();
  }

  void _subscribeToHandler() {
    final handler = _requireHandler();

    _handlerSubscriptions.add(
      handler.onRealSpeechStart.listen((_) {
        final now = DateTime.now();
        _speechStartedAt = now;
        _eventController.add(app.VadEvent.speechStart(timestamp: now));
        _setState(VadState.speechDetected);
      }),
    );

    _handlerSubscriptions.add(
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
      }),
    );

    _handlerSubscriptions.add(
      handler.onVADMisfire.listen((_) {
        if (_state == VadState.speechDetected) {
          _speechStartedAt = null;
          _setState(VadState.listening);
        }
      }),
    );

    _handlerSubscriptions.add(
      handler.onError.listen((error) {
        _speechStartedAt = null;
        _eventController.add(
          app.VadEvent.error(
            timestamp: DateTime.now(),
            message: error,
          ),
        );
        _setState(VadState.idle);
      }),
    );
  }

  void _setState(VadState next) {
    if (_state == next) return;
    _state = next;
    _stateController.add(next);
  }
}
