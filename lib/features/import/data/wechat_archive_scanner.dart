import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../model/wechat_archive_models.dart';
import 'messages_js_parser.dart';

class WechatArchiveScanner {
  const WechatArchiveScanner({
    this.parser = const MessagesJsParser(),
  });

  final MessagesJsParser parser;

  Future<WechatArchiveSummary> scanZip(String zipPath) async {
    final payload = await compute(_scanZipPayload, zipPath);
    return WechatArchiveSummary.fromJson(payload);
  }

  WechatArchiveSummary scanZipSync(String zipPath) {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final archivePaths = archive
          .where((entry) => entry.isFile)
          .map((entry) => _normalizeArchivePath(entry.name))
          .toSet();

      final candidates = archive
          .where((entry) => entry.isFile)
          .where((entry) => _isMessagesJsPath(entry.name))
          .toList(growable: false);

      if (candidates.isEmpty) {
        throw const FormatException('ZIP 中未找到 data/messages.js');
      }
      if (candidates.length > 1) {
        throw const FormatException('ZIP 中发现多个 data/messages.js，请一次只导入一个聊天档案');
      }

      final messagesFile = candidates.single;
      final bytes = messagesFile.readBytes();
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('data/messages.js 为空');
      }

      final exportArchive = parser.parse(utf8.decode(bytes));
      final messagesJsPath = _normalizeArchivePath(messagesFile.name);
      final archiveRoot = _archiveRoot(messagesJsPath);

      return _buildSummary(
        exportArchive: exportArchive,
        messagesJsPath: messagesJsPath,
        archiveRoot: archiveRoot,
        archivePaths: archivePaths,
      );
    } finally {
      input.closeSync();
    }
  }

  WechatArchiveSummary _buildSummary({
    required WechatExportArchive exportArchive,
    required String messagesJsPath,
    required String archiveRoot,
    required Set<String> archivePaths,
  }) {
    var imageCount = 0;
    var videoCount = 0;
    var voiceCount = 0;
    var stickerCount = 0;
    var fileCount = 0;
    var mediaReferenceCount = 0;
    var missingMediaCount = 0;
    int? startTime;
    int? endTime;

    for (final message in exportArchive.messages) {
      final kind = _messageKind(message);
      switch (kind) {
        case _MessageKind.image:
          imageCount += 1;
        case _MessageKind.video:
          videoCount += 1;
        case _MessageKind.voice:
          voiceCount += 1;
        case _MessageKind.sticker:
          stickerCount += 1;
        case _MessageKind.file:
          fileCount += 1;
        case _MessageKind.other:
          break;
      }

      final createTime = _asPositiveInt(message['createTime']);
      if (createTime != null) {
        startTime = startTime == null || createTime < startTime ? createTime : startTime;
        endTime = endTime == null || createTime > endTime ? createTime : endTime;
      }

      final mediaReference = _mediaReference(message);
      if (mediaReference == null) {
        continue;
      }

      mediaReferenceCount += 1;
      final expectedPath = _joinArchivePath(archiveRoot, mediaReference);
      if (!archivePaths.contains(expectedPath)) {
        missingMediaCount += 1;
      }
    }

    return WechatArchiveSummary(
      archiveName: exportArchive.name,
      messagesJsPath: messagesJsPath,
      archiveVersion: exportArchive.version,
      messageCount: exportArchive.messages.length,
      imageCount: imageCount,
      videoCount: videoCount,
      voiceCount: voiceCount,
      stickerCount: stickerCount,
      fileCount: fileCount,
      mediaReferenceCount: mediaReferenceCount,
      missingMediaCount: missingMediaCount,
      startTime: startTime,
      endTime: endTime,
    );
  }

  _MessageKind _messageKind(Map<String, dynamic> message) {
    final contentData = _contentData(message);
    final outerType = message['type']?.toString();
    final exportMediaType = message['exportMediaType']?.toString();
    final contentType = contentData['type']?.toString();

    if (exportMediaType == 'file' ||
        outerType == '文件' ||
        (contentType == 'share' && contentData['typeVal']?.toString() == '6')) {
      return _MessageKind.file;
    }
    if (_nonEmptyString(message['voiceDataUrl']) != null ||
        contentType == 'voice' ||
        outerType == '语音') {
      return _MessageKind.voice;
    }
    if (exportMediaType == 'image' || contentType == 'image' || outerType == '图片') {
      return _MessageKind.image;
    }
    if (exportMediaType == 'video' || contentType == 'video' || outerType == '视频') {
      return _MessageKind.video;
    }
    if (exportMediaType == 'sticker' || contentType == 'sticker' || outerType == '表情包') {
      return _MessageKind.sticker;
    }
    return _MessageKind.other;
  }

  String? _mediaReference(Map<String, dynamic> message) {
    return _nonEmptyString(message['voiceDataUrl']) ??
        _nonEmptyString(message['exportMediaUrl']);
  }

  Map<String, dynamic> _contentData(Map<String, dynamic> message) {
    final value = message['contentData'];
    return value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
  }

  String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  int? _asPositiveInt(Object? value) {
    final parsed = switch (value) {
      int intValue => intValue,
      num numValue => numValue.toInt(),
      String stringValue => int.tryParse(stringValue),
      _ => null,
    };
    return parsed != null && parsed > 0 ? parsed : null;
  }

  bool _isMessagesJsPath(String path) {
    final normalized = _normalizeArchivePath(path).toLowerCase();
    return normalized == 'data/messages.js' || normalized.endsWith('/data/messages.js');
  }

  String _archiveRoot(String messagesJsPath) {
    const suffix = 'data/messages.js';
    return messagesJsPath.substring(0, messagesJsPath.length - suffix.length);
  }

  String _joinArchivePath(String root, String relativePath) {
    final normalizedRelative = _normalizeArchivePath(relativePath)
        .replaceFirst(RegExp(r'^/+'), '');
    return _normalizeArchivePath('$root$normalizedRelative');
  }

  String _normalizeArchivePath(String path) {
    return path
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^\./+'), '')
        .replaceAll(RegExp(r'/+'), '/');
  }
}

enum _MessageKind {
  image,
  video,
  voice,
  sticker,
  file,
  other,
}

Map<String, dynamic> _scanZipPayload(String zipPath) {
  // 资源扫描和 JSON 解析放在后台 isolate，避免大型档案阻塞 Flutter UI。
  return const WechatArchiveScanner().scanZipSync(zipPath).toJson();
}
