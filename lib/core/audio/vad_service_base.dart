import 'dart:typed_data';

import '../../shared/models/vad_event.dart';
import 'vad_service.dart' show VadState;

/// Platform-agnostic interface for voice activity detection.
///
/// [VadService] (Silero) and [EnergyVadService] (energy-based fallback)
/// both implement this contract so [VoicePipeline] can work with either.
abstract class VadServiceBase {
  /// Stream of state transitions (idle -> listening -> speechDetected -> ...).
  Stream<VadState> get stateChanges;

  /// Stream of structured speech events (start / end / error).
  Stream<VadEvent> get events;

  /// Current VAD state.
  VadState get state;

  /// Prepare the underlying detection engine.
  Future<void> initialize();

  /// Begin listening for voice activity.
  ///
  /// Optionally pass [audioStream] to feed audio from an external source
  /// (e.g. for testing) instead of the default recorder.
  Future<void> startListening({Stream<Uint8List>? audioStream});

  /// Stop listening and release audio resources.
  Future<void> stopListening();

  /// Release all resources. The service cannot be reused after this call.
  void dispose();
}
