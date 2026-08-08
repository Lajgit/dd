import 'dart:io';

import 'package:archive/archive.dart';
import 'package:diandi_memory/features/import/data/wechat_archive_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('扫描 ZIP 并统计消息与媒体资源', () {
    final tempDir = Directory.systemTemp.createTempSync('diandi-memory-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    const messagesJs = '''
window.__WECHAT_EXPORT__ = {
  "version": 2,
  "name": "梨宝",
  "messages": [
    {
      "localId": 1,
      "createTime": 1735630867,
      "type": "图片",
      "contentData": {"type":"image"},
      "exportMediaType": "image",
      "exportMediaUrl": "media/image_a.jpg"
    },
    {
      "localId": 2,
      "createTime": 1735630900,
      "type": "语音",
      "voiceDataUrl": "voices/voice_a.wav"
    },
    {
      "localId": 3,
      "createTime": 1735631000,
      "type": "文件",
      "contentData": {"type":"share","typeVal":"6"},
      "exportMediaType": "file",
      "exportMediaUrl": "files/file_a.pdf"
    }
  ]
};
''';

    final archive = Archive()
      ..add(ArchiveFile.string('梨宝_聊天档案/data/messages.js', messagesJs))
      ..add(ArchiveFile.bytes('梨宝_聊天档案/media/image_a.jpg', const [1, 2, 3]))
      ..add(ArchiveFile.bytes('梨宝_聊天档案/voices/voice_a.wav', const [4, 5, 6]));

    final zipBytes = ZipEncoder().encodeBytes(archive);
    final zipFile = File('${tempDir.path}/chat.zip')..writeAsBytesSync(zipBytes);

    final summary = const WechatArchiveScanner().scanZipSync(zipFile.path);

    expect(summary.archiveName, '梨宝');
    expect(summary.messageCount, 3);
    expect(summary.imageCount, 1);
    expect(summary.voiceCount, 1);
    expect(summary.fileCount, 1);
    expect(summary.mediaReferenceCount, 3);
    expect(summary.availableMediaCount, 2);
    expect(summary.missingMediaCount, 1);
    expect(summary.messagesJsPath, '梨宝_聊天档案/data/messages.js');
  });

  test('ZIP 中没有 messages.js 时返回格式错误', () {
    final tempDir = Directory.systemTemp.createTempSync('diandi-memory-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final archive = Archive()
      ..add(ArchiveFile.string('梨宝_聊天档案/index.html', '<html></html>'));
    final zipBytes = ZipEncoder().encodeBytes(archive);
    final zipFile = File('${tempDir.path}/invalid.zip')..writeAsBytesSync(zipBytes);

    expect(
      () => const WechatArchiveScanner().scanZipSync(zipFile.path),
      throwsA(isA<FormatException>()),
    );
  });
}
