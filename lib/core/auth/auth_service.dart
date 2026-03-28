import 'dart:async';

import '../../shared/models/auth_models.dart';
import '../gateway/gateway_client.dart';
import '../gateway/gateway_protocol.dart';
import 'credential_store.dart';
import 'device_identity_service.dart';

/// Orchestrates device authentication and pairing with gateways.
///
/// Supports two auth methods:
/// 1. **Signed auth** — Ed25519-signed payload (primary, requires pairing).
/// 2. **Token auth** — Simple bearer token (alternative, no pairing needed).
class AuthService {
  final DeviceIdentityService _identityService;
  final CredentialStore _store;

  AuthService({
    required DeviceIdentityService identityService,
    required CredentialStore store,
  })  : _identityService = identityService,
        _store = store;

  final _pairingStateController =
      StreamController<PairingState>.broadcast();

  PairingState _pairingState = const PairingState.idle();

  PairingState get pairingState => _pairingState;
  Stream<PairingState> get pairingStateChanges =>
      _pairingStateController.stream;

  /// Builds the auth params for the gateway connect handshake.
  ///
  /// Returns a map suitable for inclusion in the `connect` request params.
  /// Checks for stored credentials first, falls back to signed auth.
  Future<Map<String, dynamic>> buildAuthParams({
    required String gatewayHost,
  }) async {
    final credentials = await _store.getGatewayCredentials(gatewayHost);

    if (credentials != null && credentials.method == AuthMethod.token) {
      return _buildTokenAuthParams(credentials);
    }

    return _buildSignedAuthParams();
  }

  /// Builds auth params using a pre-configured token.
  Future<Map<String, dynamic>> authenticateWithToken({
    required String gatewayHost,
    required String token,
  }) async {
    final credentials = GatewayCredentials(
      gatewayHost: gatewayHost,
      method: AuthMethod.token,
      token: token,
      paired: true,
      lastAuthAt: DateTime.now(),
    );
    await _store.setGatewayCredentials(credentials);

    return _buildTokenAuthParams(credentials);
  }

  /// Initiates the pairing code flow for a new device.
  ///
  /// 1. Sends `device.pair.request` to the gateway with the device's public key.
  /// 2. Gateway displays a pairing code to the user.
  /// 3. User enters the code via [submitPairingCode].
  Future<void> startPairing({
    required GatewayClient client,
    required String gatewayHost,
  }) async {
    _setPairingState(PairingState.awaitingCode(gatewayHost: gatewayHost));

    try {
      final identity = await _identityService.getOrCreateIdentity();

      final response = await client.send(
        GatewayRequest(
          method: 'device.pair.request',
          params: {
            'deviceId': identity.deviceId,
            'publicKey': identity.publicKey,
          },
        ),
      );

      if (!response.ok) {
        _setPairingState(PairingState.failed(
          gatewayHost: gatewayHost,
          error: response.error?.message ?? 'Pairing request rejected',
        ));
      }
    } catch (e) {
      _setPairingState(PairingState.failed(
        gatewayHost: gatewayHost,
        error: 'Failed to start pairing: $e',
      ));
    }
  }

  /// Submits the pairing code entered by the user.
  ///
  /// If the gateway accepts, stores signed-auth credentials for future use.
  Future<bool> submitPairingCode({
    required GatewayClient client,
    required String gatewayHost,
    required String code,
  }) async {
    _setPairingState(PairingState.verifying(gatewayHost: gatewayHost));

    try {
      final identity = await _identityService.getOrCreateIdentity();

      final response = await client.send(
        GatewayRequest(
          method: 'device.pair.confirm',
          params: {
            'deviceId': identity.deviceId,
            'code': code,
          },
        ),
      );

      if (response.ok) {
        final credentials = GatewayCredentials(
          gatewayHost: gatewayHost,
          method: AuthMethod.signed,
          paired: true,
          lastAuthAt: DateTime.now(),
        );
        await _store.setGatewayCredentials(credentials);
        _setPairingState(PairingState.completed(gatewayHost: gatewayHost));
        return true;
      }

      _setPairingState(PairingState.failed(
        gatewayHost: gatewayHost,
        error: response.error?.message ?? 'Invalid pairing code',
      ));
      return false;
    } catch (e) {
      _setPairingState(PairingState.failed(
        gatewayHost: gatewayHost,
        error: 'Pairing verification failed: $e',
      ));
      return false;
    }
  }

  /// Checks whether the device has stored credentials for a gateway.
  Future<bool> hasCredentials(String gatewayHost) async {
    final credentials = await _store.getGatewayCredentials(gatewayHost);
    return credentials != null && credentials.paired;
  }

  /// Returns the current device ID (SHA-256 of public key).
  Future<String> getDeviceId() async {
    final identity = await _identityService.getOrCreateIdentity();
    return identity.deviceId;
  }

  /// Clears all stored credentials for a gateway.
  Future<void> clearCredentials(String gatewayHost) async {
    await _store.deleteGatewayCredentials(gatewayHost);
  }

  /// Resets device identity and all credentials.
  Future<void> resetDevice() async {
    await _store.deleteAll();
    _identityService.clearCache();
  }

  void dispose() {
    _pairingStateController.close();
  }

  // -- Private helpers --

  Map<String, dynamic> _buildTokenAuthParams(
    GatewayCredentials credentials,
  ) {
    return {
      'auth': {'token': credentials.token},
    };
  }

  Future<Map<String, dynamic>> _buildSignedAuthParams() async {
    final identity = await _identityService.getOrCreateIdentity();
    final payload = await _identityService.signAuthPayload(
      identity: identity,
    );

    return {
      'auth': {
        'type': 'signed',
        'payload': payload.toJson(),
      },
      'device': {
        'id': identity.deviceId,
        'publicKey': identity.publicKey,
      },
    };
  }

  void _setPairingState(PairingState state) {
    _pairingState = state;
    _pairingStateController.add(state);
  }
}
