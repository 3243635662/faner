import 'dart:convert';
import 'dart:io';

import '../core/path_utils.dart';
import '../data/local/local_file_service.dart';

/// 服务端处理器共享的上下文。
class ServerContext {
  const ServerContext({
    required this.root,
    required this.deviceName,
    required this.localFileService,
  });

  final String root;
  final String deviceName;
  final LocalFileService localFileService;
}

/// 路径穿越防护：把相对路径解析到 [root] 内的绝对路径，非法返回 null。
class PathGuard {
  PathGuard(this.root);

  final String root;

  String? resolve(String relPath) {
    final normalized = normalizeRelPath(relPath);
    if (normalized == null) return null;
    // 统一用 `/` 分隔比较，避免依赖平台分隔符（Windows 为 `\`）导致误判。
    final root = this.root.replaceAll('\\', '/');
    final abs = normalized.isEmpty ? root : '$root/$normalized';
    if (abs != root && !abs.startsWith('$root/')) return null;
    return abs;
  }
}

void writeJson(HttpRequest request, Map<String, dynamic> data) {
  final res = request.response;
  res.statusCode = HttpStatus.ok;
  res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
  res.write(jsonEncode(data));
  res.close();
}

void respond(HttpRequest request, int status, [String? message]) {
  final res = request.response;
  res.statusCode = status;
  res.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
  if (message != null) res.write(message);
  res.close();
}

void badRequest(HttpRequest request) =>
    respond(request, HttpStatus.badRequest, 'bad request');

void forbidden(HttpRequest request) =>
    respond(request, HttpStatus.forbidden, 'forbidden');

void notFound(HttpRequest request) =>
    respond(request, HttpStatus.notFound, 'not found');

void serverError(HttpRequest request, [String? message]) =>
    respond(request, HttpStatus.internalServerError, message ?? 'server error');
