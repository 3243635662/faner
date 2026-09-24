import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/remote/discovery_service.dart';
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

/// 网络接口 IP 轮询间隔。4 秒足以在 Wi-Fi 重连后尽快重发广播，且开销可忽略。
const Duration _networkWatchInterval = Duration(seconds: 4);

/// 控制 MediaHttpServer 启停与网络环境自适应感知。
class ServerController extends Notifier<ServerState> {
  MediaHttpServer? _server;
  Timer? _networkWatchTimer;
  bool _checkingNetwork = false;
  Set<String> _lastKnownIps = <String>{};

  @override
  ServerState build() {
    // 容器销毁时停止轮询，避免 Timer 泄漏。
    ref.onDispose(() {
      _networkWatchTimer?.cancel();
      _networkWatchTimer = null;
    });
    return const ServerState(status: ServerStatus.stopped);
  }

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
        // 回调而非快照：在设置页改口令后无需重启共享即时生效。
        password: () => ref.read(settingsProvider).sharePassword,
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

      // 记录初始活跃 IP 集合
      _lastKnownIps = await DiscoveryService.getLocalIpv4Addresses();

      // 注册 mDNS 广播（失败不影响主流程）
      try {
        await ref
            .read(discoveryServiceProvider)
            .register(deviceName: name, port: port);
      } catch (_) {
        // 忽略
      }

      // 启动网络环境变动自适应监听（Wi-Fi 重连 / IP 动态变化）
      _startNetworkWatcher(name, port);
    } catch (e) {
      state = ServerState(status: ServerStatus.error, error: e.toString());
    }
  }

  void _startNetworkWatcher(String name, int port) {
    _networkWatchTimer?.cancel();
    _networkWatchTimer = Timer.periodic(_networkWatchInterval, (_) async {
      final server = _server;
      if (state.status != ServerStatus.running || server == null) return;
      // 空闲降频（省电）：最近 90 秒没有任何客户端访问时不检测网络变动，
      // 避免整夜空转；一旦有人访问，下一次 tick 立即恢复检测。
      if (!server.hasRecentClient) return;
      if (_checkingNetwork) return; // 上一轮尚未结束，跳过本轮避免重入
      _checkingNetwork = true;
      try {
        final currentIps = await DiscoveryService.getLocalIpv4Addresses();
        if (setEquals(_lastKnownIps, currentIps)) return;

        debugPrint(
          '[Faner] 检测到网络接口 IP 发生变动: $_lastKnownIps -> $currentIps，自动刷新广播与排重',
        );
        _lastKnownIps = currentIps;
        try {
          await ref.read(discoveryServiceProvider).refreshMyIps();
          if (currentIps.isNotEmpty) {
            await ref
                .read(discoveryServiceProvider)
                .register(deviceName: name, port: port);
            debugPrint('[Faner] mDNS 广播已在最新网络上重新发布');
          }
        } catch (e) {
          debugPrint('[Faner] 网络自适应刷新失败: $e');
        }
      } finally {
        _checkingNetwork = false;
      }
    });
  }

  Future<void> stop() async {
    _networkWatchTimer?.cancel();
    _networkWatchTimer = null;
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
