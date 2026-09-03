import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';
import '../models/device.dart';

class MdnsDiscovery {
  static const _serviceType = '_devlink._tcp.local';
  final MDnsClient _client = MDnsClient();
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    await _client.start();
    _started = true;
  }

  Future<void> stop() async {
    if (!_started) return;
    _client.stop();
    _started = false;
  }

  Future<List<Device>> discoverOnce({Duration timeout = const Duration(seconds: 4)}) async {
    await start();
    final found = <String, Device>{};

    final ptrStream = _client
        .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_serviceType))
        .timeout(timeout, onTimeout: (sink) => sink.close());

    await for (final ptr in ptrStream) {
      await for (final srv in _client
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName))
          .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
        await for (final ip in _client
            .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))
            .timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
          final id = '${ip.address.address}:${srv.port}';
          found[id] = Device(id: id, name: ptr.domainName.replaceAll('.$_serviceType', ''),
              ip: ip.address.address, port: srv.port);
        }
      }
    }
    return found.values.toList();
  }
}