import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'discovery_provider.dart';
import 'services_provider.dart';

/// 设备在线状态（设备名 → 是否可达）。
///
/// 手动添加的设备没有 mDNS 心跳，只能靠主动探测判断在线，否则用户看到的
/// 永远是「可能离线」。探测在 App 退到后台时暂停、全部离线时退避，避免耗电。
final deviceHealthProvider =
    NotifierProvider<DeviceHealthNotifier, Map<String, bool>>(
  DeviceHealthNotifier.new,
);

class DeviceHealthNotifier extends Notifier<Map<String, bool>> {
  /// 前台正常探测间隔。
  static const Duration _foregroundInterval = Duration(seconds: 10);

  /// 全部离线时的退避间隔（省电，避免空转）。
  static const Duration _idleInterval = Duration(seconds: 45);

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;
  bool _probing = false;
  bool _disposed = false;

  @override
  Map<String, bool> build() {
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChange);
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _lifecycle?.dispose();
    });
    _schedule(immediate: true);
    return const {};
  }

  void _onLifecycleChange(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      _schedule(immediate: true);
    } else {
      // 后台暂停探测：省电，且此时用户看不到状态变化。
      _timer?.cancel();
      _timer = null;
    }
  }

  void _schedule({bool immediate = false}) {
    _timer?.cancel();
    if (!_foreground || _disposed) return;
    final delay = immediate ? Duration.zero : _nextInterval;
    _timer = Timer(delay, _probe);
  }

  Duration get _nextInterval {
    final allOffline = state.isNotEmpty && state.values.every((v) => !v);
    return allOffline ? _idleInterval : _foregroundInterval;
  }

  Future<void> _probe() async {
    if (!_foreground || _probing || _disposed) return;
    _probing = true;
    try {
      final devices = ref.read(deviceListProvider);
      if (devices.isEmpty) {
        if (state.isNotEmpty) state = const {};
        return;
      }
      final client = ref.read(remoteFileClientProvider);
      final entries = await Future.wait(
        devices.map((device) async {
          // /api/info 是唯一免口令接口，正好用来做连通性探测。
          final info = await client.fetchInfo(device);
          return MapEntry(device.deviceName, info.isOk);
        }),
      );
      if (_disposed || !_foreground) return;
      state = Map<String, bool>.fromEntries(entries);
    } finally {
      _probing = false;
      _schedule();
    }
  }
}
