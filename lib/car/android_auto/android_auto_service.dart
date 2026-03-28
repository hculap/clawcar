import 'package:flutter/services.dart';

/// Bridge to native Kotlin Android Auto implementation.
///
/// The actual Android Auto UI is implemented natively using
/// the Android for Cars App Library (androidx.car.app).
/// This service communicates with the native side via platform channels.
class AndroidAutoService {
  static const _methodChannel = MethodChannel('com.clawcar/android_auto');
  static const _eventChannel = EventChannel('com.clawcar/android_auto_events');

  Stream<AndroidAutoEvent>? _eventStream;

  Stream<AndroidAutoEvent> get events {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return AndroidAutoEvent(
        type: map['type'] as String,
        data: map['data'] as Map<String, dynamic>?,
      );
    });
    return _eventStream!;
  }

  Future<bool> get isAvailable async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> updateState(String state) async {
    await _methodChannel.invokeMethod('updateState', {'state': state});
  }

  Future<void> updateStatusText(String text) async {
    await _methodChannel.invokeMethod('updateStatusText', {'text': text});
  }

  Future<void> updateContinuousMode(bool enabled) async {
    await _methodChannel.invokeMethod(
      'updateContinuousMode',
      {'enabled': enabled},
    );
  }
}

class AndroidAutoEvent {
  final String type;
  final Map<String, dynamic>? data;

  const AndroidAutoEvent({required this.type, this.data});
}
