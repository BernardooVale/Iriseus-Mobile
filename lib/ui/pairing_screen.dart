import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/pairing_manager.dart';
import '../core/ws_client.dart';
import 'camera_screen.dart';

class PairingScreen extends StatefulWidget {
  final WsClient ws;
  final String? ip;
  final int port;
  const PairingScreen({super.key, required this.ws, required this.ip, required this.port});
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> with SingleTickerProviderStateMixin {
  final _pairingManager = PairingManager();
  final _pinController = TextEditingController();
  late final TabController _tabController;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _handleQrDetect(BarcodeCapture capture) async {
    if (_busy || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;
    setState(() => _busy = true);
    try {
      final payload = QrPayload.fromJsonString(raw);
      await widget.ws.connect(payload.ip, payload.port);
      final deviceId = await _pairingManager.getOrCreateDeviceId();
      widget.ws.sendHello(deviceId, _pairingManager.deviceName);
      final welcome = await widget.ws.waitForType('welcome');

      final accepted = await _pairingManager.pair(
        ws: widget.ws, pin: payload.pin, pcPublicKeyB64: payload.pk,
        pcDeviceId: welcome?['deviceId'] ?? 'unknown',
        pcDeviceName: welcome?['deviceName'] ?? 'DevLink PC',
        pcIp: payload.ip,
      );

      if (!mounted) return;
      if (accepted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => CameraScreen(ws: widget.ws, pcIp: payload.ip)));
      } else {
        setState(() => _error = 'Pareamento rejeitado. Tente novamente.');
      }
    } catch (e) {
      setState(() => _error = 'QR inválido ou falha de conexão.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handlePinSubmit() async {
    if (widget.ip == null) {
      setState(() => _error = 'IP do PC desconhecido. Use descoberta automática ou QR.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.ws.connect(widget.ip!, widget.port);
      final deviceId = await _pairingManager.getOrCreateDeviceId();
      widget.ws.sendHello(deviceId, _pairingManager.deviceName);
      final welcome = await widget.ws.waitForType('welcome');

      // pcPublicKeyB64 vazio — ver gap de protocolo no pairing_manager.
      final accepted = await _pairingManager.pair(
        ws: widget.ws, pin: _pinController.text.trim(), pcPublicKeyB64: '',
        pcDeviceId: welcome?['deviceId'] ?? 'unknown',
        pcDeviceName: welcome?['deviceName'] ?? 'DevLink PC',
        pcIp: widget.ip!,
      );

      if (!mounted) return;
      if (accepted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => CameraScreen(ws: widget.ws, pcIp: widget.ip!)));
      } else {
        setState(() => _error = 'PIN incorreto ou rejeitado.');
      }
    } catch (e) {
      setState(() => _error = 'Falha ao conectar ao PC.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parear dispositivo'),
          bottom: TabBar(controller: _tabController,
              tabs: const [Tab(text: 'QR Code'), Tab(text: 'PIN manual')])),
      body: Column(children: [
        if (_error != null)
          Container(color: Colors.red.shade100, padding: const EdgeInsets.all(8),
              width: double.infinity, child: Text(_error!, style: const TextStyle(color: Colors.red))),
        Expanded(
          child: TabBarView(controller: _tabController, children: [
            MobileScanner(onDetect: _handleQrDetect),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                TextField(controller: _pinController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'PIN exibido no PC')),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _handlePinSubmit,
                    child: _busy ? const CircularProgressIndicator() : const Text('Parear')),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}