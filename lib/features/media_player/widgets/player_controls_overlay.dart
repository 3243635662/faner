import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../core/breakpoints.dart';
import '../../../core/tokens.dart';
import '../controllers/media_player_controller.dart';
import '../controllers/player_controls_controller.dart';
import '../models/player_state.dart';
import 'playback_speed_sheet.dart';
import 'player_progress_bar.dart';

/// 播放器控件层：顶部栏 + 中央三连按钮 + 底部（进度 / 倍速 / 音量 / 全屏）。
///
/// 显隐完全由 [controls] 驱动：隐藏时用 [IgnorePointer] 彻底放行手势，
/// 避免"看不见但仍然挡住视频区域"的问题。
class PlayerControlsOverlay extends StatefulWidget {
  const PlayerControlsOverlay({
    super.key,
    required this.controller,
    required this.controls,
    required this.title,
    this.onClose,
    this.onToggleFullscreen,
    this.fullscreen,
  });

  final MediaPlayerController controller;
  final PlayerControlsController controls;

  /// 当前播放项标题。
  final String title;

  /// 返回上一页；null 时不显示返回按钮（内嵌预览模式）。
  final VoidCallback? onClose;

  /// 覆盖默认的全屏行为（双栏返回 / 内嵌进全屏页）；null 时用控制器的显示模式切换。
  final VoidCallback? onToggleFullscreen;

  /// 全屏图标状态；null 时取控制器的显示模式。
  final bool? fullscreen;

  @override
  State<PlayerControlsOverlay> createState() => _PlayerControlsOverlayState();
}

class _PlayerControlsOverlayState extends State<PlayerControlsOverlay> {
  bool _showVolume = false;
  Timer? _volumeTimer;

  @override
  void dispose() {
    _volumeTimer?.cancel();
    super.dispose();
  }

  void _toggleVolume() {
    setState(() => _showVolume = !_showVolume);
    _volumeTimer?.cancel();
    if (_showVolume) {
      widget.controls.holdVisible();
      _volumeTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showVolume = false);
        widget.controls.releaseHold();
      });
    } else {
      widget.controls.releaseHold();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.controls,
      builder: (context, visible, _) {
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: AppMotion.mid,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= Breakpoints.compact;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // 遮罩只做视觉渐隐，必须放行点击：否则点击上下黑边
                    // 无法触发"显示 / 隐藏控件"
                    const IgnorePointer(child: _Scrim()),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _TopBar(
                        title: widget.title,
                        onClose: widget.onClose,
                      ),
                    ),
                    Center(
                      child: _CenterControls(
                        controller: widget.controller,
                        controls: widget.controls,
                        wide: wide,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_showVolume)
                            _VolumePanel(
                              controller: widget.controller,
                              onInteraction: () {
                                widget.controls.holdVisible();
                                _volumeTimer?.cancel();
                                _volumeTimer = Timer(
                                  const Duration(seconds: 3),
                                  () {
                                    if (mounted) {
                                      setState(() => _showVolume = false);
                                    }
                                    widget.controls.releaseHold();
                                  },
                                );
                              },
                            ),
                          _BottomBar(
                            controller: widget.controller,
                            controls: widget.controls,
                            wide: wide,
                            fullscreen: widget.fullscreen ?? false,
                            onToggleFullscreen: widget.onToggleFullscreen,
                            onToggleVolume: _toggleVolume,
                            volumeVisible: _showVolume,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// 上下两条黑色渐变遮罩，保证白色控件在任何画面上都可读。
class _Scrim extends StatelessWidget {
  const _Scrim();

  static double get _height =>
      AppSpacing.xxxl + AppSpacing.xxxl + AppSpacing.lg;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(height: _height, decoration: _gradient(topDown: true)),
        const Spacer(),
        Container(height: _height, decoration: _gradient(topDown: false)),
      ],
    );
  }

  BoxDecoration _gradient({required bool topDown}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: topDown ? Alignment.topCenter : Alignment.bottomCenter,
        end: topDown ? Alignment.bottomCenter : Alignment.topCenter,
        colors: const [Colors.black54, Colors.transparent],
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
              tooltip: '返回',
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

/// 中央主操作区：后退 10 秒 / 播放暂停 / 前进 10 秒（主流播放器布局）。
class _CenterControls extends StatelessWidget {
  const _CenterControls({
    required this.controller,
    required this.controls,
    required this.wide,
  });

  final MediaPlayerController controller;
  final PlayerControlsController controls;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        final playSize = wide ? 64.0 : 56.0;
        final skipSize = wide ? 40.0 : 34.0;
        // 播放结束 / 出错时，主按钮语义变为"重播"
        final ended = state.status == PlayerStatus.completed ||
            state.status == PlayerStatus.error;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoundIconButton(
              icon: LucideIcons.rotate_ccw,
              size: skipSize,
              tooltip: '后退 10 秒',
              onPressed: () {
                controls.holdVisible();
                controller.seekBy(const Duration(seconds: -10));
                controls.releaseHold();
              },
            ),
            const SizedBox(width: AppSpacing.xl),
            Container(
              width: playSize,
              height: playSize,
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: state.isPlaying ? '暂停' : '播放',
                iconSize: playSize * 0.5,
                icon: Icon(
                  ended
                      ? LucideIcons.refresh_cw
                      : (state.isPlaying ? LucideIcons.pause : LucideIcons.play),
                  color: Colors.white,
                ),
                onPressed: () {
                  controls.holdVisible();
                  controller.togglePlay();
                  controls.releaseHold();
                },
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            _RoundIconButton(
              icon: LucideIcons.rotate_cw,
              size: skipSize,
              tooltip: '前进 10 秒',
              onPressed: () {
                controls.holdVisible();
                controller.seekBy(const Duration(seconds: 10));
                controls.releaseHold();
              },
            ),
          ],
        );
      },
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.size,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final double size;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: size,
      color: Colors.white,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

/// 底部：进度条 + 倍速 / 上下一个 / 音量 / 全屏。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.controls,
    required this.wide,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onToggleVolume,
    required this.volumeVisible,
  });

  final MediaPlayerController controller;
  final PlayerControlsController controls;
  final bool wide;
  final bool fullscreen;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback onToggleVolume;
  final bool volumeVisible;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final iconSize = wide ? 30.0 : 26.0;
    return Padding(
      padding: EdgeInsets.only(
        top: AppSpacing.xl,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.sm,
        left: AppSpacing.sm,
        right: AppSpacing.sm,
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final state = controller.state;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerProgressBar(
                position: controller.position,
                duration: state.duration,
                onSeek: controller.seek,
                onDragStart: controls.holdVisible,
                onDragEnd: controls.releaseHold,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  // 倍速：显示当前倍速，点击打开选择面板
                  TextButton(
                    onPressed: () async {
                      controls.holdVisible();
                      final picked = await showPlaybackSpeedSheet(
                        context,
                        current: state.rate,
                      );
                      controls.releaseHold();
                      if (picked != null) {
                        await controller.setRate(picked);
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(56, 40),
                    ),
                    child: Text(
                      _speedLabel(state.rate),
                      style: AppTypography.subtitle.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (controller.hasMultiple) ...[
                    IconButton(
                      iconSize: iconSize,
                      color: Colors.white,
                      tooltip: '上一个',
                      icon: const Icon(LucideIcons.skip_back),
                      onPressed: () {
                        controls.holdVisible();
                        controller.previous();
                      },
                    ),
                    IconButton(
                      iconSize: iconSize,
                      color: Colors.white,
                      tooltip: '下一个',
                      icon: const Icon(LucideIcons.skip_forward),
                      onPressed: () {
                        controls.holdVisible();
                        controller.next();
                      },
                    ),
                  ],
                  const Spacer(),
                  // 列表位置（如 3/12），多视频时才有意义
                  if (controller.hasMultiple)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: Text(
                        '${state.index + 1}/${controller.playlist.length}',
                        style: AppTypography.caption
                            .copyWith(color: Colors.white70),
                      ),
                    ),
                  IconButton(
                    iconSize: iconSize,
                    color: volumeVisible ? palette.brand : Colors.white,
                    tooltip: '音量',
                    icon: const Icon(LucideIcons.volume_2),
                    onPressed: onToggleVolume,
                  ),
                  IconButton(
                    iconSize: iconSize,
                    color: Colors.white,
                    tooltip: fullscreen ? '退出全屏' : '全屏',
                    icon: Icon(
                      fullscreen ? LucideIcons.minimize : LucideIcons.maximize,
                    ),
                    onPressed: () {
                      controls.holdVisible();
                      onToggleFullscreen?.call();
                      controls.releaseHold();
                    },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 内联音量条（点击音量按钮后浮出，3 秒无操作自动收起）。
class _VolumePanel extends StatelessWidget {
  const _VolumePanel({required this.controller, required this.onInteraction});

  final MediaPlayerController controller;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Row(
            children: [
              const Icon(LucideIcons.volume_1, color: Colors.white70, size: 20),
              Expanded(
                child: Slider(
                  value: controller.state.volume.clamp(0.0, 1.0),
                  onChanged: (value) {
                    onInteraction();
                    controller.setVolume(value);
                  },
                ),
              ),
              const Icon(LucideIcons.volume_2, color: Colors.white70, size: 20),
            ],
          );
        },
      ),
    );
  }
}

String _speedLabel(double rate) {
  final text =
      rate == rate.roundToDouble() ? rate.toInt().toString() : rate.toString();
  return '${text}x';
}
