import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/discovery/discovery_screen.dart';
import 'shared/providers/providers.dart';

class ClawCarApp extends ConsumerWidget {
  const ClawCarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly initialize the CarPlay controller on iOS only.
    if (Platform.isIOS) {
      ref.watch(carPlayControllerProvider);
    }

    return MaterialApp(
      title: 'ClawCar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const DiscoveryScreen(),
    );
  }
}
