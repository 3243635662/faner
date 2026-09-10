import 'package:flutter/material.dart';

/// Faner 设计 Token（本项目 UI 唯一事实源）。
///
/// 所有页面/组件样式一律引用本文件的 Token，禁止魔法数字、魔法色值、
/// 手写阴影与散落样式。颜色通过语义 Token 自动适配亮/暗主题。
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
}

class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}

class AppMotion {
  AppMotion._();

  /// 标准转场曲线（Material 标准曲线）。
  static const Curve standard = Curves.easeInOutCubic;

  /// 弹性回弹曲线（用于强调动效）。
  static const Curve spring = Curves.easeOutBack;

  static const Duration short = Duration(milliseconds: 120);
  static const Duration mid = Duration(milliseconds: 250);
  static const Duration long = Duration(milliseconds: 400);
}

/// 语义色板。亮/暗两套，通过 [AppPalette.of] 根据上下文自动切换。
class AppPalette {
  const AppPalette({
    required this.brand,
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.text,
    required this.muted,
    required this.sidebar,
    required this.green,
    required this.amber,
    required this.red,
    required this.sky,
    required this.shadow,
  });

  final Color brand;
  final Color bg;
  final Color panel;
  final Color panel2;
  final Color line;
  final Color text;
  final Color muted;
  final Color sidebar;
  final Color green;
  final Color amber;
  final Color red;
  final Color sky;
  final Color shadow;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static const AppPalette light = AppPalette(
    brand: Color(0xFF5B67F1),
    bg: Color(0xFFF6F7FB),
    panel: Color(0xFFFFFFFF),
    panel2: Color(0xFFEEF0F6),
    line: Color(0xFFE3E6EF),
    text: Color(0xFF1A1D29),
    muted: Color(0xFF6B7280),
    sidebar: Color(0xFFF1F2F8),
    green: Color(0xFF16A34A),
    amber: Color(0xFFF59E0B),
    red: Color(0xFFEF4444),
    sky: Color(0xFF0EA5E9),
    shadow: Color(0x1A0F1420),
  );

  static const AppPalette dark = AppPalette(
    brand: Color(0xFF8B93FF),
    bg: Color(0xFF0F1117),
    panel: Color(0xFF1A1D27),
    panel2: Color(0xFF232733),
    line: Color(0xFF2E3340),
    text: Color(0xFFECEEF5),
    muted: Color(0xFF9AA0AE),
    sidebar: Color(0xFF141722),
    green: Color(0xFF22C55E),
    amber: Color(0xFFFBBF24),
    red: Color(0xFFF87171),
    sky: Color(0xFF38BDF8),
    shadow: Color(0x66000000),
  );
}

/// 主题化阴影（禁止手写 BoxShadow）。
class AppShadow {
  AppShadow._();

  static List<BoxShadow> sm(BuildContext context) => [
        BoxShadow(
          color: AppPalette.of(context).shadow,
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> md(BuildContext context) => [
        BoxShadow(
          color: AppPalette.of(context).shadow,
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> lg(BuildContext context) => [
        BoxShadow(
          color: AppPalette.of(context).shadow,
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

/// 排版 Token：字号 + 字重 + 行高。颜色由调用处用语义色覆盖。
class AppTypography {
  AppTypography._();

  static const TextStyle display =
      TextStyle(fontSize: 32, fontWeight: FontWeight.w700, height: 1.2);

  static const TextStyle title =
      TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.3);

  static const TextStyle subtitle =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w500);

  static const TextStyle body = TextStyle(fontSize: 14);

  static const TextStyle caption = TextStyle(fontSize: 12);
}
