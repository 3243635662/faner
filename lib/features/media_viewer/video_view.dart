import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/tokens.dart';
import '../../core/video_resume.dart';
import 'media_source.dart';

/// 视频播放器：基于官方 video_player。
///
/// 功能：全屏切换（横屏沉浸）、contain 屏幕适配、点击显隐控制栏、
/// 断点续播、列表顺序连播、上一个/下一个。
class VideoView extends StatefulWidget {
  const VideoView({
    super.key,
    required this.items,
    required this.initialIndex,
    this.embedded = false,
  });

  final List<MediaSource> items;
  final int initialIndex;

  /// 内嵌模式（详情面板预览）：不显示返回按钮。
  final bool embedded;

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  /// 控制栏无操作自动隐藏延时。
  static const _hideDelay = Duration(seconds: 3);

  VideoPlayerController? _controller;
  late int _index;
  bool _error = false;
  bool _ended = false;
  bool _controlsVisible = true;

  /// 用户拖动进度条时的临时位置（null 表示未在拖动）。
  Duration? _dragPosition;
  Timer? _hideTimer;

  MediaSource get _current => widget.items[_index];

  bool get _hasMultiple => widget.items.length > 1;

  bool get _isPlaying => _controller?.value.isPlaying ?? false;

  bool get _isLandscape =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _load();
  }

  @override
  void dispose() {
    _saveResume();
    _hideTimer?.cancel();
    _controller?.removeListener(_onUpdate);
    _controller?.dispose();
    _restoreOrientation();
    super.dispose();
  }

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

  Future<void> _load() async {
    final old = _controller;
    _controller = null;
    _ended = false;
    _error = false;
    _dragPosition = null;
    if (mounted) setState(() {});

    // 确保旧播放器完全释放（先暂停再销毁，避免音频残留）
    if (old != null) {
      old.removeListener(_onUpdate);
      try {
        await old.pause();
      } catch (_) {
        // 播放器可能已异常，忽略
      }
      old.dispose();
    }

    final source = _current;
    final resume = await VideoResumeStore.load(source.heroTag);
    final controller = switch (source) {
      LocalMediaSource(:final path) => VideoPlayerController.file(File(path)),
      RemoteMediaSource(:final url) =>
        VideoPlayerController.networkUrl(Uri.parse(url)),
    };
    _controller = controller;
    controller.addListener(_onUpdate);
    try {
      await controller.initialize();
      if (resume != null &&
          resume > Duration.zero &&
          resume < controller.value.duration) {
        await controller.seekTo(resume);
      }
      await controller.play();
      _showControls();
    } catch (_) {
      if (mounted) setState(() => _error = true);
      return;
    }
    if (mounted) setState(() {});
  }

  /// 播放器状态回调：驱动 UI 重建 + 检测播放结束。
  void _onUpdate() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!_ended && controller.value.duration > Duration.zero) {
      if (controller.value.position >= controller.value.duration) {
        _ended = true;
        _onEnded();
        return;
      }
    }
    if (mounted) setState(() {});
  }

  void _onEnded() {
    // 顺序连播：还有下一个则切换，否则停在末尾并显示控制栏
    if (_index < widget.items.length - 1) {
      _goTo(_index + 1);
    } else {
      _showControls();
    }
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.items.length) return;
    _saveResume();
    setState(() => _index = index);
    _load();
  }

  void _next() => _goTo((_index + 1) % widget.items.length);

  void _previous() =>
      _goTo((_index - 1 + widget.items.length) % widget.items.length);

  // ---------------------------------------------------------------------------
  // 控制栏显隐
  // ---------------------------------------------------------------------------

  void _showControls() {
    _hideTimer?.cancel();
    if (mounted) setState(() => _controlsVisible = true);
    _hideTimer = Timer(_hideDelay, () {
      // 播放中才自动隐藏；暂停/结束时保持可见
      if (mounted && _isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  // ---------------------------------------------------------------------------
  // 播放控制
  // ---------------------------------------------------------------------------

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (_ended) {
        await controller.seekTo(Duration.zero);
        _ended = false;
      }
      await controller.play();
    }
    _showControls();
  }

  // ---------------------------------------------------------------------------
  // 全屏切换（横屏沉浸 / 竖屏恢复）
  // ---------------------------------------------------------------------------

  void _toggleFullscreen() {
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _showControls();
  }

  void _restoreOrientation() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error) {
      return Center(
        child: Text(
          '无法播放该视频',
          style: AppTypography.subtitle.copyWith(color: Colors.white70),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 视频画面：contain 适配（宽高比由视频决定，不裁切不变形）
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          _buildCenterButton(),
          _buildControlsOverlay(),
        ],
      ),
    );
  }

  /// 暂停时中央的大播放按钮。
  Widget _buildCenterButton() {
    if (_isPlaying || _ended) return const SizedBox.shrink();
    return Center(
      child: _CircleButton(
        icon: LucideIcons.play,
        size: AppSpacing.xxxl + AppSpacing.xxxl,
        onTap: _togglePlay,
      ),
    );
  }

  /// 控制层：顶部（返回 + 标题）与底部（进度条 + 操作按钮）。
  Widget _buildControlsOverlay() {
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1.0 : 0.0,
      duration: AppMotion.mid,
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: Column(
          children: [
            _buildTopBar(),
            const Spacer(),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      decoration: _gradientDecoration(),
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
        bottom: AppSpacing.xl,
        left: AppSpacing.sm,
        right: AppSpacing.lg,
      ),
      child: Row(
        children: [
          if (!widget.embedded)
            IconButton(
              icon: const Icon(LucideIcons.arrow_left, color: Colors.white),
              onPressed: () => context.pop(),
            ),
          Expanded(
            child: Text(
              _current.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.subtitle.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final controller = _controller!;
    final value = controller.value;
    final duration = value.duration;
    final position = _dragPosition ?? value.position;
    final sliderMax = duration.inMilliseconds.toDouble();

    return Container(
      decoration: _gradientDecoration(bottomUp: true),
      padding: EdgeInsets.only(
        top: AppSpacing.xl,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.sm,
        left: AppSpacing.lg,
        right: AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _fmt(position),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: AppSpacing.xs,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: AppSpacing.md,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: AppSpacing.lg,
                    ),
                  ),
                  child: Slider(
                    value: position.inMilliseconds
                        .toDouble()
                        .clamp(0, sliderMax),
                    max: sliderMax,
                    activeColor: AppPalette.of(context).brand,
                    inactiveColor: Colors.white38,
                    onChanged: sliderMax <= 0
                        ? null
                        : (v) => setState(() =>
                            _dragPosition = Duration(milliseconds: v.toInt())),
                    onChangeEnd: (v) {
                      controller.seekTo(Duration(milliseconds: v.toInt()));
                      setState(() => _dragPosition = null);
                      _showControls();
                    },
                  ),
                ),
              ),
              _fmt(duration),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? LucideIcons.pause : LucideIcons.play,
                  color: Colors.white,
                ),
                onPressed: _togglePlay,
              ),
              if (_hasMultiple) ...[
                IconButton(
                  icon: const Icon(LucideIcons.skip_back,
                      color: Colors.white),
                  onPressed: _previous,
                ),
                IconButton(
                  icon: const Icon(LucideIcons.skip_forward,
                      color: Colors.white),
                  onPressed: _next,
                ),
              ],
              const Spacer(),
              IconButton(
                icon: Icon(
                  _isLandscape
                      ? LucideIcons.minimize
                      : LucideIcons.maximize,
                  color: Colors.white,
                ),
                onPressed: _toggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 控制栏上下渐变遮罩（黑 → 透明）。
  BoxDecoration _gradientDecoration({bool bottomUp = false}) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin:
            bottomUp ? Alignment.bottomCenter : Alignment.topCenter,
        end: bottomUp ? Alignment.topCenter : Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.6),
          Colors.transparent,
        ],
      ),
    );
  }

  /// 时间文字。
  Widget _fmt(Duration d) {
    return Text(
      _formatDuration(d),
      style:
          AppTypography.caption.copyWith(color: Colors.white70),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }
}

/// 半透明圆形按钮（中央播放键）。
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.size = AppSpacing.xxxl,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size / 2),
      ),
    );
  }
}
