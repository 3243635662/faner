import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

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
  });

  final List<MediaSource> items;
  final int initialIndex;

  /// 内嵌模式（详情面板预览）：不显示返回按钮，也不接管系统状态栏。
  final bool embedded;

  @override
  ConsumerState<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends ConsumerState<VideoView>
    with WidgetsBindingObserver {
  static final Random _random = Random();

  VideoPlayerController? _controller;
  late int _index;
  String? _error;
  bool _ended = false;

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
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: _buildSurface(controller)),
          if (ready)
            ControlsOverlay(
              controlsController: _controls,
              videoController: controller,
              title: _current.title,
              hasMultiple: widget.items.length > 1,
              onPrevious: _previous,
              onNext: _next,
              onToggleFullscreen: _toggleFullscreen,
              onClose: widget.embedded ? null : () => context.pop(),
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
