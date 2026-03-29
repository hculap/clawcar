import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/auth_models.dart';

const _keyDeviceIdentity = 'device_identity';
const _keyGatewayCredentialsPrefix = 'gw_creds_';

/// Secure credential store.
///
/// - **iOS/Android**: Uses flutter_secure_storage (Keychain / Keystore).
/// - **macOS desktop**: Uses SharedPreferences to avoid Keychain password
///   prompts and entitlement requirements in debug builds.
class CredentialStore {
  CredentialStore({
    FlutterSecureStorage? secureStorage,
    SharedPreferences? prefs,
  })  : _secureStorage = secureStorage,
        _prefs = prefs,
        _usePlatformSecure = !Platform.isMacOS && !Platform.isLinux && !Platform.isWindows;

  final FlutterSecureStorage? _secureStorage;
  final SharedPreferences? _prefs;
  final bool _usePlatformSecure;

  FlutterSecureStorage get _secure =>
      _secureStorage ??
      const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );

  SharedPreferences? _resolvedPrefs;

  Future<SharedPreferences> _getPrefs() async {
    return _resolvedPrefs ??= _prefs ?? await SharedPreferences.getInstance();
  }

  // -- Low-level read/write --

  Future<String?> _read(String key) async {
    if (_usePlatformSecure) {
      return _secure.read(key: key);
    }
    final prefs = await _getPrefs();
    return prefs.getString('cred_$key');
  }

  Future<void> _write(String key, String value) async {
    if (_usePlatformSecure) {
      await _secure.write(key: key, value: value);
      return;
    }
    final prefs = await _getPrefs();
    await prefs.setString('cred_$key', value);
  }

  Future<void> _delete(String key) async {
    if (_usePlatformSecure) {
      await _secure.delete(key: key);
      return;
    }
    final prefs = await _getPrefs();
    await prefs.remove('cred_$key');
  }

  // -- Device Identity --

  Future<DeviceIdentity?> getDeviceIdentity() async {
    final raw = await _read(_keyDeviceIdentity);
    if (raw == null) return null;
    return DeviceIdentity.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> setDeviceIdentity(DeviceIdentity identity) async {
    await _write(_keyDeviceIdentity, jsonEncode(identity.toJson()));
  }

  Future<void> deleteDeviceIdentity() async {
    await _delete(_keyDeviceIdentity);
  }

  // -- Gateway Credentials --

  String _gatewayKey(String host) => '$_keyGatewayCredentialsPrefix$host';

  Future<GatewayCredentials?> getGatewayCredentials(String host) async {
    final raw = await _read(_gatewayKey(host));
    if (raw == null) return null;
    return GatewayCredentials.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> setGatewayCredentials(GatewayCredentials credentials) async {
    await _write(
      _gatewayKey(credentials.gatewayHost),
      jsonEncode(credentials.toJson()),
    );
  }

  Future<void> deleteGatewayCredentials(String host) async {
    await _delete(_gatewayKey(host));
  }

  Future<void> deleteAll() async {
    if (_usePlatformSecure) {
      await _secure.deleteAll();
      return;
    }
    final prefs = await _getPrefs();
    final keys = prefs.getKeys().where((k) => k.startsWith('cred_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
