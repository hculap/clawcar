import 'package:freezed_annotation/freezed_annotation.dart';

part 'gateway_config.freezed.dart';
part 'gateway_config.g.dart';

@freezed
abstract class GatewayConfig with _$GatewayConfig {
  const factory GatewayConfig({
    required String host,
    required int port,
    required String displayName,
    @Default(false) bool useTls,
    String? tlsSha256,
    String? tailnetDns,
    String? authToken,
  }) = _GatewayConfig;

  factory GatewayConfig.fromJson(Map<String, dynamic> json) =>
      _$GatewayConfigFromJson(json);
}
