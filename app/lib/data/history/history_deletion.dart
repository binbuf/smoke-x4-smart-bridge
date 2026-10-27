import '../db/sample_dao.dart';

/// The three explicit phone-history deletion choices from 04 §4.8 / T44.
enum HistoryDeletionScope { olderThan30Days, olderThan90Days, all }

extension HistoryDeletionScopeX on HistoryDeletionScope {
  /// How old a reading must be to be removed. `null` means every reading.
  Duration? get age => switch (this) {
    HistoryDeletionScope.olderThan30Days => const Duration(days: 30),
    HistoryDeletionScope.olderThan90Days => const Duration(days: 90),
    HistoryDeletionScope.all => null,
  };

  String get label => switch (this) {
    HistoryDeletionScope.olderThan30Days => 'Older than 30 days',
    HistoryDeletionScope.olderThan90Days => 'Older than 90 days',
    HistoryDeletionScope.all => 'All history on this phone',
  };
}

/// A counted deletion plan. The UI shows this exact count and reading span
/// before the user confirms; [HistoryDeletionService.delete] uses the same
/// range, so a later clock tick cannot silently widen the loss.
class HistoryDeletionPlan {
  const HistoryDeletionPlan({
    required this.scope,
    required this.fromMs,
    required this.toMs,
    required this.count,
    this.firstReadingMs,
    this.lastReadingMs,
    this.rangeLabelOverride,
  });

  final HistoryDeletionScope scope;

  /// Half-open deletion range, following [SampleDao.deleteRange].
  final int fromMs;
  final int toMs;

  /// Number of readings in the range when this plan was made.
  final int count;

  /// Actual first/last reading that will be removed; null when [count] is zero.
  final int? firstReadingMs;
  final int? lastReadingMs;

  /// Review-build copy only. Production always formats the real reading span.
  final String? rangeLabelOverride;

  bool get isEmpty => count <= 0;

  DateTime? get firstReadingAt => firstReadingMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(firstReadingMs!);

  DateTime? get lastReadingAt => lastReadingMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastReadingMs!);
}

/// What a confirmed phone deletion did. [deletion] is all zeroes when the plan
/// was empty: an empty plan never issues a delete.
class HistoryDeletionOutcome {
  const HistoryDeletionOutcome({required this.plan, required this.deletion});

  final HistoryDeletionPlan plan;
  final HistoryDeletion deletion;

  int get samplesDeleted => deletion.samplesDeleted;
  int get gapsAffected => deletion.gapsAffected;
}

/// Builds counted deletion plans and applies exactly those plans.
///
/// The service has no timer and no caller other than an explicit user action.
/// Nothing in this class deletes on launch, sync, generation change or storage
/// pressure.
class HistoryDeletionService {
  HistoryDeletionService({required this.dao, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SampleDao dao;
  final DateTime Function() _now;

  /// Upper bound for "All history on this phone". `deleteRange` is half-open.
  static const int allHistoryFromMs = 0;
  static const int allHistoryToMs = 0x7FFFFFFFFFFFFFFF;

  static const HistoryDeletion _nothingDeleted = HistoryDeletion(
    samplesDeleted: 0,
    gapsDeleted: 0,
    gapsTrimmed: 0,
  );

  /// Counts the readings that [scope] would remove at the current wall clock.
  ///
  /// `Older than 30/90 days` is strictly older: a reading exactly on the
  /// cutoff is kept. The phone copy spans every saved Bridge and generation,
  /// because "history on this phone" is one local copy.
  Future<HistoryDeletionPlan> plan(HistoryDeletionScope scope) async {
    final nowMs = _now().millisecondsSinceEpoch;
    final age = scope.age;
    final fromMs = allHistoryFromMs;
    final toMs = age == null ? allHistoryToMs : nowMs - age.inMilliseconds;
    if (toMs <= fromMs) {
      return HistoryDeletionPlan(
        scope: scope,
        fromMs: fromMs,
        toMs: toMs,
        count: 0,
      );
    }

    final count = await dao.countSamples(fromMs: fromMs, toMs: toMs);
    if (count == 0) {
      return HistoryDeletionPlan(
        scope: scope,
        fromMs: fromMs,
        toMs: toMs,
        count: 0,
      );
    }

    final first = await dao.samplesInRange(
      fromMs: fromMs,
      toMs: toMs,
      limit: 1,
      ascending: true,
    );
    final last = await dao.samplesInRange(
      fromMs: fromMs,
      toMs: toMs,
      limit: 1,
      ascending: false,
    );
    return HistoryDeletionPlan(
      scope: scope,
      fromMs: fromMs,
      toMs: toMs,
      count: count,
      firstReadingMs: first.isEmpty ? null : first.single.recordedMs,
      lastReadingMs: last.isEmpty ? null : last.single.recordedMs,
    );
  }

  /// Deletes exactly [plan]'s range. Gap rows detected inside the range and
  /// gap rows overlapping the deleted sequence extent are removed or trimmed by
  /// the DAO. Local sync cursors are reconciled afterwards so they never point
  /// at a deleted row.
  Future<HistoryDeletionOutcome> delete(HistoryDeletionPlan plan) async {
    if (plan.isEmpty) {
      return HistoryDeletionOutcome(plan: plan, deletion: _nothingDeleted);
    }
    final deletion = await dao.deleteRange(
      fromMs: plan.fromMs,
      toMs: plan.toMs,
    );
    await _reconcileCursors();
    return HistoryDeletionOutcome(plan: plan, deletion: deletion);
  }

  /// A phone deletion creates a local hole. Cursors describe the current
  /// generation only; if its rows are gone they are cleared so the next sync
  /// re-fetches it. Old generations remain untouched and readable.
  Future<void> _reconcileCursors() async {
    final saved = await dao.savedBridge();
    if (saved == null) return;
    final extent = await dao.extent(
      bridgeId: saved.id,
      generation: saved.generation,
    );
    await dao.updateSyncCursors(
      bridgeId: saved.id,
      generation: saved.generation,
      cursorAfter: extent?.maxSeq,
      cursorBefore: extent?.minSeq,
      deviceMinSeq: saved.deviceMinSeq,
      deviceMaxSeq: saved.deviceMaxSeq,
      lastSeenMs: saved.lastSeenMs,
    );
  }
}
