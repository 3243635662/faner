import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'controllers/video_controls_controller.dart';
import 'widgets/controls_overlay.dart';

/// 播放列表里的单条视频描述。
///
/// [url] 支持：
/// - `http://` / `https://`（局域网设备的 /api/file 流式地址）
/// - 本地绝对路径（本机文件，走 VideoPlayerController.file）
class VideoItem {
  const VideoItem({required this.url, required this.title});
  final String url;
  final String title;
}

/// 通用视频播放页。
///
/// 用法（示例）：
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => VideoPlayerPage(
///     playlist: videoList,       // List<VideoItem>
///     initialIndex: tappedIndex, // 用户点的是第几个
///   ),
/// ));
/// ```
///
/// 如果项目用 go_router，把 playlist / initialIndex 通过 extra 传进来即可，
/// 页面内部逻辑不需要改动。
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.playlist,
    this.initialIndex = 0,
  }) : assert(playlist.length > 0, 'playlist 不能为空');

  final List<VideoItem> playlist;
  final int initialIndex;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with WidgetsBindingObserver {
  late int _currentIndex;
  VideoPlayerController? _videoController;
  final VideoControlsController _controlsController =
      VideoControlsController();

  bool _isLoading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex =
        widget.initialIndex.clamp(0, widget.playlist.length - 1);
    _enterImmersiveMode();
    // 入口 1：手动进入播放页 —— 首次加载也要走统一的 _loadIndex，
    // 里面会调用 controlsController.onEnterPlayer() 强制隐藏控件。
    _loadIndex(_currentIndex);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exitImmersiveMode();
    _videoController?.removeListener(_onVideoValueChanged);
    _videoController?.dispose();
    _controlsController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 切到后台时暂停播放，避免占用资源 / 偷跑流量。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _videoController?.pause();
    }
  }

  void _enterImmersiveMode() {
    // 隐藏系统状态栏 / 导航栏，沉浸式播放。用户上滑会短暂唤出后自动收回。
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _loadIndex(int index) async {
    if (index < 0 || index >= widget.playlist.length) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _currentIndex = index;
    });

    // === 关键修复点 ===
    // 无论是首次进入、手动点上一个/下一个、还是播放完自动切下一个，
    // 都统一走这一行，把控件强制重置为隐藏状态。
    // 不要指望"默认值是隐藏"就够了 —— 只要有任何一条路径没走到这里，
    // 就会复现"切视频后状态栏意外显示"的 bug。
    _controlsController.onEnterPlayer();

    final oldController = _videoController;
    oldController?.removeListener(_onVideoValueChanged);

    final item = widget.playlist[index];
    final newController = _createController(item.url);

    try {
      await newController.initialize();
      if (!mounted) {
        await newController.dispose();
        return;
      }
      newController
        ..setLooping(false)
        ..addListener(_onVideoValueChanged)
        ..play();

      setState(() {
        _videoController = newController;
        _isLoading = false;
      });
    } catch (e) {
      await newController.dispose();
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    } finally {
      await oldController?.dispose();
    }
  }

  VideoPlayerController _createController(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return VideoPlayerController.networkUrl(Uri.parse(url));
    }
    return VideoPlayerController.file(File(url));
  }

  void _onVideoValueChanged() {
    final controller = _videoController;
    if (controller == null) return;
    final value = controller.value;

    if (value.hasError) {
      setState(() => _error = value.errorDescription);
      return;
    }

    final playbackEnded = value.isInitialized &&
        !value.isPlaying &&
        value.duration > Duration.zero &&
        value.position >= value.duration;

    if (playbackEnded) {
      // 入口 2：自动播放完毕，切换到下一个视频。
      _onAutoAdvance();
    }
  }

  void _onAutoAdvance() {
    if (_hasNext) {
      _loadIndex(_currentIndex + 1);
    }
    // 没有下一个视频了：停留在最后一帧，不重复触发。
  }

  bool get _hasPrevious => _currentIndex > 0;
  bool get _hasNext => _currentIndex < widget.playlist.length - 1;

  // 入口 3：用户手动点"上一个 / 下一个"按钮切换。
  void _onPrevious() {
    if (_hasPrevious) _loadIndex(_currentIndex - 1);
  }

  void _onNext() {
    if (_hasNext) _loadIndex(_currentIndex + 1);
  }

  void _onClose() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.playlist[_currentIndex];
    final controller = _videoController;
    final ready = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // opaque：即使点在视频区域的透明部分（比如上下黑边）也能触发 toggle。
        behavior: HitTestBehavior.opaque,
        onTap: _controlsController.toggle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: _buildVideoSurface(ready, controller)),
            if (ready)
              ControlsOverlay(
                controlsController: _controlsController,
                videoController: controller,
                title: item.title,
                hasPrevious: _hasPrevious,
                hasNext: _hasNext,
                onPrevious: _onPrevious,
                onNext: _onNext,
                onClose: _onClose,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSurface(bool ready, VideoPlayerController? controller) {
    if (_error != null) {
      return _ErrorView(
        error: _error!,
        onRetry: () => _loadIndex(_currentIndex),
      );
    }
    if (_isLoading || !ready || controller == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.white54, size: 48),
        const SizedBox(height: 12),
        Text(
          '播放失败：$error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}
