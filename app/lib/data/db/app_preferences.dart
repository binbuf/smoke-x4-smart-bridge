import 'package:sqflite/sqflite.dart';

/// Small key/value store for local-only preferences that must survive a
/// relaunch. It deliberately holds no readings and never touches the archive.
abstract interface class AppPreferences {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// Default for review builds and tests that have no database.
class InMemoryAppPreferences implements AppPreferences {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

/// SQLite-backed preferences over the `preference` table (schema v3).
class SqliteAppPreferences implements AppPreferences {
  SqliteAppPreferences(this._database);

  final Database _database;

  @override
  Future<String?> read(String key) async {
    final rows = await _database.query(
      'preference',
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  @override
  Future<void> write(String key, String value) async {
    await _database.insert(
      'preference',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
