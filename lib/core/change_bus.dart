import 'dart:async';

/// 共享目录变更总线。
///
/// 本机对共享目录做增删改（本地浏览页的新建/重命名/删除）时向外广播
/// 「发生变化的目录相对路径」，服务端 `/api/events`（SSE）据此推送给
/// 正在浏览该目录的远端设备，让对方立即刷新，而不是靠定时轮询猜测。
class ChangeBus {
  ChangeBus._();

  /// 进程内单例（服务端与本地文件服务共用）。
  static final ChangeBus instance = ChangeBus._();

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  /// 变更目录（相对共享根）的广播流。
  Stream<String> get changes => _controller.stream;

  /// 通知 [dirRelPath] 目录内容已变化。空字符串代表共享根目录。
  void notifyDir(String dirRelPath) {
    if (!_controller.isClosed) _controller.add(dirRelPath);
  }
}
