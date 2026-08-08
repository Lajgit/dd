import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  const AppDatabase._();

  static const AppDatabase instance = AppDatabase._();

  static const _databaseName = 'diandi_memory.db';
  static const _databaseVersion = 1;

  static Database? _database;

  Future<Database> get database async {
    return _database ??= await _openDatabase();
  }

  Future<String> storageRootPath() async {
    final databaseRoot = await getDatabasesPath();
    final storageRoot = path.join(databaseRoot, 'diandi_memory_store');
    await Directory(storageRoot).create(recursive: true);
    return storageRoot;
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  Future<Database> _openDatabase() async {
    final databaseRoot = await getDatabasesPath();
    final databasePath = path.join(databaseRoot, _databaseName);

    return openDatabase(
      databasePath,
      version: _databaseVersion,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
    );
  }

  Future<void> _createSchema(Database database, int version) async {
    // 原始导入来源单独记录，后续增量导入可以追溯每次 WechatExplorer 档案。
    await database.execute('''
CREATE TABLE import_sources (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_type TEXT NOT NULL,
  source_fingerprint TEXT NOT NULL UNIQUE,
  source_file_name TEXT NOT NULL,
  archive_name TEXT NOT NULL,
  archive_version INTEGER,
  messages_js_path TEXT NOT NULL,
  raw_messages_path TEXT NOT NULL,
  archive_message_count INTEGER NOT NULL,
  inserted_message_count INTEGER NOT NULL DEFAULT 0,
  media_reference_count INTEGER NOT NULL DEFAULT 0,
  missing_media_count INTEGER NOT NULL DEFAULT 0,
  imported_at INTEGER NOT NULL
)
''');

    await database.execute('''
CREATE TABLE participants (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sender_id TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  is_self INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
)
''');

    await database.execute('''
CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_message_key TEXT NOT NULL UNIQUE,
  first_source_id INTEGER NOT NULL,
  participant_id INTEGER,
  source_row_id TEXT,
  local_id INTEGER,
  server_id TEXT,
  session_id TEXT,
  sender_id TEXT,
  sender_name TEXT,
  is_sender INTEGER NOT NULL DEFAULT 0,
  message_type TEXT,
  content TEXT,
  create_time INTEGER,
  datetime_text TEXT,
  content_data_json TEXT,
  imported_at INTEGER NOT NULL,
  FOREIGN KEY(first_source_id) REFERENCES import_sources(id),
  FOREIGN KEY(participant_id) REFERENCES participants(id)
)
''');

    await database.execute(
      'CREATE INDEX messages_create_time_idx ON messages(create_time)',
    );
    await database.execute(
      'CREATE INDEX messages_session_id_idx ON messages(session_id)',
    );

    // media 表从第一版就保留 SHA-256 唯一键；下一小阶段复制媒体时直接复用该结构。
    await database.execute('''
CREATE TABLE media (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sha256 TEXT NOT NULL UNIQUE,
  local_path TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  media_type TEXT,
  display_name TEXT,
  created_at INTEGER NOT NULL
)
''');

    await database.execute('''
CREATE TABLE message_media (
  message_id INTEGER NOT NULL,
  source_id INTEGER NOT NULL,
  media_id INTEGER,
  archive_path TEXT NOT NULL,
  media_type TEXT,
  display_name TEXT,
  status TEXT NOT NULL,
  media_error TEXT,
  PRIMARY KEY(message_id, source_id, archive_path),
  FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE,
  FOREIGN KEY(source_id) REFERENCES import_sources(id) ON DELETE CASCADE,
  FOREIGN KEY(media_id) REFERENCES media(id)
)
''');
  }
}
