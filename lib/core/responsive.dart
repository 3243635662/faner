import 'package:flutter/widgets.dart';

/// 响应式布局与设备形态判断工具。
///
/// 核心原则（见 markdown/横屏修复策略.md）：
/// - 设备类型（手机/平板）用 [shortestSide] 判断，与方向无关，避免手机
///   横屏时宽度变大而被误判成平板；
/// - 主从双栏（split view）只在「平板 + 横屏 + 宽度足够」三个条件同时
///   满足时启用；
/// - 横屏是设备方向、双栏是布局状态、全屏是媒体显示状态，三者不能互相代替。
class Responsive {
  Responsive._();

  /// 平板判定最短边阈值（dp）。手机横屏时最短边仍 < 600，不会被误判。
  static const double tabletShortestSide = 600;

  /// 双栏最小宽度阈值（dp）。
  static const double splitMinWidth = 840;

  /// 是否平板：以最短边判定，与横竖屏无关。
  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= tabletShortestSide;

  /// 是否横屏。
  static bool isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  /// 是否启用主从双栏布局。
  ///
  /// [maxWidth] 可选：在 LayoutBuilder 中传入更精确的可用宽度；
  /// 不传时回退到 [MediaQuery] 的窗口宽度。
  static bool useSplitLayout(BuildContext context, [double? maxWidth]) {
    final width = maxWidth ?? MediaQuery.sizeOf(context).width;
    return isTablet(context) && isLandscape(context) && width >= splitMinWidth;
  }
}
