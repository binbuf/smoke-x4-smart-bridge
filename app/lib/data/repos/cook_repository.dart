/// The cook-annotation repository (newapp §D.1–§D.3, §D.6, §C.4).
///
/// The verbs a user reaches for — start one, name it, move its start, split it,
/// merge it, repeat it, delete it — over the `Cooks`/`CookProbeRoles` tables.
///
/// **Every one of them is a metadata write.** Nothing in this class inserts,
/// moves or deletes a sample row, and the two places that is load-bearing are
/// worth naming: [deleteCook] must not stop the recording (the cost sheet
/// promises it does not), and [backdate] must not rewrite sample keys (which is
/// what makes it instant on an eighteen-hour cook rather than a progress bar).
///
/// Wall clock is injected. Cook boundaries are the one place in this app where
/// the *phone's* clock is authoritative rather than the device's, because a
/// cook is the user's annotation and "now" means the moment they tapped —
/// §E.7's rule is about never rewriting the device's `t`, and nothing here does.
library;

import 'package:drift/drift.dart' show OrderingTerm;

import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../local/database.dart';

/// A cook plus the numbers its list row needs, so the list never loads samples.
class CookListEntry {
  const CookListEntry({
    required this.cook,
    required this.summary,
    this.status = CookStatus.finished,
  });

  final CookAnnotation cook;
  final CookSummary summary;
  final CookStatus status;
}

class CookRepository {
  CookRepository(this.db, {required this.bridgeId, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase db;
  final String bridgeId;
  final DateTime Function() _now;

  int get _nowMs => _now().millisecondsSinceEpoch;

  // ── reads ────────────────────────────────────────────────────────────

  Future<List<CookAnnotation>> cooks() => db.cookDao.forBridge(bridgeId);

  /// Watches the table, so a cook created by the background monitor or by a
  /// split shows up without a relaunch.
  Stream<List<CookAnnotation>> watchCooks() =>
      db.cookDao.watchForBridge(bridgeId);

  Future<CookAnnotation?> cook(int id) => db.cookDao.byId(id);

  Future<CookAnnotation?> running() => db.cookDao.running(bridgeId, _nowMs);

  Future<List<Sample>> samplesFor(CookAnnotation cook) =>
      db.cookDao.samplesFor(cook);

  Future<CookSummary> summaryFor(CookAnnotation cook) =>
      db.cookDao.summaryFor(cook);

  /// Wall clock at `t = 0` for the samples [cook] covers — the origin the
  /// chart's axis, the mark times, the gap times and the CSV all measure from.
  ///
  /// Read from the **session**, never inferred from the first sample inside the
  /// cook. `startUnixMs − first.t × 1000` is only right when a reading happens
  /// to land exactly on the cook's start; backdate a cook to before any reading
  /// — §D.3.1's own headline case — and every clock time on the screen and
  /// every timestamp in the export slides by the width of that hole.
  ///
  /// Null when the bridge had no clock. Callers render elapsed time then,
  /// rather than an epoch date dressed up as a wall clock (§E.7).
  Future<int?> originFor(CookAnnotation cook) async =>
      (await _sessionAround(cook))?.startedUnixMs;

  /// The list, with each row's header numbers. One query per cook rather than
  /// one per sample — see [CookDao.summaryFor].
  Future<List<CookListEntry>> listEntries() async {
    final all = await cooks();
    final now = _nowMs;
    return [
      for (final c in all)
        CookListEntry(
          cook: c,
          summary: await summaryFor(c),
          status: c.statusAt(now),
        ),
    ];
  }

  // ── the verbs ────────────────────────────────────────────────────────

  /// Start a cook from a plan. Its start is the plan's own if one was set
  /// (a scheduled or backdated cook), otherwise now.
  Future<CookAnnotation> startFromPlan(CookPlan plan) async {
    final draft = CookAnnotation.fromPlan(
      plan,
      bridgeId: bridgeId,
      nowUnixMs: _nowMs,
      id: plan.cookId ?? 0,
    );
    final id = await db.cookDao.save(draft);
    plan.cookId = id;
    return draft.copyWith(id: id);
  }

  /// §D.3.1 — "actually, it started earlier". Metadata only.
  Future<CookAnnotation> backdate(CookAnnotation cook, int newStartUnixMs) =>
      _persist(cook.backdatedTo(newStartUnixMs));

  Future<CookAnnotation> rename(CookAnnotation cook, String name) =>
      _persist(cook.copyWith(name: name));

  Future<CookAnnotation> setNotes(CookAnnotation cook, String notes) =>
      _persist(cook.copyWith(notes: notes));

  Future<CookAnnotation> setFavourite(CookAnnotation cook, bool value) =>
      _persist(cook.copyWith(favourite: value));

  /// §D.3.2 — set (or change) what a cook is aiming at, on a cook that may
  /// already be running.
  ///
  /// [next] is the whole annotation the setup sheet projects, not just its
  /// roles: the preset, the doneness, the hazard class, the safety mode and the
  /// pit band all come back with it, and all of them are targets. See
  /// [CookAnnotation.retargetedTo] for what is taken and what is kept.
  ///
  /// Goes through [CookAnnotation.toPlan] first so the food-safety gate refuses
  /// an unsafe retarget exactly as it would refuse a new plan — and refuses it
  /// before anything is written.
  Future<CookAnnotation> retarget(
    CookAnnotation cook,
    CookAnnotation next,
  ) async {
    final merged = cook.retargetedTo(next);
    merged.toPlan(); // throws ArgumentError on an unsafe target
    return _persist(merged);
  }

  /// §D.5 — the user says they took it off the heat. The one input the phase
  /// engine cannot derive.
  Future<CookAnnotation> markPulled(CookAnnotation cook, {int? atUnixMs}) =>
      _persist(cook.copyWith(pulledAtUnixMs: atUnixMs ?? _nowMs));

  /// End the annotation. The bridge keeps recording — that is the whole point,
  /// and the cost sheet says so.
  Future<CookAnnotation> end(CookAnnotation cook, {int? atUnixMs}) =>
      _persist(cook.copyWith(endUnixMs: atUnixMs ?? _nowMs));

  /// Reopen a cook that was ended by mistake.
  Future<CookAnnotation> reopen(CookAnnotation cook) =>
      _persist(cook.copyWith(clearEnd: true));

  /// §C.4 — split at a time, returning both halves with real ids.
  Future<(CookAnnotation, CookAnnotation)> split(
    CookAnnotation cook,
    int atUnixMs,
  ) async {
    final (before, after) = cook.splitAt(atUnixMs);
    final savedBefore = await _persist(before);
    final afterId = await db.cookDao.save(after);
    return (savedBefore, after.copyWith(id: afterId));
  }

  /// §C.4 — merge two cooks into the earlier one and delete the later row.
  ///
  /// **The returned cook is the survivor, and its id is not always the id you
  /// passed first.** Merging with the *earlier* neighbour keeps that cook's row
  /// and deletes this one, so a caller holding an id — a route loading by
  /// `/cooks/:id` — has to follow the id on the way back out. One that keeps
  /// re-reading its old id finds nothing and reports the cook missing at the
  /// exact moment the merge succeeded.
  Future<CookAnnotation> merge(CookAnnotation a, CookAnnotation b) async {
    final merged = a.mergedWith(b);
    final loser = merged.id == a.id ? b : a;
    final saved = await _persist(merged);
    await db.cookDao.deleteCook(loser.id);
    return saved;
  }

  /// §D.6 — "Repeat this cook".
  Future<CookAnnotation> repeat(CookAnnotation cook, {int? atUnixMs}) async {
    final draft = cook.repeatAt(atUnixMs ?? _nowMs);
    final id = await db.cookDao.save(draft);
    return draft.copyWith(id: id);
  }

  /// Deletes the **annotation**, never the readings.
  Future<void> deleteCook(int id) => db.cookDao.deleteCook(id);

  // ── retroactive start (§D.3.1) ───────────────────────────────────────

  /// Candidate start times for [cook], read off the recording it sits over.
  ///
  /// Looks a window *before* the cook's current start as well as inside it,
  /// because the whole point is to find the moment the meat went on — which is
  /// usually earlier than the moment somebody opened the app.
  Future<List<CookAnchor>> anchorsFor(
    CookAnnotation cook, {
    Duration lookBack = const Duration(hours: 6),
    int limit = 6,
  }) async {
    final session = await _sessionAround(cook);
    if (session == null) {
      return const [];
    }
    final start = session.startedUnixMs;
    if (start == null) {
      return const [];
    }
    final fromT = (((cook.startUnixMs - lookBack.inMilliseconds) - start) /
            1000)
        .round();
    final toT = (((cook.endUnixMs ?? _nowMs) - start) / 1000).round();
    final samples = await db.sampleDao.range(
      bridgeId,
      session.sessionId,
      fromT: fromT < 0 ? 0 : fromT,
      toT: toT < 0 ? 0 : toT,
    );
    final marks = await db.markDao.forSession(bridgeId, session.sessionId);
    return candidateAnchors(
      samples: samples,
      sessionStartUnixMs: start,
      marks: marks,
      limit: limit,
    );
  }

  /// The device session whose span contains this cook's start — the one whose
  /// samples the anchors come from.
  Future<SessionRow?> _sessionAround(CookAnnotation cook) async {
    final anchor = cook.anchorSessionId;
    final rows = await (db.select(db.sessions)
          ..where((s) => s.bridgeId.equals(bridgeId))
          ..orderBy([(s) => OrderingTerm.desc(s.sessionId)]))
        .get();
    if (anchor != null) {
      return rows.where((r) => r.sessionId == anchor).firstOrNull;
    }
    for (final r in rows) {
      final start = r.startedUnixMs;
      if (start == null) {
        continue;
      }
      final end = r.endedUnixMs ?? _nowMs;
      if (cook.startUnixMs >= start && cook.startUnixMs <= end) {
        return r;
      }
    }
    // No session brackets it — fall back to the newest clocked one, which is
    // the right guess for a cook someone is creating right now.
    return rows.where((r) => r.startedUnixMs != null).firstOrNull;
  }

  Future<CookAnnotation> _persist(CookAnnotation cook) async {
    final id = await db.cookDao.save(cook);
    return cook.id == id ? cook : cook.copyWith(id: id);
  }

  // ── gaps (§E.5) ──────────────────────────────────────────────────────

  /// Every hole a cook spans, both kinds, so the chart and the statistics
  /// table can render them differently.
  Future<List<RecordedGap>> gapsFor(CookAnnotation cook) async {
    final session = await _sessionAround(cook);
    if (session == null) {
      return const [];
    }
    final recorded = await db.syncStateDao.forBridgeSession(
      bridgeId,
      session.sessionId,
    );
    // Rollovers are recorded facts; connectivity holes are also *derivable*
    // from what we hold, and deriving them keeps the chart honest even for a
    // session that was cached before gap recording existed.
    final samples = await samplesFor(cook);
    final derived = detectConnectivityGaps(
      samples,
      samplePeriodS: session.samplePeriodS,
    );
    final permanent = recorded.where((g) => g.reason.isPermanent).toList();
    return [
      ...permanent,
      // A derived hole that a recorded rollover already explains must not be
      // listed twice, and the rollover is the more informative of the two.
      for (final g in derived)
        if (!permanent.any((p) => p.fromT <= g.fromT && p.toT >= g.toT)) g,
    ]..sort((a, b) => a.fromT.compareTo(b.fromT));
  }
}
