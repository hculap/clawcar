import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/agent.dart';
import '../../shared/models/gateway_config.dart';

const _keySelectedGateway = 'selected_gateway';
const _keySelectedAgent = 'selected_agent';
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

  Agent? get selectedAgent {
    final raw = _prefs.getString(_keySelectedAgent);
    if (raw == null) return null;
    return Agent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setSelectedAgent(Agent agent) async {
    await _prefs.setString(_keySelectedAgent, jsonEncode(agent.toJson()));
  }

  Future<void> clearSelectedAgent() async {
    await _prefs.remove(_keySelectedAgent);
  }

  String? get deviceId => _prefs.getString(_keyDeviceId);

  Future<void> setDeviceId(String id) async {
    await _prefs.setString(_keyDeviceId, id);
  }
}
