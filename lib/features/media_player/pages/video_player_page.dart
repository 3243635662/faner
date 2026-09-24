import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/responsive.dart';
import '../../../providers/settings_provider.dart';
import '../../media_viewer/media_source.dart';
import '../controllers/media_player_controller.dart';
import '../controllers/player_controls_controller.dart';
import '../models/media_item.dart';
import '../services/system_ui_service.dart';
import '../widgets/media_player_view.dart';
import '../widgets/player_playlist_panel.dart';

/// 独立播放页（路由 `/video`）。
///
/// 布局（方案「页面结构」）：
/// - 手机 / 竖屏：单栏播放器，画面居中铺满，控件浮在画面之上；
/// - 平板横屏：左侧播放列表 + 右侧播放器，可直接换集；
/// - 全屏模式：隐藏播放列表，锁定横屏 + 隐藏系统栏，画面撑满整屏。
///
/// 全屏与设备方向、主从双栏是三个独立状态：这里只切换"显示模式"，
/// 页面本身始终是沉浸式深色，不会出现布局状态互相污染。
class VideoPlayerPage extends ConsumerStatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.items,
    required this.initialIndex,
    this.fromSplit = false,
  });

  final List<MediaSource> items;
  final int initialIndex;

  /// 是否从平板双栏进入（此时全屏按钮 = 返回双栏，而不是切换显示模式）。
  final bool fromSplit;

  @override
  ConsumerState<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends ConsumerState<VideoPlayerPage> {
  late final MediaPlayerController _controller;
  late final PlayerControlsController _controls;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _controller = MediaPlayerController(
      playlist: MediaItem.listFromSources(widget.items),
      initialIndex: widget.initialIndex,
      rememberProgress: settings.rememberProgress,
      playMode: settings.videoPlayMode,
    );
    _controls = PlayerControlsController();
    // 播放页进入即沉浸：系统栏与自定义控件同步显隐的前提是这里先隐藏
    unawaited(SystemUiService.enterImmersive());
  }

  @override
  void dispose() {
    _controller.dispose();
    _controls.dispose();
    // 页面销毁时无条件还原方向锁定和沉浸模式，
    // 防止"锁横屏 + 隐状态栏"状态泄漏到调用方页面。
    unawaited(SystemUiService.restore());
    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    if (widget.fromSplit) {
      // 从双栏进来的"全屏"语义 = 回到双栏；先还原 UI 再 pop，
      // 确保返回双栏界面时系统栏已经显示出来。
      await SystemUiService.restore();
      if (!mounted) return;
      if (context.canPop()) context.pop();
      return;
    }
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    if (next) {
      await SystemUiService.lockLandscape();
      await SystemUiService.enterImmersive();
    } else {
      await SystemUiService.allowAllOrientations();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final player = MediaPlayerView(
            controller: _controller,
            controls: _controls,
            fullscreen: widget.fromSplit || _fullscreen,
            onToggleFullscreen: _toggleFullscreen,
            onClose: () => context.pop(),
          );
          // 平板横屏才展示播放列表；全屏时或从双栏进入全屏时让位给画面
          final showPlaylist = !widget.fromSplit && !_fullscreen &&
              Responsive.useSplitLayout(context, constraints.maxWidth);
          if (!showPlaylist) return player;
          return Row(
            children: [
              PlayerPlaylistPanel(controller: _controller),
              Expanded(child: player),
            ],
          );
        },
      ),
    );
  }
}
