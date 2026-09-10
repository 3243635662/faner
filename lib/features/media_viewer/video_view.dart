import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/format.dart';
import '../../core/tokens.dart';
import '../../core/video_play_mode.dart';
import '../../core/video_resume.dart';
import '../../providers/settings_provider.dart';
import 'controllers/video_controls_controller.dart';
import 'media_source.dart';
import 'widgets/controls_overlay.dart';

/// 视频播放器：基于官方 video_player + 自定义控件层。
///
/// 交互规范（见 markdown/视频播放优化方案.md）：
/// - 控件显隐统一由 [VideoControlsController] 管理，任何"进入新视频"
///   的路径（进页面 / 自动连播 / 手动切换）都统一走 [_loadIndex] 并强制
///   重置控件为隐藏，杜绝切换后沿用上一个视频的显示状态；
/// - 点击视频区域 toggle 控件，显示后 3 秒无操作自动隐藏；
/// - 拖动进度条期间控件不会被自动隐藏计时器打断；
/// - 独立页面模式下系统状态栏与自定义控件同步显隐（抖音/B 站标准做法）；
/// - 支持横屏全屏切换、contain 屏幕适配、断点续播、列表顺序连播。
class VideoView extends ConsumerStatefulWidget {
  const VideoView({
    super.key,
    required this.items,
    required this.initialIndex,
    this.embedded = false,
    this.fullscreen = false,
    this.onToggleFullscreen,
  });

  final List<MediaSource> items;
  final int initialIndex;

  /// 内嵌模式（详情面板预览）：不显示返回按钮，也不接管系统状态栏。
  final bool embedded;

  /// 当前是否处于全屏状态（决定右下角按钮图标）。仅在 [onToggleFullscreen]
  /// 非空时生效。
  final bool fullscreen;

  /// 自定义全屏切换行为；为空时回退到横竖屏切换（独立页面的默认行为）。
  final VoidCallback? onToggleFullscreen;

  @override
  ConsumerState<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends ConsumerState<VideoView>
    with WidgetsBindingObserver {
  static final Random _random = Random();

  /// 左右拖动快进/后退的灵敏度：**每逻辑像素**对应的跳转时长（毫秒）。
  ///
  /// 用「像素速率」而非「整屏比例」，手感与屏幕朝向/尺寸无关：
  /// 1cm ≈ 63 逻辑像素，200ms/px → 轻扫 1cm ≈ 12.6 秒。
  /// 想更迟钝就调小（如 150 → 约 9.5 秒/cm），想更灵敏就调大。
  static const double _seekMsPerPx = 200;

  /// 滑满一屏的跳转跨度：短于「整屏速率跨度」的视频仍按全片比例映射，
  /// 保证短视频可以精确微调。
  static double _seekSpanMs(Duration duration, double width) {
    final rateMs = width * _seekMsPerPx;
    final durationMs = duration.inMilliseconds;
    return durationMs < rateMs ? durationMs.toDouble() : rateMs;
  }

  VideoPlayerController? _controller;
  late int _index;
  String? _error;
  bool _ended = false;

  // 左右拖动快进/后退的临时预览进度（null 表示未在拖动）
  Duration? _dragPreview;
  double _dragStartX = 0;
  Duration _dragStartPosition = Duration.zero;

  // 亮度/音量（垂直拖动调节，左半屏亮度 / 右半屏音量）
  double _brightness = 1.0;
  double _volume = 1.0;
  bool _adjustBrightness = false;
  bool _showBrightness = false;
  bool _showVolume = false;
  double _verticalStartY = 0;
  double _startBrightness = 1.0;
  double _startVolume = 1.0;

  late final VideoControlsController _controls;

  MediaSource get _current => widget.items[_index];

  bool get _isLandscape =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _controls = VideoControlsController();
    if (!widget.embedded) {
      // 独立页面进入即沉浸（系统栏隐藏），与控件初始隐藏状态一致
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    // 系统状态栏跟随自定义控件同步显隐
    _controls.addListener(_syncSystemUi);
    // 统一入口：首次加载也走 _loadIndex，内部会强制隐藏控件
    _loadIndex(_index);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveResume();
    _controls.removeListener(_syncSystemUi);
    _controls.dispose();
    _controller?.removeListener(_onVideoValueChanged);
    _controller?.dispose();
    _restoreChrome();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切后台暂停播放，避免偷跑流量 / 占用解码器
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller?.pause();
    }
  }

  // ---------------------------------------------------------------------------
  // 换源统一入口（核心：任何路径切换视频都走这里）
  // ---------------------------------------------------------------------------

  Future<void> _loadIndex(int index) async {
    if (index < 0 || index >= widget.items.length) return;

    _saveResume(); // 保存上一个视频的断点（此时 _index 仍是旧的）
    if (mounted) {
      setState(() {
        _index = index;
        _error = null;
      });
    }

    // 关键修复：所有"进入新视频"的路径都强制把控件重置为隐藏，
    // 不依赖上一个视频结束时的显示状态
    _controls.onEnterPlayer();

    final old = _controller;
    old?.removeListener(_onVideoValueChanged);

    final source = widget.items[index];
    final resume = await VideoResumeStore.load(source.heroTag);
    final controller = _createController(source);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      if (resume != null &&
          resume > Duration.zero &&
          resume < controller.value.duration) {
        await controller.seekTo(resume);
      }
      _ended = false;
      controller
        ..setLooping(false)
        ..setVolume(_volume)
        ..addListener(_onVideoValueChanged)
        ..play();
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _error = '无法播放该视频');
    } finally {
      // 释放旧播放器（先暂停再销毁，确保旧音频立即停止）
      if (old != null) {
        try {
          await old.pause();
        } catch (_) {
          // 旧播放器可能已异常，忽略
        }
        await old.dispose();
      }
    }
  }

  VideoPlayerController _createController(MediaSource source) {
    return switch (source) {
      LocalMediaSource(:final path) => VideoPlayerController.file(File(path)),
      RemoteMediaSource(:final url) =>
        VideoPlayerController.networkUrl(Uri.parse(url)),
    };
  }

  /// 播放器状态回调：错误上报 + 播放结束检测。
  void _onVideoValueChanged() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      if (mounted) setState(() => _error = value.errorDescription);
      return;
    }
    if (!_ended &&
        value.isInitialized &&
        !value.isPlaying &&
        value.duration > Duration.zero &&
        value.position >= value.duration) {
      _ended = true;
      _onEnded();
    }
  }

  void _onEnded() {
    // 自动连播模式来自设置页（顺序/随机/循环）
    switch (ref.read(settingsProvider).videoPlayMode) {
      case VideoPlayMode.sequential:
        // 顺序连播：自动切下一个（走统一入口，控件会被强制隐藏）
        if (_index < widget.items.length - 1) {
          _loadIndex(_index + 1);
        } else {
          // 最后一个视频：停在末尾并保持控件可见，方便重播/手动切换
          _controls.holdVisible();
        }
      case VideoPlayMode.shuffle:
        // 随机连播：列表只有一个视频时退化为循环重播
        if (widget.items.length > 1) {
          _loadIndex(_randomIndex());
        } else {
          _replayCurrent();
        }
      case VideoPlayMode.loop:
        // 循环：当前视频从头重播
        _replayCurrent();
    }
  }

  /// 随机挑选下一个索引（不与当前重复）。
  int _randomIndex() {
    var next = _index;
    while (next == _index) {
      next = _random.nextInt(widget.items.length);
    }
    return next;
  }

  /// 当前视频从头重播。
  Future<void> _replayCurrent() async {
    final controller = _controller;
    if (controller == null) return;
    _ended = false;
    await controller.seekTo(Duration.zero);
    await controller.play();
  }

  // 手动切换始终按明确方向循环，不跟随播放模式（随机模式下手动
  // "下一个"随机跳会让用户失去方向感）
  void _next() => _loadIndex((_index + 1) % widget.items.length);

  void _previous() =>
      _loadIndex((_index - 1 + widget.items.length) % widget.items.length);

  // ---------------------------------------------------------------------------
  // 播放/暂停（底部按钮与双击手势共用）
  // ---------------------------------------------------------------------------

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      // 播放结束时点播放 = 从头重播
      if (controller.value.duration > Duration.zero &&
          controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
        _ended = false;
      }
      await controller.play();
    }
  }

  // ---------------------------------------------------------------------------
  // 左右拖动快进/后退（轻扫调整进度）
  // ---------------------------------------------------------------------------

  void _onHorizontalDragStart(DragStartDetails details) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.duration <= Duration.zero) return;
    _dragStartX = details.localPosition.dx;
    _dragStartPosition = controller.value.position;
    _controls.holdVisible();
    setState(() => _dragPreview = _dragStartPosition);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) return;
    final dx = details.localPosition.dx - _dragStartX;
    // 固定像素速率（[_seekMsPerPx]），短视频退化为全片比例映射
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
    final preview = _dragPreview;
    if (preview == null) return;
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      controller.seekTo(preview);
      _ended = false;
    }
    setState(() => _dragPreview = null);
    _controls.releaseHold();
  }

  void _onHorizontalDragCancel() {
    if (_dragPreview == null) return;
    setState(() => _dragPreview = null);
    _controls.releaseHold();
  }

  // ---------------------------------------------------------------------------
  // 垂直拖动：左半屏亮度 / 右半屏音量
  // ---------------------------------------------------------------------------

  void _onVerticalDragStart(DragStartDetails details) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
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
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;
    // 上滑（dy 为负）增大，整屏高度 = 全量程 0~1
    final delta = -(details.localPosition.dy - _verticalStartY) / height;
    if (_adjustBrightness) {
      setState(() => _brightness = (_startBrightness + delta).clamp(0.0, 1.0));
    } else {
      setState(() => _volume = (_startVolume + delta).clamp(0.0, 1.0));
      controller.setVolume(_volume);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _showBrightness = false;
          _showVolume = false;
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // 断点续播
  // ---------------------------------------------------------------------------

  /// 保存当前播放位置（距离结尾 5 秒内视为已看完，不保存）。
  void _saveResume() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final position = controller.value.position;
    final duration = controller.value.duration;
    if (position > Duration.zero &&
        duration > Duration.zero &&
        position < duration - const Duration(seconds: 5)) {
      VideoResumeStore.save(_current.heroTag, position);
    }
  }

  // ---------------------------------------------------------------------------
  // 全屏切换与系统 UI
  // ---------------------------------------------------------------------------

  void _toggleFullscreen() {
    final custom = widget.onToggleFullscreen;
    if (custom != null) {
      // 双栏全屏：先保存断点并暂停内嵌播放器，避免与新全屏播放器双重出声；
      // 全屏页会读取断点续播，pop 回来后内嵌播放器停留在暂停态由用户继续。
      _saveResume();
      _controller?.pause();
      custom();
      return;
    }
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      if (widget.embedded) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      if (widget.embedded) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    }
  }

  /// 系统状态栏与自定义控件同步显隐（仅独立页面模式；
  /// 内嵌模式不接管系统 UI，避免影响宿主页面）。
  void _syncSystemUi() {
    if (widget.embedded) return;
    SystemChrome.setEnabledSystemUIMode(
      _controls.value ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void _restoreChrome() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return GestureDetector(
      // opaque：点在视频区域的透明部分（上下黑边）也能触发控件 toggle
      behavior: HitTestBehavior.opaque,
      onTap: _controls.toggle,
      // 双击：播放/暂停快捷切换（短暂显示控件作为反馈）
      onDoubleTap: () {
        _controls.holdVisible();
        _togglePlay();
        _controls.releaseHold();
      },
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onHorizontalDragCancel: _onHorizontalDragCancel,
      onVerticalDragStart: _onVerticalDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: _buildSurface(controller)),
          // 亮度遮罩：亮度 < 1 时叠加半透明黑层，模拟屏幕亮度
          if (_brightness < 1.0)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 1 - _brightness),
                ),
              ),
            ),
          if (ready)
            ControlsOverlay(
              controlsController: _controls,
              videoController: controller,
              title: _current.title,
              hasMultiple: widget.items.length > 1,
              fullscreen: widget.onToggleFullscreen != null
                  ? widget.fullscreen
                  : _isLandscape,
              onPrevious: _previous,
              onNext: _next,
              onTogglePlay: _togglePlay,
              onToggleFullscreen: _toggleFullscreen,
              onClose: widget.embedded ? null : () => context.pop(),
            ),
          if (_dragPreview != null && ready) _buildDragPreview(controller),
          if (_showBrightness)
            _buildAdjustIndicator(
              icon: LucideIcons.sun,
              value: _brightness,
              left: true,
            ),
          if (_showVolume)
            _buildAdjustIndicator(
              icon: LucideIcons.volume_2,
              value: _volume,
              left: false,
            ),
        ],
      ),
    );
  }

  Widget _buildSurface(VideoPlayerController? controller) {
    if (_error != null) {
      return _ErrorView(
        message: _error!,
        onRetry: () => _loadIndex(_index),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const CircularProgressIndicator();
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }

  /// 拖动时的进度预览提示（中央：方向箭头 + 目标时间 + 进度条）。
  Widget _buildDragPreview(VideoPlayerController controller) {
    final preview = _dragPreview!;
    final duration = controller.value.duration;
    final isForward = preview >= _dragStartPosition;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (preview.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isForward ? LucideIcons.arrow_right : LucideIcons.arrow_left,
                  color: Colors.white,
                  size: 22,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  formatDuration(preview),
                  style: AppTypography.title.copyWith(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: 128,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: AppSpacing.xs,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              formatDuration(duration),
              style: AppTypography.caption.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  /// 亮度/音量调节指示条（垂直进度胶囊，位于屏幕左/右侧）。
  Widget _buildAdjustIndicator({
    required IconData icon,
    required double value,
    required bool left,
  }) {
    return Positioned(
      left: left ? AppSpacing.lg : null,
      right: left ? null : AppSpacing.lg,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: AppSpacing.xs,
                height: AppSpacing.xxl * 3,
                alignment: Alignment.bottomCenter,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: FractionallySizedBox(
                  heightFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 播放失败视图：错误信息 + 重试。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          LucideIcons.circle_alert,
          color: Colors.white54,
          size: AppSpacing.xxxl + AppSpacing.sm,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.subtitle.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}
