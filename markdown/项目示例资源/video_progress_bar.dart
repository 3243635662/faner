import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 底部进度条：显示当前时间 / 总时长，支持拖动 seek。
/// 拖动过程中不会实时 seek（避免频繁 seek 卡顿），松手时才真正跳转。
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
  double? _dragValue; // 拖动过程中的临时进度（0.0 ~ 1.0），松手后才真正 seek

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
                  trackHeight: 2.5,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                ),
                child: Slider(
                  value: _dragValue ?? progress,
                  onChangeStart: (_) {
                    widget.onDragStart();
                  },
                  onChanged: (v) {
                    setState(() => _dragValue = v);
                  },
                  onChangeEnd: (v) {
                    final target = duration * v;
                    widget.controller.seekTo(target);
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
    final text = h > 0 ? '$h:$m:$s' : '$m:$s';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
