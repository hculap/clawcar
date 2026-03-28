import 'package:freezed_annotation/freezed_annotation.dart';

part 'vad_config.freezed.dart';
part 'vad_config.g.dart';

/// Configuration for the Silero VAD engine.
///
/// Tuned for noisy car environments where false positives from road noise,
/// engine hum, and HVAC must be rejected while still catching natural speech.
///
/// - [positiveSpeechThreshold]: Confidence above which a frame is classified
///   as speech. Higher = fewer false positives but may miss quiet speech.
/// - [negativeSpeechThreshold]: Confidence below which a frame is classified
///   as silence. The gap between positive and negative creates hysteresis.
/// - [minSpeechFrames]: Minimum consecutive speech frames before a
///   [VadEvent.speechStart] is emitted. Prevents short noise bursts.
/// - [redemptionFrames]: Silence frames allowed mid-utterance before ending.
///   Accommodates natural pauses (e.g. "turn left... at the light").
/// - [preSpeechPadFrames]: Frames of audio to retain before speech onset
///   so the beginning of the utterance is not clipped.
@freezed
abstract class VadConfig with _$VadConfig {
  const factory VadConfig({
    @Default(0.8) double positiveSpeechThreshold,
    @Default(0.35) double negativeSpeechThreshold,
    @Default(5) int minSpeechFrames,
    @Default(8) int redemptionFrames,
    @Default(3) int preSpeechPadFrames,
  }) = _VadConfig;

  factory VadConfig.fromJson(Map<String, dynamic> json) =>
      _$VadConfigFromJson(json);
}
