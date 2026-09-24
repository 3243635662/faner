import 'dart:convert';
import 'dart:io';

import '../core/auth.dart';
import '../core/path_utils.dart';
import '../data/local/local_file_service.dart';

/// 未启用口令时的默认解析器（恒为空串）。
String noPassword() => '';

/// 客户端活跃度追踪：用于服务端在「无人访问」时主动降频（省电）。
class ServerActivity {
  DateTime? _lastRequestAt;

  DateTime? get lastRequestAt => _lastRequestAt;

  /// 收到任意请求时调用。
  void touch() => _lastRequestAt = DateTime.now();

  /// 最近是否有客户端在活跃访问（90 秒内有过请求）。
  bool get hasRecentClient {
    final last = _lastRequestAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < const Duration(seconds: 90);
  }
}

/// 服务端处理器共享的上下文。
class ServerContext {
  const ServerContext({
    required this.root,
    required this.deviceName,
    required this.localFileService,
    this.password = noPassword,
    this.activity,
  });

  final String root;
  final String deviceName;
  final LocalFileService localFileService;

  /// 共享口令解析器；返回空串表示不开启鉴权。
  ///
  /// 用「回调」而非字符串快照：用户在设置页改了口令后无需重启服务即时生效。
  final String Function() password;

  /// 活跃度追踪（可为空，测试场景可不传）。
  final ServerActivity? activity;

  /// 当前是否要求口令访问。
  bool get authRequired => password().isNotEmpty;

  /// 校验请求携带的令牌：`X-Auth-Token` header 或 `token` query 参数。
  ///
  /// 媒体地址（图片/视频）无法自定义 header，因此必须同时支持 query 形式。
  bool isAuthorized(HttpRequest request) {
    final expected = password();
    if (expected.isEmpty) return true;
    final supplied = request.headers.value(authHeaderName) ??
        request.uri.queryParameters[authQueryParam];
    if (supplied == null || supplied.isEmpty) return false;
    return _constantTimeEquals(supplied, expected);
  }
}

/// 恒定时间比较，避免通过响应耗时逐字节猜出口令。
bool _constantTimeEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  if (x.length != y.length) return false;
  var diff = 0;
  for (var i = 0; i < x.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
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

/// gzip 压缩阈值：小于该体积的响应压缩收益不足以抵消 CPU 开销。
const int _gzipMinBytes = 1024;

void writeJson(HttpRequest request, Map<String, dynamic> data) {
  final res = request.response;
  res.statusCode = HttpStatus.ok;
  res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');

  final body = utf8.encode(jsonEncode(data));

  // 仅在客户端声明支持 gzip 且响应体足够大时压缩：
  // 3000+ 文件的目录列表 JSON 可骤降 80%~90%，而小响应压缩得不偿失。
  if (body.length >= _gzipMinBytes && _acceptsGzip(request)) {
    final compressed = GZipCodec().encode(body);
    res.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
    res.headers.contentLength = compressed.length;
    res.add(compressed);
  } else {
    res.headers.contentLength = body.length;
    res.add(body);
  }
  res.close();
}

/// 解析 `Accept-Encoding`，判断客户端是否真正接受 gzip（尊重 `q=0` 拒绝）。
bool _acceptsGzip(HttpRequest request) {
  final header = request.headers.value(HttpHeaders.acceptEncodingHeader);
  if (header == null || header.isEmpty) return false;
  for (final part in header.split(',')) {
    final seg = part.trim().toLowerCase();
    if (seg.isEmpty) continue;
    final name = seg.split(';').first.trim();
    if (name != 'gzip' && name != '*') continue;
    var q = 1.0;
    for (final param in seg.split(';').skip(1)) {
      final kv = param.trim().split('=');
      if (kv.length == 2 && kv[0].trim() == 'q') {
        q = double.tryParse(kv[1].trim()) ?? 1.0;
      }
    }
    return q > 0;
  }
  return false;
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

/// 401：需要共享口令（或口令不正确）。
void unauthorized(HttpRequest request) =>
    respond(request, HttpStatus.unauthorized, 'unauthorized');

void forbidden(HttpRequest request) =>
    respond(request, HttpStatus.forbidden, 'forbidden');

void notFound(HttpRequest request) =>
    respond(request, HttpStatus.notFound, 'not found');

void serverError(HttpRequest request, [String? message]) =>
    respond(request, HttpStatus.internalServerError, message ?? 'server error');
