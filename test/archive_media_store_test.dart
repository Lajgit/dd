import 'dart:io';

import 'package:archive/archive.dart';
import 'package:diandi_memory/features/import/data/archive_media_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('相同媒体内容只保存一个 SHA-256 文件', () async {
    final tempDir = Directory.systemTemp.createTempSync('diandi-media-test-');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    const store = ArchiveMediaStore();
    final first = await store.store(
      archiveFile: ArchiveFile.bytes('media/first.jpg', const <int>[1, 2, 3, 4]),
      storageRoot: tempDir.path,
    );
    final second = await store.store(
      archiveFile: ArchiveFile.bytes('media/second.jpg', const <int>[1, 2, 3, 4]),
      storageRoot: tempDir.path,
    );

    expect(first.sha256, second.sha256);
    expect(first.localPath, second.localPath);
    expect(first.wasAlreadyStored, isFalse);
    expect(second.wasAlreadyStored, isTrue);
    expect(File(first.localPath).readAsBytesSync(), const <int>[1, 2, 3, 4]);

    final storedFiles = Directory('${tempDir.path}${Platform.pathSeparator}media')
        .listSync(recursive: true)
        .whereType<File>()
        .toList(growable: false);
    expect(storedFiles, hasLength(1));
  });
}
