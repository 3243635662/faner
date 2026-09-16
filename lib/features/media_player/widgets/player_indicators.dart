import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../core/format.dart';
import '../../../core/tokens.dart';

/// 双击手势的反馈类型：两侧为 ±10 秒，中央为播放 / 暂停。
enum PlayerDoubleTapHint { rewind, forward, play, pause }

/// 手势反馈浮层：亮度 / 音量 / 快进快退预览 / 长按倍速。
///
/// 全部是"短暂出现后自动消失"的提示，不参与布局计算，统一收在这里，
/// 避免这些临时状态散落在主视图里。
class PlayerIndicators {
  PlayerIndicators._();

  /// 亮度 / 音量竖条（左半屏亮度、右半屏音量）。
  static Widget adjustBar({
    required IconData icon,
    required double value,
    required bool left,
    required String label,
  }) {
    return Positioned(
      left: left ? AppSpacing.lg : null,
      right: left ? null : AppSpacing.lg,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: AppTypography.caption.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: AppSpacing.xs,
                height: AppSpacing.xxl * 3,
                alignment: Alignment.bottomCenter,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: FractionallySizedBox(
                  heightFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 左右拖动快进 / 后退时的中央预览（方向箭头 + 目标时间 + 进度）。
  static Widget seekPreview({
    required Duration preview,
    required Duration duration,
    required Duration anchor,
  }) {
    final isForward = preview >= anchor;
    final totalMs = duration.inMilliseconds;
    final progress =
        totalMs <= 0 ? 0.0 : (preview.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isForward ? LucideIcons.arrow_right : LucideIcons.arrow_left,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  formatDuration(preview),
                  style: AppTypography.title.copyWith(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: 128,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: AppSpacing.xs,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              formatDuration(duration),
              style: AppTypography.caption.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  /// 双击手势的反馈类型。
  static Widget doubleTapHint(PlayerDoubleTapHint hint) {
    final (icon, label) = switch (hint) {
      PlayerDoubleTapHint.rewind => (LucideIcons.rewind, '后退 10 秒'),
      PlayerDoubleTapHint.forward => (LucideIcons.fast_forward, '前进 10 秒'),
      PlayerDoubleTapHint.play => (LucideIcons.play, '播放'),
      PlayerDoubleTapHint.pause => (LucideIcons.pause, '暂停'),
    };
    // 播放 / 暂停是"主操作"，给更大的图标与字重做区分
    final primary = hint == PlayerDoubleTapHint.play ||
        hint == PlayerDoubleTapHint.pause;
    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: primary ? AppSpacing.xl : AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: primary ? 28 : 22),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: (primary ? AppTypography.title : AppTypography.subtitle)
                  .copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  /// 长按倍速提示。
  static Widget speedBadge(double speed) {
    final label = speed == speed.roundToDouble()
        ? '${speed.toInt()}x'
        : '${speed.toStringAsFixed(1)}x';
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.gauge, color: Colors.white, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: AppTypography.title.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
