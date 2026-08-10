import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../model/ai_summary_models.dart';

class AiSummaryRepository {
  const AiSummaryRepository({
    this.database = AppDatabase.instance,
  });

  final AppDatabase database;

  Future<List<SummaryRange>> loadRanges(SummaryPeriod period) async {
    final db = await database.database;
    final rows = await db.rawQuery('''
SELECT
  strftime('%Y-%m-%d', create_time, 'unixepoch', 'localtime') AS day_key,
  COUNT(*) AS message_count
FROM messages
WHERE create_time IS NOT NULL
GROUP BY day_key
ORDER BY day_key ASC
''');

    final days = rows
        .where((row) => row['day_key'] is String)
        .map(
          (row) => _DayBucket(
            date: _parseDateKey(row['day_key']! as String),
            messageCount: (row['message_count'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
    if (period == SummaryPeriod.day) {
      return days.map(_dayRange).toList(growable: false).reversed.toList();
    }

    final grouped = <String, List<_DayBucket>>{};
    for (final day in days) {
      final key = _periodKey(period, day.date);
      grouped.putIfAbsent(key, () => <_DayBucket>[]).add(day);
    }

    final ranges = grouped.entries.map((entry) {
      final start = _periodStart(period, entry.value.first.date);
      final end = _periodEnd(period, start);
      return SummaryRange(
        period: period,
        key: entry.key,
        startSeconds: start.millisecondsSinceEpoch ~/ 1000,
        endSeconds: end.millisecondsSinceEpoch ~/ 1000,
        messageCount: entry.value.fold(0, (sum, day) => sum + day.messageCount),
        dayCount: entry.value.length,
      );
    }).toList()
      ..sort((first, second) => second.startSeconds.compareTo(first.startSeconds));
    return ranges;
  }

  Future<Map<String, StoredAiSummary>> loadSummaries(SummaryPeriod period) async {
    final db = await database.database;
    final rows = await db.query(
      'ai_summaries',
      where: 'period_type = ?',
      whereArgs: <Object?>[period.value],
      orderBy: 'start_time DESC',
    );
    return <String, StoredAiSummary>{
      for (final row in rows) row['period_key']! as String: _summaryFromRow(row),
    };
  }

  Future<StoredAiSummary?> loadSummary(SummaryPeriod period, String key) async {
    final db = await database.database;
    final rows = await db.query(
      'ai_summaries',
      where: 'period_type = ? AND period_key = ?',
      whereArgs: <Object?>[period.value, key],
      limit: 1,
    );
    return rows.isEmpty ? null : _summaryFromRow(rows.single);
  }

  Future<List<AiTextMessage>> loadTextMessages(SummaryRange range) async {
    final db = await database.database;
    final rows = await db.query(
      'messages',
      columns: const <String>[
        'id',
        'is_sender',
        'sender_name',
        'create_time',
        'content',
      ],
      where: 'create_time >= ? AND create_time < ? AND content IS NOT NULL',
      whereArgs: <Object?>[range.startSeconds, range.endSeconds],
      orderBy: 'create_time ASC, id ASC',
    );

    return rows.map((row) {
      final content = (row['content'] as String?)?.trim() ?? '';
      return AiTextMessage(
        id: row['id']! as int,
        isSender: row['is_sender'] == 1,
        senderName: row['sender_name'] as String?,
        createTime: (row['create_time'] as num?)?.toInt() ?? range.startSeconds,
        content: content,
      );
    }).where((message) {
      if (message.content.length < 2) return false;
      final lower = message.content.toLowerCase();
      return !message.content.startsWith('<') && !lower.startsWith('http');
    }).toList(growable: false);
  }

  Future<String> sourceHashForMessages(List<AiTextMessage> messages) async {
    // 发送方也是语义的一部分；双方相同文字不应被视为同一个 AI 输入版本。
    final value = messages
        .map(
          (message) => '${message.id}|${message.createTime}|${message.isSender ? 1 : 0}|'
              '${message.senderName ?? ''}|${message.content}',
        )
        .join('\n');
    return sha256.convert(utf8.encode(value)).toString();
  }

  Future<String> sourceHashForChildren(List<StoredAiSummary> children) async {
    final value = children
        .map((summary) => '${summary.period.value}|${summary.key}|${summary.sourceHash}|${summary.summaryText}')
        .join('\n');
    return sha256.convert(utf8.encode(value)).toString();
  }

  Future<List<SummaryRange>> childRanges(SummaryRange parent) async {
    final childPeriod = parent.period.child;
    if (childPeriod == null) return const <SummaryRange>[];
    final ranges = await loadRanges(childPeriod);
    return ranges
        .where(
          (range) =>
              range.startSeconds >= parent.startSeconds &&
              range.startSeconds < parent.endSeconds,
        )
        .toList(growable: false)
      ..sort((first, second) => first.startSeconds.compareTo(second.startSeconds));
  }

  Future<StoredAiSummary> saveSummary({
    required SummaryRange range,
    required GeneratedAiSummary generated,
    required String sourceHash,
    required String modelName,
    List<int> childSummaryIds = const <int>[],
  }) async {
    final db = await database.database;
    return db.transaction((transaction) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final values = <String, Object?>{
        'period_type': range.period.value,
        'period_key': range.key,
        'start_time': range.startSeconds,
        'end_time': range.endSeconds,
        'summary_text': generated.summaryText,
        'source_hash': sourceHash,
        'model_name': modelName,
        'generated_at': now,
      };

      final existing = await transaction.query(
        'ai_summaries',
        columns: const <String>['id'],
        where: 'period_type = ? AND period_key = ?',
        whereArgs: <Object?>[range.period.value, range.key],
        limit: 1,
      );
      late final int summaryId;
      if (existing.isEmpty) {
        summaryId = await transaction.insert('ai_summaries', values);
      } else {
        summaryId = existing.single['id']! as int;
        await transaction.update(
          'ai_summaries',
          values,
          where: 'id = ?',
          whereArgs: <Object?>[summaryId],
        );
        await transaction.delete(
          'ai_events',
          where: 'summary_id = ?',
          whereArgs: <Object?>[summaryId],
        );
        await transaction.delete(
          'ai_summary_children',
          where: 'summary_id = ?',
          whereArgs: <Object?>[summaryId],
        );
      }

      for (var index = 0; index < generated.events.length; index += 1) {
        final event = generated.events[index];
        final eventId = await transaction.insert(
          'ai_events',
          <String, Object?>{
            'summary_id': summaryId,
            'title': event.title,
            'description': event.description,
            'sort_order': index,
          },
        );
        for (final messageId in event.messageIds.toSet()) {
          await transaction.insert(
            'ai_event_messages',
            <String, Object?>{'event_id': eventId, 'message_id': messageId},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      for (final childId in childSummaryIds.toSet()) {
        await transaction.insert(
          'ai_summary_children',
          <String, Object?>{'summary_id': summaryId, 'child_summary_id': childId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      final row = (await transaction.query(
        'ai_summaries',
        where: 'id = ?',
        whereArgs: <Object?>[summaryId],
        limit: 1,
      )).single;
      return _summaryFromRow(row);
    });
  }
}

class _DayBucket {
  const _DayBucket({required this.date, required this.messageCount});

  final DateTime date;
  final int messageCount;
}

SummaryRange _dayRange(_DayBucket day) {
  final start = DateTime(day.date.year, day.date.month, day.date.day);
  final end = DateTime(start.year, start.month, start.day + 1);
  return SummaryRange(
    period: SummaryPeriod.day,
    key: _dateKey(start),
    startSeconds: start.millisecondsSinceEpoch ~/ 1000,
    endSeconds: end.millisecondsSinceEpoch ~/ 1000,
    messageCount: day.messageCount,
    dayCount: 1,
  );
}

String _periodKey(SummaryPeriod period, DateTime date) {
  final start = _periodStart(period, date);
  return switch (period) {
    SummaryPeriod.day => _dateKey(start),
    SummaryPeriod.week => 'week:${_dateKey(start)}',
    SummaryPeriod.month => '${start.year}-${start.month.toString().padLeft(2, '0')}',
    SummaryPeriod.year => '${start.year}',
  };
}

DateTime _periodStart(SummaryPeriod period, DateTime date) {
  return switch (period) {
    SummaryPeriod.day => DateTime(date.year, date.month, date.day),
    SummaryPeriod.week => DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - DateTime.monday)),
    SummaryPeriod.month => DateTime(date.year, date.month),
    SummaryPeriod.year => DateTime(date.year),
  };
}

DateTime _periodEnd(SummaryPeriod period, DateTime start) {
  return switch (period) {
    SummaryPeriod.day => DateTime(start.year, start.month, start.day + 1),
    SummaryPeriod.week => start.add(const Duration(days: 7)),
    SummaryPeriod.month => DateTime(start.year, start.month + 1),
    SummaryPeriod.year => DateTime(start.year + 1),
  };
}

DateTime _parseDateKey(String value) {
  final parts = value.split('-').map(int.parse).toList(growable: false);
  return DateTime(parts[0], parts[1], parts[2]);
}

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

StoredAiSummary _summaryFromRow(Map<String, Object?> row) {
  return StoredAiSummary(
    id: row['id']! as int,
    period: SummaryPeriod.values.firstWhere(
      (period) => period.value == row['period_type'],
    ),
    key: row['period_key']! as String,
    startSeconds: (row['start_time']! as num).toInt(),
    endSeconds: (row['end_time']! as num).toInt(),
    summaryText: row['summary_text']! as String,
    sourceHash: row['source_hash']! as String,
    modelName: row['model_name']! as String,
    generatedAt: (row['generated_at']! as num).toInt(),
  );
}
