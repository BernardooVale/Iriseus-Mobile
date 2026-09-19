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
    _streamController.status.listen((s) {
      if (mounted) setState(() => _status = s);
    });

    widget.ws.enableAutoReconnect(widget.pcIp, 45678, () async {
      final deviceId = await _pairingManager.getOrCreateDeviceId();
      widget.ws.sendHello(deviceId, _pairingManager.deviceName);
      widget.ws.sendStartCamera();
      _streamController.startStreaming(widget.pcIp, 45679);
    });

    if (widget.ws.currentState == WsConnectionState.connected) {
      widget.ws.sendStartCamera();
      _streamController.startStreaming(widget.pcIp, 45679);
    }
  }

  @override
  void dispose() {
    // Não para o streaming ao sair da tela — o ForegroundService continua
    // Só envia stopCamera se for desconexão explícita pelo usuário
    _streamController.dispose();
    super.dispose();
  }

  Future<void> _disconnect() async {
    widget.ws.sendStopCamera();
    await _streamController.stopStreaming();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Preview da câmera
          const Positioned.fill(
            child: AndroidView(viewType: 'com.example.iriseus/camera_preview'),
          ),

          // Overlay superior com status
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Indicador de streaming (ponto pulsante)
                  _StatusChip(status: _status),
                  const Spacer(),
                  // Botão trocar câmera
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () => _streamController.switchCamera(),
                      icon: const Icon(Icons.cameraswitch, color: Colors.white),
                      tooltip: 'Trocar câmera',
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Aviso de erro
          if (_status == CameraStreamStatus.error)
            Center(
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: Colors.white, size: 40),
                    SizedBox(height: 8),
                    Text(
                      'Erro na transmissão',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Reconectando automaticamente...',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          // Botão desconectar (inferior)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Desconectar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatefulWidget {
  final CameraStreamStatus status;
  const _StatusChip({required this.status});

  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isStreaming = widget.status == CameraStreamStatus.streaming;
    final color = switch (widget.status) {
      CameraStreamStatus.streaming => Colors.green,
      CameraStreamStatus.error     => Colors.red,
      CameraStreamStatus.connecting => Colors.orange,
      CameraStreamStatus.idle      => Colors.grey,
    };
    final label = switch (widget.status) {
      CameraStreamStatus.streaming  => 'Transmitindo',
      CameraStreamStatus.connecting => 'Conectando...',
      CameraStreamStatus.error      => 'Erro',
      CameraStreamStatus.idle       => 'Ocioso',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isStreaming)
            FadeTransition(
              opacity: _pulse,
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            )
          else
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
