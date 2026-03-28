import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

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
///
/// Extracted to allow injection in tests.
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

WebSocketChannel _defaultFactory(Uri uri) => WebSocketChannel.connect(uri);

/// OpenClaw Gateway Protocol v3 WebSocket client.
///
/// Handles:
/// - WebSocket connection to ws(s)://host:port
/// - Three frame types: req, res, event
/// - Request/response correlation via ID
/// - Challenge-response authentication handshake
/// - Exponential backoff reconnection (1s → 30s cap)
/// - Heartbeat ping every 15s with missed-pong detection
/// - Pending request timeout (30s)
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

  GatewayClient({
    required this.host,
    required this.port,
    this.useTls = false,
    this.authToken,
    WebSocketChannelFactory? channelFactory,
    Random? random,
  })  : _channelFactory = channelFactory ?? _defaultFactory,
        _random = random ?? Random();

  /// Current connection state.
  ConnectionState get state => _state;

  /// Stream of server-initiated events.
  Stream<GatewayEvent> get events => _eventController.stream;

  /// Stream of connection state transitions.
  Stream<ConnectionState> get stateChanges => _stateController.stream;

  /// Whether the client has been disposed.
  bool get isDisposed => _disposed;

  /// Establishes a WebSocket connection to the gateway.
  ///
  /// Throws [StateError] if the client has been disposed.
  /// Rethrows connection errors after scheduling a reconnect.
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
      _reconnectAttempt = 0;
      _missedPongs = 0;
      _startHeartbeat();
    } catch (e) {
      _setState(ConnectionState.disconnected);
      _scheduleReconnect();
      rethrow;
    }
  }

  /// Sends a [GatewayRequest] and returns the correlated [GatewayResponse].
  ///
  /// Throws [StateError] if not connected.
  /// Throws [TimeoutException] if no response within 30s.
  /// Throws [GatewayException] if the response has `ok: false`.
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

  /// Sends the `connect` handshake request to initiate authentication.
  ///
  /// The gateway may respond with a `connect.challenge` event (handled
  /// internally) before returning the final [GatewayResponse].
  Future<GatewayResponse> sendConnect({
    required String clientId,
    required String deviceId,
  }) {
    return send(
      GatewayRequest(
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
      ),
    );
  }

  /// Sends raw audio data to the gateway for STT processing.
  Future<GatewayResponse> sendAudio(List<int> audioData) {
    return send(
      GatewayRequest(
        method: 'voice.send',
        params: {
          'audio': base64Encode(audioData),
          'format': 'pcm16',
          'sampleRate': 16000,
        },
      ),
    );
  }

  /// Gracefully disconnects from the gateway.
  ///
  /// Cancels heartbeat and reconnect timers, closes the WebSocket,
  /// and fails all pending requests.
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectCompleter = null;

    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;

    _failPendingRequests(StateError('Disconnected from gateway'));
    _setState(ConnectionState.disconnected);
  }

  /// Permanently tears down the client.
  ///
  /// After disposal, the client cannot be reconnected.
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

  // ---------------------------------------------------------------------------
  // Message handling
  // ---------------------------------------------------------------------------

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
        // Server-initiated requests are not expected in v3.
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
        _handleChallenge(event);
      case 'connect.ok':
        _setState(ConnectionState.connected);
        _connectCompleter?.complete();
        _connectCompleter = null;
        _eventController.add(event);
      default:
        _eventController.add(event);
    }
  }

  /// Handles the challenge-response authentication handshake.
  ///
  /// When the server sends a `connect.challenge` event, the client
  /// responds with a `connect.respond` request containing the
  /// challenge solution (HMAC of the nonce with the auth token).
  void _handleChallenge(GatewayEvent event) {
    final nonce = event.payload['nonce'] as String?;
    if (nonce == null || authToken == null) {
      _setState(ConnectionState.connected);
      return;
    }

    _connectCompleter = Completer<void>();

    send(
      GatewayRequest(
        method: 'connect.respond',
        params: {
          'nonce': nonce,
          'token': authToken,
        },
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

  // ---------------------------------------------------------------------------
  // Error / close handling
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Heartbeat
  // ---------------------------------------------------------------------------

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
    }).catchError((_) {
      // Timeout or error already handled by send().
    });
  }

  // ---------------------------------------------------------------------------
  // Reconnection with exponential backoff + jitter
  // ---------------------------------------------------------------------------

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    final delay = _backoffDuration(_reconnectAttempt);
    _reconnectAttempt++;

    _reconnectTimer = Timer(delay, () {
      if (!_disposed && _state == ConnectionState.reconnecting) {
        connect().catchError((_) {
          // connect() already schedules the next reconnect on failure.
        });
      }
    });
  }

  /// Calculates exponential backoff with jitter.
  ///
  /// Base delay doubles each attempt (1s, 2s, 4s, …) capped at 30s.
  /// Jitter adds ±25% randomness to prevent thundering-herd.
  Duration _backoffDuration(int attempt) {
    final baseSeconds = min(1 << attempt, 30);
    final jitter = baseSeconds * 0.25 * (2 * _random.nextDouble() - 1);
    final totalMs = ((baseSeconds + jitter) * 1000).round();
    return Duration(milliseconds: max(totalMs, 500));
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _setState(ConnectionState newState) {
    if (_disposed || _state == newState) return;
    _state = newState;
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
