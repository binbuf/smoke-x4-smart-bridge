/// What a `/cooks` row is made of, and how the list is grouped (16 §16.6,
/// newapp §C.3).
///
/// Two things live here that [CookRepository] deliberately does not carry,
/// because both are presentation decisions rather than facts about a cook:
///
///  * the **sparkline and the probe count**, read in one bucketed aggregate so
///    a 54-day list costs the same to draw as a one-cook list and no row ever
///    materialises a sample — the same discipline `SampleDao.sparkline` applies
///    to a device session, applied to a wall-clock cook;
///  * the **grouping** — "recording now", "today", "this week", "earlier" — a
///    pure function over plain values, so the whole matrix is testable with no
///    database and no widget behind it.
///
/// Flutter-free on purpose. The list *view* is stateless over what this file
/// produces, which is what lets a golden or a widget test render the real list
/// without a repository.
library;

import 'package:drift/drift.dart' show Variable;

import '../../data/local/database.dart';
import '../../data/repos/cook_repository.dart';
import '../../domain/plan/plan.dart';

/// One row's data: the cook, its aggregate numbers, and its mark.
class CookListRow {
  const CookListRow({
    required this.entry,
    this.spark = const CookSparkline(),
  });

  final CookListEntry entry;
  final CookSparkline spark;

  CookAnnotation get cook => entry.cook;
  CookSummary get summary => entry.summary;
}

/// The bucketed line under a row, and how many jacks ever reported inside it.
class CookSparkline {
  const CookSparkline({this.points = const [], this.probeCount = 0});

  /// `(t, °F)` pairs, at most `points` of them. Empty when nothing in this
  /// cook's span ever read — and an empty sparkline is **drawn as nothing**,
  /// never as a flat line, because a flat line is a claim.
  final List<({int t, double f})> points;

  /// Jacks that reported at least once. **Zero means none did**, and the row
  /// says so in words rather than rendering "0 probes".
  final int probeCount;

  bool get hasLine => points.length > 2;
}

/// Where a cook sits in the list.
///
/// Five buckets, at most three of which are ever on screen at once. They exist
/// so the list reads as a history rather than as an undifferentiated stack —
/// and so the open cook is never something you have to go looking for.
enum CookGroup {
  scheduled,
  running,
  today,
  thisWeek,
  earlier;

  /// Rendered as-is by the section label, which the type scale assumes is
  /// already upper case (§16.5).
  String get label => switch (this) {
    CookGroup.scheduled => 'SCHEDULED',
    CookGroup.running => 'RECORDING NOW',
    CookGroup.today => 'TODAY',
    CookGroup.thisWeek => 'THIS WEEK',
    CookGroup.earlier => 'EARLIER',
  };
}

/// One labelled run of rows.
class CookSection {
  const CookSection({required this.group, required this.rows});

  final CookGroup group;
  final List<CookListRow> rows;
}

/// Bucket and order the list.
///
/// Scheduled cooks come first and read **forwards** (the soonest one is next);
/// everything else reads backwards from now, which is the order a history is
/// actually scanned in. Empty buckets do not render a label.
List<CookSection> groupCooks(
  List<CookListRow> rows, {
  required int nowUnixMs,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(nowUnixMs);
  final startOfToday = DateTime(
    now.year,
    now.month,
    now.day,
  ).millisecondsSinceEpoch;
  // "This week" is today and the six days before it — a rolling window, not an
  // ISO week, because nobody thinks of a Sunday brisket as last week's.
  const dayMs = 24 * 60 * 60 * 1000;
  final startOfWeek = startOfToday - 6 * dayMs;

  final buckets = <CookGroup, List<CookListRow>>{};
  for (final row in rows) {
    final cook = row.cook;
    final group = switch (cook.statusAt(nowUnixMs)) {
      CookStatus.scheduled => CookGroup.scheduled,
      CookStatus.running => CookGroup.running,
      CookStatus.finished => cook.startUnixMs >= startOfToday
          ? CookGroup.today
          : cook.startUnixMs >= startOfWeek
          ? CookGroup.thisWeek
          : CookGroup.earlier,
    };
    buckets.putIfAbsent(group, () => []).add(row);
  }

  final out = <CookSection>[];
  for (final group in CookGroup.values) {
    final rows = buckets[group];
    if (rows == null || rows.isEmpty) {
      continue;
    }
    rows.sort(
      group == CookGroup.scheduled
          ? (a, b) => a.cook.startUnixMs.compareTo(b.cook.startUnixMs)
          : (a, b) => b.cook.startUnixMs.compareTo(a.cook.startUnixMs),
    );
    out.add(CookSection(group: group, rows: rows));
  }
  return out;
}

/// The row's mark and probe count, in one aggregate query.
///
/// Bucketed in SQL to at most [points] values, so the cost of a row is the
/// cost of the aggregate and not the cost of the cook. The probe count rides
/// along in the same pass — four `MAX(pN IS NOT NULL)` columns OR-ed together
/// in Dart across the buckets — rather than costing a second scan of the same
/// range.
///
/// A cook pinned to one device session by [CookAnnotation.anchorSessionId] (a
/// bridge whose clock was never set) groups on the session-relative `t`; every
/// other cook groups on wall clock, so a cook that spans two device sessions —
/// where `t` restarts from zero — still draws left to right.
Future<CookSparkline> loadCookSparkline(
  AppDatabase db,
  CookAnnotation cook, {
  required CookSummary summary,
  int points = 48,
}) async {
  final lo = summary.minT;
  final hi = summary.maxT;
  if (lo == null || hi == null || summary.count == 0) {
    return const CookSparkline();
  }
  final anchor = cook.anchorSessionId;
  final slots = points < 2 ? 2 : points;

  final String where;
  final List<Variable<Object>> scope;
  final String bucketExpr;
  final String xExpr;
  final int bucket;
  if (anchor != null) {
    where = 'bridge_id = ? AND session_id = ?';
    scope = [Variable<String>(cook.bridgeId), Variable<int>(anchor)];
    bucketExpr = 't / ?';
    xExpr = 'MIN(t) AS x';
    bucket = ((hi - lo) / slots).ceil().clamp(1, 1 << 30);
  } else {
    where =
        'bridge_id = ? AND unix_ms IS NOT NULL AND unix_ms >= ? '
        'AND unix_ms < ?';
    scope = [
      Variable<String>(cook.bridgeId),
      Variable<int>(cook.startUnixMs),
      Variable<int>(cook.endUnixMs ?? 0x7fffffffffffff),
    ];
    bucketExpr = 'unix_ms / ?';
    // Seconds, so the axis is an int the painter can subtract without
    // losing precision on a millisecond epoch.
    xExpr = 'MIN(unix_ms) / 1000 AS x';
    bucket = (((hi - lo) * 1000) / slots).ceil().clamp(1, 1 << 30);
  }

  final rows = await db
      .customSelect(
        'SELECT $xExpr, AVG(COALESCE(p1, p2, p3, p4)) AS v, '
        'MAX(p1 IS NOT NULL) AS a1, MAX(p2 IS NOT NULL) AS a2, '
        'MAX(p3 IS NOT NULL) AS a3, MAX(p4 IS NOT NULL) AS a4 '
        'FROM samples WHERE $where '
        'GROUP BY $bucketExpr ORDER BY $bucketExpr',
        variables: [...scope, Variable<int>(bucket), Variable<int>(bucket)],
        readsFrom: {db.samples},
      )
      .get();

  final line = <({int t, double f})>[];
  var attached = 0;
  for (final row in rows) {
    final v = row.read<double?>('v');
    if (v != null) {
      line.add((t: row.read<int>('x'), f: v / 10.0));
    }
    for (var jack = 1; jack <= 4; jack++) {
      if ((row.read<int?>('a$jack') ?? 0) != 0) {
        attached |= 1 << (jack - 1);
      }
    }
  }
  var probeCount = 0;
  for (var bit = 0; bit < 4; bit++) {
    if (attached & (1 << bit) != 0) {
      probeCount++;
    }
  }
  return CookSparkline(points: line, probeCount: probeCount);
}
