import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:clawcar/core/audio/audio_recorder.dart';
import 'package:clawcar/core/audio/energy_vad_config.dart';
import 'package:clawcar/core/audio/energy_vad_service.dart';
import 'package:clawcar/core/audio/vad_service.dart';
import 'package:clawcar/shared/models/vad_event.dart';

import 'audio_recorder_test.mocks.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a PCM16 little-endian chunk from normalised float samples.
Uint8List floatToPcm16(List<double> samples) {
  final bytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    bytes.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Generate a PCM16 chunk whose RMS energy is approximately [energy].
Uint8List chunkWithEnergy(double energy, {int sampleCount = 160}) {
  final samples = List<double>.filled(sampleCount, energy);
  return floatToPcm16(samples);
}

Uint8List silentChunk({int sampleCount = 160}) =>
    chunkWithEnergy(0.0, sampleCount: sampleCount);

Uint8List loudChunk({int sampleCount = 160}) =>
    chunkWithEnergy(0.15, sampleCount: sampleCount);

/// Creates an [AudioRecorderService] backed by a mock that won't hit
/// platform channels, plus a [StreamController] to push fake chunks.
({AudioRecorderService recorder, StreamController<Uint8List> chunks})
    makeFakeRecorder() {
  final mock = MockAudioRecorder();
  final chunks = StreamController<Uint8List>.broadcast();

  when(mock.hasPermission()).thenAnswer((_) async => true);
  when(mock.startStream(any)).thenAnswer((_) async => chunks.stream);
  when(mock.stop()).thenAnswer((_) async => null);
  when(mock.dispose()).thenAnswer((_) async {});

  return (recorder: AudioRecorderService(recorder: mock), chunks: chunks);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testConfig = EnergyVadConfig(
    energyThreshold: 0.02,
    speechStartFrames: 2,
    silenceFrames: 3,
    maxRecordingDuration: Duration(seconds: 5),
    preSpeechPadFrames: 2,
  );

  late StreamController<Uint8List> audio;
  late EnergyVadService service;
  late ({AudioRecorderService recorder, StreamController<Uint8List> chunks})
      fakeRec;

  setUp(() {
    audio = StreamController<Uint8List>.broadcast();
    fakeRec = makeFakeRecorder();
    service = EnergyVadService(recorder: fakeRec.recorder, config: testConfig);
  });

  tearDown(() async {
    service.dispose();
    await audio.close();
    await fakeRec.chunks.close();
  });

  group('EnergyVadService', () {
    test('starts in idle state', () {
      expect(service.state, VadState.idle);
    });

    test('throws when startListening called before initialize', () {
      expect(() => service.startListening(), throwsStateError);
    });

    test('transitions to listening on startListening', () async {
      await service.initialize();

      final states = <VadState>[];
      service.stateChanges.listen(states.add);

      await service.startListening(audioStream: audio.stream);
      await Future<void>.delayed(Duration.zero);

      expect(service.state, VadState.listening);
      expect(states, contains(VadState.listening));
    });

    test('starts the recorder when no external stream provided', () async {
      await service.initialize();
      await service.startListening();

      // The service should have called startRecording on the recorder,
      // which calls startStream on the mock.
      expect(fakeRec.recorder.isRecording, true);
    });

    test('does not start recorder when external stream provided', () async {
      await service.initialize();
      await service.startListening(audioStream: audio.stream);

      expect(fakeRec.recorder.isRecording, false);
    });

    test('detects speech start after speechStartFrames loud chunks', () async {
      await service.initialize();

      final events = <VadEvent>[];
      service.events.listen(events.add);

      await service.startListening(audioStream: audio.stream);

      audio.add(loudChunk());
      audio.add(loudChunk());

      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<VadSpeechStart>().length, 1);
      expect(service.state, VadState.speechDetected);
    });

    test('does not trigger speech start from transient noise', () async {
      await service.initialize();

      final events = <VadEvent>[];
      service.events.listen(events.add);

      await service.startListening(audioStream: audio.stream);

      audio.add(loudChunk());
      audio.add(silentChunk());

      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<VadSpeechStart>().length, 0);
      expect(service.state, VadState.listening);
    });

    test('emits speechEnd after silenceFrames silent chunks', () async {
      await service.initialize();

      final events = <VadEvent>[];
      service.events.listen(events.add);

      await service.startListening(audioStream: audio.stream);

      // Trigger speech start.
      audio.add(loudChunk());
      audio.add(loudChunk());

      // Continue speaking.
      audio.add(loudChunk());

      // Silence for silenceFrames chunks.
      audio.add(silentChunk());
      audio.add(silentChunk());
      audio.add(silentChunk());

      await Future<void>.delayed(Duration.zero);

      final ends = events.whereType<VadSpeechEnd>().toList();
      expect(ends.length, 1);
      expect(ends.first.audioData, isNotEmpty);
      expect(ends.first.speechDuration, isNot(Duration.zero));
      expect(service.state, VadState.speechEnded);
    });

    test('speechEnd audioData contains pre-speech padding', () async {
      await service.initialize();

      final events = <VadEvent>[];
      service.events.listen(events.add);

      await service.startListening(audioStream: audio.stream);

      // Push pre-speech frames that should be retained.
      audio.add(silentChunk(sampleCount: 10));
      audio.add(silentChunk(sampleCount: 10));

      // Trigger speech (speechStartFrames = 2).
      audio.add(loudChunk(sampleCount: 10));
      audio.add(loudChunk(sampleCount: 10));

      // End speech (silenceFrames = 3).
      audio.add(silentChunk(sampleCount: 10));
      audio.add(silentChunk(sampleCount: 10));
      audio.add(silentChunk(sampleCount: 10));

      await Future<void>.delayed(Duration.zero);

      final ends = events.whereType<VadSpeechEnd>().toList();
      expect(ends.length, 1);

      // Pre-speech pad (2 frames * 10) + speechStart frame (10)
      // + loud chunk during speech (10) + silence accumulated (30)
      expect(ends.first.audioData.length, greaterThanOrEqualTo(20));
    });

    test('stopListening returns to idle', () async {
      await service.initialize();
      await service.startListening(audioStream: audio.stream);

      await service.stopListening();

      expect(service.state, VadState.idle);
    });

    test('max duration timeout forces speechEnd during speech', () async {
      final shortConfig = EnergyVadConfig(
        energyThreshold: 0.02,
        speechStartFrames: 1,
        silenceFrames: 100,
        maxRecordingDuration: const Duration(milliseconds: 200),
        preSpeechPadFrames: 0,
      );

      final svc =
          EnergyVadService(recorder: fakeRec.recorder, config: shortConfig);
      await svc.initialize();

      final events = <VadEvent>[];
      svc.events.listen(events.add);

      await svc.startListening(audioStream: audio.stream);
      audio.add(loudChunk());
      await Future<void>.delayed(Duration.zero);

      // Wait for the timeout.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(events.whereType<VadSpeechEnd>().length, 1);

      svc.dispose();
    });

    test('max duration timeout emits error when no speech detected', () async {
      final shortConfig = EnergyVadConfig(
        energyThreshold: 0.02,
        speechStartFrames: 100,
        silenceFrames: 3,
        maxRecordingDuration: const Duration(milliseconds: 200),
        preSpeechPadFrames: 0,
      );

      final svc =
          EnergyVadService(recorder: fakeRec.recorder, config: shortConfig);
      await svc.initialize();

      final events = <VadEvent>[];
      svc.events.listen(events.add);

      await svc.startListening(audioStream: audio.stream);

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(events.whereType<VadError>().length, 1);

      svc.dispose();
    });

    test('dispose closes streams without error', () {
      expect(() => service.dispose(), returnsNormally);
    });

    test('stateChanges and events streams are broadcast', () {
      final sub1 = service.stateChanges.listen((_) {});
      final sub2 = service.stateChanges.listen((_) {});
      final sub3 = service.events.listen((_) {});
      final sub4 = service.events.listen((_) {});

      sub1.cancel();
      sub2.cancel();
      sub3.cancel();
      sub4.cancel();
    });

    test('uses provided config', () {
      expect(service.config, testConfig);
    });

    test('audio stream error emits VadError event', () async {
      await service.initialize();

      final events = <VadEvent>[];
      service.events.listen(events.add);

      await service.startListening(audioStream: audio.stream);

      audio.addError('mic disconnected');
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<VadError>().length, 1);
      expect(service.state, VadState.idle);
    });
  });
}
