import 'package:diandi_memory/features/memories/model/memory_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('每日小结包含消息双方与媒体统计', () {
    const summary = MemoryDaySummary(
      dateKey: '2025-01-08',
      dayStartSeconds: 1736265600,
      messageCount: 120,
      selfMessageCount: 58,
      otherMessageCount: 62,
      mediaMessageCount: 9,
    );

    expect(summary.summaryText, contains('120 条聊天'));
    expect(summary.summaryText, contains('58 条'));
    expect(summary.summaryText, contains('62 条'));
    expect(summary.summaryText, contains('9 条'));
  });
}
