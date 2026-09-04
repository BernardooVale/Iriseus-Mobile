import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/mdns_discovery.dart';
import '../core/pairing_manager.dart';
import '../core/ws_client.dart';
import '../models/device.dart';
import 'pairing_screen.dart';
import 'camera_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _mdns = MdnsDiscovery();
  final _pairingManager = PairingManager();
  List<Device> _devices = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await [Permission.camera, Permission.nearbyWifiDevices].request();
    await _tryUsbAutoConnect();
    await _scan();
  }

  Future<void> _tryUsbAutoConnect() async {
    final ws = WsClient();
    try {
      await ws.connect('127.0.0.1', 45678).timeout(const Duration(seconds: 1));
      await _proceedAfterConnect(ws, '127.0.0.1');
    } catch (_) {
      // sem USB — segue fluxo normal de mDNS
    }
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final found = await _mdns.discoverOnce();
    if (mounted) setState(() { _devices = found; _scanning = false; });
  }

  Future<void> _connectUsb() async {
    final ws = WsClient();
    try {
      await ws.connect('127.0.0.1', 45678);
      await _proceedAfterConnect(ws, '127.0.0.1');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sem conexão USB. Verifique adb reverse.')));
      }
    }
  }

  Future<void> _connectDevice(Device device) async {
    final pairing = await _pairingManager.loadPairingInfo();
    final ws = WsClient();
    await ws.connect(device.ip, device.port);

    if (pairing != null) {
      final deviceId = await _pairingManager.getOrCreateDeviceId();
      ws.sendHello(deviceId, _pairingManager.deviceName);
      await _pairingManager.updateLastKnownIp(device.ip);
      await _proceedAfterConnect(ws, device.ip);
    } else {
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => PairingScreen(ws: ws, ip: device.ip, port: device.port)));
    }
  }

  Future<void> _proceedAfterConnect(WsClient ws, String ip) async {
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => CameraScreen(ws: ws, pcIp: ip)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iriseus'),
          actions: [IconButton(onPressed: _scan, icon: const Icon(Icons.refresh))]),
      body: Column(children: [
        if (_scanning) const LinearProgressIndicator(),
        Expanded(
          child: _devices.isEmpty
              ? const Center(child: Text('Nenhum PC encontrado na rede'))
              : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (_, i) {
                final d = _devices[i];
                return ListTile(
                    leading: const Icon(Icons.computer),
                    title: Text(d.name),
                    subtitle: Text('${d.ip}:${d.port}'),
                    onTap: () => _connectDevice(d));
              }),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _connectUsb,
                icon: const Icon(Icons.usb), label: const Text('Conectar via USB'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PairingScreen(ws: WsClient(), ip: null, port: 45678))),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Parear novo dispositivo'))),
          ]),
        ),
      ]),
    );
  }
}