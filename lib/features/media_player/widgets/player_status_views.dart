import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../core/tokens.dart';

/// 加载 / 缓冲视图。
///
/// 两种形态刻意区分，核心目标都是"状态清晰可见，但不遮挡关键内容"：
/// - 首次加载（`compact = false`）：此时还没有任何画面，居中显示最直观；
/// - 播放中缓冲（`compact = true`）：画面已定格，中央的大转圈会挡住人物 /
///   字幕，因此收成小胶囊，由调用方摆到画面下方。
class PlayerLoadingView extends StatelessWidget {
  const PlayerLoadingView({
    super.key,
    required this.label,
    this.progress,
    this.compact = false,
  });

  final String label;

  /// 缓冲进度 0.0 ~ 1.0；未知时传 null（显示不确定进度转圈）。
  final double? progress;

  /// 是否使用紧凑胶囊形态（播放中缓冲）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return compact ? _buildCompact(context) : _buildFull(context);
  }

  /// 首次加载：居中的圆环 + 文案。
  Widget _buildFull(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: AppSpacing.xxxl + AppSpacing.sm,
          height: AppSpacing.xxxl + AppSpacing.sm,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 2.5,
            color: Colors.white,
            backgroundColor: Colors.white24,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          label,
          style: AppTypography.subtitle.copyWith(color: Colors.white70),
        ),
      ],
    );
  }

  /// 播放中缓冲：半透明胶囊（小圆环 + 文案），体积小、可读性高。
  Widget _buildCompact(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: AppSpacing.lg,
            height: AppSpacing.lg,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTypography.caption.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// 播放失败视图：错误原因 + 重新播放。
///
/// 展示的是已经分类过的中文原因（见 `describePlayerError`），
/// 绝不把内核的异常堆栈直接甩给用户。
class PlayerErrorView extends StatelessWidget {
  const PlayerErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.circle_alert,
            color: Colors.white54,
            size: AppSpacing.xxxl + AppSpacing.sm,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '视频无法播放',
            style: AppTypography.title.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.rotate_cw),
            label: const Text('重新播放'),
          ),
        ],
      ),
    );
  }
}
