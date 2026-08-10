import 'dart:async';

import 'package:diandi_memory/core/async/serial_task_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('串行队列等待前一个任务完成，并在失败后继续执行后续任务', () async {
    final queue = SerialTaskQueue();
    final gate = Completer<void>();
    final events = <String>[];

    final first = queue.run(() async {
      events.add('first-start');
      await gate.future;
      events.add('first-end');
      return 1;
    });
    final second = queue.run(() async {
      events.add('second-start');
      return 2;
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, <String>['first-start']);

    gate.complete();
    expect(await first, 1);
    expect(await second, 2);
    expect(events, <String>['first-start', 'first-end', 'second-start']);

    final failed = queue.run<int>(() async {
      throw StateError('expected');
    });
    final afterFailure = queue.run(() async => 4);

    await expectLater(failed, throwsStateError);
    expect(await afterFailure, 4);
  });
}
