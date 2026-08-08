import 'dart:convert';

import '../model/wechat_archive_models.dart';

class MessagesJsParser {
  const MessagesJsParser();

  WechatExportArchive parse(String source) {
    final assignmentIndex = source.indexOf('=');
    if (assignmentIndex < 0) {
      throw const FormatException('messages.js 格式无法识别：缺少赋值符号');
    }

    final jsonSource = source
        .substring(assignmentIndex + 1)
        .trim()
        .replaceFirst(RegExp(r';\s*$'), '');

    final decoded = jsonDecode(jsonSource);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('messages.js 根节点不是对象');
    }

    final rawMessages = decoded['messages'];
    if (rawMessages is! List) {
      throw const FormatException('messages.js 缺少 messages 数组');
    }

    final messages = <Map<String, dynamic>>[];
    for (var index = 0; index < rawMessages.length; index += 1) {
      final rawMessage = rawMessages[index];
      if (rawMessage is! Map) {
        throw FormatException('messages[$index] 不是对象');
      }
      messages.add(Map<String, dynamic>.from(rawMessage));
    }

    final versionValue = decoded['version'];
    final version = versionValue is num ? versionValue.toInt() : null;
    final name = _resolveArchiveName(decoded);

    return WechatExportArchive(
      name: name,
      version: version,
      messages: messages,
    );
  }

  String _resolveArchiveName(Map<String, dynamic> decoded) {
    final name = decoded['name'];
    if (name is String && name.trim().isNotEmpty) {
      return name.trim();
    }

    final conversations = decoded['conversations'];
    if (conversations is List && conversations.length == 1) {
      final conversation = conversations.first;
      if (conversation is Map) {
        final conversationName = conversation['name'];
        if (conversationName is String && conversationName.trim().isNotEmpty) {
          return conversationName.trim();
        }
      }
    }

    return '微信聊天档案';
  }
}
