import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/concurrency.dart';
import '../../core/file_type.dart';
import '../../core/image_thumbnail.dart';
import '../../core/path_utils.dart';
import '../../core/video_thumbnail.dart';
import '../server_context.dart';

/// 缩略图生成的全局并发闸门。
///
/// 网格翻页时若不加节制地并发解码，会把 CPU 与内存瞬间打满，
/// 反而拖慢整体响应；这里把并发压到 3 路。
final Semaphore _thumbSemaphore = Semaphore(3);

/// 批量接口单次最多处理的路径数。
const int maxBatchThumbnails = 48;

/// 生成缩略图字节，统一经过并发闸门。图片返回 PNG，视频返回 JPEG。
Future<({Uint8List bytes, String subtype})?> _generateThumb(String abs) async {
  final type = fileTypeFromName(abs);
  if (type == EntryType.image) {
    final bytes = await _thumbSemaphore.run(
      () => generateImageThumbnailBytes(abs, size: 240),
    );
    if (bytes == null) return null;
    return (bytes: bytes, subtype: 'png');
  }
  if (type == EntryType.video) {
    final bytes = await _thumbSemaphore.run(
      () => generateVideoThumbnailBytes(abs, size: 240, quality: 70),
    );
    if (bytes == null) return null;
    return (bytes: bytes, subtype: 'jpeg');
  }
  return null;
}

/// GET /api/thumbnail?path=xxx
///
/// 单张缩略图：支持视频与图片，复用「内存 + 磁盘」多级缓存。
Future<void> handleThumbnail(HttpRequest request, ServerContext ctx) async {
  final path = request.uri.queryParameters['path'] ?? '';
  if (normalizeRelPath(path) == null) return forbidden(request);
  final abs = PathGuard(ctx.root).resolve(path);
  if (abs == null) return forbidden(request);

  final type = FileSystemEntity.typeSync(abs, followLinks: false);
  if (type != FileSystemEntityType.file) return notFound(request);

  try {
    final thumb = await _generateThumb(abs);
    if (thumb == null) return notFound(request);

    final res = request.response;
    res.statusCode = HttpStatus.ok;
    res.headers.contentType = ContentType('image', thumb.subtype);
    res.headers.contentLength = thumb.bytes.length;
    // 缩略图 7 天强缓存，避免重复拉取
    res.headers.set(
      HttpHeaders.cacheControlHeader,
      'public, max-age=604800, immutable',
    );
    res.add(thumb.bytes);
    await res.close();
  } catch (_) {
    serverError(request);
  }
}

/// GET /api/thumbs?path=a&path=b&...
///
/// 批量缩略图：网格/列表首屏一次要几十张，逐张 HTTP 往返在弱网下延迟极高。
/// 这里一次往返打包返回（base64 内嵌 JSON，整体还能再被 gzip 压一次）。
Future<void> handleThumbnails(HttpRequest request, ServerContext ctx) async {
  final paths = request.uri.queryParametersAll['path'] ?? const <String>[];
  if (paths.isEmpty) return badRequest(request);

  final guard = PathGuard(ctx.root);
  final wanted = paths.take(maxBatchThumbnails).toList();
  final thumbs = <String, String?>{};

  await Future.wait(wanted.map((path) async {
    if (normalizeRelPath(path) == null) {
      thumbs[path] = null;
      return;
    }
    final abs = guard.resolve(path);
    if (abs == null) {
      thumbs[path] = null;
      return;
    }
    if (FileSystemEntity.typeSync(abs, followLinks: false) !=
        FileSystemEntityType.file) {
      thumbs[path] = null;
      return;
    }
    try {
      final thumb = await _generateThumb(abs);
      thumbs[path] = thumb == null ? null : base64Encode(thumb.bytes);
    } catch (_) {
      thumbs[path] = null;
    }
  }));

  writeJson(request, {'thumbs': thumbs});
}
