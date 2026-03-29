import 'package:flutter/services.dart';

/// Bridge to native Swift CarPlay implementation.
///
/// The actual CarPlay UI is implemented natively using CPVoiceControlTemplate
/// (iOS 26.4+ Voice-based Conversational Apps category).
/// This service communicates with the native side via platform channels.
class CarPlayService {
  static const _methodChannel = MethodChannel('com.clawcar/carplay');
  static const _eventChannel = EventChannel('com.clawcar/carplay_events');

  Stream<CarPlayEvent>? _eventStream;

  Stream<CarPlayEvent> get events {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return CarPlayEvent(
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

  Future<void> setAgents(List<dynamic> agents) async {
    final mapped = agents.map((a) => a is Map ? a : {'id': a.toString()}).toList();
    await _methodChannel.invokeMethod('setAgents', {'agents': mapped});
  }

  Future<void> setSelectedAgent(String agentId) async {
    await _methodChannel.invokeMethod('setSelectedAgent', {'agentId': agentId});
  }
}

class CarPlayEvent {
  final String type;
  final Map<String, dynamic>? data;

  const CarPlayEvent({required this.type, this.data});
}
