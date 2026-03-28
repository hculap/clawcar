import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/audio_player_service.dart';
import '../../core/audio/audio_recorder.dart';
import '../../core/audio/vad_config.dart';
import '../../core/audio/vad_service.dart';
import '../../core/config/app_config.dart';
import '../../core/gateway/gateway_client.dart';
import '../../core/gateway/gateway_discovery.dart';
import '../../shared/models/gateway_config.dart';
import '../../shared/models/vad_event.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig(ref.watch(sharedPreferencesProvider));
});

final gatewayDiscoveryProvider = Provider<GatewayDiscovery>((ref) {
  final discovery = GatewayDiscovery();
  ref.onDispose(discovery.dispose);
  return discovery;
});

final discoveredGatewaysProvider = StreamProvider<List<GatewayConfig>>((ref) {
  final discovery = ref.watch(gatewayDiscoveryProvider);
  discovery.startDiscovery().ignore();
  ref.onDispose(() => discovery.stopDiscovery());
  return discovery.gateways;
});

final selectedGatewayProvider = StateProvider<GatewayConfig?>((ref) => null);

final gatewayClientProvider = Provider<GatewayClient?>((ref) {
  final gateway = ref.watch(selectedGatewayProvider);
  if (gateway == null) return null;

  final client = GatewayClient(
    host: gateway.host,
    port: gateway.port,
    useTls: gateway.useTls,
    authToken: gateway.authToken,
  );
  ref.onDispose(client.dispose);
  return client;
});

final audioRecorderProvider = Provider<AudioRecorderService>((ref) {
  final recorder = AudioRecorderService();
  ref.onDispose(() => recorder.dispose());
  return recorder;
});

final audioStreamProvider = StreamProvider<Uint8List>((ref) {
  return ref.watch(audioRecorderProvider).audioStream;
});

final vadConfigProvider = Provider<VadConfig>((ref) => const VadConfig());

final vadProvider = Provider<VadService>((ref) {
  final config = ref.watch(vadConfigProvider);
  final vad = VadService(config: config);
  ref.onDispose(vad.dispose);
  return vad;
});

final vadStateProvider = StreamProvider<VadState>((ref) {
  return ref.watch(vadProvider).stateChanges;
});

final vadEventProvider = StreamProvider<VadEvent>((ref) {
  return ref.watch(vadProvider).events;
});

final audioPlayerProvider = Provider<AudioPlayerService>((ref) {
  final player = AudioPlayerService();
  ref.onDispose(player.dispose);
  return player;
});
