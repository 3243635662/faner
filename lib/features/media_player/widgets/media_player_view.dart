import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/seek_sensitivity.dart';
import '../../../core/tokens.dart';
import '../../../providers/settings_provider.dart';
import '../controllers/media_player_controller.dart';
import '../controllers/player_controls_controller.dart';
import '../models/player_state.dart';
import '../services/system_ui_service.dart';
import 'player_controls_overlay.dart';
import 'player_indicators.dart';
import 'player_status_views.dart';
import 'video_surface.dart';

/// 播放器主视图：把"画面 + 手势 + 控件"组装起来。
///
/// 播放会话（[MediaPlayerController]）由宿主页面创建并注入，
/// 这样宿主既能用同一个控制器搭建播放列表面板，也能把它嵌进详情面板预览。
///
/// 手势规格（方案「手势设计」）：
/// - 单击：显示 / 隐藏控件
/// - 双击左侧 35%：后退 10 秒
/// - 双击中央 30%：播放 / 暂停交替
/// - 双击右侧 35%：前进 10 秒
/// - 长按：临时倍速（倍率来自设置）
/// - 左右拖动：快进 / 后退（需超过 [_seekActivateThreshold] 才激活，避免与双击打架）
/// - 左半屏上下拖动：亮度；右半屏上下拖动：音量
class MediaPlayerView extends ConsumerStatefulWidget {
  const MediaPlayerView({
    super.key,
    required this.controller,
    required this.controls,
    this.fullscreen = false,
    this.onToggleFullscreen,
    this.onClose,
  });

  final MediaPlayerController controller;
  final PlayerControlsController controls;

  /// 当前是否处于全屏显示模式（决定右下角按钮图标）。
  final bool fullscreen;

  /// 覆盖默认全屏行为（双栏返回 / 内嵌进全屏页）。
  final VoidCallback? onToggleFullscreen;

  /// 返回按钮回调；null 时不显示（内嵌预览）。
  final VoidCallback? onClose;

  @override
  ConsumerState<MediaPlayerView> createState() => _MediaPlayerViewState();
}

class _MediaPlayerViewState extends ConsumerState<MediaPlayerView> {
  /// 双击分区边界：中央 [0.35, 0.65] 为播放 / 暂停区，两侧为 ±10 秒区。
  static const double _centerStartRatio = 0.35;
  static const double _centerEndRatio = 0.65;

  /// 水平拖动激活阈值（逻辑像素）。
  ///
  /// 位移小于该值一律视为手抖：双击的第二下常带轻微位移，
  /// 若"一动就进入快进模式"，双击播放/暂停会误触发 seek。
  static const double _seekActivateThreshold = 18;

  /// 左右滑动灵敏度（每逻辑像素跳转的毫秒数），来自设置页。
  double _msPerPx = SeekSensitivity.standard.msPerPx;

  // 拖动 seek 的临时状态
  Duration? _dragPreview;
  double _dragStartX = 0;
  Duration _dragStartPosition = Duration.zero;
  bool _seekActive = false;

  // 亮度 / 音量（垂直拖动）
  double _brightness = 1.0;
  double _volume = 1.0;
  bool _adjustBrightness = false;
  bool _showBrightness = false;
  bool _showVolume = false;
  double _verticalStartY = 0;
  double _startBrightness = 1.0;
  double _startVolume = 1.0;

  // 双击提示 / 长按倍速提示
  Offset? _doubleTapPosition;
  PlayerDoubleTapHint? _doubleTapHint;
  Timer? _doubleTapTimer;
  double? _speeding;

  // 屏幕锁定状态
  bool _isLocked = false;
  bool _showLockedControl = false;
  Timer? _lockedControlTimer;

  int _lastIndex = -1;

  MediaPlayerController get _player => widget.controller;

  @override
  void initState() {
    super.initState();
    // 记录当前下标：只有"换到另一个视频"才需要重置控件，
    // 避免首帧状态回调把预览模式刻意显示的控件又藏起来。
    _lastIndex = _player.state.index;
    _player.addListener(_onControllerChanged);
    // 系统状态栏与自定义控件同步显隐（内嵌预览不接管宿主页面的系统 UI）
    widget.controls.addListener(_syncSystemUi);
  }

  @override
  void dispose() {
    _doubleTapTimer?.cancel();
    _lockedControlTimer?.cancel();
    _player.removeListener(_onControllerChanged);
    widget.controls.removeListener(_syncSystemUi);
    super.dispose();
  }

  void _syncSystemUi() {
    // 内嵌预览不接管宿主页面的系统 UI
    if (widget.controller.embedded) return;
    unawaited(SystemUiService.setImmersive(!widget.controls.value));
  }

  void _onControllerChanged() {
    final state = _player.state;
    // 任何"进入新视频"的路径都重置控件为隐藏，避免沿用上一集的显示状态
    if (state.index != _lastIndex) {
      _lastIndex = state.index;
      _isLocked = false;
      _showLockedControl = false;
      _lockedControlTimer?.cancel();
      widget.controls.onEnterPlayer();
    }
    // 播完停在结尾时，把控件交还给用户
    if (state.status == PlayerStatus.completed) {
      widget.controls.holdVisible();
    }
  }

  // ---------------------------------------------------------------------------
  // 手势
  // ---------------------------------------------------------------------------

  bool _initialized() => _player.state.duration > Duration.zero;

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  /// 双击：左侧后退 10 秒 / 中央播放暂停 / 右侧前进 10 秒。
  void _onDoubleTap() {
    if (!_initialized()) return;
    final width = context.size?.width ?? MediaQuery.sizeOf(context).width;
    if (width <= 0) return;
    final ratio =
        ((_doubleTapPosition?.dx ?? width / 2) / width).clamp(0.0, 1.0);
    HapticFeedback.lightImpact();

    if (ratio < _centerStartRatio) {
      _showDoubleTapHint(PlayerDoubleTapHint.rewind);
      unawaited(_player.seekBy(const Duration(seconds: -10)));
    } else if (ratio > _centerEndRatio) {
      _showDoubleTapHint(PlayerDoubleTapHint.forward);
      unawaited(_player.seekBy(const Duration(seconds: 10)));
    } else {
      // 中央：播放 / 暂停交替，直接切换，不在中央显示提示文字以免影响观感。
      unawaited(_player.togglePlay());
    }
  }

  void _showDoubleTapHint(PlayerDoubleTapHint hint) {
    setState(() => _doubleTapHint = hint);
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _doubleTapHint = null);
    });
  }

  void _startSpeed() {
    final speed = ref.read(settingsProvider).longPressSpeed;
    if (speed <= 1.0 || !_initialized()) return;
    unawaited(_player.beginTemporarySpeed(speed));
    HapticFeedback.lightImpact();
    setState(() => _speeding = speed);
  }

  void _endSpeed() {
    if (_speeding == null) return;
    unawaited(_player.endTemporarySpeed());
    setState(() => _speeding = null);
  }

  /// 手指按下即记录基准点。
  ///
  /// 不能等到 [DragStartDetails]：拖动识别器要等位移超过系统 slop 才回调
  /// start，那时指针已经移动了十几个像素，用它当基准会让进度"凭空跳一下"。
  void _onHorizontalDragDown(DragDownDetails details) {
    // 不做初始化判断：起手就要记住手指位置，否则加载完成瞬间起拖会算错基准
    _dragStartX = details.localPosition.dx;
    _dragStartPosition = _player.position.value;
    _seekActive = false;
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    // 起点已在 down 阶段记录；这里只标记"尚未激活快进模式"，
    // 等位移真正超过阈值再激活，避免与双击手势互相干扰。
    if (!_initialized()) return;
    _seekActive = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_initialized()) return;
    final duration = _player.state.duration;
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) return;
    final dx = details.localPosition.dx - _dragStartX;

    if (!_seekActive) {
      // 位移不足视为手抖（双击时最常见），直接忽略
      if (dx.abs() < _seekActivateThreshold) return;
      _seekActive = true;
      widget.controls.holdVisible();
      setState(() => _dragPreview = _dragStartPosition);
    }

    // 固定像素速率（灵敏度来自设置）：手感与屏幕尺寸无关；
    // 短视频退化为全片比例映射，保证仍能精确微调
    final spanMs = _seekSpanMs(duration, width);
    final deltaMs = (dx / width) * spanMs;
    final targetMs = (_dragStartPosition.inMilliseconds + deltaMs).round();
    setState(() {
      _dragPreview = Duration(
        milliseconds: targetMs.clamp(0, duration.inMilliseconds),
      );
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_seekActive) {
      _resetSeekDrag();
      return;
    }
    final preview = _dragPreview;
    _seekActive = false;
    if (preview == null) return;
    unawaited(_player.seek(preview));
    setState(() => _dragPreview = null);
    widget.controls.releaseHold();
  }

  void _onHorizontalDragCancel() {
    if (!_seekActive) return;
    _resetSeekDrag();
  }

  void _resetSeekDrag() {
    _seekActive = false;
    if (_dragPreview == null) return;
    setState(() => _dragPreview = null);
    widget.controls.releaseHold();
  }

  double _seekSpanMs(Duration duration, double width) {
    final rateMs = width * _msPerPx;
    final durationMs = duration.inMilliseconds;
    return durationMs < rateMs ? durationMs.toDouble() : rateMs;
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (!_initialized()) return;
    final width = MediaQuery.sizeOf(context).width;
    _adjustBrightness = details.localPosition.dx < width / 2;
    _verticalStartY = details.localPosition.dy;
    _startBrightness = _brightness;
    _startVolume = _volume;
    setState(() {
      _showBrightness = _adjustBrightness;
      _showVolume = !_adjustBrightness;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_initialized()) return;
    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;
    // 上滑（dy 为负）增大，整屏高度 = 全量程
    final delta = -(details.localPosition.dy - _verticalStartY) / height;
    if (_adjustBrightness) {
      setState(() => _brightness = (_startBrightness + delta).clamp(0.0, 1.0));
    } else {
      setState(() => _volume = (_startVolume + delta).clamp(0.0, 1.0));
      unawaited(_player.setVolume(_volume));
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _showBrightness = false;
        _showVolume = false;
      });
    });
  }

  void _toggleLock() {
    HapticFeedback.mediumImpact();
    if (_isLocked) {
      setState(() {
        _isLocked = false;
        _showLockedControl = false;
      });
      _lockedControlTimer?.cancel();
      widget.controls.showTemporarily();
    } else {
      _endSpeed();
      setState(() {
        _isLocked = true;
        _showLockedControl = true;
      });
      widget.controls.onEnterPlayer();
      _lockedControlTimer?.cancel();
      _lockedControlTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showLockedControl = false);
      });
    }
  }

  void _onTapScreen() {
    if (_isLocked) {
      _lockedControlTimer?.cancel();
      setState(() {
        _showLockedControl = !_showLockedControl;
      });
      if (_showLockedControl) {
        _lockedControlTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showLockedControl = false);
        });
      }
    } else {
      widget.controls.toggle();
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 灵敏度可在设置页随时调整，保持在手势使用前同步
    _msPerPx = ref
        .watch(settingsProvider.select((s) => s.seekSensitivity))
        .msPerPx;
    return PopScope(
      canPop: !_isLocked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isLocked) {
          setState(() => _showLockedControl = true);
          _lockedControlTimer?.cancel();
          _lockedControlTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _showLockedControl = false);
          });
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('屏幕已锁定，点击左侧锁图标解锁'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      child: ListenableBuilder(
        listenable: _player,
        builder: (context, _) {
          final state = _player.state;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTapScreen,
            onDoubleTapDown: _isLocked ? null : _onDoubleTapDown,
            onDoubleTap: _isLocked ? null : _onDoubleTap,
            onLongPressStart: _isLocked ? null : (_) => _startSpeed(),
            onLongPressEnd: _isLocked ? null : (_) => _endSpeed(),
            onLongPressCancel: _isLocked ? null : _endSpeed,
            onHorizontalDragDown: _isLocked ? null : _onHorizontalDragDown,
            onHorizontalDragStart: _isLocked ? null : _onHorizontalDragStart,
            onHorizontalDragUpdate: _isLocked ? null : _onHorizontalDragUpdate,
            onHorizontalDragEnd: _isLocked ? null : _onHorizontalDragEnd,
            onHorizontalDragCancel: _isLocked ? null : _onHorizontalDragCancel,
            onVerticalDragStart: _isLocked ? null : _onVerticalDragStart,
            onVerticalDragUpdate: _isLocked ? null : _onVerticalDragUpdate,
            onVerticalDragEnd: _isLocked ? null : _onVerticalDragEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: Center(child: _buildSurface(state)),
                ),
                // 亮度遮罩（无系统亮度权限，用半透明黑层模拟）
                if (_brightness < 1.0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 1 - _brightness),
                      ),
                    ),
                  ),
                if (!_isLocked)
                  PlayerControlsOverlay(
                    controller: _player,
                    controls: widget.controls,
                    title: _player.current?.title ?? '',
                    onClose: widget.onClose,
                    fullscreen: widget.fullscreen,
                    onToggleFullscreen: widget.onToggleFullscreen,
                  ),
                if (!_isLocked && _dragPreview != null && state.isReady)
                  PlayerIndicators.seekPreview(
                    preview: _dragPreview!,
                    duration: state.duration,
                    anchor: _dragStartPosition,
                  ),
                if (!_isLocked && _showBrightness)
                  PlayerIndicators.adjustBar(
                    icon: LucideIcons.sun,
                    value: _brightness,
                    left: true,
                    label: '${(_brightness * 100).round()}%',
                  ),
                if (!_isLocked && _showVolume)
                  PlayerIndicators.adjustBar(
                    icon: LucideIcons.volume_2,
                    value: _volume,
                    left: false,
                    label: '${(_volume * 100).round()}%',
                  ),
                if (!_isLocked && _doubleTapHint != null)
                  PlayerIndicators.doubleTapHint(_doubleTapHint!),
                if (!_isLocked && _speeding != null)
                  PlayerIndicators.speedBadge(_speeding!),
                _buildLockButton(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLockButton(BuildContext context) {
    if (_isLocked) {
      return Positioned(
        left: MediaQuery.paddingOf(context).left + AppSpacing.xl,
        top: 0,
        bottom: 0,
        child: Center(
          child: IgnorePointer(
            ignoring: !_showLockedControl,
            child: AnimatedOpacity(
              opacity: _showLockedControl ? 1.0 : 0.0,
              duration: AppMotion.mid,
              child: _PlayerLockButton(
                isLocked: true,
                onTap: _toggleLock,
              ),
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: widget.controls,
      builder: (context, visible, _) {
        return Positioned(
          left: MediaQuery.paddingOf(context).left + AppSpacing.xl,
          top: 0,
          bottom: 0,
          child: Center(
            child: IgnorePointer(
              ignoring: !visible,
              child: AnimatedOpacity(
                opacity: visible ? 1.0 : 0.0,
                duration: AppMotion.mid,
                child: _PlayerLockButton(
                  isLocked: false,
                  onTap: _toggleLock,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSurface(PlayerState state) {
    if (state.status == PlayerStatus.error) {
      return PlayerErrorView(
        message: state.error ?? '视频无法播放',
        onRetry: () => _player.retry(),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            // 宽高比未知时按 16:9 占位，拿到真实值后自动修正
            aspectRatio: state.aspectRatio ?? 16 / 9,
            child: VideoSurface(controller: _player.videoOutput),
          ),
        ),
        // 首次加载：此时还没有任何画面，居中提示最直观
        if (state.status == PlayerStatus.loading)
          const Center(child: PlayerLoadingView(label: '正在加载视频')),
        // 播放中缓冲：画面已定格，提示下移并收成胶囊，避免遮住画面中央
        if (state.status == PlayerStatus.buffering)
          Align(
            alignment: const Alignment(0.0, 0.62),
            child: PlayerLoadingView(
              label: state.bufferingRatio > 0
                  ? '正在缓冲 ${(state.bufferingRatio * 100).round()}%'
                  : '正在缓冲',
              progress:
                  state.bufferingRatio > 0 ? state.bufferingRatio : null,
              compact: true,
            ),
          ),
      ],
    );
  }
}

class _PlayerLockButton extends StatelessWidget {
  const _PlayerLockButton({
    required this.isLocked,
    required this.onTap,
  });

  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isLocked ? Colors.black87 : Colors.black45,
            shape: BoxShape.circle,
            border: Border.all(
              color: isLocked ? const Color(0xFFF59E0B) : Colors.white30,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isLocked
                    ? const Color(0x66F59E0B)
                    : Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            isLocked ? LucideIcons.lock : LucideIcons.lock_open,
            color: isLocked ? const Color(0xFFF59E0B) : Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

