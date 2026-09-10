import 'package:flutter/material.dart';

import 'media_source.dart';
import 'video_view.dart';

class VideoPlayerPage extends StatelessWidget {
  const VideoPlayerPage({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<MediaSource> items;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: VideoView(items: items, initialIndex: initialIndex),
    );
  }
}
