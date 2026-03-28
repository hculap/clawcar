import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/agent.dart';
import '../../shared/providers/providers.dart';
import '../voice_chat/voice_chat_screen.dart';

class AgentsScreen extends ConsumerStatefulWidget {
  const AgentsScreen({super.key});

  @override
  ConsumerState<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends ConsumerState<AgentsScreen> {
  List<Agent> _agents = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = ref.read(gatewayClientProvider);
      if (client == null) {
        throw StateError('Not connected to gateway');
      }

      await client.connect();

      // TODO: Fetch real agent list from gateway
      // For now, show a default agent
      setState(() {
        _agents = [
          const Agent(
            id: 'main',
            name: 'Main Agent',
            description: 'Default OpenClaw agent',
            isDefault: true,
          ),
        ];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _selectAgent(Agent agent) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => VoiceChatScreen(agent: agent)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: Navigate to settings
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              'Connection failed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadAgents, child: const Text('Retry')),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _agents.length,
      itemBuilder: (context, index) {
        final agent = _agents[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(child: Text(agent.name[0].toUpperCase())),
            title: Text(agent.name),
            subtitle: agent.description != null
                ? Text(agent.description!)
                : null,
            trailing: agent.isDefault
                ? Chip(
                    label: const Text('Default'),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                  )
                : null,
            onTap: () => _selectAgent(agent),
          ),
        );
      },
    );
  }
}
