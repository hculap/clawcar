import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../car/carplay/carplay_controller.dart';
import '../../car/carplay/carplay_service.dart';
import '../../core/audio/audio_player_service.dart';
import '../../core/audio/audio_recorder.dart';
import '../../core/audio/energy_vad_config.dart';
import '../../core/audio/energy_vad_service.dart';
import '../../core/audio/vad_config.dart';
import '../../core/audio/vad_service.dart';
import '../../core/audio/vad_service_base.dart';
import '../../core/audio/voice_pipeline.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/credential_store.dart';
import '../../core/auth/device_identity_service.dart';
import '../../core/config/app_config.dart';
import '../../core/gateway/gateway_client.dart';
import '../../core/gateway/gateway_discovery.dart';
import '../../core/gateway/gateway_protocol.dart';
import '../../shared/models/auth_models.dart';
import '../../shared/models/agent.dart';
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

final selectedGatewayProvider = StateProvider<GatewayConfig?>((ref) {
  return ref.read(appConfigProvider).selectedGateway;
});

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

final energyVadConfigProvider =
    Provider<EnergyVadConfig>((ref) => const EnergyVadConfig());

bool get _useEnergyVad =>
    Platform.isMacOS || Platform.isLinux || Platform.isWindows;

final vadProvider = Provider<VadServiceBase>((ref) {
  if (_useEnergyVad) {
    final config = ref.watch(energyVadConfigProvider);
    final recorder = ref.watch(audioRecorderProvider);
    final vad = EnergyVadService(recorder: recorder, config: config);
    ref.onDispose(vad.dispose);
    return vad;
  }

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

// -- Auth providers --

final credentialStoreProvider = Provider<CredentialStore>((ref) {
  return CredentialStore(prefs: ref.watch(sharedPreferencesProvider));
});

final deviceIdentityServiceProvider = Provider<DeviceIdentityService>((ref) {
  return DeviceIdentityService(store: ref.watch(credentialStoreProvider));
});

final authServiceProvider = Provider<AuthService>((ref) {
  final service = AuthService(
    identityService: ref.watch(deviceIdentityServiceProvider),
    store: ref.watch(credentialStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final pairingStateProvider = StreamProvider<PairingState>((ref) {
  return ref.watch(authServiceProvider).pairingStateChanges;
});

// -- Pairing check --

final isPairedProvider = FutureProvider.family<bool, String>((ref, host) {
  final authService = ref.watch(authServiceProvider);
  return authService.hasCredentials(host);
});

// -- Agent providers --

final selectedAgentProvider = StateProvider<Agent?>((ref) => null);

final agentsProvider = FutureProvider<List<Agent>>((ref) async {
  final client = ref.watch(gatewayClientProvider);
  final gateway = ref.watch(selectedGatewayProvider);
  if (client == null || gateway == null) {
    throw StateError('Not connected to gateway');
  }

  // 1. Ensure fresh connection
  final authService = ref.read(authServiceProvider);
  final paired = await authService.hasCredentials(gateway.host);

  if (client.state != ConnectionState.disconnected) {
    await client.disconnect(clearAuth: true);
  }

  // 2. Open WebSocket — capture nonce for signed auth before connect
  final nonceFuture = paired ? client.waitForChallengeNonce() : null;
  await client.connect();
  final nonce = await nonceFuture;

  // 3. Send connect handshake
  final GatewayResponse response;
  if (paired && nonce != null) {
    final authParams = await authService.buildAuthParams(
      gatewayHost: gateway.host,
      nonce: nonce,
    );
    response = await client.sendConnect(
      authParams: authParams,
      authParamsBuilder: () async {
        final freshNonce = await client.waitForChallengeNonce();
        return authService.buildAuthParams(
          gatewayHost: gateway.host,
          nonce: freshNonce,
        );
      },
    );
  } else {
    response = await client.sendConnect(authToken: client.authToken);
  }

  // 3. Extract agents from the connect response snapshot
  return GatewayClient.extractAgentsFromSnapshot(response);
});

// -- Continuous conversation --

final continuousConversationProvider = StateProvider<bool>((ref) {
  return ref.read(appConfigProvider).continuousConversation;
});

// -- Voice pipeline providers --

final voicePipelineProvider = Provider.family<VoicePipeline?, String>((ref, agentId) {
  final client = ref.watch(gatewayClientProvider);
  if (client == null) return null;

  final vad = ref.watch(vadProvider);
  final player = ref.watch(audioPlayerProvider);
  final continuous = ref.watch(continuousConversationProvider);

  final recorder = ref.watch(audioRecorderProvider);

  final pipeline = VoicePipeline(
    gateway: client,
    vad: vad,
    player: player,
    recorder: recorder,
    agentId: agentId,
  )..continuousMode = continuous;
  ref.onDispose(pipeline.dispose);
  return pipeline;
});

// -- CarPlay providers --

final carPlayServiceProvider = Provider<CarPlayService>((ref) {
  return CarPlayService();
});

final carPlayConnectedProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(carPlayServiceProvider);
  return service.events
      .where((e) =>
          e.type == 'carplayConnected' || e.type == 'carplayDisconnected')
      .map((e) => e.type == 'carplayConnected');
});

final carPlayControllerProvider = Provider<CarPlayController?>((ref) {
  final service = ref.watch(carPlayServiceProvider);
  final selectedAgent = ref.watch(selectedAgentProvider);
  final agentId = selectedAgent?.id;
  if (agentId == null) return null;

  final pipeline = ref.watch(voicePipelineProvider(agentId));
  if (pipeline == null) return null;

  final controller = CarPlayController(
    service: service,
    pipelineGetter: () => pipeline,
    onAgentSwitch: (newAgentId) {
      ref.read(selectedAgentProvider.notifier).state = Agent(
        id: newAgentId,
        name: newAgentId,
      );
    },
  );

  controller.start();
  controller.attachPipeline(pipeline);

  ref.onDispose(controller.dispose);
  return controller;
});
