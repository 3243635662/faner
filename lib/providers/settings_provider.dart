import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/file_view_mode.dart';
import '../core/seek_sensitivity.dart';
import '../core/video_play_mode.dart';

class SettingsState {
  const SettingsState({
    required this.deviceName,
    required this.serverEnabled,
    required this.autoStartServer,
    required this.themeMode,
    required this.viewMode,
    required this.videoPlayMode,
    required this.longPressSpeed,
    required this.seekSensitivity,
    required this.rememberProgress,
    required this.sharePassword,
  });

  const SettingsState.initial()
      : deviceName = '',
        serverEnabled = false,
        autoStartServer = false,
        themeMode = ThemeMode.system,
        viewMode = FileViewMode.list,
        videoPlayMode = VideoPlayMode.sequential,
        longPressSpeed = 2.0,
        seekSensitivity = SeekSensitivity.standard,
        rememberProgress = true,
        sharePassword = '';

  final String deviceName;
  final bool serverEnabled;

  /// 下次进入应用时是否自动开启局域网共享。
  final bool autoStartServer;

  final ThemeMode themeMode;
  final FileViewMode viewMode;
  final VideoPlayMode videoPlayMode;

  /// 视频长按倍速播放的倍率。
  final double longPressSpeed;

  /// 左右滑动快进 / 后退的灵敏度。
  final SeekSensitivity seekSensitivity;

  /// 是否记住媒体播放进度（视频断点续播）。
  final bool rememberProgress;

  /// 共享口令；为空表示不开启口令保护（同网设备可直接访问）。
  final String sharePassword;

  SettingsState copyWith({
    String? deviceName,
    bool? serverEnabled,
    bool? autoStartServer,
    ThemeMode? themeMode,
    FileViewMode? viewMode,
    VideoPlayMode? videoPlayMode,
    double? longPressSpeed,
    SeekSensitivity? seekSensitivity,
    bool? rememberProgress,
    String? sharePassword,
  }) =>
      SettingsState(
        deviceName: deviceName ?? this.deviceName,
        serverEnabled: serverEnabled ?? this.serverEnabled,
        autoStartServer: autoStartServer ?? this.autoStartServer,
        themeMode: themeMode ?? this.themeMode,
        viewMode: viewMode ?? this.viewMode,
        videoPlayMode: videoPlayMode ?? this.videoPlayMode,
        longPressSpeed: longPressSpeed ?? this.longPressSpeed,
        seekSensitivity: seekSensitivity ?? this.seekSensitivity,
        rememberProgress: rememberProgress ?? this.rememberProgress,
        sharePassword: sharePassword ?? this.sharePassword,
      );
}

class SettingsNotifier extends Notifier<SettingsState> {
  static const _kDeviceName = 'device_name';
  static const _kServerEnabled = 'server_enabled';
  static const _kAutoStartServer = 'auto_start_server';
  static const _kThemeMode = 'theme_mode';
  static const _kViewMode = 'view_mode';
  static const _kVideoPlayMode = 'video_play_mode';
  static const _kLongPressSpeed = 'long_press_speed';
  static const _kSeekSensitivity = 'seek_sensitivity';
  static const _kRememberProgress = 'remember_progress';
  static const _kSharePassword = 'share_password';

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
      final autoStart = prefs.getBool(_kAutoStartServer) ?? false;
      // 若开启了自启，则本次会话默认启用；否则默认关闭
      final enabled = prefs.getBool(_kServerEnabled) ?? autoStart;
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
      final videoPlayMode = _enumFromName(
        VideoPlayMode.values,
        prefs.getString(_kVideoPlayMode),
        VideoPlayMode.sequential,
      );
      final longPressSpeed = prefs.getDouble(_kLongPressSpeed) ?? 2.0;
      final seekSensitivity = _enumFromName(
        SeekSensitivity.values,
        prefs.getString(_kSeekSensitivity),
        SeekSensitivity.standard,
      );
      final rememberProgress = prefs.getBool(_kRememberProgress) ?? true;
      final sharePassword = prefs.getString(_kSharePassword) ?? '';
      final finalName = (name == null || name.isEmpty)
          ? await _defaultDeviceName()
          : name;
      state = SettingsState(
        deviceName: finalName,
        serverEnabled: enabled,
        autoStartServer: autoStart,
        themeMode: themeMode,
        viewMode: viewMode,
        videoPlayMode: videoPlayMode,
        longPressSpeed: longPressSpeed,
        seekSensitivity: seekSensitivity,
        rememberProgress: rememberProgress,
        sharePassword: sharePassword,
      );
    } catch (_) {
      state = SettingsState(
        deviceName: await _defaultDeviceName(),
        serverEnabled: false,
        autoStartServer: false,
        themeMode: ThemeMode.system,
        viewMode: FileViewMode.list,
        videoPlayMode: VideoPlayMode.sequential,
        longPressSpeed: 2.0,
        seekSensitivity: SeekSensitivity.standard,
        rememberProgress: true,
        sharePassword: '',
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

  Future<void> setAutoStartServer(bool value) async {
    state = state.copyWith(autoStartServer: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoStartServer, value);
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

  Future<void> setVideoPlayMode(VideoPlayMode mode) async {
    state = state.copyWith(videoPlayMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVideoPlayMode, mode.name);
  }

  Future<void> setLongPressSpeed(double speed) async {
    state = state.copyWith(longPressSpeed: speed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kLongPressSpeed, speed);
  }

  Future<void> setSeekSensitivity(SeekSensitivity sensitivity) async {
    state = state.copyWith(seekSensitivity: sensitivity);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSeekSensitivity, sensitivity.name);
  }

  Future<void> setRememberProgress(bool value) async {
    state = state.copyWith(rememberProgress: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRememberProgress, value);
  }

  /// 设置共享口令；传空串表示关闭口令保护。
  Future<void> setSharePassword(String value) async {
    final password = value.trim();
    state = state.copyWith(sharePassword: password);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSharePassword, password);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
