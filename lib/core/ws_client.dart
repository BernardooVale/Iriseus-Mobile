import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

enum WsConnectionState { disconnected, connecting, connected }

class WsClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<WsConnectionState>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<WsConnectionState> get state => _stateController.stream;

  WsConnectionState _current = WsConnectionState.disconnected;
  WsConnectionState get currentState => _current;

  Future<void> connect(String ip, int port) async {
    await disconnect();
    _setState(WsConnectionState.connecting);
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://$ip:$port'));
      _sub = _channel!.stream.listen(
            (data) {
          try {
            _messageController.add(jsonDecode(data as String) as Map<String, dynamic>);
          } catch (_) {
            // mensagem inválida, ignora
          }
        },
        onDone: () => _setState(WsConnectionState.disconnected),
        onError: (_) => _setState(WsConnectionState.disconnected),
      );
      _setState(WsConnectionState.connected);
      _startKeepalive();
    } catch (_) {
      _setState(WsConnectionState.disconnected);
      rethrow;
    }
  }

  void _startKeepalive() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) => send({'type': 'ping'}));
  }

  void send(Map<String, dynamic> message) {
    if (_channel == null || _current != WsConnectionState.connected) return;
    _channel!.sink.add(jsonEncode(message));
  }

  void sendHello(String deviceId, String deviceName) =>
      send({'type': 'hello', 'deviceId': deviceId, 'deviceName': deviceName});

  void sendPairRequest({
    required String pin,
    required String pk,
    required String deviceId,
    required String deviceName,
  }) =>
      send({'type': 'pair_request', 'pin': pin, 'pk': pk, 'deviceId': deviceId, 'deviceName': deviceName});

  void sendStartCamera() => send({'type': 'start_camera'});
  void sendStopCamera() => send({'type': 'stop_camera'});

  /// Espera mensagem de tipo específico, com timeout. Usado após hello/pair_request.
  Future<Map<String, dynamic>?> waitForType(String type, {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      return await messages.firstWhere((m) => m['type'] == type).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// Reconecta automaticamente ao IP salvo se socket cair. Sem novo pareamento.
  void enableAutoReconnect(String ip, int port, void Function() onReconnected) {
    state.listen((s) {
      if (s == WsConnectionState.disconnected) {
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(const Duration(seconds: 3), () async {
          try {
            await connect(ip, port);
            onReconnected();
          } catch (_) {
            // próxima tentativa disparada pelo próximo evento disconnected
          }
        });
      }
    });
  }

  void _setState(WsConnectionState s) {
    _current = s;
    _stateController.add(s);
  }

  Future<void> disconnect() async {
    _pingTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _setState(WsConnectionState.disconnected);
  }

  void dispose() {
    _reconnectTimer?.cancel();
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}