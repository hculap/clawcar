import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../shared/models/agent.dart';
import 'gateway_protocol.dart';

/// Connection lifecycle states for [GatewayClient].
enum ConnectionState {
  disconnected,
  connecting,
  authenticating,
  connected,
  reconnecting,
}

/// Configuration constants for the gateway client.
abstract final class GatewayClientDefaults {
  static const heartbeatInterval = Duration(seconds: 15);
  static const requestTimeout = Duration(seconds: 30);
  static const reconnectMin = Duration(seconds: 1);
  static const reconnectMax = Duration(seconds: 30);
  static const maxMissedPongs = 2;
}

/// Factory function for creating WebSocket channels.
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

WebSocketChannel _defaultFactory(Uri uri) => WebSocketChannel.connect(uri);

const _uuid = Uuid();

/// OpenClaw Gateway Protocol v3 WebSocket client.
class GatewayClient {
  final String host;
  final int port;
  final bool useTls;
  final String? authToken;
  final WebSocketChannelFactory _channelFactory;
  final Random _random;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _pendingRequests = <String, Completer<GatewayResponse>>{};
  final _eventController = StreamController<GatewayEvent>.broadcast();
  final _stateController = StreamController<ConnectionState>.broadcast();

  ConnectionState _state = ConnectionState.disconnected;
  int _reconnectAttempt = 0;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _missedPongs = 0;
  bool _disposed = false;
  Completer<void>? _connectCompleter;
  Completer<String>? _nonceCompleter;

  // Cached auth for reconnection.
  String? _cachedAuthToken;
  Future<Map<String, dynamic>> Function()? _authParamsBuilder;

  GatewayClient({
    required this.host,
    required this.port,
    this.useTls = false,
    this.authToken,
    WebSocketChannelFactory? channelFactory,
    Random? random,
  })  : _channelFactory = channelFactory ?? _defaultFactory,
        _random = random ?? Random();

  ConnectionState get state => _state;
  Stream<GatewayEvent> get events => _eventController.stream;
  Stream<ConnectionState> get stateChanges => _stateController.stream;
  bool get isDisposed => _disposed;

  Future<void> connect() async {
    if (_disposed) {
      throw StateError('Cannot connect: client has been disposed');
    }

    _setState(ConnectionState.connecting);

    try {
      final scheme = useTls ? 'wss' : 'ws';
      final uri = Uri.parse('$scheme://$host:$port');
      _channel = _channelFactory(uri);
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _setState(ConnectionState.authenticating);
      _missedPongs = 0;

      if (_authParamsBuilder != null) {
        final freshParams = await _authParamsBuilder!();
        await sendConnect(authParams: freshParams);
        _reconnectAttempt = 0;
      } else if (_cachedAuthToken != null) {
        await sendConnect(authToken: _cachedAuthToken);
        _reconnectAttempt = 0;
      }
    } catch (e) {
      if (_state != ConnectionState.reconnecting) {
        _setState(ConnectionState.reconnecting);
        _scheduleReconnect();
      }
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
      GatewayClientDefaults.requestTimeout,
      onTimeout: () {
        _pendingRequests.remove(request.id);
        throw TimeoutException(
          'Request ${request.method} timed out',
          GatewayClientDefaults.requestTimeout,
        );
      },
    );
  }

  /// Returns a future that completes with the nonce from the next
  /// `connect.challenge` event.
  Future<String> waitForChallengeNonce() {
    _nonceCompleter ??= Completer<String>();
    return _nonceCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _nonceCompleter = null;
        throw TimeoutException('No challenge nonce received');
      },
    );
  }

  Future<GatewayResponse> sendConnect({
    String? authToken,
    Map<String, dynamic>? authParams,
    Future<Map<String, dynamic>> Function()? authParamsBuilder,
  }) async {
    final params = <String, dynamic>{
      'minProtocol': gatewayProtocolVersion,
      'maxProtocol': gatewayProtocolVersion,
      'client': {
        'id': 'cli',
        'version': '0.1.0',
        'platform': 'mobile',
        'mode': 'cli',
      },
      'role': 'operator',
      'scopes': ['operator.admin', 'operator.read', 'operator.write'],
    };

    if (authParams != null) {
      params.addAll(authParams);
      _authParamsBuilder = authParamsBuilder;
      _cachedAuthToken = null;
    } else {
      final token = authToken ?? this.authToken;
      if (token != null) {
        params['auth'] = {'token': token};
      }
      _authParamsBuilder = null;
      _cachedAuthToken = token;
    }

    final response = await send(
      GatewayRequest(method: 'connect', params: params),
    );
    if (response.ok) {
      _setState(ConnectionState.connected);
    }
    return response;
  }

  /// Sends a chat message and collects the full assistant response text
  /// via streaming events.
  ///
  /// Returns the complete response text once the `chat` event with
  /// `state: "final"` is received.
  Future<String> sendChat(String message) async {
    final sessionKey = _uuid.v4();
    final idempotencyKey = _uuid.v4();

    // Set up event listener BEFORE sending to avoid missing early events
    final responseCompleter = Completer<String>();
    final buffer = StringBuffer();

    late final StreamSubscription<GatewayEvent> sub;
    sub = events.listen((event) {
      if (responseCompleter.isCompleted) return;

      final payload = event.payload;

      if (event.event == 'chat') {
        final state = payload['state'] as String?;
        if (state == 'final') {
          final msg = payload['message'] as Map<String, dynamic>?;
          final content = msg?['content'] as List<dynamic>?;
          final text = content
              ?.whereType<Map<String, dynamic>>()
              .where((c) => c['type'] == 'text')
              .map((c) => c['text'] as String?)
              .where((t) => t != null)
              .join('');
          responseCompleter.complete(text ?? buffer.toString());
          sub.cancel();
        } else if (state == 'error') {
          final errorMsg =
              payload['errorMessage'] as String? ?? 'Chat error';
          responseCompleter.completeError(
            GatewayException(code: 'CHAT_ERROR', message: errorMsg),
          );
          sub.cancel();
        }
      }
    });

    // Send the chat request
    final response = await send(
      GatewayRequest(
        method: 'chat.send',
        params: {
          'message': message,
          'sessionKey': sessionKey,
          'idempotencyKey': idempotencyKey,
        },
      ),
    );

    if (!response.ok) {
      sub.cancel();
      throw GatewayException(
        code: response.error?.code ?? 'CHAT_SEND_FAILED',
        message: response.error?.message ?? 'Failed to send chat',
      );
    }

    // Wait for the complete response (60s timeout for LLM responses)
    return responseCompleter.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        sub.cancel();
        final partial = buffer.toString();
        if (partial.isNotEmpty) return partial;
        throw TimeoutException('Chat response timed out');
      },
    );
  }

  /// Converts text to speech via the gateway's TTS provider.
  ///
  /// Returns the audio file path on the gateway host.
  Future<String> convertTts(String text) async {
    final response = await send(
      GatewayRequest(
        method: 'tts.convert',
        params: {'text': text},
      ),
    );

    if (!response.ok) {
      throw GatewayException(
        code: response.error?.code ?? 'TTS_FAILED',
        message: response.error?.message ?? 'TTS conversion failed',
      );
    }

    final audioPath = response.payload?['audioPath'] as String?;
    if (audioPath == null) {
      throw const GatewayException(
        code: 'TTS_NO_PATH',
        message: 'TTS response missing audioPath',
      );
    }

    return audioPath;
  }

  static List<Agent> extractAgentsFromSnapshot(GatewayResponse response) {
    final snapshot =
        response.payload?['snapshot'] as Map<String, dynamic>? ?? {};
    final health = snapshot['health'] as Map<String, dynamic>? ?? {};
    final agents = (health['agents'] as List<dynamic>?) ?? [];
    return agents.map((a) {
      final map = a as Map<String, dynamic>;
      return Agent(
        id: map['agentId'] as String,
        name: map['agentId'] as String,
        isDefault: map['isDefault'] as bool? ?? false,
      );
    }).toList();
  }

  /// Gracefully disconnects from the gateway.
  Future<void> disconnect({bool clearAuth = false}) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectCompleter = null;
    _nonceCompleter = null;

    if (clearAuth) {
      _cachedAuthToken = null;
      _authParamsBuilder = null;
    }

    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;

    _failPendingRequests(StateError('Disconnected from gateway'));
    _setState(ConnectionState.disconnected);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectCompleter = null;

    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;

    _failPendingRequests(StateError('Client disposed'));
    _eventController.close();
    _stateController.close();
  }

  // -- Message handling --

  void _onMessage(dynamic raw) {
    if (raw is! String) return;

    final GatewayFrame frame;
    try {
      frame = GatewayFrame.fromJson(raw);
    } on FormatException {
      return;
    }

    switch (frame) {
      case GatewayResponse():
        _handleResponse(frame);
      case GatewayEvent():
        _handleEvent(frame);
      case GatewayRequest():
        break;
    }
  }

  void _handleResponse(GatewayResponse response) {
    _missedPongs = 0;

    final completer = _pendingRequests.remove(response.id);
    if (completer == null) return;

    if (response.ok) {
      completer.complete(response);
    } else {
      final error = response.error ??
          const GatewayError(code: 'UNKNOWN', message: 'Request failed');
      completer.completeError(GatewayException.fromError(error));
    }
  }

  void _handleEvent(GatewayEvent event) {
    switch (event.event) {
      case 'connect.challenge':
        final nonce = event.payload['nonce'] as String?;
        if (nonce != null &&
            _nonceCompleter != null &&
            !_nonceCompleter!.isCompleted) {
          _nonceCompleter!.complete(nonce);
          _nonceCompleter = null;
        } else {
          _handleChallenge(event);
        }
      case 'connect.ok':
        _setState(ConnectionState.connected);
        _connectCompleter?.complete();
        _connectCompleter = null;
        _eventController.add(event);
      default:
        _eventController.add(event);
    }
  }

  void _handleChallenge(GatewayEvent event) {
    final nonce = event.payload['nonce'] as String?;
    final token = _cachedAuthToken ?? authToken;
    if (nonce == null || token == null) {
      _setState(ConnectionState.connected);
      return;
    }

    _connectCompleter = Completer<void>();

    send(
      GatewayRequest(
        method: 'connect.respond',
        params: {'nonce': nonce, 'token': token},
      ),
    ).then((_) {
      _setState(ConnectionState.connected);
      _connectCompleter?.complete();
      _connectCompleter = null;
    }).catchError((Object error) {
      _connectCompleter?.completeError(error);
      _connectCompleter = null;
      disconnect();
    });
  }

  // -- Error / close handling --

  void _onError(Object error) {
    if (_disposed) return;
    _cleanupConnection();
    _setState(ConnectionState.reconnecting);
    _scheduleReconnect();
  }

  void _onDone() {
    if (_disposed) return;
    _cleanupConnection();
    if (_state != ConnectionState.disconnected) {
      _setState(ConnectionState.reconnecting);
      _scheduleReconnect();
    }
  }

  void _cleanupConnection() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _failPendingRequests(StateError('Connection lost'));
  }

  // -- Heartbeat --

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _missedPongs = 0;

    _heartbeatTimer = Timer.periodic(
      GatewayClientDefaults.heartbeatInterval,
      (_) => _sendPing(),
    );
  }

  void _sendPing() {
    if (_channel == null || _disposed) return;

    if (_missedPongs >= GatewayClientDefaults.maxMissedPongs) {
      _onError(StateError('Heartbeat timeout: missed $_missedPongs pongs'));
      return;
    }

    _missedPongs++;
    send(GatewayRequest(method: 'ping')).then((_) {
      _missedPongs = 0;
    }).catchError((_) {});
  }

  // -- Reconnection --

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    final delay = _backoffDuration(_reconnectAttempt);
    _reconnectAttempt++;

    _reconnectTimer = Timer(delay, () {
      if (!_disposed && _state == ConnectionState.reconnecting) {
        connect().catchError((_) {});
      }
    });
  }

  Duration _backoffDuration(int attempt) {
    final baseSeconds = min(1 << attempt, 30);
    final jitter = baseSeconds * 0.25 * (2 * _random.nextDouble() - 1);
    final totalMs = ((baseSeconds + jitter) * 1000).round();
    return Duration(milliseconds: max(totalMs, 500));
  }

  // -- Helpers --

  void _setState(ConnectionState newState) {
    if (_disposed || _state == newState) return;
    _state = newState;
    if (newState == ConnectionState.connected) {
      _startHeartbeat();
    }
    _stateController.add(newState);
  }

  void _failPendingRequests(Object error) {
    final pending = Map.of(_pendingRequests);
    _pendingRequests.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }
}
