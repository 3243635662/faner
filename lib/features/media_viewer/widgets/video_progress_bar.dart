import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/tokens.dart';

/// 底部进度条：当前时间 / 总时长 + 可拖动 seek。
///
/// 拖动过程中不实时 seek（避免频繁 seek 卡顿），松手时才真正跳转；
/// 拖动开始/结束通过 [onDragStart] / [onDragEnd] 联动控件显隐控制器，
/// 防止操作途中控件被自动隐藏计时器打断。
class VideoProgressBar extends StatefulWidget {
  const VideoProgressBar({
    super.key,
    required this.controller,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final VideoPlayerController controller;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  /// 拖动中的临时进度（0.0 ~ 1.0），松手后才 seek。
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final duration = value.duration;
        final position = value.position;
        final durationMs = duration.inMilliseconds;
        final progress = durationMs == 0
            ? 0.0
            : (position.inMilliseconds / durationMs).clamp(0.0, 1.0);

        return Row(
          children: [
            _timeText(_dragValue == null ? position : duration * _dragValue!),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: AppSpacing.xs,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: AppSpacing.md,
                  ),
                  overlayShape: RoundSliderOverlayShape(
                    overlayRadius: AppSpacing.lg,
                  ),
                  activeTrackColor: AppPalette.of(context).brand,
                  inactiveTrackColor: Colors.white38,
                  thumbColor: AppPalette.of(context).brand,
                  overlayColor: Colors.white24,
                ),
                child: Slider(
                  value: _dragValue ?? progress,
                  onChangeStart: (_) => widget.onDragStart(),
                  onChanged: (v) => setState(() => _dragValue = v),
                  onChangeEnd: (v) {
                    widget.controller.seekTo(duration * v);
                    setState(() => _dragValue = null);
                    widget.onDragEnd();
                  },
                ),
              ),
            ),
            _timeText(duration),
          ],
        );
      },
    );
  }

  Widget _timeText(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Text(
        h > 0 ? '$h:$m:$s' : '$m:$s',
        style: AppTypography.caption.copyWith(color: Colors.white70),
      ),
    );
  }
}
