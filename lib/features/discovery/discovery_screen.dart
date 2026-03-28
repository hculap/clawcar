import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/gateway_config.dart';
import '../../shared/providers/providers.dart';
import '../../core/gateway/gateway_discovery.dart';
import '../../core/gateway/gateway_protocol.dart';
import '../agents/agents_screen.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final _hostController = TextEditingController();
  List<GatewayConfig> _discoveredGateways = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    setState(() => _isScanning = true);

    final discovery = ref.read(gatewayDiscoveryProvider);
    discovery.gateways.listen((gateways) {
      if (mounted) {
        setState(() => _discoveredGateways = gateways);
      }
    });

    try {
      await discovery.startDiscovery();
    } catch (e) {
      // mDNS may not be available on all networks
    }
  }

  void _connectToGateway(GatewayConfig config) {
    ref.read(selectedGatewayProvider.notifier).state = config;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AgentsScreen()),
    );
  }

  void _connectManually() {
    final host = _hostController.text.trim();
    if (host.isEmpty) return;

    final config = GatewayDiscovery.manualConfig(host);
    _connectToGateway(config);
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Icon(
                Icons.mic,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'ClawCar',
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Voice-first client for OpenClaw',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Manual entry
              TextField(
                controller: _hostController,
                decoration: InputDecoration(
                  labelText: 'Gateway address',
                  hintText: 'e.g. 192.168.1.100 or myhost.local',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _connectManually,
                  ),
                ),
                onSubmitted: (_) => _connectManually(),
              ),
              const SizedBox(height: 24),

              // Discovered gateways
              Row(
                children: [
                  Text(
                    'Discovered on network',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  if (_isScanning)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _discoveredGateways.isEmpty
                    ? Center(
                        child: Text(
                          'Scanning for OpenClaw gateways...',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _discoveredGateways.length,
                        itemBuilder: (context, index) {
                          final gw = _discoveredGateways[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.router),
                              title: Text(gw.displayName),
                              subtitle: Text('${gw.host}:${gw.port}'),
                              trailing: gw.useTls
                                  ? const Icon(Icons.lock, size: 16)
                                  : null,
                              onTap: () => _connectToGateway(gw),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
