import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:clawcar/core/gateway/gateway_discovery.dart';
import 'package:clawcar/core/gateway/gateway_protocol.dart';
import 'package:clawcar/shared/models/gateway_config.dart';

void main() {
  group('GatewayDiscovery', () {
    group('manualConfig', () {
      test('uses default port when none provided', () {
        final config = GatewayDiscovery.manualConfig('192.168.1.10');

        expect(config.host, '192.168.1.10');
        expect(config.port, defaultGatewayPort);
        expect(config.displayName, '192.168.1.10');
        expect(config.useTls, false);
        expect(config.tlsSha256, isNull);
        expect(config.tailnetDns, isNull);
        expect(config.authToken, isNull);
      });

      test('uses custom port when provided', () {
        final config = GatewayDiscovery.manualConfig(
          'myhost.local',
          port: 9999,
        );

        expect(config.host, 'myhost.local');
        expect(config.port, 9999);
        expect(config.displayName, 'myhost.local');
      });
    });
  });

  group('GatewayConfig', () {
    test('serializes to and from JSON', () {
      const config = GatewayConfig(
        host: '10.0.0.5',
        port: 18789,
        displayName: 'My Gateway',
        useTls: true,
        tlsSha256: 'abc123',
        tailnetDns: 'gw.tail.ts.net',
      );

      final json = config.toJson();
      final restored = GatewayConfig.fromJson(json);

      expect(restored.host, config.host);
      expect(restored.port, config.port);
      expect(restored.displayName, config.displayName);
      expect(restored.useTls, config.useTls);
      expect(restored.tlsSha256, config.tlsSha256);
      expect(restored.tailnetDns, config.tailnetDns);
    });

    test('defaults useTls to false', () {
      const config = GatewayConfig(
        host: 'localhost',
        port: 18789,
        displayName: 'test',
      );

      expect(config.useTls, false);
    });
  });

  group('GatewayDiscovery stream', () {
    late GatewayDiscovery discovery;

    setUp(() {
      discovery = GatewayDiscovery();
    });

    tearDown(() {
      discovery.dispose();
    });

    test('currentGateways starts empty', () {
      expect(discovery.currentGateways, isEmpty);
    });

    test('gateways stream is broadcast', () {
      // Should not throw when listened to multiple times
      discovery.gateways.listen((_) {});
      discovery.gateways.listen((_) {});
    });
  });
}
