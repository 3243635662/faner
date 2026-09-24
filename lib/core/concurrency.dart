import 'dart:async';
import 'dart:collection';

/// 极简异步信号量：限制同时执行的任务数。
///
/// 典型用途：缩略图生成。网格翻页时若无节制地并发解码，会把 CPU 与内存
/// 瞬间打满，反而拖慢整体响应。用信号量把并发压到可控范围。
class Semaphore {
  Semaphore(this._permits) : assert(_permits > 0);

  int _permits;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  /// 占用一个许可执行 [task]，结束后自动释放。
  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_permits > 0) {
      _permits--;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // 直接把许可移交给队首等待者，保持总数不变。
      _waiters.removeFirst().complete();
      return;
    }
    _permits++;
  }
}
