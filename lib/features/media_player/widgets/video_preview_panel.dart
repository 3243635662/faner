import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/tokens.dart';
import '../../../providers/settings_provider.dart';
import '../controllers/media_player_controller.dart';
import '../controllers/player_controls_controller.dart';
import '../models/media_item.dart';
import 'media_player_view.dart';

/// 双栏详情面板里的内嵌视频预览。
///
/// 与独立播放页共用同一套播放视图，但：
/// - `embedded = true`：不接管系统 UI、不保持屏幕常亮；
/// - 不显示返回按钮，右下角按钮改为"进入全屏播放页"。
class VideoPreviewPanel extends ConsumerStatefulWidget {
  const VideoPreviewPanel({
    super.key,
    required this.items,
    required this.onOpenFullscreen,
  });

  final List<MediaItem> items;

  /// 点击全屏按钮：由宿主构造完整列表并 push 独立播放页。
  final VoidCallback onOpenFullscreen;

  @override
  ConsumerState<VideoPreviewPanel> createState() => _VideoPreviewPanelState();
}

class _VideoPreviewPanelState extends ConsumerState<VideoPreviewPanel> {
  late final MediaPlayerController _controller;
  late final PlayerControlsController _controls;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _controller = MediaPlayerController(
      playlist: widget.items,
      initialIndex: 0,
      embedded: true,
      rememberProgress: settings.rememberProgress,
      playMode: settings.videoPlayMode,
    );
    _controls = PlayerControlsController();
    // 预览时先亮一下控件，让用户一眼看到"可操作"，随后按常规自动隐藏
    _controls.showTemporarily();
  }

  @override
  void dispose() {
    _controller.dispose();
    _controls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: ColoredBox(
        color: Colors.black,
        child: MediaPlayerView(
          controller: _controller,
          controls: _controls,
          onToggleFullscreen: widget.onOpenFullscreen,
        ),
      ),
    );
  }
}
