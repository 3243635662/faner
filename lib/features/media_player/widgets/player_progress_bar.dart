import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/tokens.dart';

/// 底部进度条：当前时间 + 可拖动 seek + 总时长。
///
/// 进度来自 [position]（ValueListenable），只重建这一小块；
/// 拖动过程中不实时 seek（避免频繁 seek 造成卡顿），松手时才真正跳转。
class PlayerProgressBar extends StatefulWidget {
  const PlayerProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final ValueListenable<Duration> position;
  final Duration duration;

  final ValueChanged<Duration> onSeek;

  /// 拖动开始 / 结束：联动控件显隐控制器，防止操作途中控件被自动隐藏。
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  /// 拖动中的临时进度 0.0 ~ 1.0；null 表示未在拖动。
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.position,
      builder: (context, current, _) {
        final durationMs = widget.duration.inMilliseconds;
        final progress = durationMs <= 0
            ? 0.0
            : (current.inMilliseconds / durationMs).clamp(0.0, 1.0);
        final shown = _dragValue == null
            ? current
            : widget.duration * _dragValue!;

        return Row(
          children: [
            _timeText(shown),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: AppSpacing.xs,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: AppSpacing.md,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: AppSpacing.lg,
                  ),
                  activeTrackColor: palette.brand,
                  inactiveTrackColor: Colors.white38,
                  thumbColor: palette.brand,
                  overlayColor: Colors.white24,
                ),
                child: Slider(
                  // 时长未知时禁用拖动，避免拖到 0 后又跳回
                  value: durationMs <= 0 ? 0 : (_dragValue ?? progress),
                  onChangeStart:
                      durationMs <= 0 ? null : (_) => widget.onDragStart(),
                  onChanged: durationMs <= 0
                      ? null
                      : (value) => setState(() => _dragValue = value),
                  onChangeEnd: durationMs <= 0
                      ? null
                      : (value) {
                          widget.onSeek(widget.duration * value);
                          setState(() => _dragValue = null);
                          widget.onDragEnd();
                        },
                ),
              ),
            ),
            _timeText(widget.duration),
          ],
        );
      },
    );
  }

  Widget _timeText(Duration d) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Text(
        formatDuration(d),
        style: AppTypography.caption.copyWith(color: Colors.white70),
      ),
    );
  }
}
