class PairingInfo {
  final String pcDeviceId;
  final String pcDeviceName;
  final String pcPublicKeyB64;
  final String lastKnownIp;

  const PairingInfo({
    required this.pcDeviceId,
    required this.pcDeviceName,
    required this.pcPublicKeyB64,
    required this.lastKnownIp,
  });

  Map<String, dynamic> toJson() => {
    'pcDeviceId': pcDeviceId,
    'pcDeviceName': pcDeviceName,
    'pcPublicKeyB64': pcPublicKeyB64,
    'lastKnownIp': lastKnownIp,
  };

  factory PairingInfo.fromJson(Map<String, dynamic> json) => PairingInfo(
    pcDeviceId: json['pcDeviceId'] as String,
    pcDeviceName: json['pcDeviceName'] as String,
    pcPublicKeyB64: json['pcPublicKeyB64'] as String,
    lastKnownIp: json['lastKnownIp'] as String,
  );
}