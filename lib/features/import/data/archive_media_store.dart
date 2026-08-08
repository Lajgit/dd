import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

class StoredArchiveMedia {
  const StoredArchiveMedia({
    required this.sha256,
    required this.localPath,
    required this.byteSize,
    required this.wasAlreadyStored,
  });

  final String sha256;
  final String localPath;
  final int byteSize;
  final bool wasAlreadyStored;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sha256': sha256,
        'localPath': localPath,
        'byteSize': byteSize,
        'wasAlreadyStored': wasAlreadyStored,
      };

  factory StoredArchiveMedia.fromJson(Map<String, dynamic> json) {
    return StoredArchiveMedia(
      sha256: json['sha256']! as String,
      localPath: json['localPath']! as String,
      byteSize: json['byteSize']! as int,
      wasAlreadyStored: json['wasAlreadyStored']! as bool,
    );
  }
}

class ArchiveMediaStore {
  const ArchiveMediaStore();

  Future<StoredArchiveMedia> store({
    required ArchiveFile archiveFile,
    required String storageRoot,
  }) async {
    final mediaRoot = Directory(path.join(storageRoot, 'media'))
      ..createSync(recursive: true);
    final tempRoot = Directory(path.join(storageRoot, 'tmp'))
      ..createSync(recursive: true);
    final tempPath = path.join(
      tempRoot.path,
      '.${DateTime.now().microsecondsSinceEpoch}-${archiveFile.name.hashCode.abs()}.part',
    );
    final tempFile = File(tempPath);

    try {
      final output = OutputFileStream(tempPath);
      try {
        // ZIP 条目直接流式解压到临时文件，避免把大图片或视频整体放进 Dart 内存。
        archiveFile.writeContent(output);
      } finally {
        output.closeSync();
      }

      final digest = (await sha256.bind(tempFile.openRead()).first).toString();
      final targetDirectory = Directory(
        path.join(mediaRoot.path, digest.substring(0, 2)),
      )..createSync(recursive: true);
      final targetFile = File(path.join(targetDirectory.path, digest));
      final byteSize = tempFile.lengthSync();
      final wasAlreadyStored = targetFile.existsSync();

      if (wasAlreadyStored) {
        tempFile.deleteSync();
      } else {
        tempFile.renameSync(targetFile.path);
      }

      return StoredArchiveMedia(
        sha256: digest,
        localPath: targetFile.path,
        byteSize: byteSize,
        wasAlreadyStored: wasAlreadyStored,
      );
    } catch (_) {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
      rethrow;
    }
  }
}
