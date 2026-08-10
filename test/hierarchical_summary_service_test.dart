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

  test('周月年使用不会跨周期边界的下一级总结', () {
    expect(SummaryPeriod.week.child, SummaryPeriod.day);
    expect(SummaryPeriod.month.child, SummaryPeriod.day);
    expect(SummaryPeriod.year.child, SummaryPeriod.month);
    expect(SummaryPeriod.day.child, isNull);
  });

  test('轻量模型输出上限保持在移动端快速总结预算内', () {
    expect(localAiChunkMaxTokens, lessThanOrEqualTo(300));
    expect(localAiDayMaxTokens, lessThanOrEqualTo(240));
    expect(localAiAggregateMaxTokens, lessThanOrEqualTo(360));
    expect(localAiYearMaxTokens, lessThanOrEqualTo(520));
  });

  test('日总结拒绝把提示词问题句当成真实总结', () {
    expect(
      parseSingleSummaryOutput('总结：今天做了什么，商量了什么，有什么值得记住的互动。'),
      isEmpty,
    );
  });

  test('片段总结拒绝模板占位词但保留真实事件', () {
    final result = parseChunkSummaryOutput(
      '''
总结：这一段发生了什么，1-3句
事件：短标题｜发生了什么｜10,12
事件：看电影｜两个人约好晚上去看电影｜12,16
''',
      allowedMessageIds: const <int>{10, 12, 16},
    );

    expect(result.summaryText, '两个人约好晚上去看电影');
    expect(result.events, hasLength(1));
    expect(result.events.single.title, '看电影');
    expect(result.events.single.messageIds, <int>[12, 16]);
  });

  test('提示词版本存在以强制旧的错误总结失效', () {
    expect(localAiPromptVersion, isNotEmpty);
  });
}
