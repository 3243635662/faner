import 'package:flutter/services.dart';

/// 系统 UI（状态栏 / 导航栏 / 屏幕方向）的统一出入口。
///
/// 播放器组件不直接调用 `SystemChrome`：沉浸式的进入与还原全部收敛到这里，
/// 保证任何退出路径（返回键、全屏切换、异常、页面销毁）都能还原系统 UI，
/// 不会出现"退出播放器后状态栏再也回不来"的问题。
class SystemUiService {
  SystemUiService._();

  /// 进入沉浸式（隐藏状态栏与导航栏）。
  static Future<void> enterImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  /// 还原为常规边到边模式。
  static Future<void> exitImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  static Future<void> setImmersive(bool immersive) =>
      immersive ? enterImmersive() : exitImmersive();

  /// 解除方向锁定，跟随系统旋转。
  static Future<void> allowAllOrientations() =>
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);

  /// 锁定横屏（全屏观看用）。
  static Future<void> lockLandscape() =>
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

  /// 还原到"未接管系统 UI"的默认状态。
  ///
  /// 页面销毁时必须调用，否则沉浸式与方向锁定会泄漏到其他页面。
  static Future<void> restore() async {
    await allowAllOrientations();
    await exitImmersive();
  }
}
