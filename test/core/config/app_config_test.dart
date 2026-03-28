import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clawcar/core/config/app_config.dart';
import 'package:clawcar/shared/models/gateway_config.dart';

void main() {
  group('AppConfig gateway persistence', () {
    late AppConfig config;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      config = AppConfig(prefs);
    });

    test('selectedGateway returns null when nothing saved', () {
      expect(config.selectedGateway, isNull);
    });

    test('setSelectedGateway persists and retrieves gateway', () async {
      const gateway = GatewayConfig(
        host: '192.168.1.10',
        port: 18789,
        displayName: 'Test Gateway',
        useTls: true,
        tlsSha256: 'abc123',
      );

      await config.setSelectedGateway(gateway);

      final restored = config.selectedGateway;
      expect(restored, isNotNull);
      expect(restored!.host, '192.168.1.10');
      expect(restored.port, 18789);
      expect(restored.displayName, 'Test Gateway');
      expect(restored.useTls, true);
      expect(restored.tlsSha256, 'abc123');
    });

    test('clearSelectedGateway removes persisted gateway', () async {
      const gateway = GatewayConfig(
        host: '10.0.0.1',
        port: 18789,
        displayName: 'To Clear',
      );

      await config.setSelectedGateway(gateway);
      expect(config.selectedGateway, isNotNull);

      await config.clearSelectedGateway();
      expect(config.selectedGateway, isNull);
    });

    test('selectedGateway survives SharedPreferences reload', () async {
      const gateway = GatewayConfig(
        host: '10.0.0.5',
        port: 9999,
        displayName: 'Persistent GW',
      );

      await config.setSelectedGateway(gateway);

      // Simulate app restart by creating new AppConfig with same prefs
      final prefs = await SharedPreferences.getInstance();
      final freshConfig = AppConfig(prefs);

      final restored = freshConfig.selectedGateway;
      expect(restored, isNotNull);
      expect(restored!.host, '10.0.0.5');
      expect(restored.port, 9999);
      expect(restored.displayName, 'Persistent GW');
    });

  });

  group('AppConfig continuous conversation', () {
    late AppConfig config;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      config = AppConfig(prefs);
    });

    test('defaults to false when nothing saved', () {
      expect(config.continuousConversation, false);
    });

    test('persists and retrieves enabled state', () async {
      await config.setContinuousConversation(true);
      expect(config.continuousConversation, true);
    });

    test('persists and retrieves disabled state', () async {
      await config.setContinuousConversation(true);
      await config.setContinuousConversation(false);
      expect(config.continuousConversation, false);
    });

    test('survives SharedPreferences reload', () async {
      await config.setContinuousConversation(true);

      final prefs = await SharedPreferences.getInstance();
      final freshConfig = AppConfig(prefs);

      expect(freshConfig.continuousConversation, true);
    });
  });

  group('AppConfig malformed data', () {
    test('handles malformed JSON gracefully', () async {
      SharedPreferences.setMockInitialValues({
        'selected_gateway': '{invalid json}',
      });
      final prefs = await SharedPreferences.getInstance();
      final badConfig = AppConfig(prefs);

      expect(() => badConfig.selectedGateway, throwsA(isA<FormatException>()));
    });
  });
}
