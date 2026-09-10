import 'dart:async';
import 'package:flutter/foundation.dart';

/// 统一管理"播放控件（顶部栏 + 底部进度条 + 中间三按钮）"的显示状态。
///
/// 核心设计原则（用来解决"切视频后控件状态错乱"的问题）：
/// 1. 默认永远是隐藏的（[value] 初始为 false）。
/// 2. 无论是"用户手动点进播放页"还是"自动播放下一个视频"，
///    只要发生了"进入一个新的播放会话"，都必须显式调用 [onEnterPlayer]
///    重置为隐藏 —— 不要依赖默认值或者上一次的显示状态，
///    这是唯一能保证所有入口行为一致的方式。
/// 3. 点击视频区域调用 [toggle]：隐藏 -> 显示 -> （3 秒无操作）自动隐藏。
/// 4. 拖动进度条等操作时调用 [holdVisible] / [releaseHold]，
///    避免用户正在操作时控件被自动隐藏计时器打断。
class VideoControlsController extends ValueNotifier<bool> {
  VideoControlsController({
    this.autoHideDuration = const Duration(seconds: 3),
  }) : super(false);

  final Duration autoHideDuration;

  Timer? _autoHideTimer;
  bool _held = false; // 用户正在拖动进度条等交互中，暂停自动隐藏计时

  /// 进入一个新的播放会话时调用：
  /// - 首次进入播放页（initState）
  /// - 自动播放完切换到下一个视频
  /// - 用户点击"上一个/下一个"按钮切换视频
  /// 三个入口都必须调用这个方法，不能只依赖某一个入口"顺便"隐藏了控件。
  void onEnterPlayer() {
    _cancelTimer();
    _held = false;
    value = false;
  }

  /// 点击视频区域时调用：显示 <-> 隐藏 切换。
  void toggle() {
    if (value) {
      _hide();
    } else {
      _show();
    }
  }

  void _show() {
    value = true;
    _restartTimerIfNeeded();
  }

  void _hide() {
    _cancelTimer();
    value = false;
  }

  /// 用户开始拖动进度条 / 长按快进等交互时调用，防止控件被计时器隐藏。
  void holdVisible() {
    _held = true;
    _cancelTimer();
    value = true;
  }

  /// 交互结束后调用，重新开始自动隐藏计时。
  void releaseHold() {
    _held = false;
    _restartTimerIfNeeded();
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
