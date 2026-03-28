import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'gateway_protocol.dart';

enum ConnectionState {
  disconnected,
  connecting,
  authenticating,
  connected,
  reconnecting,
}

class GatewayClient {
  final String host;
  final int port;
  final bool useTls;
  final String? authToken;

  WebSocketChannel? _channel;
  final _pendingRequests = <String, Completer<GatewayResponse>>{};
  final _eventController = StreamController<GatewayEvent>.broadcast();
  final _stateController =
      StreamController<ConnectionState>.broadcast();

  ConnectionState _state = ConnectionState.disconnected;
  int _reconnectAttempt = 0;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  GatewayClient({
    required this.host,
    required this.port,
    this.useTls = false,
    this.authToken,
  });

  ConnectionState get state => _state;
  Stream<GatewayEvent> get events => _eventController.stream;
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  Future<void> connect() async {
    _setState(ConnectionState.connecting);

    try {
      final scheme = useTls ? 'wss' : 'ws';
      final uri = Uri.parse('$scheme://$host:$port');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _setState(ConnectionState.authenticating);
      _reconnectAttempt = 0;
      _startHeartbeat();
    } catch (e) {
      _setState(ConnectionState.disconnected);
      _scheduleReconnect();
      rethrow;
    }
  }

  Future<GatewayResponse> send(GatewayRequest request) {
    if (_channel == null) {
      throw StateError('Not connected to gateway');
    }

    final completer = Completer<GatewayResponse>();
    _pendingRequests[request.id] = completer;
    _channel!.sink.add(request.toJson());

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(request.id);
        throw TimeoutException('Request ${request.method} timed out');
      },
    );
  }

  Future<GatewayResponse> sendConnect({
    required String clientId,
    required String deviceId,
  }) {
    return send(GatewayRequest(
      method: 'connect',
      params: {
        'minProtocol': gatewayProtocolVersion,
        'maxProtocol': gatewayProtocolVersion,
        'client': {
          'id': clientId,
          'version': '0.1.0',
          'platform': 'mobile',
          'mode': 'operator',
        },
        'role': 'operator',
        'scopes': ['operator.read', 'operator.write'],
        if (authToken != null) 'auth': {'token': authToken},
        'device': {'id': deviceId},
      },
    ));
  }

  Future<void> sendAudio(List<int> audioData) {
    return send(GatewayRequest(
      method: 'voice.send',
      params: {
        'audio': base64Encode(audioData),
        'format': 'pcm16',
        'sampleRate': 16000,
      },
    )).then((_) {});
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(ConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _stateController.close();
    for (final completer in _pendingRequests.values) {
      completer.completeError(StateError('Client disposed'));
    }
    _pendingRequests.clear();
  }

  void _onMessage(dynamic raw) {
    final frame = GatewayFrame.fromJson(raw as String);

    switch (frame) {
      case GatewayResponse():
        final completer = _pendingRequests.remove(frame.id);
        if (completer != null) {
          completer.complete(frame);
        }
      case GatewayEvent():
        if (frame.event == 'connect.challenge') {
          _setState(ConnectionState.connected);
        }
        _eventController.add(frame);
      case GatewayRequest():
        break;
    }
  }

  void _onError(Object error) {
    _setState(ConnectionState.reconnecting);
    _scheduleReconnect();
  }

  void _onDone() {
    _heartbeatTimer?.cancel();
    if (_state != ConnectionState.disconnected) {
      _setState(ConnectionState.reconnecting);
      _scheduleReconnect();
    }
  }

  void _setState(ConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (_channel != null) {
          send(GatewayRequest(method: 'ping')).catchError((_) {});
        }
      },
    );
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = _backoffDuration(_reconnectAttempt);
    _reconnectAttempt++;

    _reconnectTimer = Timer(delay, () {
      if (_state == ConnectionState.reconnecting) {
        connect();
      }
    });
  }

  Duration _backoffDuration(int attempt) {
    final seconds = (1 << attempt).clamp(1, 30);
    return Duration(seconds: seconds);
  }
}
