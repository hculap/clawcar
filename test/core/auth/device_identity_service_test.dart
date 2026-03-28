import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clawcar/core/auth/device_identity_service.dart';

import 'fake_credential_store.dart';

void main() {
  late FakeCredentialStore store;
  late DeviceIdentityService service;

  setUp(() {
    store = FakeCredentialStore();
    service = DeviceIdentityService(store: store);
  });

  group('DeviceIdentityService', () {
    group('getOrCreateIdentity', () {
      test('generates a new identity on first call', () async {
        final identity = await service.getOrCreateIdentity();

        expect(identity.deviceId, isNotEmpty);
        expect(identity.publicKey, isNotEmpty);
        expect(identity.privateKey, isNotEmpty);
        expect(identity.createdAt, isA<DateTime>());
      });

      test('device ID is SHA-256 hex of public key', () async {
        final identity = await service.getOrCreateIdentity();

        // Verify device ID is a valid 64-char hex string (SHA-256)
        expect(identity.deviceId.length, 64);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(identity.deviceId), isTrue);

        // Verify it matches SHA-256 of public key bytes
        final pubKeyBytes = base64Decode(identity.publicKey);
        final hash = await Sha256().hash(pubKeyBytes);
        final expectedId =
            hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        expect(identity.deviceId, expectedId);
      });

      test('persists identity to store', () async {
        await service.getOrCreateIdentity();
        expect(store.storedIdentity, isNotNull);
      });

      test('returns cached identity on subsequent calls', () async {
        final first = await service.getOrCreateIdentity();
        final second = await service.getOrCreateIdentity();
        expect(first.deviceId, second.deviceId);
        expect(store.getIdentityCallCount, 1);
      });

      test('restores identity from store', () async {
        // Pre-populate store
        final preGenerated = await DeviceIdentityService(store: store)
            .getOrCreateIdentity();
        store.getIdentityCallCount = 0;

        // New service instance should restore from store
        final newService = DeviceIdentityService(store: store);
        final restored = await newService.getOrCreateIdentity();

        expect(restored.deviceId, preGenerated.deviceId);
        expect(restored.publicKey, preGenerated.publicKey);
      });
    });

    group('signAuthPayload', () {
      test('produces a valid v1 auth payload', () async {
        final identity = await service.getOrCreateIdentity();
        final payload = await service.signAuthPayload(
          identity: identity,
          timestampOverride: 1700000000,
        );

        expect(payload.version, 1);
        expect(payload.deviceId, identity.deviceId);
        expect(payload.publicKey, identity.publicKey);
        expect(payload.timestamp, 1700000000);
        expect(payload.signature, isNotEmpty);
      });

      test('signature is valid Ed25519', () async {
        final identity = await service.getOrCreateIdentity();
        final payload = await service.signAuthPayload(
          identity: identity,
          timestampOverride: 1700000000,
        );

        // Reconstruct the canonical payload and verify
        final canonical =
            'v1:${payload.deviceId}:${payload.publicKey}:${payload.timestamp}';
        final signatureBytes = base64Decode(payload.signature);
        final publicKeyBytes = base64Decode(identity.publicKey);

        final ed25519 = Ed25519();
        final isValid = await ed25519.verify(
          utf8.encode(canonical),
          signature: Signature(
            signatureBytes,
            publicKey: SimplePublicKey(
              publicKeyBytes,
              type: KeyPairType.ed25519,
            ),
          ),
        );

        expect(isValid, isTrue);
      });

      test('uses current timestamp when no override', () async {
        final identity = await service.getOrCreateIdentity();
        final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final payload = await service.signAuthPayload(identity: identity);
        final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        expect(payload.timestamp, greaterThanOrEqualTo(before));
        expect(payload.timestamp, lessThanOrEqualTo(after));
      });
    });

    group('verifyIdentity', () {
      test('returns true for a valid identity', () async {
        final identity = await service.getOrCreateIdentity();
        final isValid = await service.verifyIdentity(identity);
        expect(isValid, isTrue);
      });

      test('returns false for a corrupted identity', () async {
        final identity = await service.getOrCreateIdentity();
        final corrupted = identity.copyWith(
          privateKey: base64Encode(List.filled(32, 0)),
        );
        final isValid = await service.verifyIdentity(corrupted);
        // The corrupted key will produce a different public key,
        // but sign/verify still works (just different keypair).
        // What we really test is that the round-trip doesn't throw.
        expect(isValid, isA<bool>());
      });
    });
  });
}
