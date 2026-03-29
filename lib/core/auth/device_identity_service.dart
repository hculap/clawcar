import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../shared/models/auth_models.dart';
import 'credential_store.dart';

/// Base64url encoding without padding (RFC 4648 §5).
String _base64UrlNoPad(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Manages the Ed25519 device identity: keypair generation, persistence,
/// device ID derivation, and auth payload signing.
///
/// Signs connect payloads using the v2 canonical format expected by the
/// OpenClaw gateway:
/// `v2|{deviceId}|{clientId}|{clientMode}|{role}|{scopes}|{signedAtMs}|{token}|{nonce}`
class DeviceIdentityService {
  DeviceIdentityService({
    required CredentialStore store,
    Ed25519? ed25519,
    Sha256? sha256,
  })  : _store = store,
        _ed25519 = ed25519 ?? Ed25519(),
        _sha256 = sha256 ?? Sha256();

  final CredentialStore _store;
  final Ed25519 _ed25519;
  final Sha256 _sha256;

  DeviceIdentity? _cached;
  Future<DeviceIdentity>? _pendingInit;

  void clearCache() {
    _cached = null;
    _pendingInit = null;
  }

  /// Returns the current device identity, generating one if needed.
  ///
  /// Safe against concurrent callers — only one init runs at a time.
  Future<DeviceIdentity> getOrCreateIdentity() {
    if (_cached != null) return Future.value(_cached!);
    return _pendingInit ??= _initIdentity();
  }

  Future<DeviceIdentity> _initIdentity() async {
    try {
      final stored = await _store.getDeviceIdentity();
      if (stored != null) {
        _cached = stored;
        return stored;
      }

      final identity = await _generateIdentity();
      await _store.setDeviceIdentity(identity);
      _cached = identity;
      return identity;
    } finally {
      _pendingInit = null;
    }
  }

  /// Builds the `device` object for the gateway connect handshake.
  ///
  /// The returned map contains `id`, `publicKey`, `signature`, `signedAt`,
  /// and `nonce` — ready to be included in `connect.params.device`.
  ///
  /// Signs the v2 canonical payload:
  /// `v2|{deviceId}|{clientId}|{clientMode}|{role}|{scopes}|{signedAtMs}|{token}|{nonce}`
  Future<Map<String, dynamic>> buildDeviceParams({
    required DeviceIdentity identity,
    required String nonce,
    required String clientId,
    required String clientMode,
    required String role,
    required List<String> scopes,
    String token = '',
  }) async {
    final signedAt = DateTime.now().millisecondsSinceEpoch;

    final canonicalPayload = [
      'v2',
      identity.deviceId,
      clientId,
      clientMode,
      role,
      scopes.join(','),
      signedAt.toString(),
      token,
      nonce,
    ].join('|');

    final keyPair = await _restoreKeyPair(identity);
    final signature = await _ed25519.sign(
      utf8.encode(canonicalPayload),
      keyPair: keyPair,
    );

    return {
      'id': identity.deviceId,
      'publicKey': _base64UrlNoPad(base64Decode(identity.publicKey)),
      'signature': _base64UrlNoPad(signature.bytes),
      'signedAt': signedAt,
      'nonce': nonce,
    };
  }

  /// Verifies that a stored identity's keypair is valid by performing
  /// a sign-and-verify round trip.
  Future<bool> verifyIdentity(DeviceIdentity identity) async {
    try {
      final keyPair = await _restoreKeyPair(identity);
      final testMessage = utf8.encode('clawcar-verify');
      final signature = await _ed25519.sign(testMessage, keyPair: keyPair);
      return _ed25519.verify(testMessage, signature: signature);
    } catch (_) {
      return false;
    }
  }

  Future<DeviceIdentity> _generateIdentity() async {
    final keyPair = await _ed25519.newKeyPair();
    final keyPairData = await keyPair.extract();
    final publicKey = keyPairData.publicKey;

    final deviceId = await _deriveDeviceId(publicKey.bytes);

    return DeviceIdentity(
      deviceId: deviceId,
      publicKey: base64Encode(publicKey.bytes),
      privateKey: base64Encode(keyPairData.bytes),
      createdAt: DateTime.now(),
    );
  }

  Future<String> _deriveDeviceId(List<int> publicKeyBytes) async {
    final hash = await _sha256.hash(publicKeyBytes);
    return hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<SimpleKeyPairData> _restoreKeyPair(DeviceIdentity identity) async {
    final privateKeyBytes = base64Decode(identity.privateKey);
    final keyPair = await _ed25519.newKeyPairFromSeed(privateKeyBytes);
    return keyPair.extract();
  }
}
