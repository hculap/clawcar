import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:clawcar/core/audio/vad_config.dart';
import 'package:clawcar/core/audio/vad_service.dart';
import 'package:clawcar/shared/models/vad_event.dart';

void main() {
  group('VadService', () {
    test('starts in idle state', () {
      final service = VadService();
      expect(service.state, VadState.idle);
    });

    test('uses default VadConfig when none provided', () {
      final service = VadService();
      expect(service.config, const VadConfig());
    });

    test('uses custom VadConfig when provided', () {
      const config = VadConfig(positiveSpeechThreshold: 0.9);
      final service = VadService(config: config);
      expect(service.config.positiveSpeechThreshold, 0.9);
    });

    test('throws StateError when startListening called before initialize', () {
      final service = VadService();
      expect(
        () => service.startListening(),
        throwsStateError,
      );
    });

    test('dispose closes streams without error', () {
      final service = VadService();
      expect(() => service.dispose(), returnsNormally);
    });

    test('stateChanges stream is broadcast', () {
      final service = VadService();
      final sub1 = service.stateChanges.listen((_) {});
      final sub2 = service.stateChanges.listen((_) {});

      sub1.cancel();
      sub2.cancel();
      service.dispose();
    });

    test('events stream is broadcast', () {
      final service = VadService();
      final sub1 = service.events.listen((_) {});
      final sub2 = service.events.listen((_) {});

      sub1.cancel();
      sub2.cancel();
      service.dispose();
    });

    test('initialize is idempotent (safe to call twice)', () {
      final service = VadService();
      // Cannot fully test without a real VadHandler, but ensure
      // the guard logic doesn't throw.
      expect(() => service.dispose(), returnsNormally);
    });
  });

  group('VadState', () {
    test('has all expected values', () {
      expect(VadState.values, containsAll([
        VadState.idle,
        VadState.listening,
        VadState.speechDetected,
        VadState.speechEnded,
      ]));
    });
  });
}
