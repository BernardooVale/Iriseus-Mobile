import 'package:flutter/material.dart';
import '../core/stream_controller.dart';
import '../core/ws_client.dart';
import '../core/pairing_manager.dart';

class CameraScreen extends StatefulWidget {
  final WsClient ws;
  final String pcIp;
  const CameraScreen({super.key, required this.ws, required this.pcIp});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final _streamController = CameraStreamController();
  final _pairingManager = PairingManager();
  CameraStreamStatus _status = CameraStreamStatus.idle;

  @override
  void initState() {
    super.initState();
    _streamController.init();
    _streamController.status.listen((s) => setState(() => _status = s));
    widget.ws.sendStartCamera();
    _streamController.startStreaming(widget.pcIp, 45679);

    widget.ws.enableAutoReconnect(widget.pcIp, 45678, () async {
      final deviceId = await _pairingManager.getOrCreateDeviceId();
      widget.ws.sendHello(deviceId, _pairingManager.deviceName);
      widget.ws.sendStartCamera();
      _streamController.startStreaming(widget.pcIp, 45679);
    });

    // inicia stream só se já conectado
    if (widget.ws.currentState == WsConnectionState.connected) {
      widget.ws.sendStartCamera();
      _streamController.startStreaming(widget.pcIp, 45679);
    }
  }

  @override
  void dispose() {
    widget.ws.sendStopCamera();
    _streamController.stopStreaming();
    _streamController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Streaming — ${widget.pcIp}'), actions: [
        IconButton(onPressed: () => _streamController.switchCamera(),
            icon: const Icon(Icons.cameraswitch)),
      ]),
      body: Stack(children: [
        const Positioned.fill(child: AndroidView(viewType: 'com.example.iriseus/camera_preview')),
        Positioned(top: 16, left: 16,
            child: Chip(label: Text(_statusLabel()), backgroundColor: _statusColor())),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            widget.ws.sendStopCamera();
            _streamController.stopStreaming();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.stop), label: const Text('Desconectar')),
    );
  }

  String _statusLabel() => switch (_status) {
    CameraStreamStatus.idle => 'Ocioso',
    CameraStreamStatus.connecting => 'Conectando...',
    CameraStreamStatus.streaming => 'Transmitindo',
    CameraStreamStatus.error => 'Erro',
  };

  Color _statusColor() => switch (_status) {
    CameraStreamStatus.streaming => Colors.green.shade200,
    CameraStreamStatus.error => Colors.red.shade200,
    _ => Colors.grey.shade300,
  };
}