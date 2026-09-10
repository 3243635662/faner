import 'dart:io';

import 'handlers/file_handler.dart';
import 'handlers/info_handler.dart';
import 'handlers/list_handler.dart';
import 'handlers/search_handler.dart';
import 'handlers/thumbnail_handler.dart';
import 'server_context.dart';

/// 简单的按路径前缀分发，无需正则路由引擎。
class Router {
  Router({required this.ctx});

  final ServerContext ctx;

  Future<void> handle(HttpRequest request) async {
    try {
      switch (request.uri.path) {
        case '/api/info':
          await handleInfo(request, ctx);
        case '/api/list':
          await handleList(request, ctx);
        case '/api/search':
          await handleSearch(request, ctx);
        case '/api/file':
          await handleFile(request, ctx);
        case '/api/thumbnail':
          await handleThumbnail(request, ctx);
        default:
          notFound(request);
      }
    } catch (e) {
      try {
        serverError(request, 'server error: $e');
      } catch (_) {
        // 响应可能已关闭，忽略
      }
    }
  }
}
