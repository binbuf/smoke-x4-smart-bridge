import 'db/app_database.dart';

/// A small, immutable cache summary the shell can read at startup.
///
/// The full repository (samples, gaps, cursors and two-phase sync) is owned by
/// T41. T05 establishes only the seam so widgets and the controller never touch
/// SQLite directly.
class BridgeSnapshot {
  const BridgeSnapshot({required this.readingCount, this.lastReadingAt});

  static const BridgeSnapshot empty = BridgeSnapshot(readingCount: 0);

  final int readingCount;
  final DateTime? lastReadingAt;
}

/// The app's data seam. Implementations own all persistence; UI-facing code
/// only sees [BridgeSnapshot].
abstract interface class BridgeRepository {
  Future<BridgeSnapshot> loadSnapshot();

  Future<void> close();
}

/// Used by bootstrap/tests before a database exists. It reports no readings.
class EmptyBridgeRepository implements BridgeRepository {
  const EmptyBridgeRepository();

  @override
  Future<BridgeSnapshot> loadSnapshot() async => BridgeSnapshot.empty;

  @override
  Future<void> close() async {}
}

/// SQLite-backed repository over [AppDatabase].
///
/// The queries are deliberately tolerant of the schema not existing yet: T40
/// adds the tables and this method starts returning real counts without a
/// second wiring change.
class SqliteBridgeRepository implements BridgeRepository {
  SqliteBridgeRepository(this._database);

  final AppDatabase _database;

  @override
  Future<BridgeSnapshot> loadSnapshot() async {
    final tables = await _database.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sample'",
    );
    if (tables.isEmpty) return BridgeSnapshot.empty;

    final count = await _database.database.rawQuery(
      'SELECT COUNT(*) AS count FROM sample',
    );
    final readingCount = (count.first['count'] as int?) ?? 0;

    final newest = await _database.database.rawQuery(
      'SELECT MAX(recorded_ms) AS newest FROM sample',
    );
    final newestMs = newest.first['newest'] as int?;
    return BridgeSnapshot(
      readingCount: readingCount,
      lastReadingAt: newestMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(newestMs),
    );
  }

  @override
  Future<void> close() => _database.close();
}
