import 'dart:convert';

import 'package:uuid/uuid.dart';

const gatewayProtocolVersion = 3;
const defaultGatewayPort = 18789;

const _uuid = Uuid();

sealed class GatewayFrame {
  const GatewayFrame();

  factory GatewayFrame.fromJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final type = json['type'] as String;

    return switch (type) {
      'req' => GatewayRequest.fromMap(json),
      'res' => GatewayResponse.fromMap(json),
      'event' => GatewayEvent.fromMap(json),
      _ => throw FormatException('Unknown frame type: $type'),
    };
  }
}

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
    return GatewayEvent(
      event: map['event'] as String,
      payload: (map['payload'] as Map<String, dynamic>?) ?? {},
      seq: map['seq'] as int?,
      stateVersion: map['stateVersion'] as String?,
    );
  }
}

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
