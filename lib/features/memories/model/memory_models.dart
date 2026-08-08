class MemoryDaySummary {
  const MemoryDaySummary({
    required this.dateKey,
    required this.dayStartSeconds,
    required this.messageCount,
    required this.selfMessageCount,
    required this.otherMessageCount,
    required this.mediaMessageCount,
  });

  final String dateKey;
  final int dayStartSeconds;
  final int messageCount;
  final int selfMessageCount;
  final int otherMessageCount;
  final int mediaMessageCount;

  String get summaryText {
    final buffer = StringBuffer('这一天留下了 $messageCount 条聊天');
    if (selfMessageCount > 0 || otherMessageCount > 0) {
      buffer.write('，你发了 $selfMessageCount 条，对方发了 $otherMessageCount 条');
    }
    if (mediaMessageCount > 0) {
      buffer.write('，还有 $mediaMessageCount 条带着照片、视频或其他媒体');
    }
    buffer.write('。');
    return buffer.toString();
  }
}

class MemoryChatMessage {
  const MemoryChatMessage({
    required this.id,
    required this.isSender,
    this.senderName,
    this.messageType,
    this.content,
    this.createTime,
    this.mediaType,
    this.mediaName,
    this.mediaLocalPath,
  });

  final int id;
  final bool isSender;
  final String? senderName;
  final String? messageType;
  final String? content;
  final int? createTime;
  final String? mediaType;
  final String? mediaName;
  final String? mediaLocalPath;
}
