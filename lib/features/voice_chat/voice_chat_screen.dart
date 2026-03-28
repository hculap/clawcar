import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/voice_pipeline.dart';
import '../../shared/models/agent.dart';
import '../../shared/providers/providers.dart';

class VoiceChatScreen extends ConsumerStatefulWidget {
  final Agent agent;

  const VoiceChatScreen({super.key, required this.agent});

  @override
  ConsumerState<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends ConsumerState<VoiceChatScreen> {
  PipelineState _pipelineState = PipelineState.idle;
  String _statusText = 'Tap to speak';
  String? _errorMessage;

  StreamSubscription<PipelineState>? _stateSub;
  StreamSubscription<VoicePipelineError>? _errorSub;
  VoicePipeline? _currentPipeline;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      voicePipelineProvider(widget.agent.id),
      (_, next) => _bindPipeline(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  void _cancelSubscriptions() {
    _stateSub?.cancel();
    _stateSub = null;
    _errorSub?.cancel();
    _errorSub = null;
  }

  void _bindPipeline(VoicePipeline? pipeline) {
    if (identical(pipeline, _currentPipeline)) return;

    _cancelSubscriptions();
    _currentPipeline = pipeline;
    _generation++;
    final gen = _generation;

    setState(() {
      _pipelineState = PipelineState.idle;
      _statusText = 'Tap to speak';
      _errorMessage = null;
    });

    if (pipeline == null) return;

    _initializePipeline(pipeline, gen);
  }

  Future<void> _initializePipeline(VoicePipeline pipeline, int gen) async {
    try {
      await pipeline.initialize();
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _pipelineState = PipelineState.error;
        _statusText = 'Failed to initialize';
        _errorMessage = e.toString();
      });
      return;
    }

    if (!mounted || gen != _generation) return;

    _stateSub = pipeline.stateChanges.listen((state) {
      if (!mounted) return;
      setState(() {
        _pipelineState = state;
        _statusText = _statusTextFor(state);
        if (state != PipelineState.error) {
          _errorMessage = null;
        }
      });
    });

    _errorSub = pipeline.errors.listen((error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
      });
    });
  }

  bool get _isContinuous => ref.read(continuousConversationProvider);

  String _statusTextFor(PipelineState state) {
    final continuous = _isContinuous;
    return switch (state) {
      PipelineState.idle => 'Tap to speak',
      PipelineState.listening when continuous => 'Listening (continuous)',
      PipelineState.listening => 'Listening...',
      PipelineState.processing when continuous => 'Processing (continuous)',
      PipelineState.processing => 'Processing...',
      PipelineState.speaking when continuous => 'Speaking (continuous)',
      PipelineState.speaking => 'Speaking...',
      PipelineState.error => 'Something went wrong',
    };
  }

  Future<void> _onMicPressed() async {
    final pipeline = _currentPipeline;
    if (pipeline == null) return;

    try {
      switch (_pipelineState) {
        case PipelineState.idle:
        case PipelineState.error:
          await pipeline.startListening();
        case PipelineState.listening:
          await pipeline.stopListening();
        case PipelineState.processing:
        case PipelineState.speaking:
          await pipeline.cancel();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pipelineState = PipelineState.error;
        _statusText = _statusTextFor(PipelineState.error);
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _onStopContinuous() async {
    final pipeline = _currentPipeline;
    if (pipeline == null) return;
    await pipeline.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final continuous = ref.watch(continuousConversationProvider);
    final color = _colorFor(_pipelineState, context);
    final isActive = _pipelineState == PipelineState.listening;
    final isRunning = _pipelineState != PipelineState.idle &&
        _pipelineState != PipelineState.error;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.agent.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              continuous ? Icons.repeat_on : Icons.repeat,
              color: continuous
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: continuous
                ? 'Continuous mode on'
                : 'Continuous mode off',
            onPressed: () {
              final next = !continuous;
              ref.read(continuousConversationProvider.notifier).state = next;
              ref.read(appConfigProvider).setContinuousConversation(next);
              _currentPipeline?.continuousMode = next;
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (continuous && isRunning)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Chip(
                  avatar: Icon(
                    Icons.repeat,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  label: const Text('Continuous'),
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.6),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isActive ? 200 : 160,
              height: isActive ? 200 : 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color, width: 3),
              ),
              child: IconButton(
                iconSize: 64,
                icon: Icon(_iconFor(_pipelineState), color: color),
                onPressed: _onMicPressed,
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
            if (_pipelineState == PipelineState.processing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 64),
                child: LinearProgressIndicator(),
              ),
            if (continuous && isRunning) ...[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: _onStopContinuous,
                icon: const Icon(Icons.stop),
                label: const Text('Stop conversation'),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _colorFor(PipelineState state, BuildContext context) {
    return switch (state) {
      PipelineState.idle => Theme.of(context).colorScheme.primary,
      PipelineState.listening => Colors.red,
      PipelineState.processing => Colors.orange,
      PipelineState.speaking => Colors.green,
      PipelineState.error => Colors.grey,
    };
  }

  IconData _iconFor(PipelineState state) {
    return switch (state) {
      PipelineState.idle => Icons.mic_none,
      PipelineState.listening => Icons.mic,
      PipelineState.processing => Icons.hourglass_top,
      PipelineState.speaking => Icons.volume_up,
      PipelineState.error => Icons.mic_off,
    };
  }
}
