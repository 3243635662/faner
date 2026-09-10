import 'dart:io';

import 'package:video_player/video_player.dart';

/// 本地媒体元数据（时长）获取，用于文件列表角标。
///
/// 仅对本地视频生效（远程文件无本地路径，且服务端未返回元数据）。
/// 带内存缓存 + 失败静默降级（返回 null，UI 隐藏角标）。
final Map<String, Duration> _videoDurationCache = {};

/// 获取本地视频时长；失败返回 null。
Future<Duration?> fetchVideoDuration(String path) async {
  final cached = _videoDurationCache[path];
  if (cached != null) return cached;
  VideoPlayerController? controller;
  try {
    controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    final duration = controller.value.duration;
    if (duration > Duration.zero) {
      _videoDurationCache[path] = duration;
      return duration;
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    await controller?.dispose();
  }
}
