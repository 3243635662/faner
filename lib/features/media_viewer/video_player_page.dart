import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'media_source.dart';
import 'video_view.dart';

class VideoPlayerPage extends StatelessWidget {
  const VideoPlayerPage({
    super.key,
    required this.items,
    required this.initialIndex,
    this.fromSplit = false,
  });

  final List<MediaSource> items;
  final int initialIndex;

  /// 是否从平板双栏进入（此时全屏按钮 = 返回双栏，而非横竖屏切换）。
  final bool fromSplit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: VideoView(
        items: items,
        initialIndex: initialIndex,
        fullscreen: fromSplit,
        onToggleFullscreen: fromSplit ? () => context.pop() : null,
      ),
    );
  }
}
