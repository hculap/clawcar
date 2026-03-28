import 'dart:async';

import 'package:nsd/nsd.dart';

import '../../shared/models/gateway_config.dart';
import 'gateway_protocol.dart';

const _serviceType = '_openclaw-gw._tcp';

class GatewayDiscovery {
  Discovery? _discovery;
  final _gatewaysController =
      StreamController<List<GatewayConfig>>.broadcast();
  final _gateways = <String, GatewayConfig>{};

  Stream<List<GatewayConfig>> get gateways => _gatewaysController.stream;
  List<GatewayConfig> get currentGateways => _gateways.values.toList();

  Future<void> startDiscovery() async {
    _discovery = await startNsdDiscovery(_serviceType);

    _discovery!.addServiceListener((service, status) {
      final host = service.host;
      final port = service.port;

      if (host == null || port == null) return;

      final txt = service.txt ?? {};
      final key = '$host:$port';

      switch (status) {
        case ServiceStatus.found:
          final config = GatewayConfig(
            host: host,
            port: port,
            displayName: _txtValue(txt, 'displayName') ?? service.name ?? host,
            useTls: _txtValue(txt, 'gatewayTls') == '1',
            tlsSha256: _txtValue(txt, 'gatewayTlsSha256'),
            tailnetDns: _txtValue(txt, 'tailnetDns'),
          );
          _gateways[key] = config;
          _gatewaysController.add(_gateways.values.toList());

        case ServiceStatus.lost:
          _gateways.remove(key);
          _gatewaysController.add(_gateways.values.toList());
      }
    });
  }

  Future<void> stopDiscovery() async {
    await _discovery?.cancel();
    _discovery = null;
  }

  void dispose() {
    stopDiscovery();
    _gatewaysController.close();
  }

  static String? _txtValue(Map<String, Uint8List?> txt, String key) {
    final bytes = txt[key];
    if (bytes == null) return null;
    return String.fromCharCodes(bytes);
  }

  static GatewayConfig manualConfig(String host, {int? port}) {
    return GatewayConfig(
      host: host,
      port: port ?? defaultGatewayPort,
      displayName: host,
    );
  }
}
