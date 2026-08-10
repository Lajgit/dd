import 'package:diandi_memory/features/memories/data/daily_activity_summarizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const summarizer = DailyActivitySummarizer();

  test('优先从真实聊天片段提取当天活动', () {
    final result = summarizer.summarize(
      activityCandidates: const <String>[
        '哈哈哈哈',
        '中午去吃火锅了',
        '晚上回家一起看电影',
        '你吃了吗？',
      ],
      fallbackCandidates: const <String>['今天聊天好多'],
    );

    expect(result, contains('中午去吃火锅了'));
    expect(result, contains('晚上回家一起看电影'));
    expect(result, startsWith('从聊天里能看到'));
  });

  test('没有活动片段时回退到有代表性的真实聊天', () {
    final result = summarizer.summarize(
      activityCandidates: const <String>[],
      fallbackCandidates: const <String>['今天心情很好', '早点休息'],
    );

    expect(result, contains('今天心情很好'));
  });
}
