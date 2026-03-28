import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clawcar/app.dart';
import 'package:clawcar/shared/providers/providers.dart';
import 'package:clawcar/shared/models/gateway_config.dart';

void main() {
  group('App routing based on saved gateway', () {
    testWidgets('shows DiscoveryScreen when no gateway saved', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            discoveredGatewaysProvider.overrideWith(
              (ref) => const Stream<List<GatewayConfig>>.empty(),
            ),
          ],
          child: const ClawCarApp(),
        ),
      );

      expect(find.text('ClawCar'), findsOneWidget);
      expect(find.text('Gateway address'), findsOneWidget);
    });

    testWidgets('shows AgentsScreen when gateway is saved', (tester) async {
      SharedPreferences.setMockInitialValues({
        'selected_gateway':
            '{"host":"10.0.0.1","port":18789,"displayName":"Saved GW","useTls":false}',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const ClawCarApp(),
        ),
      );

      // AgentsScreen shows "Agents" in AppBar
      expect(find.text('Agents'), findsOneWidget);
    });
  });
}
