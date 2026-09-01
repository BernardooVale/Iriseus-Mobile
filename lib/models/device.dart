class Device {
  final String id;
  final String name;
  final String ip;
  final int port;

  const Device({required this.id, required this.name, required this.ip, required this.port});

  @override
  String toString() => 'Device($name @ $ip:$port)';
}