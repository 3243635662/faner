import 'package:faner/core/file_view_mode.dart';
import 'package:faner/core/video_play_mode.dart';
import 'package:faner/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SettingsState 初始状态局域网共享与自启默认均为关闭', () {
    const state = SettingsState.initial();
    expect(state.serverEnabled, isFalse);
    expect(state.autoStartServer, isFalse);
    expect(state.themeMode, ThemeMode.system);
    expect(state.viewMode, FileViewMode.list);
    expect(state.videoPlayMode, VideoPlayMode.sequential);
  });

  test('SettingsState copyWith 支持修改 autoStartServer', () {
    const state = SettingsState.initial();
    final updated = state.copyWith(autoStartServer: true, serverEnabled: true);
    expect(updated.autoStartServer, isTrue);
    expect(updated.serverEnabled, isTrue);
  });
}
