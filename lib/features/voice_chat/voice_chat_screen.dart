import 'dart:typed_data';

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
  bool _initialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeVad();
  }

  Future<void> _initializeVad() async {
    try {
      final vad = ref.read(vadProvider);
      await vad.initialize();
      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initialized = false;
        _errorMessage = 'Microphone unavailable';
      });
    }
  }

  VoiceSessionState _mapVadState(VadState vadState) {
    return switch (vadState) {
      VadState.idle => VoiceSessionState.idle,
      VadState.listening => VoiceSessionState.listening,
      VadState.speechDetected => VoiceSessionState.listening,
      VadState.speechEnded => VoiceSessionState.processing,
    };
  }

  String _mapStatusText(VadState vadState) {
    return switch (vadState) {
      VadState.idle => 'Tap to speak',
      VadState.listening => 'Listening...',
      VadState.speechDetected => 'Hearing you...',
      VadState.speechEnded => 'Processing...',
    };
  }

  void _handleSpeechEnd(List<double> audioData) {
    final client = ref.read(gatewayClientProvider);
    if (client == null) return;

    // Convert float samples [-1.0, 1.0] to PCM16 bytes for the gateway.
    final pcm16 = Int16List.fromList(
      audioData
          .map((s) => (s * 32767).round().clamp(-32768, 32767))
          .toList(),
    );
    client.sendAudio(pcm16.buffer.asUint8List().toList());
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _toggleListening() async {
    final vad = ref.read(vadProvider);

    if (vad.state == VadState.listening ||
        vad.state == VadState.speechDetected) {
      await vad.stopListening();
    } else {
      await vad.startListening();
    }
  }

  @override
  void dispose() {
    ref.read(vadProvider).stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vadState = ref.watch(vadStateProvider);

    // React to speech events via the StreamProvider.
    ref.listen<AsyncValue<VadEvent>>(vadEventProvider, (prev, next) {
      next.whenData((event) {
        switch (event) {
          case VadSpeechEnd(:final audioData):
            _handleSpeechEnd(audioData);
          case VadSpeechStart():
            break;
          case VadError(:final message):
            _showError(message);
        }
      });
    });

    final currentVadState = vadState.when(
      data: (state) => state,
      loading: () => VadState.idle,
      error: (_, _) => VadState.idle,
    );
    final sessionState = _errorMessage != null
        ? VoiceSessionState.error
        : _mapVadState(currentVadState);
    final statusText = _errorMessage ?? _mapStatusText(currentVadState);

    final color = switch (sessionState) {
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
              width: sessionState == VoiceSessionState.listening ? 200 : 160,
              height: sessionState == VoiceSessionState.listening ? 200 : 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color, width: 3),
              ),
              child: IconButton(
                iconSize: 64,
                icon: Icon(
                  sessionState == VoiceSessionState.listening
                      ? Icons.mic
                      : Icons.mic_none,
                  color: color,
                ),
                onPressed: _initialized ? _toggleListening : null,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              statusText,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            if (sessionState == VoiceSessionState.processing)
              const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
