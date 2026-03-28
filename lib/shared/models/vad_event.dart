import 'package:freezed_annotation/freezed_annotation.dart';

part 'vad_event.freezed.dart';

/// Events emitted by the VAD service during voice activity detection.
///
/// [speechStart] fires when speech is first detected (after [minSpeechFrames]
/// consecutive frames above [positiveSpeechThreshold]).
///
/// [speechEnd] fires when speech ends (after [redemptionFrames] consecutive
/// frames below [negativeSpeechThreshold]), carrying the accumulated audio
/// data including pre-speech padding.
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
}
