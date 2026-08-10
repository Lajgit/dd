import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../model/ai_summary_models.dart';

class LocalAiModelManager {
  const LocalAiModelManager({
    this.database = AppDatabase.instance,
  });

  static const _modelPathKey = 'local_ai_model_path';
  static const _modelNameKey = 'local_ai_model_name';
  static const _modelSizeKey = 'local_ai_model_size';

  final AppDatabase database;

  Future<LocalAiModelInfo?> currentModel() async {
    final db = await database.database;
    final rows = await db.query(
      'app_settings',
      columns: const <String>['key', 'value'],
      where: 'key IN (?, ?, ?)',
      whereArgs: const <Object?>[_modelPathKey, _modelNameKey, _modelSizeKey],
    );
    final values = <String, String>{
      for (final row in rows) row['key']! as String: row['value']! as String,
    };
    final modelPath = values[_modelPathKey];
    if (modelPath == null || !File(modelPath).existsSync()) {
      return null;
    }
    return LocalAiModelInfo(
      path: modelPath,
      name: values[_modelNameKey] ?? path.basename(modelPath),
      byteSize: int.tryParse(values[_modelSizeKey] ?? '') ?? File(modelPath).lengthSync(),
    );
  }

  Future<LocalAiModelInfo> importModel(
    String sourcePath, {
    void Function(double progress)? onProgress,
  }) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw FileSystemException('GGUF 模型文件不存在', sourcePath);
    }
    if (path.extension(sourcePath).toLowerCase() != '.gguf') {
      throw const FormatException('请选择 .gguf 本地模型文件');
    }

    final previous = await currentModel();
    final totalBytes = source.lengthSync();
    final modified = source.lastModifiedSync().millisecondsSinceEpoch;
    final storageRoot = await database.storageRootPath();
    final modelDirectory = Directory(path.join(storageRoot, 'models'))
      ..createSync(recursive: true);
    final targetPath = path.join(
      modelDirectory.path,
      'local_summary_${totalBytes}_$modified.gguf',
    );
    final tempPath = '$targetPath.part';
    final tempFile = File(tempPath);
    if (tempFile.existsSync()) tempFile.deleteSync();

    final sink = tempFile.openWrite();
    var copiedBytes = 0;
    var sinkClosed = false;
    var lastReportedPercent = -1;
    try {
      // 大模型按块复制到 App 私有目录，避免 1GB 级 GGUF 整体进入 Dart 内存。
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        copiedBytes += chunk.length;
        if (totalBytes > 0) {
          var percent = copiedBytes * 100 ~/ totalBytes;
          if (percent > 100) percent = 100;
          if (percent != lastReportedPercent) {
            lastReportedPercent = percent;
            onProgress?.call(percent / 100);
          }
        }
      }
      await sink.flush();
      await sink.close();
      sinkClosed = true;
    } catch (_) {
      if (!sinkClosed) await sink.close();
      if (tempFile.existsSync()) tempFile.deleteSync();
      rethrow;
    }

    final target = File(targetPath);
    if (target.existsSync()) target.deleteSync();
    tempFile.renameSync(targetPath);

    final info = LocalAiModelInfo(
      path: targetPath,
      name: path.basename(sourcePath),
      byteSize: totalBytes,
    );
    await _saveModelInfo(info);

    final previousPath = previous?.path;
    if (previousPath != null && previousPath != targetPath) {
      try {
        final previousFile = File(previousPath);
        if (previousFile.existsSync()) previousFile.deleteSync();
      } catch (_) {
        // 旧模型可能仍被 native mmap 使用；删除失败不影响新模型启用，下次可继续覆盖。
      }
    }
    return info;
  }

  Future<void> _saveModelInfo(LocalAiModelInfo info) async {
    final db = await database.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((transaction) async {
      await _upsertSetting(transaction, _modelPathKey, info.path, now);
      await _upsertSetting(transaction, _modelNameKey, info.name, now);
      await _upsertSetting(transaction, _modelSizeKey, '${info.byteSize}', now);
    });
  }

  Future<void> _upsertSetting(
    Transaction transaction,
    String key,
    String value,
    int now,
  ) async {
    await transaction.insert(
      'app_settings',
      <String, Object?>{'key': key, 'value': value, 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
