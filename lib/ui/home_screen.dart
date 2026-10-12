import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/pairing_manager.dart';
import '../core/ws_client.dart';
import '../core/file_transfer_manager.dart';
import 'pairing_screen.dart';
import 'camera_screen.dart';
import 'transfers_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pairingManager = PairingManager();
  bool _checking = false;
  bool _usbAvailable = false;
  WsClient? _ws;
  FileTransferManager? _fileManager;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  @override
  void dispose() {
    _fileManager?.dispose();
    _ws?.disconnect();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      await [Permission.camera, Permission.notification].request();
    } catch (_) {}

    if (mounted) {
      await _checkUsb();
    }
  }

  Future<void> _checkUsb() async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        45678,
        timeout: const Duration(milliseconds: 500),
      );
      socket.destroy();
      if (mounted) setState(() => _usbAvailable = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _usbAvailable = false;
          _isConnected = false;
        });
      }
    }
  }

  Future<void> _connectUsb() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ws = WsClient();
    try {
      await ws.connect('127.0.0.1', 45678).timeout(const Duration(seconds: 3));

      final pairing = await _pairingManager.loadPairingInfo();
      final deviceId = await _pairingManager.getOrCreateDeviceId();

      if (pairing != null) {
        final welcomeFuture = ws.messages
            .firstWhere((m) => m['type'] == 'welcome')
            .timeout(const Duration(seconds: 5));

        ws.sendHello(deviceId, _pairingManager.deviceName);
        await welcomeFuture;

        _fileManager?.dispose();
        _ws?.disconnect();

        if (!mounted) return;
        setState(() {
          _ws = ws;
          _fileManager = FileTransferManager(ws);
          _isConnected = true;
          _usbAvailable = true;
        });

        // Configura listener de desconexão
        ws.state.listen((state) {
          if (state == WsConnectionState.disconnected && mounted) {
            setState(() {
              _isConnected = false;
            });
          }
        });
      } else {
        if (!mounted) return;
        final paired = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => PairingScreen(ws: ws, port: 45678),
          ),
        );
        if (paired == true) {
          _connectUsb();
        }
      }
    } catch (_) {
      await ws.disconnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sem conexão USB. Verifique se o cabo está conectado e o Iriseus está rodando no PC.'),
          duration: Duration(seconds: 4),
        ),
      );
      setState(() {
        _usbAvailable = false;
        _isConnected = false;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _openCamera() {
    if (_ws == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          ws: _ws!,
          pcIp: '127.0.0.1',
          fileManager: _fileManager,
        ),
      ),
    );
  }

  void _openTransfers() {
    if (_fileManager == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransfersScreen(manager: _fileManager!, pcIp: '127.0.0.1'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),

              // Logo / ícone
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isConnected ? Icons.phonelink_ring : Icons.camera_alt_rounded,
                  size: 48,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Iriseus',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isConnected
                    ? 'Conectado ao PC! Escolha o que deseja fazer:'
                    : 'Câmera e transferência de arquivos via USB',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(),

              // Status de conexão
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: _isConnected
                      ? Colors.green.withValues(alpha: 0.15)
                      : (_usbAvailable
                          ? Colors.blue.withValues(alpha: 0.15)
                          : Colors.orange.withValues(alpha: 0.10)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isConnected
                        ? Colors.green.withValues(alpha: 0.4)
                        : (_usbAvailable
                            ? Colors.blue.withValues(alpha: 0.4)
                            : Colors.orange.withValues(alpha: 0.3)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isConnected
                          ? Icons.check_circle
                          : (_usbAvailable ? Icons.usb : Icons.usb_off),
                      size: 18,
                      color: _isConnected
                          ? Colors.green
                          : (_usbAvailable ? Colors.blue : Colors.orange),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isConnected
                          ? 'Conectado e pronto'
                          : (_usbAvailable ? 'PC detectado via USB' : 'PC não detectado via USB'),
                      style: TextStyle(
                        color: _isConnected
                            ? Colors.green
                            : (_usbAvailable ? Colors.blue : Colors.orange),
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              if (!_isConnected) ...[
                // Botão conectar USB
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _checking ? null : _connectUsb,
                    icon: _checking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cable),
                    label: Text(_checking ? 'Conectando...' : 'Conectar via USB'),
                    style: FilledButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _checking
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PairingScreen(ws: WsClient(), port: 45678),
                              ),
                            ),
                    icon: const Icon(Icons.add_link),
                    label: const Text('Parear novo PC'),
                  ),
                ),
              ] else ...[
                // Conectado: Botões de Câmera e Arquivos
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _openCamera,
                    icon: const Icon(Icons.videocam_rounded),
                    label: const Text('Abrir Câmera'),
                    style: FilledButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.tonalIcon(
                    onPressed: _openTransfers,
                    icon: const Icon(Icons.folder_shared_rounded),
                    label: const Text('Transferir Arquivos'),
                    style: FilledButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton.icon(
                    onPressed: () {
                      _ws?.disconnect();
                      setState(() => _isConnected = false);
                    },
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('Desconectar'),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              Text(
                'Mantenha o cabo USB conectado ao PC',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () {
          setState(() => _usbAvailable = false);
          _checkUsb();
        },
        tooltip: 'Verificar conexão USB',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
