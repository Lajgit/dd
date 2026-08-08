import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import 'archive_media_store.dart';
import 'messages_js_parser.dart';

class WechatArchiveImportResult {
  const WechatArchiveImportResult({
    required this.archiveName,
    required this.archiveMessageCount,
    required this.insertedMessageCount,
    required this.existingMessageCount,
    required this.participantCount,
    required this.mediaReferenceCount,
    required this.storedMediaReferenceCount,
    required this.uniqueMediaCount,
    required this.newlyStoredMediaCount,
    required this.missingMediaCount,
    required this.isDuplicateSource,
  });

  final String archiveName;
  final int archiveMessageCount;
  final int insertedMessageCount;
  final int existingMessageCount;
  final int participantCount;
  final int mediaReferenceCount;
  final int storedMediaReferenceCount;
  final int uniqueMediaCount;
  final int newlyStoredMediaCount;
  final int missingMediaCount;
  final bool isDuplicateSource;
}

class WechatArchiveImporter {
  const WechatArchiveImporter({
    this.database = AppDatabase.instance,
  });

  final AppDatabase database;

  Future<WechatArchiveImportResult> importZip(String zipPath) async {
    final storageRoot = await database.storageRootPath();
    final payload = _PreparedWechatArchive.fromJson(
      await compute(
        _prepareWechatArchivePayload,
        <String, String>{
          'zipPath': zipPath,
          'storageRoot': storageRoot,
        },
      ),
    );

    final db = await database.database;
    final duplicateSource = await db.query(
      'import_sources',
      columns: const <String>['id'],
      where: 'source_fingerprint = ?',
      whereArgs: <Object?>[payload.sourceFingerprint],
      limit: 1,
    );
    final isDuplicateSource = duplicateSource.isNotEmpty;

    return db.transaction((transaction) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      late final int sourceId;
      if (isDuplicateSource) {
        sourceId = duplicateSource.single['id']! as int;
      } else {
        sourceId = await transaction.insert(
          'import_sources',
          <String, Object?>{
            'source_type': 'wechat_explorer_zip',
            'source_fingerprint': payload.sourceFingerprint,
            'source_file_name': payload.sourceFileName,
            'archive_name': payload.archiveName,
            'archive_version': payload.archiveVersion,
            'messages_js_path': payload.messagesJsPath,
            'raw_messages_path': payload.rawMessagesPath,
            'archive_message_count': payload.messages.length,
            'inserted_message_count': 0,
            'media_reference_count': payload.mediaReferenceCount,
            'missing_media_count': payload.missingMediaCount,
            'imported_at': now,
          },
        );
      }

      final participantIds = <String, int>{};
      for (final participant in payload.participants) {
        final existing = await transaction.query(
          'participants',
          columns: const <String>['id', 'display_name', 'is_self'],
          where: 'sender_id = ?',
          whereArgs: <Object?>[participant.senderId],
          limit: 1,
        );

        if (existing.isEmpty) {
          participantIds[participant.senderId] = await transaction.insert(
            'participants',
            <String, Object?>{
              'sender_id': participant.senderId,
              'display_name': participant.displayName,
              'is_self': participant.isSelf ? 1 : 0,
              'updated_at': now,
            },
          );
          continue;
        }

        final existingRow = existing.single;
        final participantId = existingRow['id']! as int;
        participantIds[participant.senderId] = participantId;
        await transaction.update(
          'participants',
          <String, Object?>{
            'display_name': participant.displayName.isEmpty
                ? existingRow['display_name']
                : participant.displayName,
            'is_self': participant.isSelf || existingRow['is_self'] == 1 ? 1 : 0,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: <Object?>[participantId],
        );
      }

      var insertedMessageCount = 0;
      var existingMessageCount = 0;

      for (final message in payload.messages) {
        final existing = await transaction.query(
          'messages',
          columns: const <String>['id'],
          where: 'source_message_key = ?',
          whereArgs: <Object?>[message.sourceMessageKey],
          limit: 1,
        );

        late final int messageId;
        if (existing.isNotEmpty) {
          messageId = existing.single['id']! as int;
          existingMessageCount += 1;
        } else {
          messageId = await transaction.insert(
            'messages',
            <String, Object?>{
              'source_message_key': message.sourceMessageKey,
              'first_source_id': sourceId,
              'participant_id': message.senderId == null
                  ? null
                  : participantIds[message.senderId!],
              'source_row_id': message.sourceRowId,
              'local_id': message.localId,
              'server_id': message.serverId,
              'session_id': message.sessionId,
              'sender_id': message.senderId,
              'sender_name': message.senderName,
              'is_sender': message.isSender ? 1 : 0,
              'message_type': message.messageType,
              'content': message.content,
              'create_time': message.createTime,
              'datetime_text': message.datetimeText,
              'content_data_json': message.contentDataJson,
              'imported_at': now,
            },
          );
          insertedMessageCount += 1;
        }

        int? mediaId;
        final mediaSha256 = message.mediaSha256;
        if (mediaSha256 != null &&
            message.mediaLocalPath != null &&
            message.mediaByteSize != null) {
          await transaction.insert(
            'media',
            <String, Object?>{
              'sha256': mediaSha256,
              'local_path': message.mediaLocalPath,
              'byte_size': message.mediaByteSize,
              'media_type': message.mediaType,
              'display_name': message.mediaName,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          final mediaRows = await transaction.query(
            'media',
            columns: const <String>['id'],
            where: 'sha256 = ?',
            whereArgs: <Object?>[mediaSha256],
            limit: 1,
          );
          mediaId = mediaRows.single['id']! as int;

          final mediaUpdates = <String, Object?>{
            'local_path': message.mediaLocalPath,
            'byte_size': message.mediaByteSize,
          };
          if (message.mediaType != null) {
            mediaUpdates['media_type'] = message.mediaType;
          }
          if (message.mediaName != null) {
            mediaUpdates['display_name'] = message.mediaName;
          }
          await transaction.update(
            'media',
            mediaUpdates,
            where: 'id = ?',
            whereArgs: <Object?>[mediaId],
          );
        }

        final archivePath = message.mediaArchivePath;
        if (archivePath == null) {
          continue;
        }

        final status = mediaId != null
            ? 'stored'
            : message.mediaAvailable
                ? 'available_in_archive'
                : 'missing_in_archive';
        final messageMediaValues = <String, Object?>{
          'message_id': messageId,
          'source_id': sourceId,
          'media_id': mediaId,
          'archive_path': archivePath,
          'media_type': message.mediaType,
          'display_name': message.mediaName,
          'status': status,
          'media_error': message.mediaError,
        };
        await transaction.insert(
          'message_media',
          messageMediaValues,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await transaction.update(
          'message_media',
          <String, Object?>{
            'media_id': mediaId,
            'media_type': message.mediaType,
            'display_name': message.mediaName,
            'status': status,
            'media_error': message.mediaError,
          },
          where: 'message_id = ? AND source_id = ? AND archive_path = ?',
          whereArgs: <Object?>[messageId, sourceId, archivePath],
        );
      }

      final sourceUpdates = <String, Object?>{
        'media_reference_count': payload.mediaReferenceCount,
        'missing_media_count': payload.missingMediaCount,
      };
      if (!isDuplicateSource) {
        sourceUpdates['inserted_message_count'] = insertedMessageCount;
      }
      await transaction.update(
        'import_sources',
        sourceUpdates,
        where: 'id = ?',
        whereArgs: <Object?>[sourceId],
      );

      return WechatArchiveImportResult(
        archiveName: payload.archiveName,
        archiveMessageCount: payload.messages.length,
        insertedMessageCount: insertedMessageCount,
        existingMessageCount: existingMessageCount,
        participantCount: payload.participants.length,
        mediaReferenceCount: payload.mediaReferenceCount,
        storedMediaReferenceCount: payload.storedMediaReferenceCount,
        uniqueMediaCount: payload.uniqueMediaCount,
        newlyStoredMediaCount: payload.newlyStoredMediaCount,
        missingMediaCount: payload.missingMediaCount,
        isDuplicateSource: isDuplicateSource,
      );
    });
  }
}

class WechatMessageNormalizer {
  const WechatMessageNormalizer();

  String sourceMessageKey(Map<String, dynamic> message) {
    final sessionId = _nonEmptyString(message['sessionId']) ?? 'unknown-session';
    final serverId = _nonEmptyString(message['serverId']);
    if (serverId != null) {
      return 'wechat:$sessionId:server:$serverId';
    }

    final localId = _asInt(message['localId']);
    if (localId != null) {
      return 'wechat:$sessionId:local:$localId';
    }

    final sourceRowId = _nonEmptyString(message['id']);
    if (sourceRowId != null) {
      return 'wechat:$sessionId:id:$sourceRowId';
    }

    final stableFallback = Map<String, dynamic>.from(message)
      ..remove('img')
      ..remove('exportAvatarUrl');
    final digest = sha256.convert(utf8.encode(jsonEncode(stableFallback)));
    return 'wechat:$sessionId:hash:$digest';
  }

  _PreparedMessage _normalize({
    required Map<String, dynamic> message,
    required String archiveRoot,
    required Set<String> archivePaths,
  }) {
    final contentData = message['contentData'];
    final contentDataMap = contentData is Map
        ? Map<String, dynamic>.from(contentData)
        : const <String, dynamic>{};
    final mediaReference = _nonEmptyString(message['voiceDataUrl']) ??
        _nonEmptyString(message['exportMediaUrl']);
    final mediaArchivePath = mediaReference == null
        ? null
        : _joinArchivePath(archiveRoot, mediaReference);

    return _PreparedMessage(
      sourceMessageKey: sourceMessageKey(message),
      sourceRowId: _nonEmptyString(message['id']),
      localId: _asInt(message['localId']),
      serverId: _nonEmptyString(message['serverId']),
      sessionId: _nonEmptyString(message['sessionId']),
      senderId: _nonEmptyString(message['senderId']),
      senderName: _nonEmptyString(message['name']),
      isSender: message['isSender'] == true,
      messageType: _nonEmptyString(message['type']),
      content: message['content']?.toString(),
      createTime: _asInt(message['createTime']),
      datetimeText: _nonEmptyString(message['datetime']),
      contentDataJson: contentData is Map ? jsonEncode(contentDataMap) : null,
      mediaArchivePath: mediaArchivePath,
      mediaType: _nonEmptyString(message['exportMediaType']) ??
          _nonEmptyString(contentDataMap['type']),
      mediaName: _nonEmptyString(message['exportMediaName']),
      mediaError: _nonEmptyString(message['exportMediaError']),
      mediaAvailable: mediaArchivePath != null && archivePaths.contains(mediaArchivePath),
    );
  }
}

Future<Map<String, dynamic>> _prepareWechatArchivePayload(
  Map<String, String> arguments,
) async {
  final zipPath = arguments['zipPath']!;
  final storageRoot = arguments['storageRoot']!;
  final input = InputFileStream(zipPath);

  try {
    final archive = ZipDecoder().decodeStream(input);
    final archiveFiles = <String, ArchiveFile>{};
    for (final entry in archive.where((entry) => entry.isFile)) {
      archiveFiles[_normalizeArchivePath(entry.name)] = entry;
    }

    final candidates = archiveFiles.entries
        .where((entry) => _isMessagesJsPath(entry.key))
        .toList(growable: false);
    if (candidates.isEmpty) {
      throw const FormatException('ZIP 中未找到 data/messages.js');
    }
    if (candidates.length > 1) {
      throw const FormatException('ZIP 中发现多个 data/messages.js，请一次只导入一个聊天档案');
    }

    final messagesJsPath = candidates.single.key;
    final messagesFile = candidates.single.value;
    final bytes = messagesFile.readBytes();
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('data/messages.js 为空');
    }

    final sourceFingerprint = sha256.convert(bytes).toString();
    final rawDirectory = Directory(path.join(storageRoot, 'raw'))
      ..createSync(recursive: true);
    final rawMessagesPath = path.join(
      rawDirectory.path,
      '$sourceFingerprint.messages.js',
    );
    final rawMessagesFile = File(rawMessagesPath);
    if (!rawMessagesFile.existsSync()) {
      // 原始 messages.js 只保存一份，规范化字段变化时仍可从原始来源重新构建。
      rawMessagesFile.writeAsBytesSync(bytes, flush: false);
    }

    final exportArchive = const MessagesJsParser().parse(utf8.decode(bytes));
    final archiveRoot = _archiveRoot(messagesJsPath);
    final archivePaths = archiveFiles.keys.toSet();

    const normalizer = WechatMessageNormalizer();
    final preparedMessages = <_PreparedMessage>[];
    final participants = <String, _PreparedParticipant>{};
    var mediaReferenceCount = 0;
    var missingMediaCount = 0;

    for (final message in exportArchive.messages) {
      final prepared = normalizer._normalize(
        message: message,
        archiveRoot: archiveRoot,
        archivePaths: archivePaths,
      );
      preparedMessages.add(prepared);

      final senderId = prepared.senderId;
      if (senderId != null) {
        final existing = participants[senderId];
        participants[senderId] = _PreparedParticipant(
          senderId: senderId,
          displayName: prepared.senderName ?? existing?.displayName ?? '',
          isSelf: prepared.isSender || (existing?.isSelf ?? false),
        );
      }

      if (prepared.mediaArchivePath != null) {
        mediaReferenceCount += 1;
        if (!prepared.mediaAvailable) {
          missingMediaCount += 1;
        }
      }
    }

    const mediaStore = ArchiveMediaStore();
    final storedByArchivePath = <String, StoredArchiveMedia>{};
    var newlyStoredMediaCount = 0;
    for (final message in preparedMessages) {
      final archivePath = message.mediaArchivePath;
      if (archivePath == null ||
          !message.mediaAvailable ||
          storedByArchivePath.containsKey(archivePath)) {
        continue;
      }
      final archiveFile = archiveFiles[archivePath];
      if (archiveFile == null) {
        continue;
      }

      final stored = await mediaStore.store(
        archiveFile: archiveFile,
        storageRoot: storageRoot,
      );
      storedByArchivePath[archivePath] = stored;
      if (!stored.wasAlreadyStored) {
        newlyStoredMediaCount += 1;
      }
    }

    final messagesWithMedia = preparedMessages
        .map(
          (message) => message._withStoredMedia(
            message.mediaArchivePath == null
                ? null
                : storedByArchivePath[message.mediaArchivePath!],
          ),
        )
        .toList(growable: false);
    final storedMediaReferenceCount = messagesWithMedia
        .where((message) => message.mediaSha256 != null)
        .length;
    final uniqueMediaCount = messagesWithMedia
        .map((message) => message.mediaSha256)
        .whereType<String>()
        .toSet()
        .length;

    return <String, dynamic>{
      'sourceFingerprint': sourceFingerprint,
      'sourceFileName': path.basename(zipPath),
      'archiveName': exportArchive.name,
      'archiveVersion': exportArchive.version,
      'messagesJsPath': messagesJsPath,
      'rawMessagesPath': rawMessagesPath,
      'messages': messagesWithMedia.map((message) => message.toJson()).toList(),
      'participants': participants.values
          .map((participant) => participant.toJson())
          .toList(),
      'mediaReferenceCount': mediaReferenceCount,
      'storedMediaReferenceCount': storedMediaReferenceCount,
      'uniqueMediaCount': uniqueMediaCount,
      'newlyStoredMediaCount': newlyStoredMediaCount,
      'missingMediaCount': missingMediaCount,
    };
  } finally {
    input.closeSync();
  }
}

class _PreparedWechatArchive {
  const _PreparedWechatArchive({
    required this.sourceFingerprint,
    required this.sourceFileName,
    required this.archiveName,
    required this.messagesJsPath,
    required this.rawMessagesPath,
    required this.messages,
    required this.participants,
    required this.mediaReferenceCount,
    required this.storedMediaReferenceCount,
    required this.uniqueMediaCount,
    required this.newlyStoredMediaCount,
    required this.missingMediaCount,
    this.archiveVersion,
  });

  final String sourceFingerprint;
  final String sourceFileName;
  final String archiveName;
  final int? archiveVersion;
  final String messagesJsPath;
  final String rawMessagesPath;
  final List<_PreparedMessage> messages;
  final List<_PreparedParticipant> participants;
  final int mediaReferenceCount;
  final int storedMediaReferenceCount;
  final int uniqueMediaCount;
  final int newlyStoredMediaCount;
  final int missingMediaCount;

  factory _PreparedWechatArchive.fromJson(Map<String, dynamic> json) {
    return _PreparedWechatArchive(
      sourceFingerprint: json['sourceFingerprint']! as String,
      sourceFileName: json['sourceFileName']! as String,
      archiveName: json['archiveName']! as String,
      archiveVersion: json['archiveVersion'] as int?,
      messagesJsPath: json['messagesJsPath']! as String,
      rawMessagesPath: json['rawMessagesPath']! as String,
      messages: (json['messages']! as List<dynamic>)
          .map((value) => _PreparedMessage.fromJson(
                Map<String, dynamic>.from(value as Map),
              ))
          .toList(growable: false),
      participants: (json['participants']! as List<dynamic>)
          .map((value) => _PreparedParticipant.fromJson(
                Map<String, dynamic>.from(value as Map),
              ))
          .toList(growable: false),
      mediaReferenceCount: json['mediaReferenceCount']! as int,
      storedMediaReferenceCount: json['storedMediaReferenceCount']! as int,
      uniqueMediaCount: json['uniqueMediaCount']! as int,
      newlyStoredMediaCount: json['newlyStoredMediaCount']! as int,
      missingMediaCount: json['missingMediaCount']! as int,
    );
  }
}

class _PreparedParticipant {
  const _PreparedParticipant({
    required this.senderId,
    required this.displayName,
    required this.isSelf,
  });

  final String senderId;
  final String displayName;
  final bool isSelf;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'senderId': senderId,
        'displayName': displayName,
        'isSelf': isSelf,
      };

  factory _PreparedParticipant.fromJson(Map<String, dynamic> json) {
    return _PreparedParticipant(
      senderId: json['senderId']! as String,
      displayName: json['displayName']! as String,
      isSelf: json['isSelf']! as bool,
    );
  }
}

class _PreparedMessage {
  const _PreparedMessage({
    required this.sourceMessageKey,
    required this.isSender,
    required this.mediaAvailable,
    this.sourceRowId,
    this.localId,
    this.serverId,
    this.sessionId,
    this.senderId,
    this.senderName,
    this.messageType,
    this.content,
    this.createTime,
    this.datetimeText,
    this.contentDataJson,
    this.mediaArchivePath,
    this.mediaType,
    this.mediaName,
    this.mediaError,
    this.mediaSha256,
    this.mediaLocalPath,
    this.mediaByteSize,
  });

  final String sourceMessageKey;
  final String? sourceRowId;
  final int? localId;
  final String? serverId;
  final String? sessionId;
  final String? senderId;
  final String? senderName;
  final bool isSender;
  final String? messageType;
  final String? content;
  final int? createTime;
  final String? datetimeText;
  final String? contentDataJson;
  final String? mediaArchivePath;
  final String? mediaType;
  final String? mediaName;
  final String? mediaError;
  final bool mediaAvailable;
  final String? mediaSha256;
  final String? mediaLocalPath;
  final int? mediaByteSize;

  _PreparedMessage _withStoredMedia(StoredArchiveMedia? stored) {
    if (stored == null) {
      return this;
    }
    return _PreparedMessage(
      sourceMessageKey: sourceMessageKey,
      sourceRowId: sourceRowId,
      localId: localId,
      serverId: serverId,
      sessionId: sessionId,
      senderId: senderId,
      senderName: senderName,
      isSender: isSender,
      messageType: messageType,
      content: content,
      createTime: createTime,
      datetimeText: datetimeText,
      contentDataJson: contentDataJson,
      mediaArchivePath: mediaArchivePath,
      mediaType: mediaType,
      mediaName: mediaName,
      mediaError: mediaError,
      mediaAvailable: mediaAvailable,
      mediaSha256: stored.sha256,
      mediaLocalPath: stored.localPath,
      mediaByteSize: stored.byteSize,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sourceMessageKey': sourceMessageKey,
        'sourceRowId': sourceRowId,
        'localId': localId,
        'serverId': serverId,
        'sessionId': sessionId,
        'senderId': senderId,
        'senderName': senderName,
        'isSender': isSender,
        'messageType': messageType,
        'content': content,
        'createTime': createTime,
        'datetimeText': datetimeText,
        'contentDataJson': contentDataJson,
        'mediaArchivePath': mediaArchivePath,
        'mediaType': mediaType,
        'mediaName': mediaName,
        'mediaError': mediaError,
        'mediaAvailable': mediaAvailable,
        'mediaSha256': mediaSha256,
        'mediaLocalPath': mediaLocalPath,
        'mediaByteSize': mediaByteSize,
      };

  factory _PreparedMessage.fromJson(Map<String, dynamic> json) {
    return _PreparedMessage(
      sourceMessageKey: json['sourceMessageKey']! as String,
      sourceRowId: json['sourceRowId'] as String?,
      localId: json['localId'] as int?,
      serverId: json['serverId'] as String?,
      sessionId: json['sessionId'] as String?,
      senderId: json['senderId'] as String?,
      senderName: json['senderName'] as String?,
      isSender: json['isSender']! as bool,
      messageType: json['messageType'] as String?,
      content: json['content'] as String?,
      createTime: json['createTime'] as int?,
      datetimeText: json['datetimeText'] as String?,
      contentDataJson: json['contentDataJson'] as String?,
      mediaArchivePath: json['mediaArchivePath'] as String?,
      mediaType: json['mediaType'] as String?,
      mediaName: json['mediaName'] as String?,
      mediaError: json['mediaError'] as String?,
      mediaAvailable: json['mediaAvailable']! as bool,
      mediaSha256: json['mediaSha256'] as String?,
      mediaLocalPath: json['mediaLocalPath'] as String?,
      mediaByteSize: json['mediaByteSize'] as int?,
    );
  }
}

String? _nonEmptyString(Object? value) {
  if (value == null) return null;
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

int? _asInt(Object? value) {
  return switch (value) {
    int intValue => intValue,
    num numValue => numValue.toInt(),
    String stringValue => int.tryParse(stringValue),
    _ => null,
  };
}

bool _isMessagesJsPath(String value) {
  final normalized = _normalizeArchivePath(value).toLowerCase();
  return normalized == 'data/messages.js' ||
      normalized.endsWith('/data/messages.js');
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

String _normalizeArchivePath(String value) {
  return value
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^\./+'), '')
      .replaceAll(RegExp(r'/+'), '/');
}
