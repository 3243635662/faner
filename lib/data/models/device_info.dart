/// 局域网内的一个 Faner 设备。
class DeviceInfo {
  const DeviceInfo({
    required this.deviceName,
    required this.ip,
    required this.port,
    this.isManual = false,
  });

  final String deviceName;
  final String ip;
  final int port;
  final bool isManual;

  String get baseUrl => 'http://$ip:$port';

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        deviceName: json['deviceName'] as String,
        ip: json['ip'] as String,
        port: json['port'] as int,
        isManual: json['isManual'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'deviceName': deviceName,
        'ip': ip,
        'port': port,
        'isManual': isManual,
      };

  @override
  bool operator ==(Object other) =>
      other is DeviceInfo && other.ip == ip && other.port == port;

  @override
  int get hashCode => Object.hash(ip, port);
}
