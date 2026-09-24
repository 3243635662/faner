import 'package:media_kit/media_kit.dart';

/// 本地媒体元数据（时长）获取，用于文件列表角标。
///
/// 仅对本地视频生效（远程文件无本地路径，且服务端未返回元数据）。
/// 带内存缓存 + 失败静默降级（返回 null，UI 隐藏角标）。
final Map<String, Duration> _videoDurationCache = {};

/// 探测任务串行队列。
///
/// media_kit 的 `Player` 会创建原生解码实例，成本不低；列表快速滚动时
/// 若并发拉起多个实例会明显抢占资源，因此这里把探测串行化。
Future<void> _probeQueue = Future<void>.value();

/// 获取本地视频时长；失败返回 null。
Future<Duration?> fetchVideoDuration(String path) {
  final cached = _videoDurationCache[path];
  if (cached != null) return Future.value(cached);
  final task = _probeQueue.then((_) => _probe(path));
  // 使用onError吞掉本次任务的异常，避免阻断队列任务
  _probeQueue = task.then<void>((_) {}, onError: (_) {});
  return task;
}

// 获取视频时长
Future<Duration?> _probe(String path) async {
  final cached = _videoDurationCache[path];
  if (cached != null) return cached;

  final player = Player();
  try {
    await player.open(Media(path), play: false);
    var duration = player.state.duration;
    if (duration <= Duration.zero) {
      // 少数容器在 open 返回后稍晚才给出时长：当视频时长尚未就绪时，异步等待内核报出真实时长
      // firstWhere从流里取第一个大于零的值 —— 也就是真正解析出有效时长的那一刻
      // timeout最多等 3 秒。若超时仍未拿到有效时长，就返回一个 Duration.zero 作为"放弃探测"的哨兵值，避免无限挂起阻塞串行队列。
      duration = await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 3), onTimeout: () => Duration.zero);
    }
    if (duration > Duration.zero) {
      _videoDurationCache[path] = duration;
      return duration;
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    await player.dispose();
  }
}
