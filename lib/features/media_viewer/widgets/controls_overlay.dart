import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:video_player/video_player.dart';

import '../../../core/breakpoints.dart';
import '../../../core/tokens.dart';
import '../controllers/video_controls_controller.dart';
import 'video_progress_bar.dart';

/// 播放控件覆盖层：顶部栏（返回/标题）+ 底部（进度条 + 控制按钮）。
///
/// 控制按钮（上一个 / 播放暂停 / 下一个 / 全屏）集中在底部区域，
/// 便于单手操作。
///
/// 显隐完全由 [controlsController] 驱动；隐藏时通过 [IgnorePointer]
/// 彻底禁用点击，避免"看不见但仍挡住视频区域手势"。
class ControlsOverlay extends StatelessWidget {
  const ControlsOverlay({
    super.key,
    required this.controlsController,
    required this.videoController,
    required this.title,
    required this.hasMultiple,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlay,
    required this.onToggleFullscreen,
    this.onClose,
  });

  final VideoControlsController controlsController;
  final VideoPlayerController videoController;
  final String title;

  /// 是否为多视频列表（控制上一个/下一个按钮显隐）。
  final bool hasMultiple;

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleFullscreen;

  /// 返回上一页；null 时不显示返回按钮（内嵌模式）。
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controlsController,
      builder: (context, visible, child) {
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: AppMotion.mid,
            child: child,
          ),
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 平板/横屏：按断点放大按钮触控热区
          final wide = constraints.maxWidth >= Breakpoints.compact;
          final sizes = wide ? _ControlSizes.wide : _ControlSizes.compact;
          return Stack(
            fit: StackFit.expand,
            children: [
              const _Scrim(),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _TopBar(title: title, onClose: onClose),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomBar(
                  controlsController: controlsController,
                  videoController: videoController,
                  hasMultiple: hasMultiple,
                  onPrevious: onPrevious,
                  onNext: onNext,
                  onTogglePlay: onTogglePlay,
                  onToggleFullscreen: onToggleFullscreen,
                  sizes: sizes,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 底部控制按钮触控尺寸（按断点切换，平板/横屏放大热区）。
class _ControlSizes {
  const _ControlSizes({
    required this.play,
    required this.side,
    required this.fullscreen,
  });

  /// 播放/暂停按钮（圆形，直径）。
  final double play;

  /// 上一个/下一个按钮图标尺寸。
  final double side;

  /// 全屏按钮图标尺寸。
  final double fullscreen;

  /// 手机竖屏。
  static const compact = _ControlSizes(play: 56, side: 32, fullscreen: 28);

  /// 平板/横屏（宽度 >= [Breakpoints.compact]）。
  static const wide = _ControlSizes(play: 64, side: 40, fullscreen: 32);
}

/// 顶部/底部黑色渐变遮罩，保证控件在任何画面背景下可读。
class _Scrim extends StatelessWidget {
  const _Scrim();

  /// 遮罩渐变高度。
  static double get _height =>
      AppSpacing.xxxl + AppSpacing.xxxl + AppSpacing.lg;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: _height,
          decoration: _gradient(topDown: true),
        ),
        const Spacer(),
        Container(
          height: _height,
          decoration: _gradient(topDown: false),
        ),
      ],
    );
  }

  BoxDecoration _gradient({required bool topDown}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: topDown ? Alignment.topCenter : Alignment.bottomCenter,
        end: topDown ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [Colors.black54, Colors.transparent],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, this.onClose});

  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
        bottom: AppSpacing.xl,
        left: AppSpacing.sm,
        right: AppSpacing.lg,
      ),
      child: Row(
        children: [
          if (onClose != null)
            IconButton(
              icon: const Icon(LucideIcons.arrow_left, color: Colors.white),
              onPressed: onClose,
            ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.subtitle.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部：进度条 + 控制按钮（上一/播放/下一 + 全屏）。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controlsController,
    required this.videoController,
    required this.hasMultiple,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlay,
    required this.onToggleFullscreen,
    required this.sizes,
  });

  final VideoControlsController controlsController;
  final VideoPlayerController videoController;
  final bool hasMultiple;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleFullscreen;
  final _ControlSizes sizes;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Padding(
      padding: EdgeInsets.only(
        top: AppSpacing.xl,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.sm,
        left: AppSpacing.sm,
        right: AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VideoProgressBar(
            controller: videoController,
            onDragStart: controlsController.holdVisible,
            onDragEnd: controlsController.releaseHold,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (hasMultiple)
                _IconButton(
                  icon: LucideIcons.skip_back,
                  size: sizes.side,
                  onPressed: () {
                    controlsController.holdVisible();
                    onPrevious();
                  },
                ),
              if (hasMultiple) const SizedBox(width: AppSpacing.md),
              _PlayButton(
                videoController: videoController,
                size: sizes.play,
                onPressed: () {
                  controlsController.holdVisible();
                  onTogglePlay();
                  controlsController.releaseHold();
                },
              ),
              if (hasMultiple) const SizedBox(width: AppSpacing.md),
              if (hasMultiple)
                _IconButton(
                  icon: LucideIcons.skip_forward,
                  size: sizes.side,
                  onPressed: () {
                    controlsController.holdVisible();
                    onNext();
                  },
                ),
              const Spacer(),
              _IconButton(
                icon: isLandscape ? LucideIcons.minimize : LucideIcons.maximize,
                size: sizes.fullscreen,
                onPressed: () {
                  controlsController.holdVisible();
                  onToggleFullscreen();
                  controlsController.releaseHold();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 播放/暂停按钮：圆形半透明背景，突出主操作。
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.videoController,
    required this.size,
    required this.onPressed,
  });

  final VideoPlayerController videoController;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: videoController,
      builder: (context, value, child) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(
              value.isPlaying ? LucideIcons.pause : LucideIcons.play,
              color: Colors.white,
            ),
            iconSize: size * 0.5,
            onPressed: onPressed,
          ),
        );
      },
    );
  }
}

/// 普通图标按钮（上一个/下一个/全屏）。
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.size,
    required this.onPressed,
  });

  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: size,
      color: Colors.white,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}
