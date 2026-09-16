import 'dart:async';

import 'package:flutter/foundation.dart';

/// 统一管理"播放控件（顶栏 + 中央按钮 + 底部进度条）"的显示状态。
///
/// 核心原则（解决"切视频后控件状态错乱"）：
/// 1. 默认永远隐藏；
/// 2. 任何"进入新播放会话"的路径（进页面 / 自动连播 / 手动切换）都必须显式
///    调用 [onEnterPlayer] 重置为隐藏，不依赖上一次的显示状态；
/// 3. 点击视频区域 [toggle]：隐藏 → 显示 →（3 秒无操作）自动隐藏；
/// 4. 拖动进度条等交互期间调用 [holdVisible] / [releaseHold]，
///    避免控件在操作途中被自动隐藏计时器打断。
class PlayerControlsController extends ValueNotifier<bool> {
  PlayerControlsController({
    this.autoHideDuration = const Duration(seconds: 3),
  }) : super(false);

  final Duration autoHideDuration;

  Timer? _autoHideTimer;

  /// 交互进行中（拖动进度条 / 打开面板），暂停自动隐藏计时。
  bool _held = false;

  /// 进入新的播放会话时调用：重置为隐藏。
  void onEnterPlayer() {
    _cancelTimer();
    _held = false;
    value = false;
  }

  /// 点击视频区域：显示 <-> 隐藏。
  ///
  /// 用户主动操作即视为"接管"控件，恢复到自动隐藏语义（否则上一次
  /// [holdVisible] 会让控件此后永不自动隐藏）。
  void toggle() {
    _held = false;
    if (value) {
      _hide();
    } else {
      _show();
    }
  }

  /// 立即显示并开始自动隐藏倒计时。
  ///
  /// 用于"进入预览即提示可操作"，与 [holdVisible]（交互期间锁定显示）区分。
  void showTemporarily() {
    _held = false;
    _show();
  }

  /// 立即显示（用于"播放结束"等需要把控制权交还用户的时刻）。
  void holdVisible() {
    _held = true;
    _cancelTimer();
    value = true;
  }

  /// 交互结束，重新开始自动隐藏计时。
  void releaseHold() {
    _held = false;
    _restartTimerIfNeeded();
  }

  void _show() {
    value = true;
    _restartTimerIfNeeded();
  }

  void _hide() {
    _cancelTimer();
    value = false;
  }

  void _restartTimerIfNeeded() {
    _cancelTimer();
    if (_held) return;
    _autoHideTimer = Timer(autoHideDuration, () {
      if (!_held) value = false;
    });
  }

  void _cancelTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }
}
