import 'package:flutter_test/flutter_test.dart';

import 'package:clawcar/shared/models/vad_event.dart';

void main() {
  group('VadEvent', () {
    test('speechStart carries timestamp', () {
      final now = DateTime.now();
      final event = VadEvent.speechStart(timestamp: now);

      expect(event, isA<VadSpeechStart>());
      expect(event.timestamp, now);
    });

    test('speechEnd carries audio data and duration', () {
      final now = DateTime.now();
      final audio = [0.1, 0.2, -0.5, 0.8];
      const duration = Duration(milliseconds: 1200);

      final event = VadEvent.speechEnd(
        timestamp: now,
        audioData: audio,
        speechDuration: duration,
      );

      expect(event, isA<VadSpeechEnd>());
      final end = event as VadSpeechEnd;
      expect(end.audioData, audio);
      expect(end.speechDuration, duration);
    });

    test('supports pattern matching', () {
      final event = VadEvent.speechStart(timestamp: DateTime.now());

      final result = switch (event) {
        VadSpeechStart() => 'started',
        VadSpeechEnd() => 'ended',
      };

      expect(result, 'started');
    });

    test('supports equality via Freezed', () {
      final ts = DateTime(2026, 3, 28, 12, 0);
      final a = VadEvent.speechStart(timestamp: ts);
      final b = VadEvent.speechStart(timestamp: ts);
      final c = VadEvent.speechStart(timestamp: DateTime(2026, 3, 28, 13, 0));

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
