import '../../../core/database/app_database.dart';
import '../model/memory_models.dart';

class MemoryRepository {
  const MemoryRepository({
    this.database = AppDatabase.instance,
  });

  final AppDatabase database;

  Future<List<MemoryDaySummary>> loadDailySummaries() async {
    final db = await database.database;
    final rows = await db.rawQuery('''
SELECT
  strftime('%Y-%m-%d', m.create_time, 'unixepoch', 'localtime') AS day_key,
  COUNT(*) AS message_count,
  SUM(CASE WHEN m.is_sender = 1 THEN 1 ELSE 0 END) AS self_count,
  SUM(CASE WHEN m.is_sender = 0 AND m.sender_id IS NOT NULL THEN 1 ELSE 0 END) AS other_count,
  SUM(CASE WHEN COALESCE(mm.has_media, 0) = 1 THEN 1 ELSE 0 END) AS media_count
FROM messages m
LEFT JOIN (
  SELECT
    message_id,
    MAX(CASE WHEN media_id IS NOT NULL THEN 1 ELSE 0 END) AS has_media
  FROM message_media
  GROUP BY message_id
) mm ON mm.message_id = m.id
WHERE m.create_time IS NOT NULL
GROUP BY day_key
ORDER BY day_key DESC
''');

    return rows
        .where((row) => row['day_key'] is String)
        .map((row) {
          final dateKey = row['day_key']! as String;
          final dateParts = dateKey.split('-').map(int.parse).toList();
          final dayStart = DateTime(dateParts[0], dateParts[1], dateParts[2]);
          return MemoryDaySummary(
            dateKey: dateKey,
            dayStartSeconds: dayStart.millisecondsSinceEpoch ~/ 1000,
            messageCount: (row['message_count'] as num?)?.toInt() ?? 0,
            selfMessageCount: (row['self_count'] as num?)?.toInt() ?? 0,
            otherMessageCount: (row['other_count'] as num?)?.toInt() ?? 0,
            mediaMessageCount: (row['media_count'] as num?)?.toInt() ?? 0,
          );
        })
        .toList(growable: false);
  }

  Future<List<MemoryChatMessage>> loadMessagesForDay(
    MemoryDaySummary summary,
  ) async {
    final db = await database.database;
    final start = DateTime.fromMillisecondsSinceEpoch(
      summary.dayStartSeconds * 1000,
    );
    final end = DateTime(start.year, start.month, start.day + 1);
    final rows = await db.rawQuery(
      '''
SELECT
  m.id,
  m.is_sender,
  m.sender_name,
  m.message_type,
  m.content,
  m.create_time,
  mm.media_type,
  mm.display_name AS media_name,
  stored.local_path AS media_local_path
FROM messages m
LEFT JOIN (
  SELECT
    message_id,
    MAX(media_id) AS media_id,
    MAX(media_type) AS media_type,
    MAX(display_name) AS display_name
  FROM message_media
  WHERE media_id IS NOT NULL
  GROUP BY message_id
) mm ON mm.message_id = m.id
LEFT JOIN media stored ON stored.id = mm.media_id
WHERE m.create_time >= ? AND m.create_time < ?
ORDER BY m.create_time ASC, m.id ASC
''',
      <Object?>[
        summary.dayStartSeconds,
        end.millisecondsSinceEpoch ~/ 1000,
      ],
    );

    // 总结只负责索引，展开后始终从 SQLite 读取真实导入消息，避免展示脱离证据的文本。
    return rows
        .map(
          (row) => MemoryChatMessage(
            id: row['id']! as int,
            isSender: row['is_sender'] == 1,
            senderName: row['sender_name'] as String?,
            messageType: row['message_type'] as String?,
            content: row['content'] as String?,
            createTime: (row['create_time'] as num?)?.toInt(),
            mediaType: row['media_type'] as String?,
            mediaName: row['media_name'] as String?,
            mediaLocalPath: row['media_local_path'] as String?,
          ),
        )
        .toList(growable: false);
  }
}
