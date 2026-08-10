import 'package:diandi_memory/features/memories/data/hierarchical_summary_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析轻量模型的总结与事件行，不依赖严格 JSON', () {
    final result = parseChunkSummaryOutput(
      '''
总结：两个人商量了吃饭和看电影。
事件：吃饭｜讨论晚饭安排｜10,12
事件：看电影｜计划一起去看电影｜12,16
''',
      allowedMessageIds: const <int>{10, 12, 16},
    );

    expect(result.summaryText, '两个人商量了吃饭和看电影。');
    expect(result.events, hasLength(2));
    expect(result.events.first.title, '吃饭');
    expect(result.events.first.messageIds, <int>[10, 12]);
  });

  test('事件格式有噪声时保留可用总结并过滤非法消息 id', () {
    final result = parseChunkSummaryOutput(
      '''
```text
总结: 今天主要聊了晚饭。
- 事件: 晚饭 | 商量吃什么 | 1, 999, 2
这是一行模型额外解释
```
''',
      allowedMessageIds: const <int>{1, 2},
    );

    expect(result.summaryText, '今天主要聊了晚饭。');
    expect(result.events, hasLength(1));
    expect(result.events.single.messageIds, <int>[1, 2]);
  });
}
