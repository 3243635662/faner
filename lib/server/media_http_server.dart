import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../data/local/local_file_service.dart';
import 'router.dart';
import 'server_context.dart';

/// 本机 HTTP 媒体服务器（dart:io HttpServer）。
class MediaHttpServer {
  MediaHttpServer({required this.localFileService, this.password});

  final LocalFileService localFileService;

  /// 共享口令解析器；为空表示不启用鉴权。
  final String Function()? password;

  final ServerActivity _activity = ServerActivity();

  HttpServer? _server;

  bool get isRunning => _server != null;

  int? get port => _server?.port;

  /// 最近是否有客户端在访问（用于空闲降频省电）。
  bool get hasRecentClient => _activity.hasRecentClient;

  /// 启动服务器，返回实际监听端口。
  Future<int> start({required String deviceName}) async {
    final current = _server;
    if (current != null) return current.port;

    final root = await localFileService.sharedRoot();
    final ctx = ServerContext(
      root: root,
      deviceName: deviceName,
      localFileService: localFileService,
      password: password ?? noPassword,
      activity: _activity,
    );
    final router = Router(ctx: ctx);

    HttpServer? server;
    for (var i = 0; i < AppConstants.maxPortRetries; i++) {
      try {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          AppConstants.basePort + i,
        );
        break;
      } on SocketException {
        continue;
      }
    }
    if (server == null) {
      throw StateError(
        '端口 ${AppConstants.basePort}~'
        '${AppConstants.basePort + AppConstants.maxPortRetries - 1} 均被占用',
      );
    }

    _server = server;
    server.listen(
      router.handle,
      onError: (Object _) {},
      onDone: () {
        if (_server == server) _server = null;
      },
    );
    debugPrint('[Faner] HTTP 服务器已启动：端口 ${server.port}，根目录 $root');
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {
        // 忽略
      }
    }
  }
}
