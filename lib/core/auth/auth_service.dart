import 'dart:async';

import '../../shared/models/auth_models.dart';
import '../gateway/gateway_client.dart';
import 'credential_store.dart';
import 'device_identity_service.dart';

/// Orchestrates device authentication and pairing with gateways.
///
/// The gateway supports implicit device pairing: including a signed
/// `device` object alongside a valid `auth.token` in the connect
/// handshake automatically registers the device and returns a
/// `deviceToken` for future signed-only connects.
///
/// Auth modes:
/// 1. **Token only** — `{'auth': {'token': '...'}}`  (limited scopes)
/// 2. **Device + token** — device identity signed + token (first pair, full scopes)
/// 3. **Device + deviceToken** — signed + stored token (subsequent connects)
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

  /// Builds auth params for the gateway connect handshake.
  ///
  /// If a [nonce] from `connect.challenge` is provided, includes a signed
  /// device identity for full operator scopes. Otherwise falls back to
  /// token-only auth.
  ///
  /// The returned map is merged into `connect.params`.
  Future<Map<String, dynamic>> buildAuthParams({
    required String gatewayHost,
    String? nonce,
  }) async {
    final credentials = await _store.getGatewayCredentials(gatewayHost);
    final identity = await _identityService.getOrCreateIdentity();

    final params = <String, dynamic>{};

    // Auth block
    if (credentials?.deviceToken != null) {
      params['auth'] = {'deviceToken': credentials!.deviceToken};
    } else if (credentials?.token != null) {
      params['auth'] = {'token': credentials!.token};
    }

    // Device identity (signed)
    if (nonce != null) {
      final token = credentials?.deviceToken ?? credentials?.token ?? '';
      params['device'] = await _identityService.buildDeviceParams(
        identity: identity,
        nonce: nonce,
        clientId: 'cli',
        clientMode: 'cli',
        role: 'operator',
        scopes: ['operator.admin', 'operator.read', 'operator.write'],
        token: token,
      );
    }

    return params;
  }

  /// Stores token-only credentials for a gateway.
  Future<Map<String, dynamic>> authenticateWithToken({
    required String gatewayHost,
    required String token,
  }) async {
    final credentials = GatewayCredentials(
      gatewayHost: gatewayHost,
      method: AuthMethod.token,
      token: token,
      paired: false,
      lastAuthAt: DateTime.now(),
    );
    await _store.setGatewayCredentials(credentials);

    return {'auth': {'token': token}};
  }

  /// Initiates device pairing by sending a connect with device identity.
  ///
  /// Flow:
  /// 1. Client connects with token auth (already done by caller)
  /// 2. This method disconnects, reconnects, and sends a connect with
  ///    device identity + token
  /// 3. Gateway auto-pairs the device and returns a deviceToken
  /// 4. Credentials are stored for future signed-only connects
  Future<bool> pairDevice({
    required GatewayClient client,
    required String gatewayHost,
    required String token,
  }) async {
    _setPairingState(PairingState.verifying(gatewayHost: gatewayHost));

    try {
      final identity = await _identityService.getOrCreateIdentity();

      // Disconnect and clear cached auth so connect() doesn't auto-replay
      await client.disconnect(clearAuth: true);

      // Set up nonce listener BEFORE connect (challenge arrives on open)
      final nonceFuture = client.waitForChallengeNonce();
      await client.connect();
      final nonce = await nonceFuture;

      // Build signed device params
      final deviceParams = await _identityService.buildDeviceParams(
        identity: identity,
        nonce: nonce,
        clientId: 'cli',
        clientMode: 'cli',
        role: 'operator',
        scopes: ['operator.admin', 'operator.read', 'operator.write'],
        token: token,
      );

      // Send connect with device identity + token
      final response = await client.sendConnect(
        authParams: {
          'auth': {'token': token},
          'device': deviceParams,
        },
      );

      if (response.ok) {
        // Extract deviceToken from response
        final authData =
            response.payload?['auth'] as Map<String, dynamic>? ?? {};
        final deviceToken = authData['deviceToken'] as String?;

        final credentials = GatewayCredentials(
          gatewayHost: gatewayHost,
          method: AuthMethod.signed,
          token: token,
          deviceToken: deviceToken,
          paired: true,
          lastAuthAt: DateTime.now(),
        );
        await _store.setGatewayCredentials(credentials);

        // Disconnect so the caller's agentsProvider opens a fresh
        // connection with the newly stored signed credentials.
        await client.disconnect();

        _setPairingState(PairingState.completed(gatewayHost: gatewayHost));
        return true;
      }

      final errorMsg = response.error?.message ?? 'Pairing failed';
      _setPairingState(
        PairingState.failed(gatewayHost: gatewayHost, error: errorMsg),
      );
      return false;
    } catch (e) {
      _setPairingState(PairingState.failed(
        gatewayHost: gatewayHost,
        error: 'Pairing failed: $e',
      ));
      return false;
    }
  }

  /// Checks whether the device has stored paired credentials for a gateway.
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

  void _setPairingState(PairingState state) {
    _pairingState = state;
    _pairingStateController.add(state);
  }
}
