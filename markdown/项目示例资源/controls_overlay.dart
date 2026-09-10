import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../controllers/video_controls_controller.dart';
import 'video_progress_bar.dart';

/// 播放页控件覆盖层：顶部返回栏 + 中间三连按钮 + 底部进度条。
/// 显示/隐藏完全由 [controlsController] 驱动，隐藏时用 IgnorePointer
/// 彻底禁用点击穿透，避免"看不见但还能点到"的问题。
class ControlsOverlay extends StatelessWidget {
  const ControlsOverlay({
    super.key,
    required this.controlsController,
    required this.videoController,
    required this.title,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final VideoControlsController controlsController;
  final VideoPlayerController videoController;
  final String title;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controlsController,
      builder: (context, visible, child) {
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: child,
          ),
        );
      },
      child: Stack(
        children: [
          const _TopBottomScrim(),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _TopBar(title: title, onClose: onClose),
            ),
          ),
          Center(
            child: _CenterControls(
              videoController: videoController,
              hasPrevious: hasPrevious,
              hasNext: hasNext,
              onPrevious: onPrevious,
              onNext: onNext,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: VideoProgressBar(
                  controller: videoController,
                  onDragStart: controlsController.holdVisible,
                  onDragEnd: controlsController.releaseHold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部/底部的黑色渐变遮罩，保证控件在任何画面背景下都清晰可读。
class _TopBottomScrim extends StatelessWidget {
  const _TopBottomScrim();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 90,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black54, Colors.transparent],
            ),
          ),
        ),
        const Spacer(),
        Container(
          height: 90,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black54, Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: onClose,
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ],
    );
  }
}

/// 中间的"上一个 / 播放暂停 / 下一个"三连按钮。
/// 平板等宽屏设备下可以在这里加大按钮尺寸和间距（用 LayoutBuilder 判断宽度）。
class _CenterControls extends StatelessWidget {
  const _CenterControls({
    required this.videoController,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
  });

  final VideoPlayerController videoController;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // 简单的宽屏（平板/横屏）适配：屏幕越宽，按钮和间距略微放大。
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 720;
    final sideIconSize = isWide ? 44.0 : 36.0;
    final playIconSize = isWide ? 64.0 : 52.0;
    final gap = isWide ? 32.0 : 24.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircleIconButton(
          icon: Icons.skip_previous,
          enabled: hasPrevious,
          onPressed: onPrevious,
          size: sideIconSize,
        ),
        SizedBox(width: gap),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: videoController,
          builder: (context, value, child) {
            return _CircleIconButton(
              icon: value.isPlaying ? Icons.pause : Icons.play_arrow,
              enabled: true,
              size: playIconSize,
              onPressed: () {
                if (value.isPlaying) {
                  videoController.pause();
                } else {
                  videoController.play();
                }
              },
            );
          },
        ),
        SizedBox(width: gap),
        _CircleIconButton(
          icon: Icons.skip_next,
          enabled: hasNext,
          onPressed: onNext,
          size: sideIconSize,
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
    required this.size,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: IconButton(
        iconSize: size,
        color: Colors.white,
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
      ),
    );
  }
}
