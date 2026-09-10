import 'dart:io';

import '../../core/path_utils.dart';
import '../../core/video_thumbnail.dart';
import '../server_context.dart';

/// GET /api/thumbnail?path=xxx
///
/// 复用 [generateVideoThumbnailBytes] 的「内存 + 磁盘」三级缓存，
/// 与本地浏览共享，避免重复用 MediaMetadataRetriever 解码。
Future<void> handleThumbnail(HttpRequest request, ServerContext ctx) async {
  final path = request.uri.queryParameters['path'] ?? '';
  if (normalizeRelPath(path) == null) return forbidden(request);
  final guard = PathGuard(ctx.root);
  final abs = guard.resolve(path);
  if (abs == null) return forbidden(request);

  final type = FileSystemEntity.typeSync(abs, followLinks: false);
  if (type != FileSystemEntityType.file) return notFound(request);

  try {
    final bytes =
        await generateVideoThumbnailBytes(abs, size: 240, quality: 70);
    if (bytes == null) return notFound(request);

    final res = request.response;
    res.statusCode = HttpStatus.ok;
    res.headers.contentType = ContentType('image', 'jpeg');
    res.headers.contentLength = bytes.length;
    res.add(bytes);
    res.close();
  } catch (_) {
    serverError(request);
  }
}
