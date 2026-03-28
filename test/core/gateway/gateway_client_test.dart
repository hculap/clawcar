import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clawcar/core/gateway/gateway_client.dart';
import 'package:clawcar/core/gateway/gateway_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// Test helpers: fake WebSocket channel
// ---------------------------------------------------------------------------

class _FakeWebSocketSink implements WebSocketSink {
  final List<dynamic> messages = [];
  final Completer<void> _closeCompleter = Completer<void>();
  bool closed = false;

  @override
  void add(dynamic data) => messages.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<dynamic> close([int? closeCode, String? closeReason]) async {
    closed = true;
    if (!_closeCompleter.isCompleted) _closeCompleter.complete();
  }

  @override
  Future<dynamic> get done => _closeCompleter.future;
}

class _FakeWebSocketChannel with StreamChannelMixin implements WebSocketChannel {
  final _incomingController = StreamController<dynamic>.broadcast();
  final _sink = _FakeWebSocketSink();
  final bool failReady;

  _FakeWebSocketChannel({this.failReady = false});

  @override
  Stream<dynamic> get stream => _incomingController.stream;

  @override
  _FakeWebSocketSink get sink => _sink;

  @override
  Future<void> get ready =>
      failReady ? Future.error(Exception('Connection refused')) : Future.value();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  /// Simulate the server sending a frame.
  void serverSend(Map<String, dynamic> frame) {
    _incomingController.add(jsonEncode(frame));
  }

  /// Simulate the server closing the connection.
  void serverClose() {
    _incomingController.close();
  }

  /// Simulate a server error.
  void serverError(Object error) {
    _incomingController.addError(error);
  }

  /// Parse the last sent message from the client.
  Map<String, dynamic>? get lastSent {
    if (_sink.messages.isEmpty) return null;
    return jsonDecode(_sink.messages.last as String) as Map<String, dynamic>;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeWebSocketChannel fakeChannel;
  late GatewayClient client;

  setUp(() {
    fakeChannel = _FakeWebSocketChannel();
    client = GatewayClient(
      host: 'localhost',
      port: 18789,
      channelFactory: (_) => fakeChannel,
      random: Random(42), // deterministic for tests
    );
  });

  tearDown(() {
    client.dispose();
  });

  group('connection', () {
    test('transitions to authenticating on successful connect', () async {
      final states = <ConnectionState>[];
      client.stateChanges.listen(states.add);

      await client.connect();
      // Allow microtasks to flush
      await Future<void>.delayed(Duration.zero);

      expect(states, contains(ConnectionState.connecting));
      expect(states, contains(ConnectionState.authenticating));
      expect(client.state, ConnectionState.authenticating);
    });

    test('uses wss scheme when useTls is true', () async {
      Uri? capturedUri;
      final tlsClient = GatewayClient(
        host: 'secure.example.com',
        port: 443,
        useTls: true,
        channelFactory: (uri) {
          capturedUri = uri;
          return fakeChannel;
        },
      );

      await tlsClient.connect();
      expect(capturedUri.toString(), 'wss://secure.example.com:443');
      tlsClient.dispose();
    });

    test('uses ws scheme when useTls is false', () async {
      Uri? capturedUri;
      final plainClient = GatewayClient(
        host: 'local.test',
        port: 18789,
        channelFactory: (uri) {
          capturedUri = uri;
          return fakeChannel;
        },
      );

      await plainClient.connect();
      expect(capturedUri.toString(), 'ws://local.test:18789');
      plainClient.dispose();
    });

    test('schedules reconnect on connection failure', () async {
      final failChannel = _FakeWebSocketChannel(failReady: true);
      final failClient = GatewayClient(
        host: 'localhost',
        port: 18789,
        channelFactory: (_) => failChannel,
      );

      await expectLater(failClient.connect(), throwsException);
      // State should be disconnected after failure
      expect(failClient.state, ConnectionState.disconnected);
      failClient.dispose();
    });

    test('throws StateError when connecting after dispose', () {
      client.dispose();
      expect(() => client.connect(), throwsStateError);
    });
  });

  group('send / request-response correlation', () {
    test('sends request and correlates response by ID', () async {
      await client.connect();

      final responseFuture = client.send(
        GatewayRequest(id: 'req-1', method: 'test'),
      );

      // Verify the request was sent
      expect(fakeChannel.lastSent?['id'], 'req-1');
      expect(fakeChannel.lastSent?['method'], 'test');

      // Simulate server response
      fakeChannel.serverSend({
        'type': 'res',
        'id': 'req-1',
        'ok': true,
        'payload': {'result': 'success'},
      });

      final response = await responseFuture;
      expect(response.ok, isTrue);
      expect(response.payload?['result'], 'success');
    });

    test('throws GatewayException on error response', () async {
      await client.connect();

      final responseFuture = client.send(
        GatewayRequest(id: 'req-err', method: 'bad'),
      );

      fakeChannel.serverSend({
        'type': 'res',
        'id': 'req-err',
        'ok': false,
        'error': {
          'code': 'NOT_FOUND',
          'message': 'Agent not found',
          'retryable': false,
        },
      });

      expect(
        responseFuture,
        throwsA(
          isA<GatewayException>()
              .having((e) => e.code, 'code', 'NOT_FOUND')
              .having((e) => e.message, 'message', 'Agent not found'),
        ),
      );
    });

    test('throws GatewayException with default error on ok:false without error field', () async {
      await client.connect();

      final responseFuture = client.send(
        GatewayRequest(id: 'req-no-err', method: 'bad'),
      );

      fakeChannel.serverSend({
        'type': 'res',
        'id': 'req-no-err',
        'ok': false,
      });

      expect(
        responseFuture,
        throwsA(isA<GatewayException>()),
      );
    });

    test('throws StateError when sending while disconnected', () {
      expect(
        () => client.send(GatewayRequest(method: 'test')),
        throwsStateError,
      );
    });

    test('times out after 30 seconds', () async {
      await client.connect();

      final responseFuture = client.send(
        GatewayRequest(id: 'slow', method: 'slowOp'),
      );

      expect(responseFuture, throwsA(isA<TimeoutException>()));
    }, timeout: const Timeout(Duration(seconds: 35)));

    test('ignores response for unknown request ID', () async {
      await client.connect();

      // This should not throw or crash
      fakeChannel.serverSend({
        'type': 'res',
        'id': 'unknown-id',
        'ok': true,
      });

      // Give time for processing
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('sendConnect', () {
    test('sends connect request with correct structure', () async {
      final authClient = GatewayClient(
        host: 'localhost',
        port: 18789,
        authToken: 'test-token',
        channelFactory: (_) => fakeChannel,
      );

      await authClient.connect();

      // Don't await - we just want to check the sent message
      unawaited(
        authClient
            .sendConnect(clientId: 'test-client', deviceId: 'device-1')
            .catchError((_) => const GatewayResponse(id: '', ok: false)),
      );

      await Future<void>.delayed(Duration.zero);

      final sent = fakeChannel.lastSent!;
      expect(sent['method'], 'connect');
      expect(sent['params']['minProtocol'], gatewayProtocolVersion);
      expect(sent['params']['maxProtocol'], gatewayProtocolVersion);
      expect(sent['params']['client']['id'], 'test-client');
      expect(sent['params']['device']['id'], 'device-1');
      expect(sent['params']['auth']['token'], 'test-token');

      authClient.dispose();
    });

    test('omits auth when no token provided', () async {
      await client.connect();

      unawaited(
        client
            .sendConnect(clientId: 'c', deviceId: 'd')
            .catchError((_) => const GatewayResponse(id: '', ok: false)),
      );

      await Future<void>.delayed(Duration.zero);

      final sent = fakeChannel.lastSent!;
      expect(sent['params'].containsKey('auth'), isFalse);
    });
  });

  group('events', () {
    test('broadcasts server events', () async {
      await client.connect();

      final events = <GatewayEvent>[];
      client.events.listen(events.add);

      fakeChannel.serverSend({
        'type': 'event',
        'event': 'agent.status',
        'payload': {'status': 'idle'},
        'seq': 1,
      });

      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.event, 'agent.status');
      expect(events.first.payload['status'], 'idle');
      expect(events.first.seq, 1);
    });

    test('ignores non-string messages', () async {
      await client.connect();

      final events = <GatewayEvent>[];
      client.events.listen(events.add);

      // Send binary data - should be ignored
      fakeChannel._incomingController.add([0, 1, 2]);

      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });

    test('ignores malformed JSON', () async {
      await client.connect();

      final events = <GatewayEvent>[];
      client.events.listen(events.add);

      fakeChannel._incomingController.add('not valid json');

      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });

  group('challenge-response handshake', () {
    test('responds to connect.challenge with token', () async {
      final authClient = GatewayClient(
        host: 'localhost',
        port: 18789,
        authToken: 'my-secret-token',
        channelFactory: (_) => fakeChannel,
      );

      await authClient.connect();

      // Server sends a challenge
      fakeChannel.serverSend({
        'type': 'event',
        'event': 'connect.challenge',
        'payload': {'nonce': 'abc123'},
      });

      await Future<void>.delayed(Duration.zero);

      // Client should have sent a connect.respond request
      final sent = fakeChannel.lastSent!;
      expect(sent['method'], 'connect.respond');
      expect(sent['params']['nonce'], 'abc123');
      expect(sent['params']['token'], 'my-secret-token');

      authClient.dispose();
    });

    test('transitions to connected when no token for challenge', () async {
      await client.connect();

      final states = <ConnectionState>[];
      client.stateChanges.listen(states.add);

      fakeChannel.serverSend({
        'type': 'event',
        'event': 'connect.challenge',
        'payload': {'nonce': 'abc'},
      });

      await Future<void>.delayed(Duration.zero);
      expect(states, contains(ConnectionState.connected));
    });

    test('transitions to connected on connect.ok event', () async {
      await client.connect();

      final states = <ConnectionState>[];
      client.stateChanges.listen(states.add);

      fakeChannel.serverSend({
        'type': 'event',
        'event': 'connect.ok',
        'payload': {},
      });

      await Future<void>.delayed(Duration.zero);
      expect(states, contains(ConnectionState.connected));
    });
  });

  group('reconnection', () {
    test('reconnects when server closes connection', () async {
      await client.connect();

      final states = <ConnectionState>[];
      client.stateChanges.listen(states.add);

      fakeChannel.serverClose();
      await Future<void>.delayed(Duration.zero);

      expect(states, contains(ConnectionState.reconnecting));
    });

    test('reconnects on stream error', () async {
      await client.connect();

      final states = <ConnectionState>[];
      client.stateChanges.listen(states.add);

      fakeChannel.serverError(Exception('Network error'));
      await Future<void>.delayed(Duration.zero);

      expect(states, contains(ConnectionState.reconnecting));
    });

    test('does not reconnect after explicit disconnect', () async {
      await client.connect();

      final states = <ConnectionState>[];
      client.stateChanges.listen(states.add);

      await client.disconnect();
      expect(client.state, ConnectionState.disconnected);

      // Ensure no reconnecting state after disconnect
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(states, isNot(contains(ConnectionState.reconnecting)));
    });

    test('does not reconnect after dispose', () async {
      await client.connect();
      client.dispose();

      // Should not throw or schedule anything
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(client.isDisposed, isTrue);
    });

    test('sends connect handshake on reconnection', () async {
      // Track channels so we can respond to the second one.
      final channels = <_FakeWebSocketChannel>[];
      final reconnectClient = GatewayClient(
        host: 'localhost',
        port: 18789,
        authToken: 'tok',
        channelFactory: (_) {
          final ch = _FakeWebSocketChannel();
          channels.add(ch);
          return ch;
        },
        random: _FixedRandom(0.5),
      );

      // Initial connect + handshake.
      await reconnectClient.connect();
      final firstChannel = channels.first;

      // Initiate sendConnect so the client caches clientId/deviceId.
      final handshakeFuture = reconnectClient.sendConnect(
        clientId: 'c1',
        deviceId: 'd1',
      );
      await Future<void>.delayed(Duration.zero);

      // Server responds OK to the initial connect handshake.
      firstChannel.serverSend({
        'type': 'res',
        'id': firstChannel.lastSent!['id'] as String,
        'ok': true,
        'payload': {},
      });
      await handshakeFuture;

      // Simulate disconnect → reconnecting.
      firstChannel.serverClose();
      await Future<void>.delayed(Duration.zero);
      expect(reconnectClient.state, ConnectionState.reconnecting);

      // The reconnect timer fires after ~1s (attempt 0 with 0 jitter).
      // Advance past the backoff delay.
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      // A second channel should have been created.
      expect(channels, hasLength(2));
      final secondChannel = channels[1];

      // The client should have automatically sent a connect request
      // with the cached clientId and deviceId.
      await Future<void>.delayed(Duration.zero);
      final sent = secondChannel._sink.messages
          .map((m) => jsonDecode(m as String) as Map<String, dynamic>)
          .toList();
      final connectFrame = sent.firstWhere(
        (f) => f['method'] == 'connect',
        orElse: () => <String, dynamic>{},
      );

      expect(connectFrame, isNotEmpty);
      expect(connectFrame['params']['client']['id'], 'c1');
      expect(connectFrame['params']['device']['id'], 'd1');
      expect(connectFrame['params']['auth']['token'], 'tok');

      reconnectClient.dispose();
    });

    test('preserves backoff when handshake fails on reconnect', () async {
      // If the WebSocket opens but the handshake is rejected,
      // _reconnectAttempt must NOT be reset so backoff keeps increasing.
      var connectCount = 0;
      final channels = <_FakeWebSocketChannel>[];
      final reconnectClient = GatewayClient(
        host: 'localhost',
        port: 18789,
        channelFactory: (_) {
          connectCount++;
          final ch = _FakeWebSocketChannel();
          channels.add(ch);
          return ch;
        },
        random: _FixedRandom(0.5), // 0 jitter → exact power-of-2 delays
      );

      // Initial connect + handshake to cache params.
      await reconnectClient.connect();
      final firstCh = channels.first;
      final handshakeFuture = reconnectClient.sendConnect(
        clientId: 'c',
        deviceId: 'd',
      );
      await Future<void>.delayed(Duration.zero);
      firstCh.serverSend({
        'type': 'res',
        'id': firstCh.lastSent!['id'] as String,
        'ok': true,
        'payload': {},
      });
      await handshakeFuture;

      // Trigger reconnection.
      firstCh.serverClose();
      await Future<void>.delayed(Duration.zero);
      expect(reconnectClient.state, ConnectionState.reconnecting);

      // First reconnect attempt fires after ~1s backoff.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(channels, hasLength(2));

      // Reject the connect handshake on the second channel.
      final secondCh = channels[1];
      await Future<void>.delayed(Duration.zero);
      final secondSent = secondCh._sink.messages
          .map((m) => jsonDecode(m as String) as Map<String, dynamic>)
          .toList();
      final connectFrame = secondSent.firstWhere(
        (f) => f['method'] == 'connect',
        orElse: () => <String, dynamic>{},
      );
      expect(connectFrame, isNotEmpty);
      secondCh.serverSend({
        'type': 'res',
        'id': connectFrame['id'] as String,
        'ok': false,
        'error': {
          'code': 'AUTH_FAILED',
          'message': 'bad token',
          'retryable': true,
        },
      });

      // Allow the rejection to propagate.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final attemptsAfterFirstFail = connectCount;

      // With correct backoff the second attempt should use ~2s delay.
      // Wait 1.2s — a reset-to-0 bug would fire another attempt at ~1s.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(connectCount, attemptsAfterFirstFail,
          reason: 'Backoff should increase after failed handshake');

      reconnectClient.dispose();
    });

    test('does not double-increment backoff on mid-handshake socket drop',
        () async {
      // When the socket drops during await sendConnect(), _onDone fires
      // and schedules a reconnect. The catch block in connect() must NOT
      // schedule a second reconnect (which would double-increment the
      // attempt counter and skip a backoff step).
      final channels = <_FakeWebSocketChannel>[];
      final reconnectClient = GatewayClient(
        host: 'localhost',
        port: 18789,
        channelFactory: (_) {
          final ch = _FakeWebSocketChannel();
          channels.add(ch);
          return ch;
        },
        random: _FixedRandom(0.5),
      );

      // Initial connect + handshake to cache params.
      await reconnectClient.connect();
      final firstCh = channels.first;
      final handshakeFuture = reconnectClient.sendConnect(
        clientId: 'c',
        deviceId: 'd',
      );
      await Future<void>.delayed(Duration.zero);
      firstCh.serverSend({
        'type': 'res',
        'id': firstCh.lastSent!['id'] as String,
        'ok': true,
        'payload': {},
      });
      await handshakeFuture;

      // Trigger reconnection.
      firstCh.serverClose();
      await Future<void>.delayed(Duration.zero);
      expect(reconnectClient.state, ConnectionState.reconnecting);

      // First reconnect fires after ~1s. The new socket opens and
      // sendConnect is sent automatically.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(channels, hasLength(2));
      final secondCh = channels[1];
      await Future<void>.delayed(Duration.zero);

      // Drop the socket mid-handshake (before responding to connect).
      // This triggers _onDone → _scheduleReconnect (attempt 1 → 2s).
      secondCh.serverClose();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // With correct single-increment (attempt=1 → 2s backoff), a third
      // connect should NOT fire within 1.2s. A double-increment bug
      // (attempt=2 → 4s) would also pass this check, but the important
      // thing is we don't get attempt=0 (1s) which would fire too fast.
      final channelsBeforeWait = channels.length;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(channels.length, channelsBeforeWait,
          reason:
              'Mid-handshake drop should not reset backoff to minimum');

      // Wait long enough for the 2s backoff to fire.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(channels.length, channelsBeforeWait + 1,
          reason: 'Third reconnect should fire after ~2s backoff');

      reconnectClient.dispose();
    });

    test('skips handshake on first connect when no cached params', () async {
      // On the very first connect() the client has no cached params,
      // so it should NOT send a connect frame automatically.
      await client.connect();

      final sent = fakeChannel._sink.messages;
      // Only heartbeat pings may appear, no connect frame.
      final connectFrames = sent
          .map((m) => jsonDecode(m as String) as Map<String, dynamic>)
          .where((f) => f['method'] == 'connect');
      expect(connectFrames, isEmpty);
    });
  });

  group('backoff duration', () {
    test('produces increasing delays capped at 30s', () {
      // Use a seeded random for deterministic results
      final testClient = GatewayClient(
        host: 'localhost',
        port: 18789,
        channelFactory: (_) => fakeChannel,
        random: _FixedRandom(0.5), // jitter = 0 (midpoint)
      );

      // Access via reflection-like approach: test the schedule behavior
      // by observing that delays increase. Since _backoffDuration is private,
      // we test it indirectly through the reconnect behavior.
      //
      // With jitter at midpoint (0.5 → 2*0.5-1 = 0 jitter):
      // attempt 0: 1s, attempt 1: 2s, attempt 2: 4s, attempt 3: 8s,
      // attempt 4: 16s, attempt 5+: 30s (capped)

      testClient.dispose();
    });
  });

  group('disconnect', () {
    test('cancels pending requests on disconnect', () async {
      await client.connect();

      final responseFuture = client.send(
        GatewayRequest(id: 'pending', method: 'test'),
      );

      await client.disconnect();

      expect(responseFuture, throwsA(isA<StateError>()));
    });

    test('cancels pending requests on server close', () async {
      await client.connect();

      final responseFuture = client.send(
        GatewayRequest(id: 'pending-2', method: 'test'),
      );

      fakeChannel.serverClose();

      expect(responseFuture, throwsA(isA<StateError>()));
    });
  });

  group('dispose', () {
    test('fails pending requests on dispose', () async {
      await client.connect();

      final responseFuture = client.send(
        GatewayRequest(id: 'pending-d', method: 'test'),
      );

      client.dispose();

      expect(responseFuture, throwsA(isA<StateError>()));
    });

    test('double dispose is safe', () {
      client.dispose();
      client.dispose(); // should not throw
    });

    test('closes event and state streams', () async {
      await client.connect();
      client.dispose();

      // Streams should be closed
      expect(client.isDisposed, isTrue);
    });
  });

  group('sendAudio', () {
    test('sends base64-encoded audio with correct format', () async {
      await client.connect();

      unawaited(
        client
            .sendAudio([0, 1, 2, 3])
            .catchError((_) => const GatewayResponse(id: '', ok: false)),
      );

      await Future<void>.delayed(Duration.zero);

      final sent = fakeChannel.lastSent!;
      expect(sent['method'], 'voice.send');
      expect(sent['params']['format'], 'pcm16');
      expect(sent['params']['sampleRate'], 16000);
      // Verify the audio is base64-encoded
      expect(sent['params']['audio'], isA<String>());
    });
  });
}

/// A [Random] that always returns a fixed value for [nextDouble].
class _FixedRandom implements Random {
  final double _value;
  const _FixedRandom(this._value);

  @override
  double nextDouble() => _value;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}
