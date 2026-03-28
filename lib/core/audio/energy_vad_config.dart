import 'package:freezed_annotation/freezed_annotation.dart';

part 'energy_vad_config.freezed.dart';
part 'energy_vad_config.g.dart';

/// Configuration for the energy-based VAD fallback (desktop platforms).
///
/// Uses RMS (root mean square) energy of PCM16 audio frames to detect
/// speech start and end, with timeouts as safety nets.
///
/// - [energyThreshold]: RMS energy above which a frame is considered speech.
///   Range 0.0–1.0 on normalized float samples. Default 0.02 works for
///   typical desktop microphones.
/// - [speechStartFrames]: Consecutive frames above [energyThreshold] required
///   before emitting speechStart. Prevents transient noise triggers.
/// - [silenceFrames]: Consecutive frames below [energyThreshold] after speech
///   was detected before emitting speechEnd.
/// - [maxRecordingDuration]: Hard cap on recording length. Forces speechEnd
///   even if silence is never detected.
/// - [preSpeechPadFrames]: Frames of audio retained before speech onset.
@freezed
abstract class EnergyVadConfig with _$EnergyVadConfig {
  const factory EnergyVadConfig({
    @Default(0.02) double energyThreshold,
    @Default(4) int speechStartFrames,
    @Default(20) int silenceFrames,
    @Default(Duration(seconds: 30)) Duration maxRecordingDuration,
    @Default(3) int preSpeechPadFrames,
  }) = _EnergyVadConfig;

  factory EnergyVadConfig.fromJson(Map<String, dynamic> json) =>
      _$EnergyVadConfigFromJson(json);
}
