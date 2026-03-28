import 'package:flutter_test/flutter_test.dart';

import 'package:clawcar/core/audio/vad_config.dart';

void main() {
  group('VadConfig', () {
    test('has correct default thresholds for car environment', () {
      const config = VadConfig();

      expect(config.positiveSpeechThreshold, 0.8);
      expect(config.negativeSpeechThreshold, 0.35);
      expect(config.minSpeechFrames, 5);
      expect(config.redemptionFrames, 8);
      expect(config.preSpeechPadFrames, 3);
    });

    test('can be created with custom thresholds', () {
      const config = VadConfig(
        positiveSpeechThreshold: 0.9,
        negativeSpeechThreshold: 0.4,
        minSpeechFrames: 10,
        redemptionFrames: 12,
        preSpeechPadFrames: 5,
      );

      expect(config.positiveSpeechThreshold, 0.9);
      expect(config.negativeSpeechThreshold, 0.4);
      expect(config.minSpeechFrames, 10);
      expect(config.redemptionFrames, 12);
      expect(config.preSpeechPadFrames, 5);
    });

    test('supports equality comparison via Freezed', () {
      const a = VadConfig();
      const b = VadConfig();
      const c = VadConfig(positiveSpeechThreshold: 0.5);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('supports copyWith for immutable updates', () {
      const original = VadConfig();
      final updated = original.copyWith(positiveSpeechThreshold: 0.6);

      expect(original.positiveSpeechThreshold, 0.8);
      expect(updated.positiveSpeechThreshold, 0.6);
      expect(updated.negativeSpeechThreshold, 0.35);
    });

    test('serializes to and from JSON', () {
      const config = VadConfig(
        positiveSpeechThreshold: 0.75,
        minSpeechFrames: 7,
      );

      final json = config.toJson();
      final restored = VadConfig.fromJson(json);

      expect(restored, equals(config));
    });
  });
}
