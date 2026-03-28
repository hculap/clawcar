import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:clawcar/core/audio/voice_pipeline.dart';
import 'package:clawcar/core/gateway/gateway_client.dart';
import 'package:clawcar/core/gateway/gateway_protocol.dart';
import 'package:clawcar/core/audio/audio_player_service.dart';
import 'package:clawcar/core/audio/vad_service.dart';
import 'package:clawcar/shared/models/vad_event.dart';

// --- Fakes ---

class FakeVadService extends VadService {
  final _eventController = StreamController<VadEvent>.broadcast();
  final _stateController = StreamController<VadState>.broadcast();
  bool initialized = false;
  bool listening = false;

  @override
  Stream<VadEvent> get events => _eventController.stream;

  @override
  Stream<VadState> get stateChanges => _stateController.stream;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> startListening({Stream<Uint8List>? audioStream}) async {
    listening = true;
    _stateController.add(VadState.listening);
  }

  @override
  Future<void> stopListening() async {
    listening = false;
    _stateController.add(VadState.idle);
  }

  void emitSpeechEnd(List<double> samples) {
    _eventController.add(VadEvent.speechEnd(
      timestamp: DateTime.now(),
      audioData: samples,
      speechDuration: const Duration(seconds: 1),
    ));
  }

  @override
  void dispose() {
    _eventController.close();
    _stateController.close();
  }
}

class FakeGatewayClient extends GatewayClient {
  final _eventController = StreamController<GatewayEvent>.broadcast();
  List<int>? lastSentAudio;
  bool sendAudioShouldFail = false;
  String? sendAudioErrorMessage;

  FakeGatewayClient() : super(host: 'localhost', port: 18789);

  @override
  Stream<GatewayEvent> get events => _eventController.stream;

  @override
  Future<GatewayResponse> sendAudio(List<int> audioData) async {
    if (sendAudioShouldFail) {
      throw Exception(sendAudioErrorMessage ?? 'Send failed');
    }
    lastSentAudio = audioData;
    return GatewayResponse(id: 'test', ok: true, payload: {'status': 'ok'});
  }

  void emitEvent(GatewayEvent event) {
    _eventController.add(event);
  }

  @override
  void dispose() {
    _eventController.close();
  }
}

class FakeAudioPlayerService implements AudioPlayerBase {
  Uint8List? lastPlayedAudio;
  String? lastMimeType;
  bool playShouldFail = false;
  final _playerStateController = StreamController<dynamic>.broadcast();

  @override
  Stream<dynamic> get playerState => _playerStateController.stream;

  @override
  bool get isPlaying => false;

  @override
  Future<void> playAudioBytes(Uint8List audioData, {String? mimeType}) async {
    if (playShouldFail) {
      throw Exception('Playback failed');
    }
    lastPlayedAudio = audioData;
    lastMimeType = mimeType;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  void dispose() {
    _playerStateController.close();
  }
}

// --- Tests ---

void main() {
  late FakeVadService vad;
  late FakeGatewayClient gateway;
  late FakeAudioPlayerService player;
  late VoicePipeline pipeline;

  setUp(() {
    vad = FakeVadService();
    gateway = FakeGatewayClient();
    player = FakeAudioPlayerService();
    pipeline = VoicePipeline(
      gateway: gateway,
      vad: vad,
      player: player,
    );
  });

  tearDown(() {
    pipeline.dispose();
    vad.dispose();
    gateway.dispose();
    player.dispose();
  });

  group('VoicePipeline', () {
    group('initialization', () {
      test('starts in idle state', () {
        expect(pipeline.state, PipelineState.idle);
      });

      test('initializes VAD on initialize()', () async {
        await pipeline.initialize();
        expect(vad.initialized, true);
      });
    });

    group('listening', () {
      test('transitions to listening state on startListening', () async {
        await pipeline.initialize();

        final states = <PipelineState>[];
        pipeline.stateChanges.listen(states.add);

        await pipeline.startListening();
        await Future<void>.delayed(Duration.zero);

        expect(pipeline.state, PipelineState.listening);
        expect(states, contains(PipelineState.listening));
      });

      test('transitions to idle on stopListening', () async {
        await pipeline.initialize();

        final states = <PipelineState>[];
        pipeline.stateChanges.listen(states.add);

        await pipeline.startListening();
        await pipeline.stopListening();
        await Future<void>.delayed(Duration.zero);

        expect(pipeline.state, PipelineState.idle);
        expect(states, contains(PipelineState.idle));
      });

      test('ignores startListening when processing', () async {
        await pipeline.initialize();
        await pipeline.startListening();

        // Simulate speech end to move to processing
        vad.emitSpeechEnd([0.5, -0.5, 0.3]);
        await Future<void>.delayed(Duration.zero);

        final stateBefore = pipeline.state;
        await pipeline.startListening();
        expect(pipeline.state, stateBefore);
      });
    });

    group('audio sending', () {
      test('sends PCM16-encoded audio to gateway on speech end', () async {
        await pipeline.initialize();
        await pipeline.startListening();

        final samples = [0.5, -0.5, 0.0, 1.0, -1.0];
        vad.emitSpeechEnd(samples);
        await Future<void>.delayed(Duration.zero);

        expect(gateway.lastSentAudio, isNotNull);
        expect(gateway.lastSentAudio!.length, samples.length * 2);
      });

      test('transitions to processing after speech end', () async {
        await pipeline.initialize();
        await pipeline.startListening();

        final states = <PipelineState>[];
        pipeline.stateChanges.listen(states.add);

        vad.emitSpeechEnd([0.1, 0.2]);
        await Future<void>.delayed(Duration.zero);

        expect(states, contains(PipelineState.processing));
      });

      test('emits error and recovers on send failure', () async {
        await pipeline.initialize();
        await pipeline.startListening();

        gateway.sendAudioShouldFail = true;
        gateway.sendAudioErrorMessage = 'Network error';

        final errors = <VoicePipelineError>[];
        pipeline.errors.listen(errors.add);

        vad.emitSpeechEnd([0.1]);
        await Future<void>.delayed(Duration.zero);

        expect(errors, hasLength(1));
        expect(errors.first.code, 'send_failed');
        expect(errors.first.retryable, true);
        expect(pipeline.state, PipelineState.error);
      });
    });

    group('audio response', () {
      test('plays audio from voice.audio event', () async {
        await pipeline.initialize();

        final audioBytes = Uint8List.fromList([1, 2, 3, 4]);
        final audioBase64 = base64Encode(audioBytes);

        gateway.emitEvent(GatewayEvent(
          event: 'voice.audio',
          payload: {'audio': audioBase64, 'format': 'mp3'},
        ));
        await Future<void>.delayed(Duration.zero);

        expect(player.lastPlayedAudio, audioBytes);
        expect(player.lastMimeType, 'audio/mpeg');
      });

      test('handles opus format', () async {
        await pipeline.initialize();

        final audioBytes = Uint8List.fromList([5, 6, 7]);
        gateway.emitEvent(GatewayEvent(
          event: 'voice.audio',
          payload: {'audio': base64Encode(audioBytes), 'format': 'opus'},
        ));
        await Future<void>.delayed(Duration.zero);

        expect(player.lastMimeType, 'audio/opus');
      });

      test('transitions to speaking then idle on playback', () async {
        await pipeline.initialize();

        final states = <PipelineState>[];
        pipeline.stateChanges.listen(states.add);

        gateway.emitEvent(GatewayEvent(
          event: 'voice.audio',
          payload: {'audio': base64Encode([1, 2]), 'format': 'mp3'},
        ));
        await Future<void>.delayed(Duration.zero);

        expect(states, contains(PipelineState.speaking));
        expect(states.last, PipelineState.idle);
      });

      test('emits error on missing audio data', () async {
        await pipeline.initialize();

        final errors = <VoicePipelineError>[];
        pipeline.errors.listen(errors.add);

        gateway.emitEvent(const GatewayEvent(
          event: 'voice.audio',
          payload: {},
        ));
        await Future<void>.delayed(Duration.zero);

        expect(errors, hasLength(1));
        expect(errors.first.code, 'invalid_response');
      });

      test('emits error on playback failure', () async {
        await pipeline.initialize();
        player.playShouldFail = true;

        final errors = <VoicePipelineError>[];
        pipeline.errors.listen(errors.add);

        gateway.emitEvent(GatewayEvent(
          event: 'voice.audio',
          payload: {'audio': base64Encode([1, 2]), 'format': 'mp3'},
        ));
        await Future<void>.delayed(Duration.zero);

        expect(errors, hasLength(1));
        expect(errors.first.code, 'playback_failed');
      });
    });

    group('voice error events', () {
      test('emits error from voice.error event', () async {
        await pipeline.initialize();

        final errors = <VoicePipelineError>[];
        pipeline.errors.listen(errors.add);

        gateway.emitEvent(const GatewayEvent(
          event: 'voice.error',
          payload: {
            'code': 'stt_failed',
            'message': 'Speech recognition failed',
            'retryable': true,
          },
        ));
        await Future<void>.delayed(Duration.zero);

        expect(errors, hasLength(1));
        expect(errors.first.code, 'stt_failed');
        expect(errors.first.message, 'Speech recognition failed');
        expect(errors.first.retryable, true);
        expect(pipeline.state, PipelineState.error);
      });
    });

    group('cancel', () {
      test('stops player and VAD, returns to idle', () async {
        await pipeline.initialize();
        await pipeline.startListening();

        await pipeline.cancel();

        expect(pipeline.state, PipelineState.idle);
        expect(vad.listening, false);
      });
    });
  });

  group('floatToPcm16', () {
    test('converts silence to zero bytes', () {
      final result = floatToPcm16([0.0, 0.0]);
      expect(result.length, 4);
      expect(result.buffer.asByteData().getInt16(0, Endian.little), 0);
      expect(result.buffer.asByteData().getInt16(2, Endian.little), 0);
    });

    test('converts full scale positive', () {
      final result = floatToPcm16([1.0]);
      final value = result.buffer.asByteData().getInt16(0, Endian.little);
      expect(value, 32767);
    });

    test('converts full scale negative', () {
      final result = floatToPcm16([-1.0]);
      final value = result.buffer.asByteData().getInt16(0, Endian.little);
      expect(value, -32767);
    });

    test('clamps values beyond range', () {
      final result = floatToPcm16([2.0, -2.0]);
      final pos = result.buffer.asByteData().getInt16(0, Endian.little);
      final neg = result.buffer.asByteData().getInt16(2, Endian.little);
      expect(pos, 32767);
      expect(neg, -32767);
    });
  });
}
