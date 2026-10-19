import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import '../core/stream_controller.dart';
import '../core/ws_client.dart';
import '../core/pairing_manager.dart';
import '../core/file_transfer_manager.dart';

class CameraScreen extends StatefulWidget {
  final WsClient ws;
  final String pcIp;
  final FileTransferManager? fileManager;
  const CameraScreen({
    super.key,
    required this.ws,
    required this.pcIp,
    this.fileManager,
  });
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final _streamController = CameraStreamController();
  final _pairingManager = PairingManager();
  late final FileTransferManager _fileTransferManager;
  CameraStreamStatus _status = CameraStreamStatus.idle;
  StreamMode _mode = StreamMode.camera;

  bool _ownsFileManager = false;

  @override
  void initState() {
    super.initState();
    if (widget.fileManager != null) {
      _fileTransferManager = widget.fileManager!;
      _ownsFileManager = false;
    } else {
      _fileTransferManager = FileTransferManager(widget.ws);
      _ownsFileManager = true;
    }
    _streamController.init();
    _streamController.status.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _streamController.mode.listen((m) {
      if (mounted) setState(() => _mode = m);
    });

    widget.ws.enableAutoReconnect(widget.pcIp, 45678, () async {
      final deviceId = await _pairingManager.getOrCreateDeviceId();
      widget.ws.sendHello(deviceId, _pairingManager.deviceName);
      if (_mode == StreamMode.screen) {
        widget.ws.sendStartScreen();
      } else {
        widget.ws.sendStartCamera();
      }
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
    if (_ownsFileManager) {
      _fileTransferManager.dispose();
    }
    _streamController.dispose();
    super.dispose();
  }

  Future<void> _toggleScreenShare() async {
    if (_mode == StreamMode.camera) {
      final ok = await _streamController.startScreenShare();
      if (ok) {
        widget.ws.sendStartScreen();
      }
    } else {
      await _streamController.stopScreenShare();
      widget.ws.sendStopScreen();
    }
  }

  Future<void> _disconnect() async {
    if (_mode == StreamMode.screen) {
      widget.ws.sendStopScreen();
    }
    widget.ws.sendStopCamera();
    await _streamController.stopStreaming();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Preview da câmera preenchendo a tela inteira quando em modo câmera
          // Anti-loop: removido e substituído por painel estático quando em modo tela
          if (_mode == StreamMode.camera)
            PlatformViewLink(
              viewType: 'com.example.iriseus/camera_preview',
              surfaceFactory: (context, controller) {
                return AndroidViewSurface(
                  controller: controller as AndroidViewController,
                  hitTestBehavior: PlatformViewHitTestBehavior.opaque,
                  gestureRecognizers: const {},
                );
              },
              onCreatePlatformView: (params) {
                return PlatformViewsService.initExpensiveAndroidView(
                  id: params.id,
                  viewType: 'com.example.iriseus/camera_preview',
                  layoutDirection: TextDirection.ltr,
                  creationParams: const {},
                  creationParamsCodec: const StandardMessageCodec(),
                  onFocus: () {
                    params.onFocusChanged(true);
                  },
                )
                  ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                  ..create();
              },
            )
          else
            // Painel estático anti-loop durante a transmissão da tela
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.screen_share_rounded, size: 56, color: Colors.blueAccent),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Transmitindo a tela do celular',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'A tela está sendo espelhada no PC.\nVocê pode minimizar este aplicativo com segurança.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // Overlay superior com status, botão de tela e botão de câmera
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Indicador de streaming (ponto pulsante)
                    _StatusChip(status: _status, mode: _mode),
                    const Spacer(),

                    // Botão transmitir/parar tela
                    Container(
                      decoration: BoxDecoration(
                        color: _mode == StreamMode.screen
                            ? Colors.blueAccent.withValues(alpha: 0.8)
                            : Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: _toggleScreenShare,
                        icon: Icon(
                          _mode == StreamMode.screen
                              ? Icons.stop_screen_share_outlined
                              : Icons.screen_share_outlined,
                          color: Colors.white,
                        ),
                        tooltip: _mode == StreamMode.screen
                            ? 'Voltar para a câmera'
                            : 'Transmitir tela do celular',
                      ),
                    ),

                    // Botão trocar câmera (só visível no modo câmera)
                    if (_mode == StreamMode.camera) ...[
                      const SizedBox(width: 8),
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
                  ],
                ),
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
  final StreamMode mode;
  const _StatusChip({required this.status, required this.mode});

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
      CameraStreamStatus.streaming => widget.mode == StreamMode.screen ? Colors.blueAccent : Colors.green,
      CameraStreamStatus.error     => Colors.red,
      CameraStreamStatus.connecting => Colors.orange,
      CameraStreamStatus.idle      => Colors.grey,
    };
    final label = switch (widget.status) {
      CameraStreamStatus.streaming  => widget.mode == StreamMode.screen ? 'Tela ativa' : 'Transmitindo',
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
