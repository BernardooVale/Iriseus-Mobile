import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/pairing_manager.dart';
import '../core/ws_client.dart';

class PairingScreen extends StatefulWidget {
  final WsClient ws;
  final int port;
  const PairingScreen({super.key, required this.ws, required this.port});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _pairingManager = PairingManager();
  final _pinController = TextEditingController();
  final _focusNode = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-foca no campo PIN
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handlePinSubmit() async {
    final pin = _pinController.text.trim();
    if (pin.length < 6) {
      setState(() => _error = 'O PIN deve ter 6 dígitos.');
      return;
    }

    setState(() { _busy = true; _error = null; });

    try {
      // Conecta ao PC via USB (adb reverse)
      await widget.ws.connect('127.0.0.1', widget.port)
          .timeout(const Duration(seconds: 3));

      // IMPORTANTE: cria o listener ANTES de qualquer envio para evitar race condition.
      // O stream broadcast do WsClient garante que mensagens chegadas após a subscrição
      // são entregues; ao criar o Future aqui, capturamos a mensagem mesmo que chegue
      // muito rapidamente após o pair_request.
      final pairResultFuture = widget.ws.messages
          .firstWhere((m) => m['type'] == 'pair_accepted' || m['type'] == 'pair_rejected')
          .timeout(const Duration(seconds: 15));

      final deviceId = await _pairingManager.getOrCreateDeviceId();
      final myPk = await _pairingManager.generateEphemeralKeyPair();

      // 1. Hello — listener de welcome também criado antes do envio
      final welcomeFuture = widget.ws.messages
          .firstWhere((m) => m['type'] == 'welcome')
          .timeout(const Duration(seconds: 5));

      widget.ws.sendHello(deviceId, _pairingManager.deviceName);
      final welcome = await welcomeFuture;
      final pcPk = welcome['pk'] as String? ?? '';

      // 2. Pair request — resultado já sendo aguardado pelo listener acima
      debugPrint('[Pairing] Enviando pair_request com pin="$pin"');
      widget.ws.sendPairRequest(
        pin: pin,
        pk: myPk,
        deviceId: deviceId,
        deviceName: _pairingManager.deviceName,
      );

      final result = await pairResultFuture;
      debugPrint('[Pairing] Resposta do PC: $result');
      final accepted = result['type'] == 'pair_accepted';

      if (accepted) {
        await _pairingManager.deriveAndPersist(
          pcPublicKeyB64: pcPk,
          pcDeviceId: welcome['deviceId'] as String? ?? 'unknown',
          pcDeviceName: welcome['deviceName'] as String? ?? 'Iriseus PC',
          pcIp: '127.0.0.1',
        );
      }

      if (!mounted) return;

      if (accepted) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = 'PIN incorreto. Verifique o código no PC e tente novamente.');
      }
    } on TimeoutException {
      setState(() => _error = 'Tempo esgotado. Verifique a conexão USB.');
    } catch (e) {
      setState(() => _error = 'Falha ao conectar ao PC. Verifique o cabo USB.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parear com PC'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              Icon(
                Icons.lock_open_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 20),

              Text(
                'Digite o código',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Abra o Iriseus no PC e clique em\n"Parear novo dispositivo" para ver o código.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Campo PIN
              TextField(
                controller: _pinController,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                enabled: !_busy,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 12,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: theme.textTheme.displaySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    letterSpacing: 12,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                ),
                onSubmitted: (_) => _busy ? null : _handlePinSubmit(),
              ),

              const SizedBox(height: 16),

              // Erro
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _error != null
                    ? Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(color: theme.colorScheme.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              const SizedBox(height: 8),

              // Botão Parear
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _handlePinSubmit,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.link),
                  label: Text(_busy ? 'Pareando...' : 'Parear'),
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
