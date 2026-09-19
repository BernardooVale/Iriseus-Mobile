import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/pairing_manager.dart';
import '../core/ws_client.dart';
import 'pairing_screen.dart';
import 'camera_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _pairingManager = PairingManager();
  bool _checking = false;
  bool _usbAvailable = false;

  @override
  void initState() {
    super.initState();
    // Garante que o primeiro frame da UI seja renderizado antes de qualquer I/O ou permissão
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  Future<void> _init() async {
    // Solicita permissões de Câmera e Notificações (Android 13+)
    try {
      await [Permission.camera, Permission.notification].request();
    } catch (_) {}

    if (mounted) {
      await _checkUsb();
    }
  }

  Future<void> _checkUsb() async {
    try {
      // Teste direto de conexão TCP na porta 45678 (adb reverse)
      // Socket.connect fecha imediatamente e não deixa conexões pendentes
      final socket = await Socket.connect(
        '127.0.0.1',
        45678,
        timeout: const Duration(milliseconds: 500),
      );
      socket.destroy();
      if (mounted) setState(() => _usbAvailable = true);
    } catch (_) {
      if (mounted) setState(() => _usbAvailable = false);
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
        // Dispositivo já pareado — apenas handshake hello/welcome
        final welcomeFuture = ws.messages
            .firstWhere((m) => m['type'] == 'welcome')
            .timeout(const Duration(seconds: 5));

        ws.sendHello(deviceId, _pairingManager.deviceName);
        await welcomeFuture;

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => CameraScreen(ws: ws, pcIp: '127.0.0.1')),
        );
      } else {
        // Primeira vez — precisa parear
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PairingScreen(ws: ws, port: 45678),
          ),
        );
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
      setState(() => _usbAvailable = false);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
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
                  Icons.camera_alt_rounded,
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
                'Use o celular como câmera do PC',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(),

              // Status USB
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: _usbAvailable
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _usbAvailable
                        ? Colors.green.withValues(alpha: 0.4)
                        : Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _usbAvailable ? Icons.usb : Icons.usb_off,
                      size: 18,
                      color: _usbAvailable ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _usbAvailable ? 'PC detectado via USB' : 'PC não detectado via USB',
                      style: TextStyle(
                        color: _usbAvailable ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              // Botão principal
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

              // Botão Parear novo
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

              const SizedBox(height: 8),

              // Instrução
              Text(
                'Conecte o cabo USB e verifique se o Iriseus está rodando no PC',
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
