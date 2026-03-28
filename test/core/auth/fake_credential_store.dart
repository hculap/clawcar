import 'dart:convert';

import 'package:clawcar/core/auth/credential_store.dart';
import 'package:clawcar/shared/models/auth_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory fake of [CredentialStore] for testing.
///
/// Avoids platform channel calls to iOS Keychain / Android Keystore.
class FakeCredentialStore extends CredentialStore {
  FakeCredentialStore() : super(storage: const FlutterSecureStorage());

  final _storage = <String, String>{};
  int getIdentityCallCount = 0;

  DeviceIdentity? get storedIdentity {
    final raw = _storage['device_identity'];
    if (raw == null) return null;
    return DeviceIdentity.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<DeviceIdentity?> getDeviceIdentity() async {
    getIdentityCallCount++;
    final raw = _storage['device_identity'];
    if (raw == null) return null;
    return DeviceIdentity.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> setDeviceIdentity(DeviceIdentity identity) async {
    _storage['device_identity'] = jsonEncode(identity.toJson());
  }

  @override
  Future<void> deleteDeviceIdentity() async {
    _storage.remove('device_identity');
  }

  @override
  Future<GatewayCredentials?> getGatewayCredentials(String host) async {
    final raw = _storage['gw_creds_$host'];
    if (raw == null) return null;
    return GatewayCredentials.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> setGatewayCredentials(GatewayCredentials credentials) async {
    _storage['gw_creds_${credentials.gatewayHost}'] =
        jsonEncode(credentials.toJson());
  }

  @override
  Future<void> deleteGatewayCredentials(String host) async {
    _storage.remove('gw_creds_$host');
  }

  @override
  Future<void> deleteAll() async {
    _storage.clear();
  }
}
