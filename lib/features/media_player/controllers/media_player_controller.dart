import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/video_play_mode.dart';
import '../../../core/video_resume.dart';
import '../models/media_item.dart';
import '../models/player_state.dart';
import '../services/media_player_service.dart';
import '../services/system_ui_service.dart';

/// 播放会话控制器：整个播放器唯一的"大脑"。
///
/// 职责边界：
/// - 状态全部来自 [MediaPlayerService] 的状态流，**不自己用 Timer 轮询**，
///   避免"UI 显示在播、内核其实已停"的错位；
/// - 业务逻辑（连播、断点续播、生命周期、屏幕常亮）都在这里，
///   UI 层只渲染状态并把用户操作转发进来；
/// - 不接触任何 `media_kit` 类型（那是 Service 的事），
///   唯一例外是给渲染层用的 [videoOutput]。
class MediaPlayerController extends ChangeNotifier with WidgetsBindingObserver {
  MediaPlayerController({
    required List<MediaItem> playlist,
    required int initialIndex,
    this.embedded = false,
    this.rememberProgress = true,
    this.playMode = VideoPlayMode.sequential,
    this.httpHeaders,
  })  : _playlist = List<MediaItem>.unmodifiable(playlist),
        _index = initialIndex {
    _service = MediaPlayerService();
    _bindStreams();
    WidgetsBinding.instance.addObserver(this);
    if (!embedded) {
      // 观看期间保持屏幕常亮（内嵌预览不霸占屏幕）
      unawaited(WakelockPlus.enable());
    }
    unawaited(_load(_index, initial: true));
  }

  final List<MediaItem> _playlist;

  /// 构造期配置：是否记住断点（来自设置）。
  final bool rememberProgress;

  /// 构造期配置：播完后的连播方式（来自设置）。
  final VideoPlayMode playMode;

  /// 预留：远端媒体鉴权 / Token 场景可直接下发请求头（方案「HTTP 视频播放」）。
  final Map<String, String>? httpHeaders;

  /// 内嵌模式（双栏详情面板预览）：不接管系统 UI、不保持常亮。
  final bool embedded;

  late final MediaPlayerService _service;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// 播放进度单独用 [ValueNotifier] 暴露：进度条每 100ms 左右更新一次，
  /// 若走 [notifyListeners] 会让整个控件层跟着重建。
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);

  PlayerState _state = const PlayerState();
  int _index;
  bool _loading = false;
  bool _completedHandled = false;
  bool _disposed = false;
  double _baseRate = 1.0;

  // ---------------------------------------------------------------------------
  // 对外只读视图
  // ---------------------------------------------------------------------------

  PlayerState get state => _state;

  /// 播放进度（高频更新，请单独监听）。
  ValueListenable<Duration> get position => _position;

  List<MediaItem> get playlist => _playlist;

  MediaItem? get current =>
      _index >= 0 && _index < _playlist.length ? _playlist[_index] : null;

  bool get hasMultiple => _playlist.length > 1;

  /// 视频输出控制器，交给渲染层（`VideoSurface`）使用。
  mkv.VideoController get videoOutput => _service.videoController;

  // ---------------------------------------------------------------------------
  // 播放控制
  // ---------------------------------------------------------------------------

  Future<void> togglePlay() async {
    if (_state.status == PlayerStatus.error) {
      await retry();
      return;
    }
    // 播完后点播放 = 从头重播
    if (_state.status == PlayerStatus.completed) {
      await _replayCurrent();
      return;
    }
    await _service.togglePlay();
  }

  Future<void> seek(Duration target) async {
    final duration = _state.duration;
    var clamped = target;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (duration > Duration.zero && clamped > duration) clamped = duration;
    _position.value = clamped;
    await _service.seek(clamped);
  }

  /// 快进 / 后退（手势与 ±10 秒按钮共用）。
  Future<void> seekBy(Duration delta) => seek(_position.value + delta);

  void next() {
    if (_playlist.length < 2) return;
    unawaited(_load((_index + 1) % _playlist.length));
  }

  void previous() {
    if (_playlist.length < 2) return;
    unawaited(_load((_index - 1 + _playlist.length) % _playlist.length));
  }

  /// 跳到播放列表中的指定项。
  void jumpTo(int index) {
    if (index == _index || index < 0 || index >= _playlist.length) return;
    unawaited(_load(index));
  }

  /// 用户选定的持久倍速（设置面板）。
  Future<void> setRate(double rate) async {
    _baseRate = rate;
    await _service.setRate(rate);
  }

  /// 长按临时倍速：按住期间加速，松手回到用户设定倍速。
  Future<void> beginTemporarySpeed(double speed) => _service.setRate(speed);

  Future<void> endTemporarySpeed() => _service.setRate(_baseRate);

  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    _state = _state.copyWith(volume: v);
    notifyListeners();
    await _service.setVolume(v);
  }

  /// 重新加载当前视频（错误页「重新播放」）。
  Future<void> retry() => _load(_index, initial: true);

  // ---------------------------------------------------------------------------
  // 生命周期：切后台一律暂停，避免偷跑流量 / 占用解码器
  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_service.pause());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _saveResume();
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _service.videoController.rect.removeListener(_onRectChanged);
    WidgetsBinding.instance.removeObserver(this);
    _position.dispose();
    if (!embedded) {
      unawaited(WakelockPlus.disable());
      unawaited(SystemUiService.restore());
    }
    unawaited(_service.dispose());
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 内部：状态订阅
  // ---------------------------------------------------------------------------

  void _bindStreams() {
    final stream = _service.stream;
    _subs.addAll([
      stream.playing.listen((_) => _refreshStatus()),
      stream.buffering.listen((_) => _refreshStatus()),
      stream.bufferingPercentage.listen((percentage) {
        if (_disposed || percentage == _state.bufferingPercentage) return;
        _state = _state.copyWith(bufferingPercentage: percentage);
        notifyListeners();
      }),
      stream.duration.listen((duration) {
        if (_disposed) return;
        _state = _state.copyWith(duration: duration);
        notifyListeners();
      }),
      stream.position.listen((position) {
        if (_disposed) return;
        _position.value = position;
      }),
      stream.rate.listen((rate) {
        if (_disposed) return;
        _state = _state.copyWith(rate: rate);
        notifyListeners();
      }),
      stream.volume.listen((volume) {
        if (_disposed) return;
        _state = _state.copyWith(volume: (volume / 100).clamp(0.0, 1.0));
        notifyListeners();
      }),
      stream.completed.listen(_onCompleted),
      stream.error.listen(_onError),
    ]);
    _service.videoController.rect.addListener(_onRectChanged);
  }

  void _onRectChanged() {
    if (_disposed) return;
    final ratio = _service.aspectRatio;
    if (ratio == null || ratio == _state.aspectRatio) return;
    _state = _state.copyWith(aspectRatio: ratio);
    notifyListeners();
  }

  void _refreshStatus() {
    if (_disposed) return;
    final status = _computeStatus();
    if (status == _state.status) return;
    _state = _state.copyWith(status: status);
    notifyListeners();
  }

  PlayerStatus _computeStatus() {
    if (_state.error != null) return PlayerStatus.error;
    if (_loading) return PlayerStatus.loading;
    if (_service.completed) return PlayerStatus.completed;
    if (_service.buffering && _service.playing) return PlayerStatus.buffering;
    return _service.playing ? PlayerStatus.playing : PlayerStatus.paused;
  }

  void _onError(String message) {
    if (_disposed) return;
    // 已经能正常播放时的告警（如个别分片解析失败）不打断观看
    if (_state.status == PlayerStatus.playing &&
        _service.duration > Duration.zero) {
      return;
    }
    _fail(message);
  }

  void _fail(String raw) {
    if (_disposed) return;
    final item = current;
    _loading = false;
    _state = _state.copyWith(
      status: PlayerStatus.error,
      error: describePlayerError(raw, isRemote: item != null && !item.isLocal),
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 内部：媒体切换
  // ---------------------------------------------------------------------------

  /// 换源统一入口：进页面、手动上一/下一个、自动连播都走这里。
  Future<void> _load(int index, {bool initial = false}) async {
    if (_playlist.isEmpty) return;
    final target = index.clamp(0, _playlist.length - 1);

    if (!initial) _saveResume();

    _index = target;
    _completedHandled = false;
    _loading = true;
    _position.value = Duration.zero;
    _state = _state.copyWith(
      status: PlayerStatus.loading,
      index: target,
      duration: Duration.zero,
      clearError: true,
    );
    notifyListeners();

    final item = _playlist[target];
    Duration? resume;
    if (rememberProgress) {
      resume = await VideoResumeStore.load(item.id);
    }
    if (_disposed) return;

    try {
      await _service.open(item, start: resume, httpHeaders: httpHeaders);
    } catch (error) {
      if (_disposed) return;
      _fail(error.toString());
      return;
    }
    if (_disposed) return;

    _loading = false;
    // open 完成后主动补一次快照：个别内核不会为初始值再 emit
    _state = _state.copyWith(
      duration: _service.duration,
      aspectRatio: _service.aspectRatio,
      volume: _service.volume,
    );
    _refreshStatus();
  }

  void _onCompleted(bool completed) {
    if (_disposed || !completed || _loading || _completedHandled) return;
    _completedHandled = true;
    _handleCompletion();
  }

  void _handleCompletion() {
    switch (playMode) {
      case VideoPlayMode.sequential:
        if (_index < _playlist.length - 1) {
          unawaited(_load(_index + 1));
        } else {
          // 最后一集：停在末尾，把决定权交还用户
          _state = _state.copyWith(status: PlayerStatus.completed);
          notifyListeners();
        }
      case VideoPlayMode.shuffle:
        if (_playlist.length > 1) {
          unawaited(_load(_randomIndex()));
        } else {
          unawaited(_replayCurrent());
        }
      case VideoPlayMode.loop:
        unawaited(_replayCurrent());
    }
  }

  Future<void> _replayCurrent() async {
    _completedHandled = false;
    await _service.seek(Duration.zero);
    await _service.play();
    _refreshStatus();
  }

  int _randomIndex() {
    if (_playlist.length < 2) return _index;
    var next = _index;
    while (next == _index) {
      next = Random().nextInt(_playlist.length);
    }
    return next;
  }

  /// 保存断点（临近结尾 5 秒内视为已看完，不保存）。
  void _saveResume() {
    if (!rememberProgress) return;
    final item = current;
    if (item == null) return;
    final pos = _service.position;
    final duration = _service.duration;
    if (pos > Duration.zero &&
        duration > Duration.zero &&
        pos < duration - const Duration(seconds: 5)) {
      unawaited(VideoResumeStore.save(item.id, pos));
    }
  }
}
