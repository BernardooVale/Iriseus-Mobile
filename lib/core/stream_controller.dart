import 'dart:async' as async;
import 'package:flutter/services.dart';

enum CameraStreamStatus { idle, connecting, streaming, error }

class CameraStreamController {
  static const _method = MethodChannel('com.example.iriseus/camera');
  static const _events = EventChannel('com.example.iriseus/camera_events');

  async.StreamSubscription? _eventSub;
  final _statusController = async.StreamController<CameraStreamStatus>.broadcast();
  async.Stream<CameraStreamStatus> get status => _statusController.stream;

  void init() {
    _eventSub = _events.receiveBroadcastStream().listen((event) {
      final map = event as Map;
      switch (map['status']) {
        case 'connecting': _statusController.add(CameraStreamStatus.connecting); break;
        case 'streaming': _statusController.add(CameraStreamStatus.streaming); break;
        case 'error': _statusController.add(CameraStreamStatus.error); break;
        default: _statusController.add(CameraStreamStatus.idle);
      }
    });
  }

  Future<void> startStreaming(String ip, int port) async =>
      _method.invokeMethod('startStream', {'ip': ip, 'port': port});
  Future<void> stopStreaming() async => _method.invokeMethod('stopStream');
  Future<void> switchCamera() async => _method.invokeMethod('switchCamera');

  void dispose() {
    _eventSub?.cancel();
    _statusController.close();
  }
}