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

/// 合并 mDNS 发现结果 + 手动设备，去重排序。
final deviceListProvider = Provider<List<DeviceInfo>>((ref) {
  final discovered = ref.watch(discoveryProvider).value ?? const <DeviceInfo>[];
  final manual = ref.watch(manualDevicesProvider);
  final map = <String, DeviceInfo>{};
  for (final d in discovered) {
    map['${d.ip}:${d.port}'] = d;
  }
  for (final d in manual) {
    map.putIfAbsent('${d.ip}:${d.port}', () => d);
  }
  final list = map.values.toList();
  list.sort((a, b) {
    if (a.isManual != b.isManual) return a.isManual ? 1 : -1;
    return a.deviceName.compareTo(b.deviceName);
  });
  return list;
});
