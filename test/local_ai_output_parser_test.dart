import 'dart:convert';

import 'package:diandi_memory/features/memories/data/local_ai_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('轻量模型在合法 JSON 后多输出关闭符号时保留第一个完整对象', () {
    final normalized = normalizeLocalAiJsonOutput(
      '''
```json
{"summary":"商量了吃饭和看电影","events":[{"title":"吃饭","description":"讨论晚饭","message_ids":[10,12]},{"title":"看电影","description":"计划看电影","message_ids":[12,16]}]}]}
```
''',
    );

    final decoded = jsonDecode(normalized) as Map<String, dynamic>;
    expect(decoded['summary'], '商量了吃饭和看电影');
    expect(decoded['events'], hasLength(2));
  });

  test('轻量模型输出尾随逗号时修复为可解析 JSON', () {
    final normalized = normalizeLocalAiJsonOutput(
      '{"summary":"今天主要聊了晚饭","events":[],}',
    );

    final decoded = jsonDecode(normalized) as Map<String, dynamic>;
    expect(decoded['summary'], '今天主要聊了晚饭');
  });
}
