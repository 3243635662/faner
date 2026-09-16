import 'package:flutter/foundation.dart';

/// 播放器显示模式。
///
/// 与设备方向（orientation）、主从双栏（split layout）是三个互相独立的
/// 概念：横屏不一定全屏，全屏也不等于切换方向。
enum PlayerDisplayMode {
  /// 常规：视频按原始比例居中显示，跟随页面布局。
  normal,

  /// 全屏：锁定横屏、隐藏系统栏、视频撑满整个屏幕。
  fullscreen,
}

/// 播放器状态机。
///
/// 刻意区分 [loading]、[buffering]、[playing]、[paused]、[completed]、
/// [error]，避免用一个 `isLoading` 布尔值代表所有"非播放中"的情况 ——
/// 这直接决定 UI 该显示转圈、进度条还是错误页。
enum PlayerStatus {
  /// 尚未加载任何媒体。
  idle,

  /// 首次打开媒体，等待首帧。
  loading,

  /// 正在播放。
  playing,

  /// 已暂停（用户主动暂停或切后台）。
  paused,

  /// 播放中缓冲（网络卡顿）：画面定格但仍在"播放"语义。
  buffering,

  /// 已播放到结尾，等待连播 / 重播决策。
  completed,

  /// 打开或解码失败。
  error,
}

/// 播放器对外暴露的状态快照。
///
/// 所有字段都来自 media_kit 的状态流（见 [MediaPlayerController]），
/// 播放器不自己用 Timer 轮询维护这些值。
@immutable
class PlayerState {
  const PlayerState({
    this.status = PlayerStatus.idle,
    this.index = 0,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.rate = 1.0,
    this.aspectRatio,
    this.bufferingPercentage = 0.0,
    this.error,
  });

  /// 当前状态机取值。
  final PlayerStatus status;

  /// 当前播放项在播放列表中的下标。
  final int index;

  /// 媒体总时长（未知时为 [Duration.zero]）。
  final Duration duration;

  /// 音量 0.0 ~ 1.0（media_kit 内部量程 0 ~ 100，由 Service 换算）。
  final double volume;

  /// 播放倍速。
  final double rate;

  /// 视频宽高比；未知时为 null（此时按 16:9 兜底）。
  final double? aspectRatio;

  /// 缓冲完成度，原样来自内核（单位见 [bufferingRatio]）。
  final double bufferingPercentage;

  /// 面向用户的错误文案（已按网络/文件/格式分类）。
  final String? error;

  /// 缓冲进度归一化到 0.0 ~ 1.0。
  ///
  /// 内核该字段在不同实现/版本间可能是 0~100 或 0~1，这里做一次防御性归一，
  /// 避免 UI 上出现"缓冲 0%"或"缓冲 4500%"。
  double get bufferingRatio {
    final value = bufferingPercentage;
    if (value <= 0) return 0;
    return (value > 1 ? value / 100 : value).clamp(0.0, 1.0);
  }

  bool get isPlaying => status == PlayerStatus.playing;

  /// 是否处于"用户需要看到加载反馈"的状态。
  bool get isBusy =>
      status == PlayerStatus.loading || status == PlayerStatus.buffering;

  /// 是否已能渲染画面（非 idle / loading / error）。
  bool get isReady =>
      status != PlayerStatus.idle &&
      status != PlayerStatus.loading &&
      status != PlayerStatus.error;

  PlayerState copyWith({
    PlayerStatus? status,
    int? index,
    Duration? duration,
    double? volume,
    double? rate,
    double? aspectRatio,
    double? bufferingPercentage,
    String? error,
    bool clearError = false,
  }) {
    return PlayerState(
      status: status ?? this.status,
      index: index ?? this.index,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      rate: rate ?? this.rate,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      bufferingPercentage: bufferingPercentage ?? this.bufferingPercentage,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  String toString() =>
      'PlayerState(${status.name}, index: $index, duration: $duration, '
      'volume: $volume, rate: $rate, error: $error)';
}

/// 把播放内核抛出的原始错误翻译成用户能看懂的原因。
///
/// 原始信息是 libmpv 的英文日志（如 `Failed to open ...`），
/// 直接展示给用户既看不懂也不礼貌（见优化方案「错误状态」一节）。
String describePlayerError(String raw, {required bool isRemote}) {
  final text = raw.toLowerCase();

  const networkKeys = [
    'connection',
    'timed out',
    'timeout',
    'network',
    'unreachable',
    'refused',
    'resolve',
    'http error',
    '404',
    '500',
    '503',
  ];
  if (networkKeys.any(text.contains)) {
    return isRemote
        ? '网络连接失败，请确认对方设备在线且处于同一局域网'
        : '无法读取该文件，请检查文件是否仍然存在';
  }

  const missingKeys = ['no such file', 'not found', 'does not exist', 'enoent'];
  if (missingKeys.any(text.contains)) {
    return isRemote ? '文件不存在或已被移动（对方设备返回 404）' : '文件不存在或已被移动';
  }

  const formatKeys = [
    'format',
    'codec',
    'unsupported',
    'unknown format',
    'could not open codec',
    'no video',
  ];
  if (formatKeys.any(text.contains)) {
    return '视频格式不支持或文件已损坏';
  }

  const permissionKeys = ['permission', 'denied', 'eacces'];
  if (permissionKeys.any(text.contains)) {
    return '没有权限读取该文件，请在系统设置中开启「所有文件访问」';
  }

  return '视频无法播放，请稍后重试';
}
