import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:video_player/video_player.dart';

import '../../../core/breakpoints.dart';
import '../../../core/tokens.dart';
import '../controllers/video_controls_controller.dart';
import 'video_progress_bar.dart';

/// 播放控件覆盖层：顶部栏（返回/标题）+ 中间三连按钮
/// （上一个 / 播放暂停 / 下一个）+ 底部进度条与全屏按钮。
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
              Center(
                child: _CenterControls(
                  controlsController: controlsController,
                  videoController: videoController,
                  hasMultiple: hasMultiple,
                  onPrevious: onPrevious,
                  onNext: onNext,
                  sizes: sizes,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomBar(
                  controlsController: controlsController,
                  videoController: videoController,
                  onToggleFullscreen: onToggleFullscreen,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 控件触控尺寸（按断点切换，平板/横屏放大热区）。
class _ControlSizes {
  const _ControlSizes({
    required this.side,
    required this.play,
    required this.gap,
  });

  /// 侧边按钮（上一个/下一个）图标尺寸。
  final double side;

  /// 中央播放/暂停按钮图标尺寸。
  final double play;

  /// 按钮间距。
  final double gap;

  /// 手机竖屏。
  static const compact = _ControlSizes(side: 36, play: 52, gap: 24);

  /// 平板/横屏（宽度 >= [Breakpoints.compact]）。
  static const wide = _ControlSizes(side: 44, play: 64, gap: 32);
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

/// 中间的"上一个 / 播放暂停 / 下一个"三连按钮。
class _CenterControls extends StatelessWidget {
  const _CenterControls({
    required this.controlsController,
    required this.videoController,
    required this.hasMultiple,
    required this.onPrevious,
    required this.onNext,
    required this.sizes,
  });

  final VideoControlsController controlsController;
  final VideoPlayerController videoController;
  final bool hasMultiple;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final _ControlSizes sizes;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasMultiple) ...[
          _CircleIconButton(
            icon: LucideIcons.skip_back,
            size: sizes.side,
            onPressed: () {
              // holdVisible 取消自动隐藏计时，随后 _loadIndex 会统一重置
              controlsController.holdVisible();
              onPrevious();
            },
          ),
          SizedBox(width: sizes.gap),
        ],
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: videoController,
          builder: (context, value, child) {
            return _CircleIconButton(
              icon: value.isPlaying ? LucideIcons.pause : LucideIcons.play,
              size: sizes.play,
              onPressed: () {
                controlsController.holdVisible();
                if (value.isPlaying) {
                  videoController.pause();
                } else {
                  // 播放结束时点播放 = 从头重播
                  if (value.duration > Duration.zero &&
                      value.position >= value.duration) {
                    videoController.seekTo(Duration.zero);
                  }
                  videoController.play();
                }
                controlsController.releaseHold();
              },
            );
          },
        ),
        if (hasMultiple) ...[
          SizedBox(width: sizes.gap),
          _CircleIconButton(
            icon: LucideIcons.skip_forward,
            size: sizes.side,
            onPressed: () {
              controlsController.holdVisible();
              onNext();
            },
          ),
        ],
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controlsController,
    required this.videoController,
    required this.onToggleFullscreen,
  });

  final VideoControlsController controlsController;
  final VideoPlayerController videoController;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Padding(
      padding: EdgeInsets.only(
        top: AppSpacing.xl,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.sm,
        left: AppSpacing.sm,
        right: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: VideoProgressBar(
              controller: videoController,
              onDragStart: controlsController.holdVisible,
              onDragEnd: controlsController.releaseHold,
            ),
          ),
          IconButton(
            icon: Icon(
              isLandscape ? LucideIcons.minimize : LucideIcons.maximize,
              color: Colors.white,
            ),
            onPressed: () {
              controlsController.holdVisible();
              onToggleFullscreen();
              controlsController.releaseHold();
            },
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
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
