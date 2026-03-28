import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/gateway_config.dart';
import '../../shared/providers/providers.dart';
import '../../core/gateway/gateway_discovery.dart';
import '../agents/agents_screen.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final _hostController = TextEditingController();
  Timer? _timeoutTimer;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  void _connectToGateway(GatewayConfig config) {
    ref.read(selectedGatewayProvider.notifier).state = config;
    ref.read(appConfigProvider).setSelectedGateway(config);
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const AgentsScreen()));
  }

  void _connectManually() {
    final host = _hostController.text.trim();
    if (host.isEmpty) return;

    final config = GatewayDiscovery.manualConfig(host);
    _connectToGateway(config);
  }

  void _retryDiscovery() {
    ref.invalidate(discoveredGatewaysProvider);
    setState(() => _timedOut = false);
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final discoveryAsync = ref.watch(discoveredGatewaysProvider);
    final lastGateway = ref.read(appConfigProvider).selectedGateway;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Icon(Icons.mic, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'ClawCar',
                style: theme.textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Voice-first client for OpenClaw',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
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

              // Last connected gateway
              if (lastGateway != null) ...[
                _LastConnectedTile(
                  gateway: lastGateway,
                  onTap: () => _connectToGateway(lastGateway),
                ),
                const SizedBox(height: 16),
              ],

              // Discovered gateways header
              Row(
                children: [
                  Text(
                    'Discovered on network',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  if (discoveryAsync.isLoading || !_timedOut)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Gateway list
              Expanded(
                child: discoveryAsync.when(
                  loading: () => _buildEmptyState(theme),
                  error: (error, _) => _buildErrorState(theme, error),
                  data: (gateways) => _buildGatewayList(theme, gateways),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    if (_timedOut) {
      return _NoGatewaysFound(onRetry: _retryDiscovery);
    }
    return Center(
      child: Text(
        'Scanning for OpenClaw gateways...',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, Object error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            'Network discovery unavailable',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Enter a gateway address manually above.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _retryDiscovery,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildGatewayList(ThemeData theme, List<GatewayConfig> gateways) {
    if (gateways.isEmpty) return _buildEmptyState(theme);

    return ListView.builder(
      itemCount: gateways.length,
      itemBuilder: (context, index) {
        final gw = gateways[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.router),
            title: Text(gw.displayName),
            subtitle: Text(
              '${gw.host}:${gw.port}'
              '${gw.tailnetDns != null ? ' (${gw.tailnetDns})' : ''}',
            ),
            trailing: gw.useTls ? const Icon(Icons.lock, size: 16) : null,
            onTap: () => _connectToGateway(gw),
          ),
        );
      },
    );
  }
}

class _LastConnectedTile extends StatelessWidget {
  const _LastConnectedTile({required this.gateway, required this.onTap});

  final GatewayConfig gateway;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text(gateway.displayName),
        subtitle: Text('Last connected \u2022 ${gateway.host}:${gateway.port}'),
        trailing: const Icon(Icons.arrow_forward),
        onTap: onTap,
      ),
    );
  }
}

class _NoGatewaysFound extends StatelessWidget {
  const _NoGatewaysFound({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No gateways found on this network',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Make sure your OpenClaw gateway is running,\nor enter the address manually above.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Scan again'),
          ),
        ],
      ),
    );
  }
}
