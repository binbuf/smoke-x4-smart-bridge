import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Owns the application's SQLite file and its open path.
///
/// T05 only establishes the path: opening the file, selecting the database
/// directory and exposing the [Database] handle. The `bridge`, `sample` and
/// `gap` schema plus migrations are owned by T40. Until then an existing empty
/// database is valid, and [schemaVersion] is the version T40 must migrate from.
class AppDatabase {
  AppDatabase._(this.database, this.path);

  /// Version written by this open path. Bump it in T40 when the schema lands.
  static const int schemaVersion = 1;

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
      options: OpenDatabaseOptions(version: schemaVersion),
    );
    return AppDatabase._(database, path);
  }

  /// Opens an in-memory database through [factory]. Host tests pass an FFI
  /// factory here; device code should use [open].
  static Future<AppDatabase> openInMemory({DatabaseFactory? factory}) async {
    final dbFactory = factory ?? databaseFactory;
    final database = await dbFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: schemaVersion),
    );
    return AppDatabase._(database, inMemoryDatabasePath);
  }

  Future<void> close() => database.close();
}
