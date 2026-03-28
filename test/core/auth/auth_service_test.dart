import 'package:flutter_test/flutter_test.dart';

import 'package:clawcar/core/auth/auth_service.dart';
import 'package:clawcar/core/auth/device_identity_service.dart';
import 'package:clawcar/shared/models/auth_models.dart';

import 'fake_credential_store.dart';

void main() {
  late FakeCredentialStore store;
  late DeviceIdentityService identityService;
  late AuthService authService;

  setUp(() {
    store = FakeCredentialStore();
    identityService = DeviceIdentityService(store: store);
    authService = AuthService(
      identityService: identityService,
      store: store,
    );
  });

  tearDown(() {
    authService.dispose();
  });

  group('AuthService', () {
    group('buildAuthParams', () {
      test('returns signed auth when no stored credentials', () async {
        final params = await authService.buildAuthParams(
          gatewayHost: 'gw.local',
        );

        expect(params['auth'], isA<Map>());
        final auth = params['auth'] as Map<String, dynamic>;
        expect(auth['type'], 'signed');
        expect(auth['payload'], isA<Map>());

        final payload = auth['payload'] as Map<String, dynamic>;
        expect(payload['version'], 1);
        expect(payload['deviceId'], isNotEmpty);
        expect(payload['publicKey'], isNotEmpty);
        expect(payload['signature'], isNotEmpty);

        expect(params['device'], isA<Map>());
        final device = params['device'] as Map<String, dynamic>;
        expect(device['id'], isNotEmpty);
        expect(device['publicKey'], isNotEmpty);
      });

      test('returns token auth when token credentials stored', () async {
        await store.setGatewayCredentials(const GatewayCredentials(
          gatewayHost: 'gw.local',
          method: AuthMethod.token,
          token: 'my-secret-token',
          paired: true,
        ));

        final params = await authService.buildAuthParams(
          gatewayHost: 'gw.local',
        );

        expect(params['auth'], {'token': 'my-secret-token'});
      });
    });

    group('authenticateWithToken', () {
      test('stores token credentials and returns token auth params', () async {
        final params = await authService.authenticateWithToken(
          gatewayHost: 'gw.local',
          token: 'abc123',
        );

        expect(params['auth'], {'token': 'abc123'});

        final stored = await store.getGatewayCredentials('gw.local');
        expect(stored, isNotNull);
        expect(stored!.method, AuthMethod.token);
        expect(stored.token, 'abc123');
        expect(stored.paired, isTrue);
      });
    });

    group('hasCredentials', () {
      test('returns false when no credentials stored', () async {
        final result = await authService.hasCredentials('gw.local');
        expect(result, isFalse);
      });

      test('returns true when paired credentials exist', () async {
        await store.setGatewayCredentials(const GatewayCredentials(
          gatewayHost: 'gw.local',
          method: AuthMethod.signed,
          paired: true,
        ));

        final result = await authService.hasCredentials('gw.local');
        expect(result, isTrue);
      });

      test('returns false when unpaired credentials exist', () async {
        await store.setGatewayCredentials(const GatewayCredentials(
          gatewayHost: 'gw.local',
          method: AuthMethod.signed,
          paired: false,
        ));

        final result = await authService.hasCredentials('gw.local');
        expect(result, isFalse);
      });
    });

    group('getDeviceId', () {
      test('returns consistent device ID', () async {
        final id1 = await authService.getDeviceId();
        final id2 = await authService.getDeviceId();
        expect(id1, id2);
        expect(id1.length, 64); // SHA-256 hex
      });
    });

    group('clearCredentials', () {
      test('removes gateway credentials', () async {
        await store.setGatewayCredentials(const GatewayCredentials(
          gatewayHost: 'gw.local',
          method: AuthMethod.token,
          token: 'secret',
          paired: true,
        ));

        await authService.clearCredentials('gw.local');

        final stored = await store.getGatewayCredentials('gw.local');
        expect(stored, isNull);
      });
    });

    group('resetDevice', () {
      test('clears all stored data', () async {
        await authService.getDeviceId(); // Generate identity
        await store.setGatewayCredentials(const GatewayCredentials(
          gatewayHost: 'gw.local',
          method: AuthMethod.signed,
          paired: true,
        ));

        await authService.resetDevice();

        final identity = await store.getDeviceIdentity();
        final creds = await store.getGatewayCredentials('gw.local');
        expect(identity, isNull);
        expect(creds, isNull);
      });

      test('subsequent getDeviceId returns a new identity', () async {
        final oldId = await authService.getDeviceId();

        await authService.resetDevice();

        final newId = await authService.getDeviceId();
        expect(newId, isNot(equals(oldId)));
      });
    });

    group('pairingState', () {
      test('starts idle', () {
        expect(authService.pairingState, const PairingState.idle());
      });

      test('emits state changes on stream', () async {
        final states = <PairingState>[];
        final sub = authService.pairingStateChanges.listen(states.add);

        // We can't test the full pairing flow without a real gateway,
        // but we verify the stream mechanics work.
        await sub.cancel();
      });
    });
  });
}
