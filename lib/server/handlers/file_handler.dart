import 'dart:io';

import '../../core/file_type.dart';
import '../../core/path_utils.dart';
import '../server_context.dart';

/// GET /api/file?path=xxx
///
/// 全项目技术含量最高的部分：必须支持 HTTP Range 请求，
/// 流式读取，禁止一次性读入内存（视频可能几个 GB）。
Future<void> handleFile(HttpRequest request, ServerContext ctx) async {
  final path = request.uri.queryParameters['path'] ?? '';
  if (normalizeRelPath(path) == null) return forbidden(request);
  final guard = PathGuard(ctx.root);
  final abs = guard.resolve(path);
  if (abs == null) return forbidden(request);

  final type = FileSystemEntity.typeSync(abs, followLinks: false);
  if (type != FileSystemEntityType.file) return notFound(request);
  final file = File(abs);
  final size = await file.length();
  final mime = mimeTypeFor(abs);

  final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
  if (rangeHeader == null) {
    _sendFull(request, file, size, mime);
    return;
  }

  final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
  if (match == null) {
    _sendInvalidRange(request, size);
    return;
  }
  final startStr = match.group(1)!;
  final endStr = match.group(2)!;

  // 后缀范围：bytes=-N 表示最后 N 字节
  if (startStr.isEmpty) {
    if (endStr.isEmpty) {
      _sendInvalidRange(request, size);
      return;
    }
    final n = int.parse(endStr);
    final start = n >= size ? 0 : size - n;
    _sendRange(request, file, start, size - 1, size, mime);
    return;
  }

  final start = int.parse(startStr);
  int end = endStr.isEmpty ? size - 1 : int.parse(endStr);
  if (start < 0 || start >= size || end < start) {
    _sendInvalidRange(request, size);
    return;
  }
  if (end >= size) end = size - 1;
  _sendRange(request, file, start, end, size, mime);
}

void _sendFull(HttpRequest request, File file, int size, String mime) {
  final res = request.response;
  res.statusCode = HttpStatus.ok;
  res.headers.contentType = ContentType.parse(mime);
  res.headers.contentLength = size;
  res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  res.headers.set(
    HttpHeaders.cacheControlHeader,
    'public, max-age=86400',
  );
  // openRead 流式读取，整文件不落内存
  request.response.addStream(file.openRead()).then((_) {
    request.response.close();
  }).catchError((_) {
    // 捕获客户端切页或取消加载时主动断开连接，静默忽略
  });
}

void _sendRange(
  HttpRequest request,
  File file,
  int start,
  int end,
  int size,
  String mime,
) {
  final res = request.response;
  final length = end - start + 1;
  res.statusCode = HttpStatus.partialContent; // 206
  res.headers.contentType = ContentType.parse(mime);
  res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  res.headers.set(
    HttpHeaders.contentRangeHeader,
    'bytes $start-$end/$size',
  );
  res.headers.contentLength = length;
  res.headers.set(
    HttpHeaders.cacheControlHeader,
    'public, max-age=86400',
  );
  // openRead(start, end+1) 只流式读取 [start, end] 区间
  request.response.addStream(file.openRead(start, end + 1)).then((_) {
    request.response.close();
  }).catchError((_) {
    // 捕获播放器拖动进度条（seek）时取消前一个 range 请求的断开，静默忽略
  });
}

void _sendInvalidRange(HttpRequest request, int size) {
  final res = request.response;
  res.statusCode = HttpStatus.requestedRangeNotSatisfiable; // 416
  res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
  res.close();
}
