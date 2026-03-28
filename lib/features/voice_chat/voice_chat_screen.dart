import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/vad_service.dart';
import '../../shared/models/agent.dart';
import '../../shared/models/session.dart';
import '../../shared/models/vad_event.dart';
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
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _initializeVad();
  }

  Future<void> _initializeVad() async {
    final vad = ref.read(vadProvider);
    await vad.initialize();

    _subscriptions.add(
      vad.stateChanges.listen((vadState) {
        if (!mounted) return;
        setState(() {
          switch (vadState) {
            case VadState.idle:
              _sessionState = VoiceSessionState.idle;
              _statusText = 'Tap to speak';
            case VadState.listening:
              _sessionState = VoiceSessionState.listening;
              _statusText = 'Listening...';
            case VadState.speechDetected:
              _sessionState = VoiceSessionState.listening;
              _statusText = 'Hearing you...';
            case VadState.speechEnded:
              _sessionState = VoiceSessionState.processing;
              _statusText = 'Processing...';
          }
        });
      }),
    );

    _subscriptions.add(
      vad.events.listen((event) {
        if (!mounted) return;
        switch (event) {
          case VadSpeechEnd(:final audioData):
            _handleSpeechEnd(audioData);
          case VadSpeechStart():
            break;
        }
      }),
    );
  }

  void _handleSpeechEnd(List<double> audioData) {
    final client = ref.read(gatewayClientProvider);
    if (client == null) return;

    // Convert float samples [-1.0, 1.0] to PCM16 integers for the gateway.
    final pcm16 = audioData
        .map((s) => (s * 32767).round().clamp(-32768, 32767))
        .toList();
    client.sendAudio(pcm16);
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
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
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
