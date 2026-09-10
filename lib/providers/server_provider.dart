import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/foreground_service.dart';
import '../server/media_http_server.dart';
import 'services_provider.dart';
import 'settings_provider.dart';

enum ServerStatus { stopped, starting, running, error }

class ServerState {
  const ServerState({required this.status, this.port, this.error});

  final ServerStatus status;
  final int? port;
  final String? error;
}

final serverControllerProvider =
    NotifierProvider<ServerController, ServerState>(ServerController.new);

/// 控制 MediaHttpServer 启停。
class ServerController extends Notifier<ServerState> {
  MediaHttpServer? _server;

  @override
  ServerState build() => const ServerState(status: ServerStatus.stopped);

  Future<void> start() async {
    if (state.status == ServerStatus.running ||
        state.status == ServerStatus.starting) {
      return;
    }
    state = const ServerState(status: ServerStatus.starting);
    try {
      await ref.read(settingsProvider.notifier).ensureLoaded();
      final settings = ref.read(settingsProvider);
      final name = settings.deviceName.isEmpty ? 'Faner' : settings.deviceName;

      final server = MediaHttpServer(
        localFileService: ref.read(localFileServiceProvider),
      );
      final port = await server.start(deviceName: name);
      _server = server;
      state = ServerState(status: ServerStatus.running, port: port);

      // 启动前台服务保活（失败不影响共享主流程）
      try {
        await ForegroundService.start();
      } catch (_) {
        // 忽略
      }

      // 注册 mDNS 广播（失败不影响主流程）
      try {
        await ref
            .read(discoveryServiceProvider)
            .register(deviceName: name, port: port);
      } catch (_) {
        // 忽略
      }
    } catch (e) {
      state = ServerState(status: ServerStatus.error, error: e.toString());
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.stop();
    }
    // 停止前台服务保活
    try {
      await ForegroundService.stop();
    } catch (_) {
      // 忽略
    }
    try {
      await ref.read(discoveryServiceProvider).unregister();
    } catch (_) {
      // 忽略
    }
    state = const ServerState(status: ServerStatus.stopped);
  }
}
