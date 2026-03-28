import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/agent.dart';
import '../../shared/models/session.dart';
import '../../shared/providers/providers.dart';

class VoiceChatScreen extends ConsumerStatefulWidget {
  final Agent agent;

  const VoiceChatScreen({super.key, required this.agent});

  @override
  ConsumerState<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends ConsumerState<VoiceChatScreen> {
  VoiceSessionState _sessionState = VoiceSessionState.idle;
  String _statusText = 'Tap to speak';

  @override
  void initState() {
    super.initState();
    _initializeVad();
  }

  Future<void> _initializeVad() async {
    final vad = ref.read(vadProvider);
    await vad.initialize();

    vad.stateChanges.listen((state) {
      if (!mounted) return;
      setState(() {
        switch (state) {
          case _:
            // VAD state mapping handled in full implementation
            break;
        }
      });
    });
  }

  Future<void> _toggleListening() async {
    final vad = ref.read(vadProvider);

    if (_sessionState == VoiceSessionState.listening) {
      await vad.stopListening();
      setState(() {
        _sessionState = VoiceSessionState.idle;
        _statusText = 'Tap to speak';
      });
    } else {
      await vad.startListening();
      setState(() {
        _sessionState = VoiceSessionState.listening;
        _statusText = 'Listening...';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (_sessionState) {
      VoiceSessionState.idle => Theme.of(context).colorScheme.primary,
      VoiceSessionState.listening => Colors.red,
      VoiceSessionState.processing => Colors.orange,
      VoiceSessionState.speaking => Colors.green,
      VoiceSessionState.error => Colors.grey,
    };

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.agent.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _sessionState == VoiceSessionState.listening ? 200 : 160,
              height: _sessionState == VoiceSessionState.listening ? 200 : 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color, width: 3),
              ),
              child: IconButton(
                iconSize: 64,
                icon: Icon(
                  _sessionState == VoiceSessionState.listening
                      ? Icons.mic
                      : Icons.mic_none,
                  color: color,
                ),
                onPressed: _toggleListening,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              _statusText,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (_sessionState == VoiceSessionState.processing)
              const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
