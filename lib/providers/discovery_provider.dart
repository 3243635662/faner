import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../data/models/device_info.dart';
import 'services_provider.dart';

/// mDNS 扫描到的设备列表流。
final discoveryProvider = StreamProvider<List<DeviceInfo>>((ref) {
  return ref.watch(discoveryServiceProvider).discover();
});

/// 手动添加的设备（持久化到 shared_preferences）。
final manualDevicesProvider =
    NotifierProvider<ManualDevicesNotifier, List<DeviceInfo>>(
  ManualDevicesNotifier.new,
);

class ManualDevicesNotifier extends Notifier<List<DeviceInfo>> {
  @override
  List<DeviceInfo> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppConstants.recentDevicesKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => DeviceInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      state = list;
    } catch (_) {
      // 忽略损坏的缓存
    }
  }

  Future<void> add(DeviceInfo device) async {
    if (state.any((d) => d == device)) return;
    state = [...state, device];
    await _persist();
  }

  Future<void> remove(DeviceInfo device) async {
    state = state.where((d) => d != device).toList();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConstants.recentDevicesKey,
        jsonEncode(state.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // 忽略
    }
  }
}

/// 合并 mDNS 发现结果 + 手动设备。
///
/// 以**设备名**为主键：对方 IP 变了（换网 / DHCP 重新分配）时，mDNS 结果里的
/// 新 IP 会自动覆盖手动记录中的旧 IP，避免一直连旧地址报「连接超时」。
final deviceListProvider = Provider<List<DeviceInfo>>((ref) {
  final discovered = ref.watch(discoveryProvider).value ?? const <DeviceInfo>[];
  final manual = ref.watch(manualDevicesProvider);

  final byName = <String, DeviceInfo>{};
  for (final d in manual) {
    byName[d.deviceName] = d;
  }
  for (final d in discovered) {
    final existing = byName[d.deviceName];
    byName[d.deviceName] = existing == null
        ? d
        : DeviceInfo(
            deviceName: existing.deviceName,
            // 用 mDNS 的最新地址覆盖，保留用户手动标记
            ip: d.ip,
            port: d.port,
            isManual: existing.isManual,
          );
  }

  final list = byName.values.toList();
  list.sort((a, b) {
    if (a.isManual != b.isManual) return a.isManual ? 1 : -1;
    return a.deviceName.compareTo(b.deviceName);
  });
  return list;
});
