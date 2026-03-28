import 'package:freezed_annotation/freezed_annotation.dart';

part 'session.freezed.dart';
part 'session.g.dart';

@freezed
abstract class VoiceSession with _$VoiceSession {
  const factory VoiceSession({
    required String id,
    required String agentId,
    required DateTime createdAt,
    DateTime? lastActiveAt,
    @Default(VoiceSessionState.idle) VoiceSessionState state,
  }) = _VoiceSession;

  factory VoiceSession.fromJson(Map<String, dynamic> json) =>
      _$VoiceSessionFromJson(json);
}

enum VoiceSessionState { idle, listening, processing, speaking, error }
