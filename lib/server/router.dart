import 'dart:io';

import 'handlers/events_handler.dart';
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
      ctx.activity?.touch();
      final path = request.uri.path;

      // `/api/info` 公开：用于连通性校验，以及连接前探测「是否需要口令」。
      if (path == '/api/info') {
        await handleInfo(request, ctx);
        return;
      }

      // 其余接口统一鉴权（口令为空时直接放行）。
      if (!ctx.isAuthorized(request)) {
        unauthorized(request);
        return;
      }

      switch (path) {
        case '/api/list':
          await handleList(request, ctx);
        case '/api/search':
          await handleSearch(request, ctx);
        case '/api/file':
          await handleFile(request, ctx);
        case '/api/thumbnail':
          await handleThumbnail(request, ctx);
        case '/api/thumbs':
          await handleThumbnails(request, ctx);
        case '/api/events':
          await handleEvents(request, ctx);
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
