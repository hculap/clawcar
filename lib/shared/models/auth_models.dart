import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_models.freezed.dart';
part 'auth_models.g.dart';

/// Authentication method used to connect to a gateway.
enum AuthMethod {
  /// Ed25519 signed payload (device keypair).
  signed,

  /// Simple bearer token.
  token,

  /// Device is not yet paired — needs pairing code.
  unpaired,
}

/// Persisted device identity derived from an Ed25519 keypair.
@freezed
abstract class DeviceIdentity with _$DeviceIdentity {
  const factory DeviceIdentity({
    /// SHA-256 hex digest of the Ed25519 public key.
    required String deviceId,

    /// Base64-encoded Ed25519 public key (32 bytes).
    required String publicKey,

    /// Base64-encoded Ed25519 private key (32 bytes seed).
    required String privateKey,

    /// ISO-8601 timestamp of when the keypair was generated.
    required DateTime createdAt,
  }) = _DeviceIdentity;

  factory DeviceIdentity.fromJson(Map<String, dynamic> json) =>
      _$DeviceIdentityFromJson(json);
}

/// Stored credentials for a specific gateway.
@freezed
abstract class GatewayCredentials with _$GatewayCredentials {
  const factory GatewayCredentials({
    /// Gateway host this credential is scoped to.
    required String gatewayHost,

    /// Auth method for this gateway.
    required AuthMethod method,

    /// Bearer token (when method == token).
    String? token,

    /// Whether pairing has been completed with this gateway.
    @Default(false) bool paired,

    /// ISO-8601 timestamp of last successful auth.
    DateTime? lastAuthAt,
  }) = _GatewayCredentials;

  factory GatewayCredentials.fromJson(Map<String, dynamic> json) =>
      _$GatewayCredentialsFromJson(json);
}

/// Current state of the pairing flow.
@freezed
abstract class PairingState with _$PairingState {
  /// Idle — no pairing in progress.
  const factory PairingState.idle() = PairingIdle;

  /// Waiting for user to enter pairing code shown on gateway.
  const factory PairingState.awaitingCode({
    required String gatewayHost,
  }) = PairingAwaitingCode;

  /// Pairing code submitted, waiting for gateway confirmation.
  const factory PairingState.verifying({
    required String gatewayHost,
  }) = PairingVerifying;

  /// Pairing succeeded.
  const factory PairingState.completed({
    required String gatewayHost,
  }) = PairingCompleted;

  /// Pairing failed.
  const factory PairingState.failed({
    required String gatewayHost,
    required String error,
  }) = PairingFailed;

  factory PairingState.fromJson(Map<String, dynamic> json) =>
      _$PairingStateFromJson(json);
}

/// Signed auth payload v1 sent during gateway connect handshake.
@freezed
abstract class AuthPayloadV1 with _$AuthPayloadV1 {
  const factory AuthPayloadV1({
    /// Always 1.
    @Default(1) int version,

    /// Device ID (SHA-256 of public key).
    required String deviceId,

    /// Base64-encoded Ed25519 public key.
    required String publicKey,

    /// Unix timestamp (seconds) when this payload was created.
    required int timestamp,

    /// Base64-encoded Ed25519 signature of the canonical payload.
    required String signature,
  }) = _AuthPayloadV1;

  factory AuthPayloadV1.fromJson(Map<String, dynamic> json) =>
      _$AuthPayloadV1FromJson(json);
}
