import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
