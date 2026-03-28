import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../shared/models/auth_models.dart';
import 'credential_store.dart';

/// Manages the Ed25519 device identity: keypair generation, persistence,
/// device ID derivation, and auth payload signing.
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

  /// Clears the in-memory cached identity so the next
  /// [getOrCreateIdentity] call reads from storage or generates fresh.
  void clearCache() {
    _cached = null;
  }

  /// Returns the current device identity, generating one if needed.
  Future<DeviceIdentity> getOrCreateIdentity() async {
    if (_cached != null) return _cached!;

    final stored = await _store.getDeviceIdentity();
    if (stored != null) {
      _cached = stored;
      return stored;
    }

    final identity = await _generateIdentity();
    await _store.setDeviceIdentity(identity);
    _cached = identity;
    return identity;
  }

  /// Creates a signed auth payload v1 for gateway authentication.
  Future<AuthPayloadV1> signAuthPayload({
    required DeviceIdentity identity,
    int? timestampOverride,
  }) async {
    final timestamp =
        timestampOverride ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final canonicalPayload = _buildCanonicalPayload(
      version: 1,
      deviceId: identity.deviceId,
      publicKey: identity.publicKey,
      timestamp: timestamp,
    );

    final keyPair = await _restoreKeyPair(identity);
    final signature = await _ed25519.sign(
      utf8.encode(canonicalPayload),
      keyPair: keyPair,
    );

    return AuthPayloadV1(
      version: 1,
      deviceId: identity.deviceId,
      publicKey: identity.publicKey,
      timestamp: timestamp,
      signature: base64Encode(signature.bytes),
    );
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

  /// Builds the canonical string representation of auth payload v1.
  /// Format: `v1:{deviceId}:{publicKey}:{timestamp}`
  String _buildCanonicalPayload({
    required int version,
    required String deviceId,
    required String publicKey,
    required int timestamp,
  }) {
    return 'v$version:$deviceId:$publicKey:$timestamp';
  }
}
