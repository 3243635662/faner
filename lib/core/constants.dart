/// 应用级常量。
class AppConstants {
  AppConstants._();

  /// 固定服务端口，被占用则自动 +1 重试。
  static const int basePort = 8848;

  /// 端口最大重试次数。
  static const int maxPortRetries = 5;

  /// mDNS 服务类型（自定义，避免扫到无关 HTTP 服务）。
  static const String serviceType = '_lanmedia._tcp';

  static const String appVersion = '1.0.0';

  /// 共享根目录展示名。
  static const String sharedRootLabel = '内部存储';

  /// 设备信息连通性校验 / 最近连接持久化键。
  static const String recentDevicesKey = 'recent_devices';
}
