enum SummaryPeriod { day, week, month, year }

extension SummaryPeriodX on SummaryPeriod {
  String get value => name;

  String get label => switch (this) {
        SummaryPeriod.day => '日',
        SummaryPeriod.week => '周',
        SummaryPeriod.month => '月',
        SummaryPeriod.year => '年',
      };

  SummaryPeriod? get child => switch (this) {
        SummaryPeriod.day => null,
        SummaryPeriod.week => SummaryPeriod.day,
        SummaryPeriod.month => SummaryPeriod.week,
        SummaryPeriod.year => SummaryPeriod.month,
      };
}

class SummaryRange {
  const SummaryRange({
    required this.period,
    required this.key,
    required this.startSeconds,
    required this.endSeconds,
    required this.messageCount,
    required this.dayCount,
  });

  final SummaryPeriod period;
  final String key;
  final int startSeconds;
  final int endSeconds;
  final int messageCount;
  final int dayCount;

  String get label {
    final start = DateTime.fromMillisecondsSinceEpoch(startSeconds * 1000);
    return switch (period) {
      SummaryPeriod.day => '${start.month}月${start.day}日',
      SummaryPeriod.week => '${start.month}月${start.day}日这一周',
      SummaryPeriod.month => '${start.year}年${start.month}月',
      SummaryPeriod.year => '${start.year}年',
    };
  }
}

class StoredAiSummary {
  const StoredAiSummary({
    required this.id,
    required this.period,
    required this.key,
    required this.startSeconds,
    required this.endSeconds,
    required this.summaryText,
    required this.sourceHash,
    required this.modelName,
    required this.generatedAt,
  });

  final int id;
  final SummaryPeriod period;
  final String key;
  final int startSeconds;
  final int endSeconds;
  final String summaryText;
  final String sourceHash;
  final String modelName;
  final int generatedAt;
}

class LocalAiModelInfo {
  const LocalAiModelInfo({
    required this.path,
    required this.name,
    required this.byteSize,
  });

  final String path;
  final String name;
  final int byteSize;
}

class AiTextMessage {
  const AiTextMessage({
    required this.id,
    required this.isSender,
    required this.createTime,
    required this.content,
    this.senderName,
  });

  final int id;
  final bool isSender;
  final int createTime;
  final String content;
  final String? senderName;
}

class GeneratedAiEvent {
  const GeneratedAiEvent({
    required this.title,
    required this.description,
    required this.messageIds,
  });

  final String title;
  final String description;
  final List<int> messageIds;
}

class GeneratedAiSummary {
  const GeneratedAiSummary({
    required this.summaryText,
    this.events = const <GeneratedAiEvent>[],
  });

  final String summaryText;
  final List<GeneratedAiEvent> events;
}
