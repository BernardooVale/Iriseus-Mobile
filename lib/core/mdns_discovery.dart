import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';
import '../models/device.dart';
import 'package:flutter/services.dart';

class MdnsDiscovery {
  static const _serviceType = '_iriseus._tcp.local';
  static const _wifiChannel = MethodChannel('com.example.iriseus/wifi');
  final MDnsClient _client = MDnsClient();
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    await _wifiChannel.invokeMethod('acquireMulticastLock');
    await _client.start();
    _started = true;
  }

  Future<void> stop() async {
    if (!_started) return;
    _client.stop();
    await _wifiChannel.invokeMethod('releaseMulticastLock');
    _started = false;
  }

  Future<List<Device>> discoverOnce({Duration timeout = const Duration(seconds: 4)}) async {
    await start();
    final found = <String, Device>{};
    print('[mDNS] iniciando scan...');

    final ptrStream = _client
        .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_serviceType))
        .timeout(timeout, onTimeout: (sink) => sink.close());

    await for (final ptr in ptrStream) {
      print('[mDNS] PTR encontrado: ${ptr.domainName}');
      await for (final srv in _client
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))
          .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
        print('[mDNS] SRV: ${srv.target}:${srv.port}');
        await for (final ip in _client
            .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))
            .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
          print('[mDNS] IP: ${ip.address.address}');
          final id = '${ip.address.address}:${srv.port}';
          found[id] = Device(id: id, name: ptr.domainName.replaceAll('.$_serviceType', ''),
              ip: ip.address.address, port: srv.port);
        }
      }
    }
    print('[mDNS] scan concluído. encontrados: ${found.length}');
    return found.values.toList();
  }
}