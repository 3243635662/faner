import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import '../models/media_item.dart';

/// 播放内核封装层。
///
/// 全项目只有本文件直接依赖 `media_kit` / `media_kit_video`：
/// UI → Controller → Service → media_kit，上层拿到的全是本项目自己的类型。
/// 将来更换播放内核（或同时支持多内核）只需重写这一个文件。
class MediaPlayerService {
  MediaPlayerService() {
    _player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        // 开启 128MB 内存缓冲区，挂载底层 mpv demuxer 预读缓存，抗弱网/Wi-Fi抖动
        bufferSize: 128 * 1024 * 1024,
        libass: false,
        logLevel: mk.MPVLogLevel.warn,
      ),
    );
    // 屏蔽不必要的 mpv 日志，阶段性效果局限于 PlayerConfiguration。
    videoController = mkv.VideoController(
      _player,
      // 默认即硬件加速，这里显式声明，避免以后被误改成软件解码。
      configuration: const mkv.VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
  }

  late final mk.Player _player;

  /// 交给 `Video` 组件渲染视频输出。
  late final mkv.VideoController videoController;

  mk.PlayerStream get stream => _player.stream;

  // ---------------------------------------------------------------------------
  // 状态读取（只暴露语义化数值，不把 media_kit 的类型泄漏给上层）
  // ---------------------------------------------------------------------------

  Duration get position => _player.state.position;
  Duration get duration => _player.state.duration;
  bool get playing => _player.state.playing;
  bool get buffering => _player.state.buffering;
  bool get completed => _player.state.completed;

  /// 音量 0.0 ~ 1.0。
  double get volume => (_player.state.volume / 100).clamp(0.0, 1.0);

  double get rate => _player.state.rate;

  /// 视频宽高比（来自渲染区域的真实矩形，已修正像素长宽比）。
  double? get aspectRatio {
    final rect = videoController.rect.value;
    if (rect == null || rect.height <= 0) return null;
    final ratio = rect.width / rect.height;
    return ratio > 0 ? ratio : null;
  }

  // ---------------------------------------------------------------------------
  // 控制
  // ---------------------------------------------------------------------------

  /// 打开媒体并（可选）从 [start] 续播。
  ///
  /// 先以 `play: false` 打开再 seek，最后才 play —— 避免"从头播放几百毫秒
  /// 再跳走"的闪跳，也保证 seek 落在真正加载完成之后。
  Future<void> open(
    MediaItem item, {
    Duration? start,
    bool play = true,
    Map<String, String>? httpHeaders,
  }) async {
    await _player.open(
      mk.Media(item.uri, httpHeaders: httpHeaders),
      play: false,
    );
    if (start != null && start > Duration.zero) {
      await _player.seek(start);
    }
    if (play) {
      await _player.play();
    }
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> togglePlay() => _player.playOrPause();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setRate(double rate) => _player.setRate(rate);

  /// [volume] 取值 0.0 ~ 1.0；media_kit 内部量程为 0 ~ 100。
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0) * 100);

  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}
