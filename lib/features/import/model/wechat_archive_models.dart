class WechatExportArchive {
  const WechatExportArchive({
    required this.name,
    required this.messages,
    this.version,
  });

  final String name;
  final int? version;
  final List<Map<String, dynamic>> messages;
}

class WechatArchiveSummary {
  const WechatArchiveSummary({
    required this.archiveName,
    required this.messagesJsPath,
    required this.messageCount,
    required this.imageCount,
    required this.videoCount,
    required this.voiceCount,
    required this.stickerCount,
    required this.fileCount,
    required this.mediaReferenceCount,
    required this.missingMediaCount,
    this.archiveVersion,
    this.startTime,
    this.endTime,
  });

  final String archiveName;
  final String messagesJsPath;
  final int? archiveVersion;
  final int messageCount;
  final int imageCount;
  final int videoCount;
  final int voiceCount;
  final int stickerCount;
  final int fileCount;
  final int mediaReferenceCount;
  final int missingMediaCount;
  final int? startTime;
  final int? endTime;

  int get availableMediaCount => mediaReferenceCount - missingMediaCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'archiveName': archiveName,
        'messagesJsPath': messagesJsPath,
        'archiveVersion': archiveVersion,
        'messageCount': messageCount,
        'imageCount': imageCount,
        'videoCount': videoCount,
        'voiceCount': voiceCount,
        'stickerCount': stickerCount,
        'fileCount': fileCount,
        'mediaReferenceCount': mediaReferenceCount,
        'missingMediaCount': missingMediaCount,
        'startTime': startTime,
        'endTime': endTime,
      };

  factory WechatArchiveSummary.fromJson(Map<String, dynamic> json) {
    return WechatArchiveSummary(
      archiveName: json['archiveName'] as String,
      messagesJsPath: json['messagesJsPath'] as String,
      archiveVersion: json['archiveVersion'] as int?,
      messageCount: json['messageCount'] as int,
      imageCount: json['imageCount'] as int,
      videoCount: json['videoCount'] as int,
      voiceCount: json['voiceCount'] as int,
      stickerCount: json['stickerCount'] as int,
      fileCount: json['fileCount'] as int,
      mediaReferenceCount: json['mediaReferenceCount'] as int,
      missingMediaCount: json['missingMediaCount'] as int,
      startTime: json['startTime'] as int?,
      endTime: json['endTime'] as int?,
    );
  }
}
