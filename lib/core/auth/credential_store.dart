import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/models/auth_models.dart';

const _keyDeviceIdentity = 'device_identity';
const _keyGatewayCredentialsPrefix = 'gw_creds_';

/// Secure credential store backed by iOS Keychain / Android Keystore.
class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  // -- Device Identity --

  Future<DeviceIdentity?> getDeviceIdentity() async {
    final raw = await _storage.read(key: _keyDeviceIdentity);
    if (raw == null) return null;
    return DeviceIdentity.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> setDeviceIdentity(DeviceIdentity identity) async {
    await _storage.write(
      key: _keyDeviceIdentity,
      value: jsonEncode(identity.toJson()),
    );
  }

  Future<void> deleteDeviceIdentity() async {
    await _storage.delete(key: _keyDeviceIdentity);
  }

  // -- Gateway Credentials --

  String _gatewayKey(String host) => '$_keyGatewayCredentialsPrefix$host';

  Future<GatewayCredentials?> getGatewayCredentials(String host) async {
    final raw = await _storage.read(key: _gatewayKey(host));
    if (raw == null) return null;
    return GatewayCredentials.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> setGatewayCredentials(GatewayCredentials credentials) async {
    await _storage.write(
      key: _gatewayKey(credentials.gatewayHost),
      value: jsonEncode(credentials.toJson()),
    );
  }

  Future<void> deleteGatewayCredentials(String host) async {
    await _storage.delete(key: _gatewayKey(host));
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
