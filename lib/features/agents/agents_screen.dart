import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/agent.dart';
import '../../shared/providers/providers.dart';
import '../settings/settings_screen.dart';
import '../voice_chat/voice_chat_screen.dart';

class AgentsScreen extends ConsumerStatefulWidget {
  const AgentsScreen({super.key});

  @override
  ConsumerState<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends ConsumerState<AgentsScreen> {
  @override
  void initState() {
    super.initState();
    _restoreLastAgent();
  }

  void _restoreLastAgent() {
    final lastAgent = ref.read(appConfigProvider).selectedAgent;
    if (lastAgent != null) {
      ref.read(selectedAgentProvider.notifier).state = lastAgent;
    }
  }

  void _selectAgent(Agent agent) {
    ref.read(selectedAgentProvider.notifier).state = agent;
    ref.read(appConfigProvider).setSelectedAgent(agent);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VoiceChatScreen(agent: agent)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final agentsAsync = ref.watch(agentsProvider);
    final lastAgent = ref.watch(selectedAgentProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(agentsProvider),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: agentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          error: error.toString(),
          onRetry: () => ref.invalidate(agentsProvider),
        ),
        data: (agents) => _AgentList(
          agents: agents,
          lastSelectedId: lastAgent?.id,
          onSelect: _selectAgent,
        ),
      ),
    );
  }
}

class _AgentList extends StatelessWidget {
  const _AgentList({
    required this.agents,
    required this.lastSelectedId,
    required this.onSelect,
  });

  final List<Agent> agents;
  final String? lastSelectedId;
  final ValueChanged<Agent> onSelect;

  @override
  Widget build(BuildContext context) {
    if (agents.isEmpty) {
      return const Center(
        child: Text('No agents available on this gateway.'),
      );
    }

    final theme = Theme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: agents.length,
      itemBuilder: (context, index) {
        final agent = agents[index];
        final isLastSelected = agent.id == lastSelectedId;

        return Card(
          elevation: isLastSelected ? 2 : 0,
          color: isLastSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: agent.isDefault
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              foregroundColor: agent.isDefault
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
              child: Text(agent.name[0].toUpperCase()),
            ),
            title: Text(agent.name),
            subtitle: _buildSubtitle(agent, theme),
            trailing: _buildTrailing(agent, isLastSelected, theme),
            onTap: () => onSelect(agent),
          ),
        );
      },
    );
  }

  Widget? _buildSubtitle(Agent agent, ThemeData theme) {
    final parts = <String>[
      if (agent.description != null) agent.description!,
      if (agent.model != null) agent.model!,
    ];

    if (parts.isEmpty) return null;

    if (agent.description != null && agent.model != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(agent.description!),
          const SizedBox(height: 4),
          Text(
            agent.model!,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Text(parts.first);
  }

  Widget? _buildTrailing(Agent agent, bool isLastSelected, ThemeData theme) {
    final chips = <Widget>[
      if (agent.isDefault)
        Chip(
          label: const Text('Default'),
          backgroundColor: theme.colorScheme.primaryContainer,
          labelStyle: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      if (isLastSelected && !agent.isDefault)
        Icon(
          Icons.history,
          size: 20,
          color: theme.colorScheme.primary,
        ),
    ];

    if (chips.isEmpty) return null;
    if (chips.length == 1) return chips.first;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: chips,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load agents',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
