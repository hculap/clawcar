import 'dart:convert';

import 'package:uuid/uuid.dart';

const gatewayProtocolVersion = 3;
const defaultGatewayPort = 18789;

const _uuid = Uuid();

/// Exception thrown when the gateway returns an error response.
class GatewayException implements Exception {
  final String code;
  final String message;
  final bool retryable;

  const GatewayException({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  factory GatewayException.fromError(GatewayError error) {
    return GatewayException(
      code: error.code,
      message: error.message,
      retryable: error.retryable,
    );
  }

  @override
  String toString() => 'GatewayException($code): $message';
}

/// Base sealed class for all gateway protocol frames.
///
/// The OpenClaw Gateway Protocol v3 uses three frame types:
/// - `req`   — client-to-server requests (correlated by ID)
/// - `res`   — server-to-client responses (correlated by ID)
/// - `event` — server-initiated push events
sealed class GatewayFrame {
  const GatewayFrame();

  /// Parses a raw JSON string into a typed [GatewayFrame].
  ///
  /// Throws [FormatException] if the JSON is malformed or the
  /// `type` field contains an unknown value.
  factory GatewayFrame.fromJson(String raw) {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Frame must be a JSON object');
    }
    final type = decoded['type'];
    if (type is! String) {
      throw const FormatException('Frame missing "type" field');
    }

    return switch (type) {
      'req' => GatewayRequest.fromMap(decoded),
      'res' => GatewayResponse.fromMap(decoded),
      'event' => GatewayEvent.fromMap(decoded),
      _ => throw FormatException('Unknown frame type: $type'),
    };
  }
}

/// A client-to-server request frame.
class GatewayRequest extends GatewayFrame {
  final String id;
  final String method;
  final Map<String, dynamic> params;

  GatewayRequest({
    String? id,
    required this.method,
    this.params = const {},
  }) : id = id ?? _uuid.v4();

  factory GatewayRequest.fromMap(Map<String, dynamic> map) {
    return GatewayRequest(
      id: map['id'] as String,
      method: map['method'] as String,
      params: (map['params'] as Map<String, dynamic>?) ?? {},
    );
  }

  String toJson() => jsonEncode({
        'type': 'req',
        'id': id,
        'method': method,
        'params': params,
      });
}

/// A server-to-client response frame, correlated to a request by [id].
class GatewayResponse extends GatewayFrame {
  final String id;
  final bool ok;
  final Map<String, dynamic>? payload;
  final GatewayError? error;

  const GatewayResponse({
    required this.id,
    required this.ok,
    this.payload,
    this.error,
  });

  factory GatewayResponse.fromMap(Map<String, dynamic> map) {
    return GatewayResponse(
      id: map['id'] as String,
      ok: map['ok'] as bool,
      payload: map['payload'] as Map<String, dynamic>?,
      error: map['error'] != null
          ? GatewayError.fromMap(map['error'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// A server-initiated push event.
class GatewayEvent extends GatewayFrame {
  final String event;
  final Map<String, dynamic> payload;
  final int? seq;
  final String? stateVersion;

  const GatewayEvent({
    required this.event,
    this.payload = const {},
    this.seq,
    this.stateVersion,
  });

  factory GatewayEvent.fromMap(Map<String, dynamic> map) {
    final sv = map['stateVersion'];
    return GatewayEvent(
      event: map['event'] as String,
      payload: (map['payload'] as Map<String, dynamic>?) ?? {},
      seq: map['seq'] as int?,
      stateVersion: sv is String ? sv : sv?.toString(),
    );
  }
}

/// Structured error returned inside a [GatewayResponse].
class GatewayError {
  final String code;
  final String message;
  final bool retryable;

  const GatewayError({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  factory GatewayError.fromMap(Map<String, dynamic> map) {
    return GatewayError(
      code: map['code'] as String,
      message: map['message'] as String,
      retryable: (map['retryable'] as bool?) ?? false,
    );
  }
}
