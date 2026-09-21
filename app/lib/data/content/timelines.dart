/// N2.11 — derive the expected-cook timeline for **every** catalog entry.
///
/// Ports `normalizeTimeline()`/`buildPhases()` from `newui/mock-data.js`
/// faithfully: a cut's `tl` seed wins where present, and a cut with no seed (or
/// a partial one) gets a synthesised expectation from its category, thickness
/// and pit band, so the Timeline tab always has something honest to show.
///
/// These are **estimates and must say so** (NOTES §4), exactly like the ETA and
/// rest timers in `cook_phase.dart`.
library;

import '../../domain/domain.dart';
import '../model/catalog_entry.dart';
import 'catalog_data.dart';

/// The named reviewer for the timeline table (NOTES §4; same class of data as
/// `presets.dart`).
const String kTimelineReviewer =
    'Smoke X4 product review — expected-cook timings, 2026-09';

/// Synthesise or lift the canonical [CookTimeline] for [entry].
CookTimeline normalizeTimeline(CatalogEntry entry) {
  final seed = entry.tl;
  final pitMaxF10 = entry.pitBandMaxF10;
  final low = pitMaxF10 <= 3000;
  final thick = entry.thickness == CutThickness.thick;
  final med = entry.thickness == CutThickness.medium;

  MinuteRange total;
  StallWindow? stall;
  var spritz = seed?.spritzEveryMin;
  final turn = seed?.turn;
  WrapStep? wrap;
  final rest = seed?.restMin ?? 5;

  final seededTotal = seed?.totalMin;
  if (seededTotal != null) {
    total = seededTotal;
  } else if (low) {
    total = thick
        ? const MinuteRange(240, 360)
        : med
        ? const MinuteRange(120, 210)
        : const MinuteRange(60, 120);
  } else {
    total = thick
        ? const MinuteRange(90, 150)
        : med
        ? const MinuteRange(45, 90)
        : const MinuteRange(20, 45);
  }

  final seededStall = seed?.stall;
  if (seededStall != null) {
    stall = StallWindow(
      minF10: seededStall.minF10,
      maxF10: seededStall.maxF10,
      durationMin: MinuteRange(seededStall.durMinLo, seededStall.durMinHi),
    );
  } else if (low && thick && total.min >= 240) {
    stall = const StallWindow(
      minF10: 1500,
      maxF10: 1650,
      durationMin: MinuteRange(45, 90),
    );
  }

  wrap = seed?.wrap;
  if (spritz == null && low && (thick || med) && stall == null) {
    spritz = 45;
  }

  final phases = buildPhases(entry, seed, total, stall, wrap, turn, rest);
  return CookTimeline(
    totalMin: total,
    stall: stall,
    wrap: wrap,
    spritzEveryMin: spritz,
    turn: turn,
    restMin: rest,
    phases: phases,
  );
}

/// The honest phase arc: on → (turn) → (stall) → (wrap) → pull → (rest).
List<CookPhaseSpec> buildPhases(
  CatalogEntry entry,
  TimelineSeed? seed,
  MinuteRange total,
  StallWindow? stall,
  WrapStep? wrap,
  TurnStep? turn,
  int rest,
) {
  final phases = <CookPhaseSpec>[
    CookPhaseSpec(
      id: 'on',
      label: 'On the smoker',
      note: (seed?.onNote.isNotEmpty ?? false)
          ? seed!.onNote
          : 'Set it and watch the numbers.',
    ),
  ];
  if (total.max <= 30) {
    phases.add(
      const CookPhaseSpec(
        id: 'flip',
        label: 'Flip / turn',
        note: 'Even cook on both sides.',
      ),
    );
  }
  if (stall != null) {
    phases.add(
      const CookPhaseSpec(
        id: 'stall',
        label: 'The stall',
        note: 'Evaporative plateau — normal.',
      ),
    );
  }
  if (wrap != null) {
    phases.add(CookPhaseSpec(id: 'wrap', label: wrap.label, note: wrap.note));
  }
  phases.add(
    CookPhaseSpec(
      id: 'pull',
      label: 'Pull',
      note: (seed?.pullNote.isNotEmpty ?? false)
          ? seed!.pullNote
          : 'At target, rest before serving.',
    ),
  );
  if (rest > 0) {
    phases.add(
      const CookPhaseSpec(
        id: 'rest',
        label: 'Rest',
        note: 'Let carryover finish it.',
      ),
    );
  }
  return phases;
}

/// The timeline database: one entry per catalog id, reviewer-owned.
final Map<String, CookTimeline> kTimelines = {
  for (final entry in kCatalog) entry.id: normalizeTimeline(entry),
};
