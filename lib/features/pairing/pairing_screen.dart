import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/auth_models.dart';
import '../../shared/models/gateway_config.dart';
import '../../shared/providers/providers.dart';
import '../agents/agents_screen.dart';

/// Device pairing screen.
///
/// The gateway auto-pairs devices when a signed device identity is
/// included alongside a valid auth token in the connect handshake.
/// No interactive pairing code is needed — one tap does it all.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({required this.gateway, super.key});

  final GatewayConfig gateway;

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

enum _Phase { loading, ready, pairing, done, failed }

class _PairingScreenState extends ConsumerState<PairingScreen> {
  DeviceIdentity? _identity;
  _Phase _phase = _Phase.loading;
  String? _error;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    try {
      final identity =
          await ref.read(deviceIdentityServiceProvider).getOrCreateIdentity();
      if (mounted) {
        setState(() {
          _identity = identity;
          _phase = _Phase.ready;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = 'Failed to load device identity: $e';
        });
      }
    }
  }

  Future<void> _startPairing() async {
    final client = ref.read(gatewayClientProvider);
    final token = widget.gateway.authToken;
    if (client == null || token == null) {
      setState(() {
        _phase = _Phase.failed;
        _error = 'No gateway connection or auth token available';
      });
      return;
    }

    setState(() {
      _phase = _Phase.pairing;
      _error = null;
    });

    final success = await ref.read(authServiceProvider).pairDevice(
          client: client,
          gatewayHost: widget.gateway.host,
          token: token,
        );

    if (!mounted) return;

    if (success) {
      setState(() => _phase = _Phase.done);
      _navigateToAgents();
    } else {
      final state = ref.read(authServiceProvider).pairingState;
      setState(() {
        _phase = _Phase.failed;
        _error = state is PairingFailed ? state.error : 'Pairing failed';
      });
    }
  }

  void _navigateToAgents() {
    if (_navigating) return;
    _navigating = true;

    ref.invalidate(agentsProvider);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AgentsScreen()),
    );
  }

  void _skipPairing() {
    if (_navigating) return;
    _navigating = true;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AgentsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWorking = _phase == _Phase.loading ||
        _phase == _Phase.pairing ||
        _phase == _Phase.done;

    return Scaffold(
      appBar: AppBar(title: const Text('Device Pairing')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.phonelink_lock,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Pair with Gateway',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Register this device with the gateway for full operator '
                'access. Your device identity will be signed and sent '
                'alongside your auth token.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Device identity card
              if (_identity != null) ...[
                _DeviceInfoCard(identity: _identity!),
                const SizedBox(height: 24),
              ],

              // Action button
              FilledButton.icon(
                onPressed: isWorking ? null : _startPairing,
                icon: isWorking
                    ? const _Spinner()
                    : Icon(_phase == _Phase.done
                        ? Icons.check_circle
                        : Icons.handshake),
                label: Text(switch (_phase) {
                  _Phase.loading => 'Loading...',
                  _Phase.ready || _Phase.failed => 'Pair Device',
                  _Phase.pairing => 'Pairing...',
                  _Phase.done => 'Paired!',
                }),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 16),
                _ErrorCard(error: _error!),
              ],

              const Spacer(),

              // Skip
              TextButton(
                onPressed: isWorking ? null : _skipPairing,
                child: Text(
                  'Skip (limited access)',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceInfoCard extends StatelessWidget {
  const _DeviceInfoCard({required this.identity});

  final DeviceIdentity identity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device Identity', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            _CopyableField(label: 'Device ID', value: identity.deviceId),
            const SizedBox(height: 8),
            _CopyableField(label: 'Public Key', value: identity.publicKey),
          ],
        ),
      ),
    );
  }
}

class _CopyableField extends StatelessWidget {
  const _CopyableField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: 'Copy $label',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
