import 'package:flutter_test/flutter_test.dart';

import 'package:clawcar/shared/models/auth_models.dart';

void main() {
  group('DeviceIdentity', () {
    test('serializes to and from JSON', () {
      final identity = DeviceIdentity(
        deviceId: 'abc123',
        publicKey: 'cHVia2V5',
        privateKey: 'cHJpdmtleQ==',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final json = identity.toJson();
      final restored = DeviceIdentity.fromJson(json);

      expect(restored.deviceId, identity.deviceId);
      expect(restored.publicKey, identity.publicKey);
      expect(restored.privateKey, identity.privateKey);
      expect(restored.createdAt, identity.createdAt);
    });
  });

  group('GatewayCredentials', () {
    test('serializes signed credentials', () {
      const creds = GatewayCredentials(
        gatewayHost: 'gw.local',
        method: AuthMethod.signed,
        paired: true,
      );

      final json = creds.toJson();
      final restored = GatewayCredentials.fromJson(json);

      expect(restored.gatewayHost, 'gw.local');
      expect(restored.method, AuthMethod.signed);
      expect(restored.paired, isTrue);
      expect(restored.token, isNull);
    });

    test('serializes token credentials', () {
      const creds = GatewayCredentials(
        gatewayHost: 'gw.local',
        method: AuthMethod.token,
        token: 'my-token',
        paired: true,
      );

      final json = creds.toJson();
      final restored = GatewayCredentials.fromJson(json);

      expect(restored.method, AuthMethod.token);
      expect(restored.token, 'my-token');
    });

    test('defaults paired to false', () {
      const creds = GatewayCredentials(
        gatewayHost: 'gw.local',
        method: AuthMethod.unpaired,
      );

      expect(creds.paired, isFalse);
    });
  });

  group('PairingState', () {
    test('idle serialization', () {
      const state = PairingState.idle();
      final json = state.toJson();
      final restored = PairingState.fromJson(json);
      expect(restored, isA<PairingIdle>());
    });

    test('awaitingCode serialization', () {
      const state = PairingState.awaitingCode(gatewayHost: 'gw.local');
      final json = state.toJson();
      final restored = PairingState.fromJson(json);
      expect(restored, isA<PairingAwaitingCode>());
      expect((restored as PairingAwaitingCode).gatewayHost, 'gw.local');
    });

    test('failed serialization', () {
      const state = PairingState.failed(
        gatewayHost: 'gw.local',
        error: 'timeout',
      );
      final json = state.toJson();
      final restored = PairingState.fromJson(json);
      expect(restored, isA<PairingFailed>());
      expect((restored as PairingFailed).error, 'timeout');
    });
  });

  group('AuthPayloadV1', () {
    test('serializes to and from JSON', () {
      const payload = AuthPayloadV1(
        version: 1,
        deviceId: 'abc123',
        publicKey: 'cHVia2V5',
        timestamp: 1700000000,
        signature: 'c2lnbmF0dXJl',
      );

      final json = payload.toJson();
      final restored = AuthPayloadV1.fromJson(json);

      expect(restored.version, 1);
      expect(restored.deviceId, 'abc123');
      expect(restored.publicKey, 'cHVia2V5');
      expect(restored.timestamp, 1700000000);
      expect(restored.signature, 'c2lnbmF0dXJl');
    });

    test('defaults version to 1', () {
      const payload = AuthPayloadV1(
        deviceId: 'abc',
        publicKey: 'pub',
        timestamp: 0,
        signature: 'sig',
      );
      expect(payload.version, 1);
    });
  });
}
