import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clawcar/features/settings/settings_screen.dart';
import 'package:clawcar/shared/models/gateway_config.dart';
import 'package:clawcar/shared/providers/providers.dart';

void main() {
  group('SettingsScreen gateway section', () {
    testWidgets('shows connected gateway info', (tester) async {
      SharedPreferences.setMockInitialValues({
        'selected_gateway':
            '{"host":"10.0.0.1","port":18789,"displayName":"My GW","useTls":false}',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

      expect(find.text('My GW (10.0.0.1:18789)'), findsOneWidget);
      expect(find.text('Disconnect & forget gateway'), findsOneWidget);
    });

    testWidgets('shows not connected when no gateway', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Disconnect & forget gateway'), findsNothing);
    });

    testWidgets('disconnect clears persisted gateway', (tester) async {
      SharedPreferences.setMockInitialValues({
        'selected_gateway':
            '{"host":"10.0.0.1","port":18789,"displayName":"My GW","useTls":false}',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            discoveredGatewaysProvider.overrideWith(
              (ref) => const Stream<List<GatewayConfig>>.empty(),
            ),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

      await tester.tap(find.text('Disconnect & forget gateway'));
      // Use pump() instead of pumpAndSettle() because DiscoveryScreen
      // has a running timer that prevents settling
      await tester.pump();
      await tester.pump();

      // Should have navigated to DiscoveryScreen
      expect(find.text('Gateway address'), findsOneWidget);

      // Persisted gateway should be cleared
      expect(prefs.getString('selected_gateway'), isNull);
    });
  });
}
