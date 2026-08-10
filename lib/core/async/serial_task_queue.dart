import 'dart:async';

/// 把必须串行执行的异步任务排队；单个任务失败不能阻断后续任务。
class SerialTaskQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() task) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;

    return () async {
      await previous;
      try {
        return await task();
      } finally {
        if (!release.isCompleted) release.complete();
      }
    }();
  }
}
