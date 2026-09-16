import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

/// 视频画面：只负责"把视频画出来"。
///
/// 这里不写播放逻辑、不写手势、不写文件列表、不做网络请求 ——
/// 它唯一的输入是一个渲染控制器，唯一的输出是画面。
class VideoSurface extends StatelessWidget {
  const VideoSurface({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
  });

  final mkv.VideoController controller;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return mkv.Video(
      controller: controller,
      fit: fit,
      alignment: Alignment.center,
      // 播放器区域永远是深色，即使 App 当前是浅色主题：
      // 视频边缘的黑边比浅色卡片舒服得多（方案「第一版 UI 我建议这样」）。
      fill: Colors.black,
      // 控件全部自研，禁用内核自带控制层，避免两套 UI 叠加。
      // ignore: avoid_redundant_argument_values
      controls: null,
      // 常亮与后台行为统一由 Controller 管理，避免两套逻辑互相打架。
      wakelock: false,
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: false,
    );
  }
}
