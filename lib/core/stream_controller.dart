import 'dart:async' as async;
import 'package:flutter/services.dart';

enum CameraStreamStatus { idle, connecting, streaming, error }
enum StreamMode { camera, screen }

class CameraStreamController {
  static const _method = MethodChannel('com.example.iriseus/camera');
  static const _events = EventChannel('com.example.iriseus/camera_events');

  async.StreamSubscription? _eventSub;
  final _statusController = async.StreamController<CameraStreamStatus>.broadcast();
  final _modeController = async.StreamController<StreamMode>.broadcast();

  async.Stream<CameraStreamStatus> get status => _statusController.stream;
  async.Stream<StreamMode> get mode => _modeController.stream;

  StreamMode _currentMode = StreamMode.camera;
  StreamMode get currentMode => _currentMode;

  void init() {
    _eventSub = _events.receiveBroadcastStream().listen((event) {
      final map = event as Map;
      switch (map['status']) {
        case 'connecting': _statusController.add(CameraStreamStatus.connecting); break;
        case 'streaming': _statusController.add(CameraStreamStatus.streaming); break;
        case 'error': _statusController.add(CameraStreamStatus.error); break;
        default: _statusController.add(CameraStreamStatus.idle);
      }
      if (map.containsKey('mode')) {
        final m = map['mode'] == 'screen' ? StreamMode.screen : StreamMode.camera;
        _currentMode = m;
        _modeController.add(m);
      }
    });
  }

  Future<void> startStreaming(String ip, int port) async =>
      _method.invokeMethod('startStream', {'ip': ip, 'port': port});
  Future<void> stopStreaming() async => _method.invokeMethod('stopStream');
  Future<void> switchCamera() async => _method.invokeMethod('switchCamera');

  Future<bool> startScreenShare() async {
    final ok = await _method.invokeMethod<bool>('startScreenShare');
    return ok ?? false;
  }

  Future<bool> stopScreenShare() async {
    final ok = await _method.invokeMethod<bool>('stopScreenShare');
    return ok ?? false;
  }

  void dispose() {
    _eventSub?.cancel();
    _statusController.close();
    _modeController.close();
  }
}