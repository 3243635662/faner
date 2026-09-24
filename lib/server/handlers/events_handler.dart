import 'dart:async';
import 'dart:io';

import '../../core/change_bus.dart';
import '../../core/path_utils.dart';
import '../server_context.dart';

/// 单条 SSE 连接的心跳间隔（防止中间设备把空闲连接判死）。
const Duration _pingInterval = Duration(seconds: 15);

/// 两次事件之间的最小间隔，用于合并短时间内的批量变更。
const Duration _eventCoalesce = Duration(milliseconds: 200);

/// 心跳写入超时：超过即认为对端已失联，主动关闭连接。
const Duration _pingTimeout = Duration(seconds: 10);

/// GET /api/events?path=xxx
///
/// Server-Sent Events 长连接，推送「该目录内容已变化」：
/// - 本机 App 内的增删改经 [ChangeBus] 即时广播；
/// - 外部写入（其他 App 落盘）尽力通过 `Directory.watch` 感知
///   （部分 Android 外部存储不派发 inotify 事件，属于尽力而为）。
///
/// 远端浏览页据此立即刷新，替代「定时轮询猜测」。
Future<void> handleEvents(HttpRequest request, ServerContext ctx) async {
  final path = request.uri.queryParameters['path'] ?? '';
  if (normalizeRelPath(path) == null) return forbidden(request);
  final guard = PathGuard(ctx.root);
  final abs = guard.resolve(path);
  if (abs == null) return forbidden(request);
  if (FileSystemEntity.typeSync(abs, followLinks: false) !=
      FileSystemEntityType.directory) {
    return notFound(request);
  }

  final res = request.response;
  res.statusCode = HttpStatus.ok;
  res.headers.contentType =
      ContentType('text', 'event-stream', charset: 'utf-8');
  res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  res.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
  // 关闭输出缓冲，事件即刻送达客户端。
  res.bufferOutput = false;

  res.write(': connected\n\n');
  await res.flush();

  StreamSubscription<String>? busSub;
  StreamSubscription<FileSystemEvent>? watcherSub;
  Timer? ping;
  var lastSent = DateTime.now();

  void send() {
    final now = DateTime.now();
    if (now.difference(lastSent) < _eventCoalesce) return;
    lastSent = now;
    ctx.activity?.touch();
    try {
      res.write('event: change\ndata: {}\n\n');
      res.flush();
    } catch (_) {
      // 客户端已断开，等待 res.done 收尾
    }
  }

  try {
    busSub = ChangeBus.instance.changes.listen((changed) {
      if (_related(path, changed)) send();
    });

    watcherSub = Directory(abs)
        .watch(events: FileSystemEvent.all)
        .listen((_) => send(), onError: (Object _) {});

    ping = Timer.periodic(_pingInterval, (_) {
      // 有人挂着事件连接说明客户端仍在活跃使用，保持"非空闲"以免降频误判
      ctx.activity?.touch();
      try {
        res.write(': ping\n\n');
        // 对端断网但未发 FIN 时 flush 会一直挂起，加超时后主动收尾，
        // 否则这条连接（及其监听）会永久滞留。
        unawaited(
          res
              .flush()
              .timeout(_pingTimeout)
              .catchError((Object _) => res.close().ignore()),
        );
      } catch (_) {
        res.close().ignore();
      }
    });

    // res.done 在客户端断开时完成
    await res.done;
  } catch (_) {
    // 连接中断属正常收尾
  } finally {
    await busSub?.cancel();
    await watcherSub?.cancel();
    ping?.cancel();
    try {
      await res.close();
    } catch (_) {
      // 已关闭
    }
  }
}

/// [watched] 与 [changed] 是否相关（同级、子级或父级变化都算）。
bool _related(String watched, String changed) {
  if (watched == changed) return true;
  // 任一方为共享根：根的变化影响整棵树，全量放行。
  if (watched.isEmpty || changed.isEmpty) return true;
  if (watched.startsWith('$changed/')) return true; // 父级被改动
  if (changed.startsWith('$watched/')) return true; // 子级被改动
  return false;
}
