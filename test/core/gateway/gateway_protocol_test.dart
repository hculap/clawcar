import 'dart:convert';

import 'package:clawcar/core/gateway/gateway_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GatewayFrame.fromJson', () {
    test('parses request frame', () {
      final json = jsonEncode({
        'type': 'req',
        'id': 'abc-123',
        'method': 'ping',
        'params': {'key': 'value'},
      });

      final frame = GatewayFrame.fromJson(json);

      expect(frame, isA<GatewayRequest>());
      final req = frame as GatewayRequest;
      expect(req.id, 'abc-123');
      expect(req.method, 'ping');
      expect(req.params, {'key': 'value'});
    });

    test('parses response frame with payload', () {
      final json = jsonEncode({
        'type': 'res',
        'id': 'abc-123',
        'ok': true,
        'payload': {'agents': []},
      });

      final frame = GatewayFrame.fromJson(json);

      expect(frame, isA<GatewayResponse>());
      final res = frame as GatewayResponse;
      expect(res.id, 'abc-123');
      expect(res.ok, isTrue);
      expect(res.payload, {'agents': []});
      expect(res.error, isNull);
    });

    test('parses response frame with error', () {
      final json = jsonEncode({
        'type': 'res',
        'id': 'abc-123',
        'ok': false,
        'error': {
          'code': 'AUTH_FAILED',
          'message': 'Invalid token',
          'retryable': false,
        },
      });

      final frame = GatewayFrame.fromJson(json);

      expect(frame, isA<GatewayResponse>());
      final res = frame as GatewayResponse;
      expect(res.ok, isFalse);
      expect(res.error, isNotNull);
      expect(res.error!.code, 'AUTH_FAILED');
      expect(res.error!.message, 'Invalid token');
      expect(res.error!.retryable, isFalse);
    });

    test('parses event frame', () {
      final json = jsonEncode({
        'type': 'event',
        'event': 'agent.status',
        'payload': {'status': 'busy'},
        'seq': 42,
        'stateVersion': 'v1',
      });

      final frame = GatewayFrame.fromJson(json);

      expect(frame, isA<GatewayEvent>());
      final event = frame as GatewayEvent;
      expect(event.event, 'agent.status');
      expect(event.payload, {'status': 'busy'});
      expect(event.seq, 42);
      expect(event.stateVersion, 'v1');
    });

    test('parses event with missing optional fields', () {
      final json = jsonEncode({
        'type': 'event',
        'event': 'connect.challenge',
      });

      final frame = GatewayFrame.fromJson(json) as GatewayEvent;
      expect(frame.payload, isEmpty);
      expect(frame.seq, isNull);
      expect(frame.stateVersion, isNull);
    });

    test('parses request with missing params', () {
      final json = jsonEncode({
        'type': 'req',
        'id': 'abc',
        'method': 'ping',
      });

      final frame = GatewayFrame.fromJson(json) as GatewayRequest;
      expect(frame.params, isEmpty);
    });

    test('throws FormatException for unknown frame type', () {
      final json = jsonEncode({'type': 'unknown', 'id': '1'});
      expect(
        () => GatewayFrame.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for non-object JSON', () {
      expect(
        () => GatewayFrame.fromJson('"just a string"'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for missing type field', () {
      final json = jsonEncode({'id': '1', 'method': 'ping'});
      expect(
        () => GatewayFrame.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for invalid JSON', () {
      expect(
        () => GatewayFrame.fromJson('not json at all'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('GatewayRequest', () {
    test('generates UUID when id is not provided', () {
      final req = GatewayRequest(method: 'ping');
      expect(req.id, isNotEmpty);
      expect(req.id.length, 36); // UUID v4 format
    });

    test('uses provided id', () {
      final req = GatewayRequest(id: 'custom-id', method: 'test');
      expect(req.id, 'custom-id');
    });

    test('toJson produces valid JSON with correct structure', () {
      final req = GatewayRequest(
        id: 'test-id',
        method: 'connect',
        params: {'key': 'value'},
      );

      final decoded = jsonDecode(req.toJson()) as Map<String, dynamic>;
      expect(decoded['type'], 'req');
      expect(decoded['id'], 'test-id');
      expect(decoded['method'], 'connect');
      expect(decoded['params'], {'key': 'value'});
    });

    test('toJson roundtrips through fromJson', () {
      final original = GatewayRequest(
        id: 'rt-id',
        method: 'chat.send',
        params: {'text': 'hello'},
      );

      final parsed = GatewayFrame.fromJson(original.toJson());
      expect(parsed, isA<GatewayRequest>());

      final req = parsed as GatewayRequest;
      expect(req.id, original.id);
      expect(req.method, original.method);
      expect(req.params, original.params);
    });
  });

  group('GatewayError', () {
    test('defaults retryable to false', () {
      final error = GatewayError.fromMap({
        'code': 'ERR',
        'message': 'fail',
      });
      expect(error.retryable, isFalse);
    });

    test('parses retryable flag', () {
      final error = GatewayError.fromMap({
        'code': 'RATE_LIMITED',
        'message': 'Too many requests',
        'retryable': true,
      });
      expect(error.retryable, isTrue);
    });
  });

  group('GatewayException', () {
    test('fromError copies fields', () {
      const error = GatewayError(
        code: 'TIMEOUT',
        message: 'Request timed out',
        retryable: true,
      );

      final exception = GatewayException.fromError(error);
      expect(exception.code, 'TIMEOUT');
      expect(exception.message, 'Request timed out');
      expect(exception.retryable, isTrue);
    });

    test('toString includes code and message', () {
      const exception = GatewayException(
        code: 'AUTH',
        message: 'Unauthorized',
      );
      expect(exception.toString(), 'GatewayException(AUTH): Unauthorized');
    });
  });

  group('constants', () {
    test('protocol version is 3', () {
      expect(gatewayProtocolVersion, 3);
    });

    test('default port is 18789', () {
      expect(defaultGatewayPort, 18789);
    });
  });
}
