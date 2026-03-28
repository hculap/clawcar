import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:record/record.dart';

import 'package:clawcar/core/audio/audio_recorder.dart';

@GenerateMocks([AudioRecorder])
import 'audio_recorder_test.mocks.dart';

void main() {
  late MockAudioRecorder mockRecorder;
  late AudioRecorderService service;

  setUp(() {
    mockRecorder = MockAudioRecorder();
    service = AudioRecorderService(recorder: mockRecorder);
  });

  tearDown(() async {
    when(mockRecorder.stop()).thenAnswer((_) async => null);
    when(mockRecorder.dispose()).thenAnswer((_) async {});
    await service.dispose();
  });

  group('hasPermission', () {
    test('returns true when microphone permission is granted', () async {
      when(mockRecorder.hasPermission()).thenAnswer((_) async => true);

      final result = await service.hasPermission();

      expect(result, isTrue);
      verify(mockRecorder.hasPermission()).called(1);
    });

    test('returns false when microphone permission is denied', () async {
      when(mockRecorder.hasPermission()).thenAnswer((_) async => false);

      final result = await service.hasPermission();

      expect(result, isFalse);
    });
  });

  group('startRecording', () {
    test('streams PCM16 audio chunks via audioStream', () async {
      final streamController = StreamController<Uint8List>();
      when(mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(mockRecorder.startStream(any))
          .thenAnswer((_) async => streamController.stream);

      await service.startRecording();

      final chunks = <Uint8List>[];
      final sub = service.audioStream.listen(chunks.add);

      final testData = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      streamController.add(testData);
      await Future<void>.delayed(Duration.zero);

      expect(chunks, hasLength(1));
      expect(chunks.first, equals(testData));

      await sub.cancel();
      await streamController.close();
    });

    test('uses correct PCM16 config', () async {
      final streamController = StreamController<Uint8List>();
      when(mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(mockRecorder.startStream(any))
          .thenAnswer((_) async => streamController.stream);

      await service.startRecording();

      final captured =
          verify(mockRecorder.startStream(captureAny)).captured.single
              as RecordConfig;
      expect(captured.encoder, AudioEncoder.pcm16bits);
      expect(captured.sampleRate, 16000);
      expect(captured.numChannels, 1);
      expect(captured.autoGain, isTrue);
      expect(captured.echoCancel, isTrue);
      expect(captured.noiseSuppress, isTrue);

      await streamController.close();
    });

    test('sets isRecording to true', () async {
      final streamController = StreamController<Uint8List>();
      when(mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(mockRecorder.startStream(any))
          .thenAnswer((_) async => streamController.stream);

      expect(service.isRecording, isFalse);
      await service.startRecording();
      expect(service.isRecording, isTrue);

      await streamController.close();
    });

    test('throws StateError when permission is denied', () async {
      when(mockRecorder.hasPermission()).thenAnswer((_) async => false);

      expect(
        () => service.startRecording(),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          'Microphone permission not granted',
        )),
      );
    });

    test('is a no-op when already recording', () async {
      final streamController = StreamController<Uint8List>();
      when(mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(mockRecorder.startStream(any))
          .thenAnswer((_) async => streamController.stream);

      await service.startRecording();
      await service.startRecording();

      verify(mockRecorder.startStream(any)).called(1);

      await streamController.close();
    });

    test('forwards stream errors to audioStream', () async {
      final streamController = StreamController<Uint8List>();
      when(mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(mockRecorder.startStream(any))
          .thenAnswer((_) async => streamController.stream);

      await service.startRecording();

      final errors = <Object>[];
      final sub = service.audioStream.listen(
        (_) {},
        onError: (Object e) => errors.add(e),
      );

      streamController.addError(Exception('mic disconnected'));
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.first, isA<Exception>());

      await sub.cancel();
      await streamController.close();
    });
  });

  group('stopRecording', () {
    test('stops the recorder and resets isRecording', () async {
      final streamController = StreamController<Uint8List>();
      when(mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(mockRecorder.startStream(any))
          .thenAnswer((_) async => streamController.stream);
      when(mockRecorder.stop()).thenAnswer((_) async => null);

      await service.startRecording();
      expect(service.isRecording, isTrue);

      await service.stopRecording();
      expect(service.isRecording, isFalse);
      verify(mockRecorder.stop()).called(1);

      await streamController.close();
    });

    test('is a no-op when not recording', () async {
      when(mockRecorder.stop()).thenAnswer((_) async => null);

      await service.stopRecording();

      verifyNever(mockRecorder.stop());
    });
  });

  group('dispose', () {
    test('stops recording and disposes recorder', () async {
      final streamController = StreamController<Uint8List>();
      when(mockRecorder.hasPermission()).thenAnswer((_) async => true);
      when(mockRecorder.startStream(any))
          .thenAnswer((_) async => streamController.stream);
      when(mockRecorder.stop()).thenAnswer((_) async => null);
      when(mockRecorder.dispose()).thenAnswer((_) async {});

      await service.startRecording();
      await service.dispose();

      expect(service.isRecording, isFalse);
      verify(mockRecorder.stop()).called(1);
      verify(mockRecorder.dispose()).called(1);

      await streamController.close();
    });

    test('throws StateError on use after dispose', () async {
      when(mockRecorder.stop()).thenAnswer((_) async => null);
      when(mockRecorder.dispose()).thenAnswer((_) async {});

      await service.dispose();

      expect(() => service.hasPermission(), throwsStateError);
      expect(() => service.startRecording(), throwsStateError);
    });
  });

  group('audioRecordConfig', () {
    test('has correct values', () {
      expect(audioRecordConfig.encoder, AudioEncoder.pcm16bits);
      expect(audioRecordConfig.sampleRate, 16000);
      expect(audioRecordConfig.numChannels, 1);
      expect(audioRecordConfig.autoGain, isTrue);
      expect(audioRecordConfig.echoCancel, isTrue);
      expect(audioRecordConfig.noiseSuppress, isTrue);
    });
  });
}
