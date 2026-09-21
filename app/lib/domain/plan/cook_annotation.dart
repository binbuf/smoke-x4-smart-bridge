/// N1.17 — cooks as **editable annotations over a continuous recording**.
///
/// The bridge records whether or not anyone "set up a cook", so a cook is a
/// named, time-bounded, targeted **window** over the sample stream. Everything
/// falls out of that: *start now, target later* is a window with no target;
/// *backdate* moves the start; *split / merge* are arithmetic on two time
/// bounds; *repeat* re-arms a fresh window.
///
/// **Every edit is metadata only.** Not one sample row is rewritten. The verbs
/// — `backdate`, `split`, `merge`, `retarget`, `repeat` — operate on the
/// annotation, never on the recording.
library;

import '../analysis/chart_series.dart' show probeValue;
import '../entities/mark.dart';
import '../entities/probe.dart';
import '../entities/sample.dart';
import 'cook_plan.dart';
import 'hazard.dart';

/// Where a cook sits relative to now.
enum CookStatus {
  /// [CookAnnotation.startUnixMs] is in the future — armed, not yet running.
  scheduled,

  /// Started, no end — the open annotation.
  running,

  /// Bounded at both ends.
  finished;

  String get label => switch (this) {
    CookStatus.scheduled => 'Scheduled',
    CookStatus.running => 'Recording',
    CookStatus.finished => 'Finished',
  };
}

/// One jack's job within a cook. The persisted form of `PlanProbe`.
class CookProbeRole {
  const CookProbeRole({
    required this.jack,
    required this.role,
    this.label = '',
    this.targetF10,
    this.pullOffsetF10 = 0,
    this.doneness = '',
    this.hazard,
    this.isIntact = true,
  });

  final ProbeJack jack;
  final ProbeRole role;

  /// The cut's name on this jack ('' → the probe's device name).
  final String label;

  /// Final (post-rest) target, tenths °F. Null is normal for a cook started
  /// before its target was chosen.
  final int? targetF10;

  /// Carryover, tenths °F. Pull temperature is `targetF10 − pullOffsetF10`.
  final int pullOffsetF10;

  final String doneness;

  /// Null takes the cook's hazard.
  final HazardClass? hazard;

  final bool isIntact;

  int? get pullF10 => targetF10 == null ? null : targetF10! - pullOffsetF10;

  CookProbeRole copyWith({
    ProbeRole? role,
    String? label,
    int? targetF10,
    bool clearTarget = false,
    int? pullOffsetF10,
    String? doneness,
    HazardClass? hazard,
    bool? isIntact,
  }) => CookProbeRole(
    jack: jack,
    role: role ?? this.role,
    label: label ?? this.label,
    targetF10: clearTarget ? null : (targetF10 ?? this.targetF10),
    pullOffsetF10: pullOffsetF10 ?? this.pullOffsetF10,
    doneness: doneness ?? this.doneness,
    hazard: hazard ?? this.hazard,
    isIntact: isIntact ?? this.isIntact,
  );
}

/// A named, time-bounded, targeted window over the bridge's recording.
class CookAnnotation {
  const CookAnnotation({
    required this.id,
    required this.bridgeId,
    required this.startUnixMs,
    required this.createdUnixMs,
    this.name = '',
    this.endUnixMs,
    this.notes = '',
    this.presetId,
    this.doneness = '',
    // Unstated, never whole-muscle red meat: red meat is the one class with no
    // floor, so defaulting to it would silently give no floor at all.
    this.hazard = HazardClass.unstated,
    this.safetyMode = SafetyMode.enthusiast,
    this.pitBandMinF10,
    this.pitBandMaxF10,
    this.favourite = false,
    this.anchorSessionId,
    this.pulledAtUnixMs,
    this.roles = const [],
  });

  /// Phone-side row id. The one id in the app the device has no opinion about.
  final int id;
  final String bridgeId;

  /// '' → the list renders "Cook #N" from the id.
  final String name;

  /// Wall clock. May be before the app was opened (backfilled) or after now
  /// (scheduled).
  final int startUnixMs;

  /// Null = running. Nothing here auto-closes on quiet.
  final int? endUnixMs;
  final int createdUnixMs;
  final String notes;
  final String? presetId;
  final String doneness;
  final HazardClass hazard;
  final SafetyMode safetyMode;
  final int? pitBandMinF10;
  final int? pitBandMaxF10;
  final bool favourite;

  /// The clockless fallback: a cook against a bridge with no RTC pins itself to
  /// one device session instead of a wall-clock range. Null means the range
  /// rules.
  final int? anchorSessionId;

  /// When the user said they pulled the food; null until they tap it.
  final int? pulledAtUnixMs;
  final List<CookProbeRole> roles;

  CookStatus statusAt(int nowUnixMs) {
    if (startUnixMs > nowUnixMs) {
      return CookStatus.scheduled;
    }
    return endUnixMs == null ? CookStatus.running : CookStatus.finished;
  }

  /// The display name, never empty.
  String displayName() => name.isNotEmpty ? name : 'Cook #$id';

  /// Whether [unixMs] falls inside this annotation. End is exclusive so two
  /// cooks split at the same instant cannot both claim the boundary sample.
  bool covers(int unixMs) =>
      unixMs >= startUnixMs && (endUnixMs == null || unixMs < endUnixMs!);

  /// Duration so far, milliseconds. Uses [nowUnixMs] while running.
  int elapsedMsAt(int nowUnixMs) {
    final end = endUnixMs ?? nowUnixMs;
    final ms = end - startUnixMs;
    return ms < 0 ? 0 : ms;
  }

  CookProbeRole? roleFor(ProbeJack jack) =>
      roles.where((r) => r.jack == jack).firstOrNull;

  CookProbeRole? get pit =>
      roles.where((r) => r.role == ProbeRole.pit).firstOrNull;

  CookProbeRole? get primaryFood =>
      roles
          .where((r) => r.role == ProbeRole.food && r.targetF10 != null)
          .firstOrNull ??
      roles.where((r) => r.role == ProbeRole.food).firstOrNull;

  /// True while nothing carries a target — "start now, target later".
  bool get hasNoTarget => roles
      .where((r) => r.role == ProbeRole.food)
      .every((r) => r.targetF10 == null);

  CookAnnotation copyWith({
    String? name,
    int? startUnixMs,
    int? endUnixMs,
    bool clearEnd = false,
    String? notes,
    String? presetId,
    String? doneness,
    HazardClass? hazard,
    SafetyMode? safetyMode,
    int? pitBandMinF10,
    int? pitBandMaxF10,
    bool? favourite,
    int? anchorSessionId,
    int? pulledAtUnixMs,
    bool clearPulledAt = false,
    List<CookProbeRole>? roles,
    int? id,
  }) => CookAnnotation(
    id: id ?? this.id,
    bridgeId: bridgeId,
    name: name ?? this.name,
    startUnixMs: startUnixMs ?? this.startUnixMs,
    endUnixMs: clearEnd ? null : (endUnixMs ?? this.endUnixMs),
    createdUnixMs: createdUnixMs,
    notes: notes ?? this.notes,
    presetId: presetId ?? this.presetId,
    doneness: doneness ?? this.doneness,
    hazard: hazard ?? this.hazard,
    safetyMode: safetyMode ?? this.safetyMode,
    pitBandMinF10: pitBandMinF10 ?? this.pitBandMinF10,
    pitBandMaxF10: pitBandMaxF10 ?? this.pitBandMaxF10,
    favourite: favourite ?? this.favourite,
    anchorSessionId: anchorSessionId ?? this.anchorSessionId,
    pulledAtUnixMs: clearPulledAt
        ? null
        : (pulledAtUnixMs ?? this.pulledAtUnixMs),
    roles: roles ?? this.roles,
  );

  // ── the metadata verbs ────────────────────────────────────────────────

  /// Re-anchor the start. **Metadata only** — not one sample moves.
  CookAnnotation backdatedTo(int newStartUnixMs) {
    final end = endUnixMs;
    if (end != null && newStartUnixMs >= end) {
      throw ArgumentError.value(
        newStartUnixMs,
        'newStartUnixMs',
        'a cook cannot start at or after it ends',
      );
    }
    return copyWith(startUnixMs: newStartUnixMs);
  }

  /// Split into `(before, after)` at [atUnixMs]. `after` carries `id: 0`
  /// ("unsaved"); the repository assigns the real id.
  (CookAnnotation, CookAnnotation) splitAt(int atUnixMs) {
    if (atUnixMs <= startUnixMs) {
      throw ArgumentError.value(
        atUnixMs,
        'atUnixMs',
        'split point is at or before the start',
      );
    }
    final end = endUnixMs;
    if (end != null && atUnixMs >= end) {
      throw ArgumentError.value(
        atUnixMs,
        'atUnixMs',
        'split point is at or after the end',
      );
    }
    final before = copyWith(endUnixMs: atUnixMs);
    final after = copyWith(
      id: 0,
      startUnixMs: atUnixMs,
      endUnixMs: end,
      clearEnd: end == null,
      name: name.isEmpty ? '' : '$name (2)',
      clearPulledAt: true,
    );
    return (before, after);
  }

  /// Merge with an adjacent cook. Keeps the earlier cook's identity and roles.
  /// A null end on either side means "still running" and absorbs the other.
  CookAnnotation mergedWith(CookAnnotation other) {
    if (other.bridgeId != bridgeId) {
      throw ArgumentError.value(
        other.bridgeId,
        'other.bridgeId',
        'cooks on different bridges cannot merge',
      );
    }
    final earlier = startUnixMs <= other.startUnixMs ? this : other;
    final later = identical(earlier, this) ? other : this;
    final end = (earlier.endUnixMs == null || later.endUnixMs == null)
        ? null
        : (earlier.endUnixMs! > later.endUnixMs!
              ? earlier.endUnixMs
              : later.endUnixMs);
    final notes = [
      if (earlier.notes.isNotEmpty) earlier.notes,
      if (later.notes.isNotEmpty) later.notes,
    ].join('\n');
    return earlier.copyWith(
      endUnixMs: end,
      clearEnd: end == null,
      notes: notes,
    );
  }

  /// Take everything the setup sheet decided, keep everything that describes
  /// *when this cook happened* — its id, bounds, creation, notes, star, pull
  /// and session anchor. Runs through the safety gate via [toPlan] on use.
  CookAnnotation retargetedTo(CookAnnotation source) => CookAnnotation(
    id: id,
    bridgeId: bridgeId,
    name: source.name == displayName() ? name : source.name,
    startUnixMs: startUnixMs,
    endUnixMs: endUnixMs,
    createdUnixMs: createdUnixMs,
    notes: notes,
    presetId: source.presetId,
    doneness: source.doneness,
    hazard: source.hazard,
    safetyMode: source.safetyMode,
    pitBandMinF10: source.pitBandMinF10,
    pitBandMaxF10: source.pitBandMaxF10,
    favourite: favourite,
    anchorSessionId: anchorSessionId,
    pulledAtUnixMs: pulledAtUnixMs,
    roles: source.roles,
  );

  /// "Repeat this cook" — a fresh annotation that copies roles, targets, pull
  /// offsets and preset, and deliberately copies neither notes nor times.
  CookAnnotation repeatAt(int atUnixMs, {String? newName}) => CookAnnotation(
    id: 0,
    bridgeId: bridgeId,
    name: newName ?? name,
    startUnixMs: atUnixMs,
    createdUnixMs: atUnixMs,
    presetId: presetId,
    doneness: doneness,
    hazard: hazard,
    safetyMode: safetyMode,
    pitBandMinF10: pitBandMinF10,
    pitBandMaxF10: pitBandMaxF10,
    roles: roles,
  );

  /// Projects into the guided-cook value the gauges render. **Re-runs the
  /// food-safety gate**, so an annotation whose targets would now be refused
  /// throws here rather than rendering gauges against an unsafe number.
  CookPlan toPlan() {
    final plan = CookPlan(
      presetId: presetId ?? 'custom',
      title: displayName(),
      hazard: hazard,
      doneness: doneness,
      safetyMode: safetyMode,
      pitBandMinF10: pitBandMinF10,
      pitBandMaxF10: pitBandMaxF10,
      probes: [
        for (final r in roles)
          if (r.role != ProbeRole.unused)
            PlanProbe(
              jack: r.jack,
              isPit: r.role == ProbeRole.pit,
              role: r.role,
              name: r.label,
              targetF10: r.targetF10,
              pullF10: r.pullF10,
              hazard: r.hazard,
              isIntact: r.isIntact,
              doneness: r.doneness,
            ),
      ],
    );
    plan.startedUnixMs = startUnixMs;
    return plan;
  }

  /// The inverse, for a sheet that builds a plan before there is a row.
  static CookAnnotation fromPlan(
    CookPlan plan, {
    required String bridgeId,
    required int nowUnixMs,
    int id = 0,
  }) => CookAnnotation(
    id: id,
    bridgeId: bridgeId,
    name: plan.title,
    startUnixMs: plan.startedUnixMs == 0 ? nowUnixMs : plan.startedUnixMs,
    createdUnixMs: nowUnixMs,
    presetId: plan.presetId,
    doneness: plan.doneness,
    hazard: plan.hazard,
    safetyMode: plan.safetyMode,
    pitBandMinF10: plan.pitBandMinF10,
    pitBandMaxF10: plan.pitBandMaxF10,
    roles: [
      for (final p in plan.probes)
        CookProbeRole(
          jack: p.jack,
          role: p.role,
          label: p.name,
          targetF10: p.targetF10,
          pullOffsetF10: p.carryoverF10,
          doneness: p.doneness.isEmpty ? plan.doneness : p.doneness,
          hazard: p.hazard,
          isIntact: p.isIntact,
        ),
    ],
  );
}

// ── retroactive start: candidate anchors ───────────────────────────────

/// What kind of evidence an anchor is.
enum AnchorKind {
  /// A probe went from detached to reading — someone plugged it in.
  probeInserted,

  /// A probe climbed through the ambient threshold — the food met the fire.
  crossedAmbient,

  /// A mark the user or the firmware placed.
  mark,

  /// The recording itself began.
  recordingStart,
}

/// One offered start time, with the reason it is being offered.
class CookAnchor {
  const CookAnchor({
    required this.unixMs,
    required this.kind,
    required this.label,
    this.probe = 0,
  });

  final int unixMs;
  final AnchorKind kind;

  /// Plain words — "Probe 2 plugged in", never "sample[413] null→2110".
  final String label;

  /// 1..4, or 0 for whole-cook evidence.
  final int probe;
}

/// Anything above this is the fire rather than the room, tenths °F.
const int anchorAmbientF10 = 900;

/// Find candidate start times in a session's samples, newest first, capped at
/// [limit]. A session with no clock returns nothing: an anchor the user cannot
/// be shown a time for is not an offer.
List<CookAnchor> candidateAnchors({
  required List<Sample> samples,
  required int? sessionStartUnixMs,
  List<Mark> marks = const [],
  int limit = 6,
}) {
  final start = sessionStartUnixMs;
  if (start == null || samples.isEmpty) {
    return const [];
  }
  int at(int t) => start + t * 1000;

  final out = <CookAnchor>[];
  final wasAttached = <int, bool>{};
  final wasHot = <int, bool>{};

  for (final s in samples) {
    for (final jack in ProbeJack.values) {
      final n = jack.n;
      final v = probeValue(s, jack);
      final attached = v != null;
      if (attached && wasAttached[n] == false) {
        out.add(
          CookAnchor(
            unixMs: at(s.t),
            kind: AnchorKind.probeInserted,
            label: 'Probe $n plugged in',
            probe: n,
          ),
        );
      }
      wasAttached[n] = attached;

      final hot = v != null && v >= anchorAmbientF10;
      if (hot && wasHot[n] == false) {
        out.add(
          CookAnchor(
            unixMs: at(s.t),
            kind: AnchorKind.crossedAmbient,
            label:
                'Probe $n went above '
                '${(anchorAmbientF10 / 10).round()}°F',
            probe: n,
          ),
        );
      }
      wasHot[n] = hot;
    }
  }

  for (final m in marks) {
    out.add(
      CookAnchor(
        unixMs: at(m.t),
        kind: AnchorKind.mark,
        label: m.text.isEmpty ? 'Marked' : m.text,
        probe: m.probe,
      ),
    );
  }

  out.add(
    CookAnchor(
      unixMs: at(samples.first.t),
      kind: AnchorKind.recordingStart,
      label: 'When recording started',
    ),
  );

  out.sort((a, b) => b.unixMs.compareTo(a.unixMs));
  return out.length <= limit ? out : out.sublist(0, limit);
}
