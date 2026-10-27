import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the application's SQLite file, schema and migrations.
///
/// Version 1 was the empty open path introduced by T05. Version 2 adds the
/// durable archive fixed by 04 §4.7: the `bridge`, `sample` and `gap` tables.
/// Both a fresh file and a version-1 development install open at the same
/// schema; an existing archive is never dropped or recreated.
class AppDatabase {
  AppDatabase._(this.database, this.path);

  /// Schema version written by this open path.
  ///
  /// - 1: empty database (T05 open path)
  /// - 2: `bridge`, `sample`, `sample_time` and `gap` (T40)
  static const int schemaVersion = 2;

  /// The default on-phone file name.
  static const String fileName = 'smoke_bridge.db';

  final Database database;
  final String path;

  /// Opens the on-phone database, creating the containing directory if needed.
  ///
  /// [factory] and [databasePath] are injection seams for host tests; production
  /// uses the platform factory and `getDatabasesPath()`.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? databasePath,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final path =
        databasePath ?? p.join(await dbFactory.getDatabasesPath(), fileName);
    final database = await dbFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return AppDatabase._(database, path);
  }

  /// Opens an in-memory database through [factory]. Host tests pass an FFI
  /// factory here; device code should use [open].
  static Future<AppDatabase> openInMemory({DatabaseFactory? factory}) async {
    final dbFactory = factory ?? databaseFactory;
    final database = await dbFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return AppDatabase._(database, inMemoryDatabasePath);
  }

  Future<void> close() => database.close();

  static Future<void> _onCreate(Database db, int version) async {
    await _applyMigrations(db, 0, version);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await _applyMigrations(db, oldVersion, newVersion);
  }

  /// Forward-only migrations. Each block is safe to run on the schema produced
  /// by every earlier version.
  static Future<void> _applyMigrations(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2 && newVersion >= 2) {
      for (final statement in _schemaV2) {
        await db.execute(statement);
      }
    }
  }

  /// The exact schema from 04 §4.7. Do not reorder or weaken the keys: the
  /// primary keys are what make re-sync idempotent.
  static const List<String> _schemaV2 = <String>[
    '''
    CREATE TABLE IF NOT EXISTS bridge (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      last_seen_ms INTEGER NOT NULL,
      generation INTEGER NOT NULL,
      cursor_after INTEGER,
      cursor_before INTEGER,
      device_min_seq INTEGER,
      device_max_seq INTEGER
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS sample (
      bridge_id TEXT NOT NULL,
      generation INTEGER NOT NULL,
      seq INTEGER NOT NULL,
      unix_s INTEGER,
      recorded_ms INTEGER NOT NULL,
      time_estimated INTEGER NOT NULL,
      p1 INTEGER,
      p2 INTEGER,
      p3 INTEGER,
      p4 INTEGER,
      flags INTEGER NOT NULL,
      PRIMARY KEY (bridge_id, generation, seq)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS sample_time ON sample(bridge_id, recorded_ms)',
    '''
    CREATE TABLE IF NOT EXISTS gap (
      bridge_id TEXT NOT NULL,
      generation INTEGER NOT NULL,
      from_seq INTEGER NOT NULL,
      to_seq INTEGER NOT NULL,
      reason TEXT NOT NULL,
      detected_ms INTEGER NOT NULL,
      PRIMARY KEY (bridge_id, generation, from_seq)
    )
    ''',
  ];
}
