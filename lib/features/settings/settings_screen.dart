import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/auth_models.dart';
import '../../shared/providers/providers.dart';
import '../discovery/discovery_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateway = ref.watch(selectedGatewayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Gateway section
          const _SectionHeader(title: 'Gateway'),
          ListTile(
            leading: const Icon(Icons.router),
            title: const Text('Connected gateway'),
            subtitle: gateway != null
                ? Text(
                    '${gateway.displayName} (${gateway.host}:${gateway.port})',
                  )
                : const Text('Not connected'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ref.read(selectedGatewayProvider.notifier).state = null;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
                (_) => false,
              );
            },
          ),

          // Device section
          const _SectionHeader(title: 'Device'),
          _DevicePairingTile(gatewayHost: gateway?.host),

          // Voice section
          const _SectionHeader(title: 'Voice'),
          _ContinuousConversationTile(),

          // About section
          const _SectionHeader(title: 'About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('ClawCar'),
            subtitle: Text('v0.1.0'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source code'),
            subtitle: const Text('github.com/hculap/clawcar'),
            onTap: () {
              // TODO: Open URL
            },
          ),
        ],
      ),
    );
  }
}

class _ContinuousConversationTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(continuousConversationProvider);
    return SwitchListTile(
      title: const Text('Continuous conversation'),
      subtitle: const Text(
        'Auto-listen after response until manually stopped',
      ),
      value: enabled,
      onChanged: (value) {
        ref.read(continuousConversationProvider.notifier).state = value;
        ref.read(appConfigProvider).setContinuousConversation(value);
      },
    );
  }
}

class _DevicePairingTile extends ConsumerStatefulWidget {
  const _DevicePairingTile({required this.gatewayHost});

  final String? gatewayHost;

  @override
  ConsumerState<_DevicePairingTile> createState() => _DevicePairingTileState();
}

class _DevicePairingTileState extends ConsumerState<_DevicePairingTile> {
  DeviceIdentity? _identity;
  bool? _paired;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final identity =
          await ref.read(deviceIdentityServiceProvider).getOrCreateIdentity();

      bool? paired;
      if (widget.gatewayHost != null) {
        paired = await ref
            .read(authServiceProvider)
            .hasCredentials(widget.gatewayHost!);
      }

      if (mounted) {
        setState(() {
          _identity = identity;
          _paired = paired;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load device info: $e');
      }
    }
  }

  Future<void> _unpair() async {
    final host = widget.gatewayHost;
    if (host == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair device?'),
        content: const Text(
          'This will clear stored credentials for this gateway. '
          'You will need to pair again to get full access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await ref.read(authServiceProvider).clearCredentials(host);
    ref.read(selectedGatewayProvider.notifier).state = null;

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ListTile(
        leading: const Icon(Icons.error_outline),
        title: const Text('Device identity'),
        subtitle: Text(_error!),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadDeviceInfo,
        ),
      );
    }

    if (_identity == null) {
      return const ListTile(
        leading: Icon(Icons.fingerprint),
        title: Text('Loading device identity...'),
      );
    }

    final theme = Theme.of(context);
    final deviceIdShort = _identity!.deviceId.length > 16
        ? '${_identity!.deviceId.substring(0, 16)}...'
        : _identity!.deviceId;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.fingerprint),
          title: const Text('Device ID'),
          subtitle: Text(
            deviceIdShort,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy Device ID',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _identity!.deviceId));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Device ID copied'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.key),
          title: const Text('Public Key'),
          subtitle: Text(
            _identity!.publicKey,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy Public Key',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _identity!.publicKey));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Public key copied'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ),
        ListTile(
          leading: Icon(
            _paired == true ? Icons.link : Icons.link_off,
            color: _paired == true
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: const Text('Pairing status'),
          subtitle: Text(_paired == true ? 'Paired' : 'Not paired'),
          trailing: _paired == true
              ? TextButton(onPressed: _unpair, child: const Text('Unpair'))
              : null,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
