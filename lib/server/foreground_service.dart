import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 前台服务保活封装。
///
/// 共享的 HttpServer 运行在主 isolate，前台服务的作用是让系统把本进程
/// 视为「前台服务」，从而在锁屏/退到后台时不被杀死，保证对方设备持续可访问。
/// 因此 TaskHandler 只需保活，无需执行共享逻辑。
class ForegroundService {
  ForegroundService._();

  static const _channelId = 'faner_server';
  static const _serviceId = 256;

  /// 初始化通知渠道与任务配置。
  ///
  /// 必须在 app 启动早期调用（而非首次点击「局域网共享」时才调用），
  /// 确保 Android 8+ 通知渠道在服务启动前已就绪（文档 11.4）。
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: '局域网共享服务',
        channelDescription: 'Faner 局域网文件共享运行中',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        // 局域网服务器关键：锁屏后保持 WiFi 不断连
        allowWifiLock: true,
      ),
    );
  }

  /// 启动前台服务（Server 运行时调用）。
  static Future<bool> start() async {
    if (await FlutterForegroundTask.isRunningService) return true;

    // Android 13+ 通知权限
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: 'Faner',
      notificationText: '局域网共享运行中',
      callback: startCallback,
    );
    return result is ServiceRequestSuccess;
  }

  /// 停止前台服务（Server 停止时调用）。
  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ForegroundServiceTaskHandler());
}

/// 前台任务处理器：仅用于保活，不承载共享业务逻辑。
class ForegroundServiceTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
