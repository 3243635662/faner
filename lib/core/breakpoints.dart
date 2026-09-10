/// 响应式布局断点（仅判断可用宽度，不判断设备类型）。
class Breakpoints {
  Breakpoints._();

  /// < 600dp：手机单栏。
  static const double compact = 600;

  /// >= 840dp：横屏平板/大屏，启用主从双栏布局。
  static const double medium = 840;
}
