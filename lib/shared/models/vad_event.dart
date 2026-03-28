import 'package:freezed_annotation/freezed_annotation.dart';

part 'vad_event.freezed.dart';

/// Events emitted by the VAD service during voice activity detection.
///
/// [speechStart] fires when validated speech is detected (after
/// [minSpeechFrames] consecutive frames above [positiveSpeechThreshold]).
///
/// [speechEnd] fires when speech ends (after [redemptionFrames] consecutive
/// frames below [negativeSpeechThreshold]), carrying the accumulated audio
/// data including pre-speech padding.
///
/// [error] fires when the VAD engine encounters a fault.
@freezed
sealed class VadEvent with _$VadEvent {
  const factory VadEvent.speechStart({
    required DateTime timestamp,
  }) = VadSpeechStart;

  const factory VadEvent.speechEnd({
    required DateTime timestamp,
    required List<double> audioData,
    required Duration speechDuration,
  }) = VadSpeechEnd;

  const factory VadEvent.error({
    required DateTime timestamp,
    required String message,
  }) = VadError;
}
