/// N8 — the Timeline screen's pure projections.
///
/// Formatting and the Gantt/upcoming/rail arithmetic only: no Flutter, no
/// repository. Kept out of the widgets so the prototype's exact projection
/// rules and the honesty rule can be unit-tested without a binding.
///
/// The rules this file holds (NOTES §4, `app.js` `viewTimeline`):
///
///  * **Gantt bar length = `totalMin` midpoint.** The bar runs from the item's
///    `addedAtMs` to `addedAtMs + mid`.
///  * **Stall band = 38–72 % of the bar; wrap tick = 55 %** — placeholder
///    fractions until real crossing data exists.
///  * **Upcoming = `wrap` + `spritzEveryMin` + `turn`, deduped and capped at
///    four.** Every intervention is optional; `autoWrapReminder` gates the
///    wrap/spritz nudges (NOTES §4.4) and the per-cook toggles (N8.10) gate
///    them individually. A cut with no wrap simply has no wrap reminder.
///  * **Event rail = actual marks ∪ predicted `phases`.** Actual events are
///    past tense; predicted ones always carry the word **expected** (N8.8).
///  * **A cut with an empty timeline is tolerated** (N8.12): the fallback is a
///    plain 60–90 minute expectation and an empty item list is not a crash.
library;

import '../../data/content/catalog.dart';
import '../../data/model/connection_state.dart';
import '../../data/model/cook_state.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';

/// Stall band start, as a fraction of the bar (prototype `0.38`).
const double kStallStartFraction = 0.38;

/// Stall band end, as a fraction of the bar (prototype `0.72`).
const double kStallEndFraction = 0.72;

/// Wrap milestone, as a fraction of the bar (prototype `0.55`).
const double kWrapFraction = 0.55;

/// The prototype shows the next spritz 20 minutes from "now".
const int kSpritzLeadMin = 20;

/// Minutes the domain extends past the last expected end.
const int kDomainTailMin = 45;

/// Minutes after the last expected end that food is "served by".
const int kServeOffsetMin = 30;

/// The most upcoming cards the prototype shows.
const int kUpcomingLimit = 4;

/// The expectation a cut with no DB entry falls back to (prototype
/// `|| { totalMin: [60, 90], restMin: 10, phases: [] }`).
const CookTimeline kFallbackTimeline = CookTimeline(
  totalMin: MinuteRange(60, 90),
  restMin: 10,
);

double _clamp01(double value) => value < 0 ? 0 : (value > 1 ? 1 : value);

/// One item's row in the Gantt.
class TimelineRow {
  const TimelineRow({
    required this.jack,
    required this.presetId,
    required this.name,
    required this.glyph,
    required this.timeline,
    required this.startMs,
    required this.expectedMin,
    required this.wrapEnabled,
    required this.spritzEnabled,
  });

  final ProbeJack jack;
  final String presetId;

  /// The cut's display name (`Item` when the preset is unknown).
  final String name;

  /// The catalog glyph name; the widget parses it through `FoodGlyph`.
  final String? glyph;

  final CookTimeline timeline;

  /// The item's `addedAtMs`.
  final int startMs;

  /// The `totalMin` midpoint, minutes.
  final double expectedMin;

  /// Whether the wrap reminder is on for this cook (already resolved against
  /// the timeline's wrap step).
  final bool wrapEnabled;

  /// Whether the spritz reminder is on for this cook.
  final bool spritzEnabled;

  /// `addedAtMs + mid`, the end of the expected cook.
  int get endMs => startMs + (expectedMin * 60000).round();

  /// The wrap milestone is a fact of the cut, so it draws whenever the cut has
  /// a wrap step — turning the *reminder* off never rewrites the schedule.
  bool get hasWrapMilestone => timeline.wrap != null;

  bool get hasStall => timeline.stall != null;

  bool get hasSpritz => timeline.spritzEveryMin != null;

  /// Where the wrap milestone sits, or null when the cut has none.
  int? get wrapAtMs => hasWrapMilestone
      ? (startMs + expectedMin * kWrapFraction * 60000).round()
      : null;

  /// The stall band's start, or null when the cut has none.
  int? get stallStartMs => hasStall
      ? (startMs + expectedMin * kStallStartFraction * 60000).round()
      : null;

  /// The stall band's end, or null when the cut has none.
  int? get stallEndMs => hasStall
      ? (startMs + expectedMin * kStallEndFraction * 60000).round()
      : null;

  /// How much of the bar is behind us, 0..1. A bar of zero length is 0.
  double progressAt(int nowMs) {
    final span = endMs - startMs;
    if (span <= 0) {
      return 0;
    }
    return _clamp01((nowMs - startMs) / span);
  }
}

/// The kind of an upcoming intervention.
enum InterventionKind { wrap, spritz, turn }

/// One upcoming intervention card.
class UpcomingIntervention {
  const UpcomingIntervention({
    required this.atMs,
    required this.kind,
    required this.label,
    required this.note,
  });

  final int atMs;
  final InterventionKind kind;
  final String label;
  final String note;
}

/// One node on the event rail.
class TimelineEvent {
  const TimelineEvent({
    required this.atMs,
    required this.title,
    required this.note,
    required this.actual,
    this.isNow = false,
  });

  final int atMs;
  final String title;
  final String note;

  /// True for a logged mark, false for a predicted phase.
  final bool actual;

  /// The first predicted node — the rail's "now" marker.
  final bool isNow;

  bool get predicted => !actual;

  TimelineEvent asNow() => TimelineEvent(
    atMs: atMs,
    title: title,
    note: note,
    actual: actual,
    isNow: true,
  );
}

/// The whole Timeline screen projection.
class TimelineModel {
  const TimelineModel({
    required this.startedMs,
    required this.nowMs,
    required this.domainEndMs,
    required this.items,
    required this.lastEndMs,
    required this.servedByMs,
    required this.upcoming,
    required this.events,
    required this.autoWrapReminder,
  });

  /// The cook's anchor (`startedAtMs`, else the pending session's start).
  final int startedMs;

  final int nowMs;

  /// `max(now, last expected end) + 45 min`.
  final int domainEndMs;

  final List<TimelineRow> items;

  /// The latest expected end, or null when nothing is on the grill.
  final int? lastEndMs;

  /// `lastEndMs + 30 min`, or null.
  final int? servedByMs;

  final List<UpcomingIntervention> upcoming;
  final List<TimelineEvent> events;
  final bool autoWrapReminder;

  int get itemCount => items.length;

  bool get isEmpty => items.isEmpty;

  /// The axis midpoint.
  int get midMs => startedMs + ((domainEndMs - startedMs) / 2).round();

  /// Where [atMs] sits across the domain, as a percentage (0–100).
  double xPercent(int atMs) {
    final span = domainEndMs - startedMs;
    if (span <= 0) {
      return 0;
    }
    return ((atMs - startedMs) / span) * 100;
  }

  /// The wall-clock time of [atMs].
  DateTime timeAt(int atMs) => DateTime.fromMillisecondsSinceEpoch(atMs);
}

/// Builds the Timeline projection for one snapshot.
TimelineModel buildTimelineModel({
  required CookState cook,
  required PendingSession? pendingSession,
  required CatalogTable catalog,
  required List<Mark> marks,
  required int nowMs,
  required bool autoWrapReminder,
}) {
  final startedMs = cook.startedAtMs ?? pendingSession?.startedAtMs ?? nowMs;

  final items = <TimelineRow>[];
  for (final item in cook.items) {
    final entry = catalog.byId(item.presetId);
    final timeline =
        item.timeline ??
        catalog.timelineFor(item.presetId) ??
        kFallbackTimeline;
    items.add(
      TimelineRow(
        jack: item.jack,
        presetId: item.presetId,
        name: entry?.name ?? 'Item',
        glyph: entry?.glyph,
        timeline: timeline,
        startMs: item.addedAtMs,
        expectedMin: timeline.totalMin.mid,
        // A null override seeds from the cut's own timeline (NOTES §7.7).
        wrapEnabled: item.wrapEnabled ?? timeline.wrap != null,
        spritzEnabled: item.spritzEnabled ?? timeline.spritzEveryMin != null,
      ),
    );
  }

  int? lastEndMs;
  for (final row in items) {
    if (lastEndMs == null || row.endMs > lastEndMs) {
      lastEndMs = row.endMs;
    }
  }

  final domainEndMs =
      (lastEndMs == null || lastEndMs < nowMs ? nowMs : lastEndMs) +
      kDomainTailMin * 60000;
  final servedByMs = lastEndMs == null
      ? null
      : lastEndMs + kServeOffsetMin * 60000;

  return TimelineModel(
    startedMs: startedMs,
    nowMs: nowMs,
    domainEndMs: domainEndMs,
    items: items,
    lastEndMs: lastEndMs,
    servedByMs: servedByMs,
    upcoming: buildUpcoming(
      items,
      nowMs: nowMs,
      autoWrapReminder: autoWrapReminder,
    ),
    events: buildRailEvents(
      rows: items,
      marks: marks,
      startedMs: startedMs,
      nowMs: nowMs,
    ),
    autoWrapReminder: autoWrapReminder,
  );
}

/// The upcoming interventions, deduped by kind + minute and capped at four.
///
/// [autoWrapReminder] gates the wrap/spritz nudges only (N8.9); a turn is a
/// schedule fact, not a reminder. The per-row enabled flags gate them
/// individually (N8.10). Only interventions still in the future are "upcoming"
/// — a turn that has already passed is not a thing to do next.
List<UpcomingIntervention> buildUpcoming(
  List<TimelineRow> rows, {
  required int nowMs,
  required bool autoWrapReminder,
}) {
  final out = <UpcomingIntervention>[];
  final seen = <String>{};
  void add(UpcomingIntervention u) {
    if (u.atMs < nowMs) {
      return;
    }
    final key = '${u.kind.name}|${(u.atMs / 60000).round()}';
    if (seen.add(key)) {
      out.add(u);
    }
  }

  for (final row in rows) {
    final wrap = row.timeline.wrap;
    if (autoWrapReminder && row.wrapEnabled && wrap != null) {
      add(
        UpcomingIntervention(
          atMs: (row.startMs + row.expectedMin * kWrapFraction * 60000).round(),
          kind: InterventionKind.wrap,
          label: wrap.label,
          note: wrap.note,
        ),
      );
    }

    final every = row.timeline.spritzEveryMin;
    if (autoWrapReminder && row.spritzEnabled && every != null) {
      add(
        UpcomingIntervention(
          atMs: nowMs + kSpritzLeadMin * 60000,
          kind: InterventionKind.spritz,
          label: 'Spritz',
          note: 'Every $every min to keep the bark moist.',
        ),
      );
    }

    final turn = row.timeline.turn;
    if (turn != null) {
      add(
        UpcomingIntervention(
          atMs:
              row.startMs +
              (turn.elapsedMin <= 0 ? 30 : turn.elapsedMin) * 60000,
          kind: InterventionKind.turn,
          label: 'Turn / rotate',
          note: turn.note,
        ),
      );
    }
  }

  out.sort((a, b) => a.atMs.compareTo(b.atMs));
  return out.take(kUpcomingLimit).toList(growable: false);
}

/// The event rail: logged marks (actual) then predicted phases (expected).
///
/// Only phases that have not happened yet are predicted; the first of those is
/// the rail's "now" node (prototype `rail-dot.now`).
List<TimelineEvent> buildRailEvents({
  required List<TimelineRow> rows,
  required List<Mark> marks,
  required int startedMs,
  required int nowMs,
}) {
  final events = <TimelineEvent>[
    for (final mark in marks)
      TimelineEvent(
        atMs: startedMs + mark.t * 1000,
        title: mark.text.isEmpty ? markKindWord(mark.kind) : mark.text,
        note: markKindWord(mark.kind),
        actual: true,
      ),
  ];

  for (final row in rows) {
    final phases = row.timeline.phases;
    final denom = phases.length <= 1 ? 1 : phases.length - 1;
    for (var idx = 0; idx < phases.length; idx++) {
      final atMs = (row.startMs + row.expectedMin * (idx / denom) * 60000)
          .round();
      if (atMs <= nowMs) {
        continue;
      }
      final phase = phases[idx];
      events.add(
        TimelineEvent(
          atMs: atMs,
          title: '${row.name} · ${phase.label}',
          note: phase.note,
          actual: false,
        ),
      );
    }
  }

  events.sort((a, b) => a.atMs.compareTo(b.atMs));
  for (var i = 0; i < events.length; i++) {
    if (events[i].predicted) {
      events[i] = events[i].asNow();
      break;
    }
  }
  return events;
}

/// A mark kind as the prototype's `kind.replace('_', ' ')` word.
String markKindWord(MarkKind kind) => switch (kind) {
  MarkKind.note => 'note',
  MarkKind.wrapped => 'wrapped',
  MarkKind.lidOpen => 'lid open',
  MarkKind.fuel => 'fuel',
  MarkKind.probeMoved => 'probe moved',
  MarkKind.alarm => 'alarm',
  MarkKind.phaseChange => 'phase change',
  MarkKind.autoDetected => 'auto detected',
  MarkKind.spritz => 'spritz',
  MarkKind.turn => 'turn',
};

/// The rail's time label: `9:41 AM`, with `· expected` on a prediction (N8.8).
String railTimeLabel(TimelineEvent event) =>
    event.actual ? fmtClock(_at(event)) : '${fmtClock(_at(event))} · expected';

DateTime _at(TimelineEvent event) =>
    DateTime.fromMillisecondsSinceEpoch(event.atMs);
