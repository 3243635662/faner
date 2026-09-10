import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/file_view_mode.dart';

class SettingsState {
  const SettingsState({
    required this.deviceName,
    required this.serverEnabled,
    required this.themeMode,
    required this.viewMode,
  });

  const SettingsState.initial()
      : deviceName = '',
        serverEnabled = true,
        themeMode = ThemeMode.system,
        viewMode = FileViewMode.list;

  final String deviceName;
  final bool serverEnabled;
  final ThemeMode themeMode;
  final FileViewMode viewMode;

  SettingsState copyWith({
    String? deviceName,
    bool? serverEnabled,
    ThemeMode? themeMode,
    FileViewMode? viewMode,
  }) =>
      SettingsState(
        deviceName: deviceName ?? this.deviceName,
        serverEnabled: serverEnabled ?? this.serverEnabled,
        themeMode: themeMode ?? this.themeMode,
        viewMode: viewMode ?? this.viewMode,
      );
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _kDeviceName = 'device_name';
  static const _kServerEnabled = 'server_enabled';
  static const _kThemeMode = 'theme_mode';
  static const _kViewMode = 'view_mode';

  Future<void>? _loaded;

  @override
  SettingsState build() {
    _loaded = _load();
    return const SettingsState.initial();
  }

  Future<void> ensureLoaded() => _loaded ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_kDeviceName);
      final enabled = prefs.getBool(_kServerEnabled) ?? true;
      final themeMode = _enumFromName(
        ThemeMode.values,
        prefs.getString(_kThemeMode),
        ThemeMode.system,
      );
      final viewMode = _enumFromName(
        FileViewMode.values,
        prefs.getString(_kViewMode),
        FileViewMode.list,
      );
      final finalName = (name == null || name.isEmpty)
          ? await _defaultDeviceName()
          : name;
      state = SettingsState(
        deviceName: finalName,
        serverEnabled: enabled,
        themeMode: themeMode,
        viewMode: viewMode,
      );
    } catch (_) {
      state = SettingsState(
        deviceName: await _defaultDeviceName(),
        serverEnabled: true,
        themeMode: ThemeMode.system,
        viewMode: FileViewMode.list,
      );
    }
  }

  static T _enumFromName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) =>
      values.firstWhere((e) => e.name == name, orElse: () => fallback);

  Future<String> _defaultDeviceName() async {
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      final model = android.model.trim();
      if (model.isNotEmpty) return model;
    } catch (_) {
      // 忽略
    }
    return 'Faner 设备';
  }

  Future<void> setDeviceName(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    state = state.copyWith(deviceName: n);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceName, n);
  }

  Future<void> setServerEnabled(bool enabled) async {
    state = state.copyWith(serverEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kServerEnabled, enabled);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> toggleViewMode() async {
    final next = state.viewMode == FileViewMode.grid
        ? FileViewMode.list
        : FileViewMode.grid;
    state = state.copyWith(viewMode: next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kViewMode, next.name);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
