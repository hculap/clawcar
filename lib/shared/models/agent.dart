import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent.freezed.dart';
part 'agent.g.dart';

@freezed
abstract class Agent with _$Agent {
  const factory Agent({
    required String id,
    required String name,
    String? description,
    String? model,
    @Default(false) bool isDefault,
  }) = _Agent;

  factory Agent.fromJson(Map<String, dynamic> json) => _$AgentFromJson(json);
}
