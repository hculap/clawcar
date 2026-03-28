import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/voice_pipeline.dart';
import '../../shared/models/agent.dart';
import '../../shared/providers/providers.dart';
import 'widgets/audio_wave.dart';
import 'widgets/mic_button.dart';

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

  String _statusTextFor(PipelineState state) {
    return switch (state) {
      PipelineState.idle => 'Tap to speak',
      PipelineState.listening => 'Listening...',
      PipelineState.processing => 'Processing...',
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

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.agent.name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white70,
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: isLandscape
            ? _buildLandscapeLayout(context)
            : _buildPortraitLayout(context),
      ),
    );
  }

  Widget _buildPortraitLayout(BuildContext context) {
    return Column(
      children: [
        const Spacer(flex: 2),
        _buildMicSection(context),
        const SizedBox(height: 40),
        _buildStatusSection(context),
        const Spacer(flex: 3),
      ],
    );
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        _buildMicSection(context),
        const SizedBox(width: 48),
        Expanded(
          flex: 2,
          child: Center(child: _buildStatusSection(context)),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildMicSection(BuildContext context) {
    final color = MicButton.colorFor(_pipelineState, context);
    final isSpeaking = _pipelineState == PipelineState.speaking;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MicButton(
          state: _pipelineState,
          onPressed: _onMicPressed,
        ),
        const SizedBox(height: 16),
        AnimatedOpacity(
          opacity: isSpeaking ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: AudioWave(color: color, width: 160, height: 40),
        ),
      ],
    );
  }

  Widget _buildStatusSection(BuildContext context) {
    final color = MicButton.colorFor(_pipelineState, context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _statusText,
            key: ValueKey(_statusText),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w300,
                  letterSpacing: 1.2,
                ),
            textAlign: TextAlign.center,
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
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
    );
  }
}
