import 'dart:io';
import 'dart:typed_data';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:path_provider/path_provider.dart';

import 'tokens.dart';

/// 视频缩略图内存缓存（绝对路径 → JPEG 字节）。
final Map<String, Uint8List> _memCache = {};

/// 生成视频缩略图字节，失败返回 null。
///
/// 三级缓存：内存 → 磁盘 → 原生生成。磁盘缓存避免 app 重启后
/// 重新用 MediaMetadataRetriever 解码（成本最高）。
Future<Uint8List?> generateVideoThumbnailBytes(
  String path, {
  int size = 240,
  int quality = 70,
}) async {
  final cached = _memCache[path];
  if (cached != null) return cached;

  final disk = await _readDiskCache(path);
  if (disk != null) {
    _memCache[path] = disk;
    return disk;
  }

  try {
    final bytes = await FcNativeVideoThumbnail().saveThumbnailToBytes(
      srcFile: path,
      width: size,
      height: size,
      quality: quality,
    );
    if (bytes == null) return null;
    _memCache[path] = bytes;
    await _writeDiskCache(path, bytes);
    return bytes;
  } catch (_) {
    return null;
  }
}

String _cacheKey(String path) =>
    '${path.hashCode.toRadixString(16)}_${path.length}';

Future<Directory> _thumbDir() async {
  final cache = await getTemporaryDirectory();
  final dir = Directory('${cache.path}${Platform.pathSeparator}video_thumbs');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<Uint8List?> _readDiskCache(String path) async {
  try {
    final dir = await _thumbDir();
    final file =
        File('${dir.path}${Platform.pathSeparator}${_cacheKey(path)}.jpg');
    if (await file.exists()) return await file.readAsBytes();
  } catch (_) {
    // 忽略缓存读取失败
  }
  return null;
}

Future<void> _writeDiskCache(String path, Uint8List bytes) async {
  try {
    final dir = await _thumbDir();
    final file =
        File('${dir.path}${Platform.pathSeparator}${_cacheKey(path)}.jpg');
    await file.writeAsBytes(bytes, flush: true);
  } catch (_) {
    // 忽略缓存写入失败
  }
}

/// 本地视频缩略图组件：异步生成并显示，失败回退播放图标。
class VideoThumbnail extends StatefulWidget {
  const VideoThumbnail({super.key, required this.path});

  final String path;

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await generateVideoThumbnailBytes(widget.path);
    if (!mounted) return;
    setState(() {
      if (bytes == null) {
        _failed = true;
      } else {
        _bytes = bytes;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (_failed) return _fallback(palette);
    final bytes = _bytes;
    if (bytes == null) {
      return Container(color: palette.panel2);
    }
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }

  Widget _fallback(AppPalette palette) => Center(
        child: Icon(
          LucideIcons.circle_play,
          color: palette.brand,
          size: 52,
        ),
      );
}
