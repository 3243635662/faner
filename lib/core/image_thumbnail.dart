import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 图片缩略图内存缓存（绝对路径 → 缩略图字节），限制最大条目数防止内存膨胀。
final Map<String, Uint8List> _imageMemCache = {};
const int _maxMemCacheEntries = 120;

/// 清空图片缩略图内存缓存。
void clearImageThumbnailMemCache() {
  _imageMemCache.clear();
}

/// 生成或读取图片缩略图字节（PNG），包含内存与磁盘两级缓存。
///
/// 利用 Flutter 引擎底层的 [ui.ImmutableBuffer.fromFilePath] 零拷贝读盘，
/// 配合 [ui.instantiateImageCodecFromBuffer] 硬件加速缩放至 [size]（默认 240px），
/// 从而将数 MB ~ 数十 MB 的 1K/2K/4K 原始照片在服务端裁剪为仅数十 KB 的轻量缩略图。
///
/// 缓存键包含文件的 size 与 mtime：同名文件被替换后旧缩略图自动失效。
Future<Uint8List?> generateImageThumbnailBytes(
  String path, {
  int size = 240,
}) async {
  final FileStat stat;
  try {
    stat = await File(path).stat();
  } catch (e) {
    debugPrint('[Thumbnail] 读取文件状态失败: $path, $e');
    return null;
  }
  if (stat.type != FileSystemEntityType.file || stat.size <= 0) return null;

  final key = _cacheKey(path, stat.size, stat.modified.millisecondsSinceEpoch);
  final cached = _imageMemCache[key];
  if (cached != null) return cached;

  final disk = await _readImageDiskCache(key);
  if (disk != null) {
    _putMemCache(key, disk);
    return disk;
  }

  try {
    // 小于 60KB 的图片无需缩放，直接返回原图
    if (stat.size <= 60 * 1024) {
      final rawBytes = await File(path).readAsBytes();
      _putMemCache(key, rawBytes);
      return rawBytes;
    }

    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final codec = await ui.instantiateImageCodecFromBuffer(
      buffer,
      targetWidth: size,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    image.dispose();
    codec.dispose();
    buffer.dispose();

    if (byteData == null) return null;
    final bytes = byteData.buffer.asUint8List();

    _putMemCache(key, bytes);
    await _writeImageDiskCache(key, bytes);
    return bytes;
  } catch (e) {
    debugPrint('[Thumbnail] 生成图片缩略图失败: $path, $e');
    return null;
  }
}

void _putMemCache(String key, Uint8List bytes) {
  if (_imageMemCache.length >= _maxMemCacheEntries) {
    _imageMemCache.remove(_imageMemCache.keys.first);
  }
  _imageMemCache[key] = bytes;
}

/// 缓存键：路径哈希 + 路径长度 + 文件大小 + 修改时间（毫秒）。
String _cacheKey(String path, int size, int mtimeMs) =>
    '${path.hashCode.toRadixString(16)}_${path.length}_${size}_$mtimeMs';

Future<Directory> _imageThumbDir() async {
  final cache = await getTemporaryDirectory();
  final dir = Directory('${cache.path}${Platform.pathSeparator}image_thumbs');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<Uint8List?> _readImageDiskCache(String key) async {
  try {
    final dir = await _imageThumbDir();
    final file = File('${dir.path}${Platform.pathSeparator}$key.png');
    if (await file.exists()) return await file.readAsBytes();
  } catch (_) {}
  return null;
}

Future<void> _writeImageDiskCache(String key, Uint8List bytes) async {
  try {
    final dir = await _imageThumbDir();
    final file = File('${dir.path}${Platform.pathSeparator}$key.png');
    await file.writeAsBytes(bytes, flush: true);
  } catch (_) {}
}
