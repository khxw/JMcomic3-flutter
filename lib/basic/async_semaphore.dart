import 'dart:async';
import 'dart:collection';

/// Limits the number of asynchronous operations running at the same time.
class AsyncSemaphore {
  AsyncSemaphore(int maxConcurrent)
      : assert(maxConcurrent > 0),
        _maxConcurrent = maxConcurrent;

  final int _maxConcurrent;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  int _active = 0;

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < _maxConcurrent) {
      _active++;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    _active--;
  }
}
