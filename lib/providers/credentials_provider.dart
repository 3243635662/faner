import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 远端设备的共享口令，按**设备名**索引。
///
/// 用设备名而非 IP 作键：对方 IP 变了（换网/重连 DHCP）后口令依然有效。
final deviceCredentialsProvider =
    NotifierProvider<DeviceCredentialsNotifier, Map<String, String>>(
  DeviceCredentialsNotifier.new,
);

class DeviceCredentialsNotifier extends Notifier<Map<String, String>> {
  static const _prefsKey = 'device_credentials';

  @override
  Map<String, String> build() {
    _load();
    return const {};
  }

  /// 取某设备已保存的口令（未保存返回 null）。
  String? tokenFor(String deviceName) => state[deviceName];

  Future<void> save(String deviceName, String token) async {
    final t = token.trim();
    if (deviceName.isEmpty || t.isEmpty) return;
    state = {...state, deviceName: t};
    await _persist();
  }

  Future<void> remove(String deviceName) async {
    if (!state.containsKey(deviceName)) return;
    final next = {...state}..remove(deviceName);
    state = next;
    await _persist();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      // 忽略损坏的缓存
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(state));
    } catch (_) {
      // 忽略
    }
  }
}
