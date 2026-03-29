import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clawcar/core/audio/audio_player_service.dart';
import 'package:clawcar/core/audio/audio_recorder.dart';
import 'package:clawcar/core/audio/vad_service.dart';
import 'package:clawcar/core/audio/voice_pipeline.dart';
import 'package:clawcar/core/gateway/gateway_client.dart';
import 'package:clawcar/features/voice_chat/voice_chat_screen.dart';
import 'package:clawcar/features/voice_chat/widgets/audio_wave.dart';
import 'package:clawcar/features/voice_chat/widgets/mic_button.dart';
import 'package:clawcar/features/voice_chat/widgets/pulse_rings.dart';
import 'package:clawcar/shared/models/agent.dart';
import 'package:clawcar/shared/providers/providers.dart';

// ---------------------------------------------------------------------------
// Minimal stubs for VoicePipeline constructor dependencies
// ---------------------------------------------------------------------------

class _StubPlayer implements AudioPlayerBase {
  @override
  bool get isPlaying => false;
  @override
  Stream<dynamic> get playerState => const Stream.empty();
  @override
  Future<void> playAudioBytes(Uint8List audioData, {String? mimeType}) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  void dispose() {}
}

class _StubRecorder implements AudioRecorderBase {
  @override
  Stream<Uint8List> get audioStream => const Stream.empty();
  @override
  bool get isRecording => false;
  @override
  Future<void> startRecording() async {}
  @override
  Future<void> stopRecording() async {}
  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Fake VoicePipeline with controllable state/error streams
// ---------------------------------------------------------------------------

class FakeVoicePipeline extends VoicePipeline {
  final _stateCtrl = StreamController<PipelineState>.broadcast();
  final _errorCtrl = StreamController<VoicePipelineError>.broadcast();

  bool initializeCalled = false;
  bool startListeningCalled = false;
  bool stopListeningCalled = false;
  bool cancelCalled = false;

  FakeVoicePipeline()
      : super(
          gateway: GatewayClient(host: 'localhost', port: 0),
          vad: VadService(),
          player: _StubPlayer(),
          recorder: _StubRecorder(),
        );

  @override
  Stream<PipelineState> get stateChanges => _stateCtrl.stream;

  @override
  Stream<VoicePipelineError> get errors => _errorCtrl.stream;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }

  @override
  Future<void> startListening() async {
    startListeningCalled = true;
  }

  @override
  Future<void> stopListening() async {
    stopListeningCalled = true;
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
  }

  void emitState(PipelineState state) => _stateCtrl.add(state);
  void emitError(VoicePipelineError error) => _errorCtrl.add(error);

  @override
  void dispose() {
    _stateCtrl.close();
    _errorCtrl.close();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testAgent = Agent(
  id: 'agent-1',
  name: 'Test Agent',
  description: 'A test agent',
  model: 'gpt-4',
  isDefault: true,
);

Widget buildTestApp(FakeVoicePipeline pipeline) {
  return ProviderScope(
    overrides: [
      voicePipelineProvider(_testAgent.id).overrideWithValue(pipeline),
    ],
    child: const MaterialApp(
      home: VoiceChatScreen(agent: _testAgent),
    ),
  );
}

/// Pump enough frames for async initialization + animations to settle,
/// without using pumpAndSettle (which hangs on repeating animations).
Future<void> pumpFrames(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakeVoicePipeline pipeline;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pipeline = FakeVoicePipeline();
  });

  tearDown(() {
    pipeline.dispose();
  });

  group('initial state', () {
    testWidgets('shows agent name in app bar', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      expect(find.text('Test Agent'), findsOneWidget);
    });

    testWidgets('shows idle status text', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      expect(find.text('Tap to speak'), findsOneWidget);
    });

    testWidgets('shows mic button', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      expect(find.byType(MicButton), findsOneWidget);
    });

    testWidgets('initializes pipeline', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      expect(pipeline.initializeCalled, isTrue);
    });

    testWidgets('does not show pulse rings in idle', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      expect(find.byType(PulseRings), findsNothing);
    });

    testWidgets('audio wave is invisible in idle', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byType(AudioWave),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 0.0);
    });
  });

  group('listening state', () {
    testWidgets('shows listening status and pulse rings', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      pipeline.emitState(PipelineState.listening);
      await tester.pump();

      expect(find.text('Listening...'), findsOneWidget);
      expect(find.byType(PulseRings), findsOneWidget);
    });
  });

  group('processing state', () {
    testWidgets('shows processing status text', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      pipeline.emitState(PipelineState.processing);
      await tester.pump();

      expect(find.text('Processing...'), findsOneWidget);
    });
  });

  group('speaking state', () {
    testWidgets('shows speaking status and audio wave becomes visible',
        (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      pipeline.emitState(PipelineState.speaking);
      await pumpFrames(tester);

      expect(find.text('Speaking...'), findsOneWidget);

      final opacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byType(AudioWave),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(opacity.opacity, 1.0);
    });
  });

  group('error state', () {
    testWidgets('shows error message when error emitted', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      pipeline.emitState(PipelineState.error);
      pipeline.emitError(const VoicePipelineError(
        code: 'test_error',
        message: 'Connection lost',
      ));
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Connection lost'), findsOneWidget);
    });

    testWidgets('clears error when state changes to non-error',
        (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      pipeline.emitState(PipelineState.error);
      pipeline.emitError(const VoicePipelineError(
        code: 'err',
        message: 'Some error',
      ));
      await tester.pump();
      expect(find.text('Some error'), findsOneWidget);

      pipeline.emitState(PipelineState.idle);
      await tester.pump();

      expect(find.text('Some error'), findsNothing);
      expect(find.text('Tap to speak'), findsOneWidget);
    });
  });

  group('tap interactions', () {
    testWidgets('tap in idle starts listening', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      await tester.tap(find.byType(MicButton));
      await tester.pump();

      expect(pipeline.startListeningCalled, isTrue);
    });

    testWidgets('tap in listening stops listening', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      pipeline.emitState(PipelineState.listening);
      await tester.pump();

      await tester.tap(find.byType(MicButton));
      await tester.pump();

      expect(pipeline.stopListeningCalled, isTrue);
    });

    testWidgets('tap in processing cancels', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      pipeline.emitState(PipelineState.processing);
      await tester.pump();

      await tester.tap(find.byType(MicButton));
      await tester.pump();

      expect(pipeline.cancelCalled, isTrue);
    });

    testWidgets('tap in speaking cancels', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      pipeline.emitState(PipelineState.speaking);
      await tester.pump();

      await tester.tap(find.byType(MicButton));
      await tester.pump();

      expect(pipeline.cancelCalled, isTrue);
    });
  });

  group('touch target size', () {
    testWidgets('mic button area is at least 48dp', (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      final size = tester.getSize(find.byType(MicButton));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('landscape layout', () {
    testWidgets('renders mic button and status in landscape', (tester) async {
      tester.view.physicalSize = const Size(1200, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);

      expect(find.byType(MicButton), findsOneWidget);
      expect(find.text('Tap to speak'), findsOneWidget);
    });
  });

  group('state transitions', () {
    testWidgets(
        'full cycle: idle -> listening -> processing -> speaking -> idle',
        (tester) async {
      await tester.pumpWidget(buildTestApp(pipeline));
      await pumpFrames(tester);
      expect(find.text('Tap to speak'), findsOneWidget);

      pipeline.emitState(PipelineState.listening);
      await tester.pump();
      expect(find.text('Listening...'), findsOneWidget);

      pipeline.emitState(PipelineState.processing);
      await tester.pump();
      expect(find.text('Processing...'), findsOneWidget);

      pipeline.emitState(PipelineState.speaking);
      await tester.pump();
      expect(find.text('Speaking...'), findsOneWidget);

      pipeline.emitState(PipelineState.idle);
      await tester.pump();
      expect(find.text('Tap to speak'), findsOneWidget);
    });
  });
}
