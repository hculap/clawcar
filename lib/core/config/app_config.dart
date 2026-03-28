import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/gateway_config.dart';

const _keySelectedGateway = 'selected_gateway';
const _keyDeviceId = 'device_id';

class AppConfig {
  final SharedPreferences _prefs;

  AppConfig(this._prefs);

  GatewayConfig? get selectedGateway {
    final raw = _prefs.getString(_keySelectedGateway);
    if (raw == null) return null;
    return GatewayConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setSelectedGateway(GatewayConfig config) async {
    await _prefs.setString(_keySelectedGateway, jsonEncode(config.toJson()));
  }

  Future<void> clearSelectedGateway() async {
    await _prefs.remove(_keySelectedGateway);
  }

  String? get deviceId => _prefs.getString(_keyDeviceId);

  Future<void> setDeviceId(String id) async {
    await _prefs.setString(_keyDeviceId, id);
  }
}
