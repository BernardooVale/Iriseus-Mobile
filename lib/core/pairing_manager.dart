import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'ws_client.dart';
import '../models/pairing_info.dart';

class QrPayload {
  final int v;
  final String ip;
  final int port;
  final String pin;
  final String pk;

  QrPayload({required this.v, required this.ip, required this.port, required this.pin, required this.pk});

  factory QrPayload.fromJsonString(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return QrPayload(v: j['v'] as int, ip: j['ip'] as String, port: j['port'] as int,
        pin: j['pin'] as String, pk: j['pk'] as String);
  }
}

class PairingManager {
  static const _kDeviceIdKey = 'iriseus_device_id';
  static const _kPairingInfoKey = 'iriseus_pairing_info';

  final _algorithm = X25519();
  SimpleKeyPair? _ephemeralKeyPair;
  String? _deviceId;
  final String deviceName = 'Iriseus Android';

  Future<String> getOrCreateDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceIdKey);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_kDeviceIdKey, id);
    }
    _deviceId = id;
    return id;
  }

  Future<String> generateEphemeralKeyPair() async {
    _ephemeralKeyPair = await _algorithm.newKeyPair();
    final pub = await _ephemeralKeyPair!.extractPublicKey();
    return _b64UrlNoPad(pub.bytes);
  }

  Future<void> deriveAndPersist({
    required String pcPublicKeyB64,
    required String pcDeviceId,
    required String pcDeviceName,
    required String pcIp,
  }) async {
    final pcPublicKey = SimplePublicKey(_b64UrlNoPadDecode(pcPublicKeyB64), type: KeyPairType.x25519);
    // Segredo usado para TOFU/autenticação futura — stream de vídeo não é criptografado.
    await _algorithm.sharedSecretKey(keyPair: _ephemeralKeyPair!, remotePublicKey: pcPublicKey);

    final info = PairingInfo(pcDeviceId: pcDeviceId, pcDeviceName: pcDeviceName,
        pcPublicKeyB64: pcPublicKeyB64, lastKnownIp: pcIp);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPairingInfoKey, jsonEncode(info.toJson()));
  }

  Future<PairingInfo?> loadPairingInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPairingInfoKey);
    if (raw == null) return null;
    return PairingInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> updateLastKnownIp(String ip) async {
    final info = await loadPairingInfo();
    if (info == null) return;
    final updated = PairingInfo(pcDeviceId: info.pcDeviceId, pcDeviceName: info.pcDeviceName,
        pcPublicKeyB64: info.pcPublicKeyB64, lastKnownIp: ip);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPairingInfoKey, jsonEncode(updated.toJson()));
  }

  Future<void> clearPairing() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPairingInfoKey);
  }

  String _b64UrlNoPad(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
  List<int> _b64UrlNoPadDecode(String s) {
    var padded = s;
    while (padded.length % 4 != 0) padded += '=';
    return base64Url.decode(padded);
  }
}