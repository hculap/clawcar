import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clawcar/features/discovery/discovery_screen.dart';
import 'package:clawcar/shared/models/gateway_config.dart';
import 'package:clawcar/shared/providers/providers.dart';

void main() {
  late StreamController<List<GatewayConfig>> gatewayStreamController;

  setUp(() {
    gatewayStreamController =
        StreamController<List<GatewayConfig>>.broadcast();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    gatewayStreamController.close();
  });

  Future<SharedPreferences> getPrefs() async {
    return SharedPreferences.getInstance();
  }

  Widget buildApp(SharedPreferences prefs,
      StreamController<List<GatewayConfig>> controller) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        discoveredGatewaysProvider.overrideWith(
          (ref) => controller.stream,
        ),
      ],
      child: const MaterialApp(home: DiscoveryScreen()),
    );
  }

  testWidgets('shows scanning state initially', (tester) async {
    final prefs = await getPrefs();
    await tester.pumpWidget(buildApp(prefs, gatewayStreamController));

    expect(find.text('ClawCar'), findsOneWidget);
    expect(find.text('Scanning for OpenClaw gateways...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows discovered gateways when available', (tester) async {
    final prefs = await getPrefs();
    await tester.pumpWidget(buildApp(prefs, gatewayStreamController));

    gatewayStreamController.add([
      const GatewayConfig(
        host: '192.168.1.50',
        port: 18789,
        displayName: 'Living Room Gateway',
        useTls: true,
      ),
      const GatewayConfig(
        host: '192.168.1.51',
        port: 18789,
        displayName: 'Office Gateway',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Living Room Gateway'), findsOneWidget);
    expect(find.text('Office Gateway'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('shows no gateways found after timeout', (tester) async {
    final prefs = await getPrefs();
    await tester.pumpWidget(buildApp(prefs, gatewayStreamController));

    gatewayStreamController.add([]);
    // Pump once to process the stream event (don't pumpAndSettle due to spinner)
    await tester.pump();

    // Before timeout: shows scanning message
    expect(find.text('Scanning for OpenClaw gateways...'), findsOneWidget);

    // Advance past 5s timeout
    await tester.pump(const Duration(seconds: 6));

    expect(find.text('No gateways found on this network'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
  });

  testWidgets('manual entry field is present', (tester) async {
    final prefs = await getPrefs();
    await tester.pumpWidget(buildApp(prefs, gatewayStreamController));

    expect(find.text('Gateway address'), findsOneWidget);
    expect(
      find.text('e.g. 192.168.1.100 or myhost.local'),
      findsOneWidget,
    );
  });

  testWidgets('shows error state when discovery fails', (tester) async {
    final prefs = await getPrefs();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        discoveredGatewaysProvider.overrideWithValue(
          AsyncValue<List<GatewayConfig>>.error(
            Exception('mDNS unavailable'),
            StackTrace.current,
          ),
        ),
      ],
      child: const MaterialApp(home: DiscoveryScreen()),
    ));

    await tester.pump();

    expect(find.text('Network discovery unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('shows last connected gateway when persisted', (tester) async {
    SharedPreferences.setMockInitialValues({
      'selected_gateway':
          '{"host":"10.0.0.1","port":18789,"displayName":"Saved GW","useTls":false}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(buildApp(prefs, gatewayStreamController));

    expect(find.text('Saved GW'), findsOneWidget);
    expect(find.textContaining('Last connected'), findsOneWidget);
  });

  testWidgets('shows tailnetDns in subtitle when available', (tester) async {
    final prefs = await getPrefs();
    await tester.pumpWidget(buildApp(prefs, gatewayStreamController));

    gatewayStreamController.add([
      const GatewayConfig(
        host: '100.64.0.1',
        port: 18789,
        displayName: 'Tailnet GW',
        tailnetDns: 'gw.tail.ts.net',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.textContaining('gw.tail.ts.net'), findsOneWidget);
  });
}
