import 'package:diandi_memory/features/memories/data/hierarchical_summary_service.dart';
import 'package:diandi_memory/features/memories/model/ai_summary_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('聊天时间间隔超过阈值时切成不同 AI 片段', () {
    const messages = <AiTextMessage>[
      AiTextMessage(
        id: 1,
        isSender: true,
        createTime: 1000,
        content: '我们中午去吃火锅吧',
      ),
      AiTextMessage(
        id: 2,
        isSender: false,
        createTime: 1100,
        content: '好呀，我下班去找你',
      ),
      AiTextMessage(
        id: 3,
        isSender: true,
        createTime: 5000,
        content: '我已经到家了',
      ),
    ];

    final chunks = buildConversationChunks(
      messages,
      gap: const Duration(minutes: 45),
    );

    expect(chunks, hasLength(2));
    expect(chunks.first.map((message) => message.id), <int>[1, 2]);
    expect(chunks.last.single.id, 3);
  });

  test('周月年周期存在逐级子周期', () {
    expect(SummaryPeriod.week.child, SummaryPeriod.day);
    expect(SummaryPeriod.month.child, SummaryPeriod.week);
    expect(SummaryPeriod.year.child, SummaryPeriod.month);
    expect(SummaryPeriod.day.child, isNull);
  });
}
