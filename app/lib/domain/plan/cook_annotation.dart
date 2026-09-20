/// Cooks as **editable annotations over a continuous recording** (newapp §D.1).
///
/// **The reframe.** A cook used to be a modal: you set one up, the app switched
/// to guided mode, you ended it and the app switched back. That model fought
/// the hardware, because the bridge records whether or not anyone has "set up a
/// cook" — so the app's central object described something that was not the
/// thing actually happening.
///
/// The object here describes what *is* happening: the bridge produces one
/// continuous sample stream per probe, and a **cook is a named, time-bounded,
/// targeted window over it**. Everything the user asked for falls out of that
/// definition rather than needing machinery of its own:
///
///  * *start now, target later* — a [CookAnnotation] with no [CookProbeRole]
///    carrying a target is completely valid, and adding one later is an edit;
///  * *backdate* — move [startUnixMs]. The samples were always there;
///  * *split / merge* — arithmetic on two time bounds ([splitAt], [mergedWith]);
///  * *schedule* — a [startUnixMs] in the future is a cook that arms itself.
///
/// None of those rewrite a single sample row, which is the property §D.2 chose
/// Option A for. This file gets it **without** minting phone-side sample keys:
/// samples stay keyed on the device-authoritative `(bridge, session, t)` that
/// §E.7 requires and that makes the delta-sync upsert idempotent, and a cook
/// resolves its membership by wall-clock range instead. See `database.dart` for
/// the projected `unix_ms` column that makes the range query possible, and
/// [anchorSessionId] for what happens when the bridge has no clock at all.
///
/// Pure Dart — no Flutter, no drift. The repository persists what these methods
/// return; the invariants are testable with no database.
library;

import '../analysis/chart_series.dart' show probeValue;
import '../entities/entities.dart';
import 'cook_plan.dart';
import 'hazard.dart';

/// Where a cook sits relative to now.
enum CookStatus {
  /// [CookAnnotation.startUnixMs] is in the future — armed, not yet running.
  scheduled,

  /// Started, no end — the open annotation. At most one per bridge in the UI,
  /// though the model does not forbid more.
  running,

  /// Bounded at both ends.
  finished;

  String get label => switch (this) {
    CookStatus.scheduled => 'Scheduled',
    CookStatus.running => 'Recording',
    CookStatus.finished => 'Finished',
  };
}

/// One jack's job within a cook. The persisted form of [PlanProbe].
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

  /// 1..4 — the physical jack.
  final int jack;
  final ProbeRole role;

  /// The cut's name on this jack ('' → the probe's device name).
  final String label;

  /// Final (post-rest) target, tenths °F. **Null is the normal state of a cook
  /// started before its target was chosen**, not a missing value.
  final int? targetF10;

  /// Carryover, tenths °F. Pull temperature is `targetF10 − pullOffsetF10`.
  final int pullOffsetF10;

  final String doneness;

  /// Null takes the cook's hazard. Set per jack for a mixed cook.
  final HazardClass? hazard;

  /// False forces the ground-meat floor on red meat (§D.4).
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
    // Unstated, never whole-muscle red meat. That class is the one
    // `SafetyFloor.forClass` returns null for in enthusiast mode, so
    // defaulting to it means an annotation built without a plan silently
    // gets *no* floor. `unstated` carries the 160 °F ground-meat floor,
    // which is §D.4's own precautionary answer for a cut nobody has
    // vouched for.
    this.hazard = HazardClass.unstated,
    this.safetyMode = SafetyMode.enthusiast,
    this.pitBandMinF10,
    this.pitBandMaxF10,
    this.favourite = false,
    this.anchorSessionId,
    this.pulledAtUnixMs,
    this.roles = const [],
  });

  /// Phone-side row id. Cooks are the app's own annotations — unlike sessions,
  /// samples and alarms, the device has no opinion about them — so this is the
  /// one id in the app that is *not* device-authoritative, and it never travels
  /// on the wire.
  final int id;
  final String bridgeId;

  /// '' → the list renders "Cook #N" from the id. Stored empty rather than
  /// pre-filled so a rename can tell "never named" from "named that on purpose".
  final String name;

  /// Wall clock. May be **before** the app was ever opened (the backfilled
  /// range) or **after** now (a scheduled cook).
  final int startUnixMs;

  /// Null = running. Bounded only by an explicit edit or "end cook": the bridge
  /// records continuously, so nothing here auto-closes after 30 minutes of
  /// quiet the way FireBoard's sessions do.
  final int? endUnixMs;

  final int createdUnixMs;

  /// Free text, 0–200 chars by UI convention ("flip burgers").
  final String notes;

  final String? presetId;
  final String doneness;
  final HazardClass hazard;
  final SafetyMode safetyMode;
  final int? pitBandMinF10;
  final int? pitBandMaxF10;
  final bool favourite;

  /// **The clockless fallback.** Membership is normally a wall-clock range over
  /// `samples.unix_ms`, but a bridge whose RTC was never set stores NULL there
  /// (§E.7: never silently rewrite device timestamps). A cook created against
  /// such a bridge pins itself to that one device session instead, and the
  /// range degenerates to "all of it". Null means the wall-clock range rules.
  final int? anchorSessionId;

  /// When the user said they took the food off the heat, for the rest phase
  /// (§D.5). Null until they tap it — the app never infers this.
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

  CookProbeRole? roleFor(int jack) =>
      roles.where((r) => r.jack == jack).firstOrNull;

  CookProbeRole? get pit =>
      roles.where((r) => r.role == ProbeRole.pit).firstOrNull;

  CookProbeRole? get primaryFood =>
      roles
          .where((r) => r.role == ProbeRole.food && r.targetF10 != null)
          .firstOrNull ??
      roles.where((r) => r.role == ProbeRole.food).firstOrNull;

  /// True while nothing carries a target — the "start now, target later" state
  /// that earns a persistent "Set a target" affordance rather than looking
  /// like a broken cook (§D.3.2).
  bool get hasNoTarget =>
      roles.where((r) => r.role == ProbeRole.food).every(
        (r) => r.targetF10 == null,
      );

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
    pulledAtUnixMs: clearPulledAt ? null : (pulledAtUnixMs ?? this.pulledAtUnixMs),
    roles: roles ?? this.roles,
  );

  // ── the four metadata edits (§D.3, §C.4) ─────────────────────────────

  /// Re-anchor the start. **Metadata only** — not one sample moves.
  ///
  /// Throws [ArgumentError] if the new start is not before the end: a cook that
  /// ends before it begins is not a degraded state to render, it is a bug to
  /// refuse.
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

  /// Split into two annotations at [atUnixMs]. Returns `(before, after)`.
  ///
  /// [after] carries `id: 0`, meaning "unsaved" — the repository assigns the
  /// real id on insert. Both halves inherit roles, preset and safety mode,
  /// because the split is about *when*, not *what*.
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
      // The pull belonged to the first half's food. Carrying it into the second
      // would open it mid-rest.
      clearPulledAt: true,
    );
    return (before, after);
  }

  /// Merge with an adjacent cook. The result spans both, keeps the **earlier**
  /// cook's identity and roles, and concatenates any notes.
  ///
  /// Adjacency is not enforced: merging across a small gap is a legitimate
  /// thing to want (the bridge restarted mid-brisket), and the gap itself is
  /// still rendered from the `Gaps` table rather than being papered over here.
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
    // A null end on either side means "still running", which absorbs any
    // bounded end — the merged cook is still running.
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

  /// §D.3.2 — take everything the setup sheet decided, keep everything that
  /// belongs to this stretch of the recording.
  ///
  /// A retarget arrives as a whole annotation projected from a fresh plan, and
  /// **all of it is what the cook is aiming at**: the preset, the doneness, the
  /// hazard class, the safety mode, the pit band and the per-jack roles.
  /// Keeping only the roles left the gauges following one thing, the chart's
  /// shaded band another, and the food-safety gate a third — while the
  /// confirmation said the targets had been saved.
  ///
  /// What [source] must not touch is anything that describes *when this cook
  /// happened*: its id, its bounds, when it was created, its notes, its star,
  /// its pull, its session anchor. The plan the sheet returns carries a start
  /// of "now", which is why this is written out field by field rather than
  /// through `copyWith` — a field that is kept should be visibly kept.
  ///
  /// The name has a rule of its own. The sheet always returns *some* title, and
  /// for a cook that was never named that title is this cook's own display name
  /// coming back round ("Cook #7"). Adopting it would turn "never named" into
  /// "named that on purpose" and silently retire the rename hint, so a title
  /// that is only the display name is dropped.
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

  /// §D.6 — "Repeat this cook". A fresh annotation starting [atUnixMs] that
  /// copies roles, targets, pull offsets and preset, and deliberately copies
  /// **neither** the notes nor the times: those belonged to the cook that
  /// happened, not to the one about to.
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

  // ── projection into the guided-cook value the gauges render ──────────

  /// The [CookPlan] this annotation projects. **Re-runs the food-safety gate**,
  /// so an annotation whose targets would now be refused throws here rather
  /// than rendering gauges against an unsafe number.
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
    plan.cookId = id;
    return plan;
  }

  /// The inverse, for the sheet that still builds a plan before there is a row.
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

// ── retroactive start: candidate anchors (§D.3.1) ──────────────────────

/// What kind of evidence an anchor is. The user picks from these rather than
/// scrubbing a raw time picker, because "when did I put the meat on" is a
/// question the recording can usually answer better than memory can.
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

/// Anything above this is the fire rather than the room, in tenths °F. 90 °F
/// clears a hot kitchen and a sunlit counter without needing the pit to be up
/// to temperature.
const int anchorAmbientF10 = 900;

/// Find candidate start times in a session's samples.
///
/// [sessionStartUnixMs] converts the samples' session-relative `t` to wall
/// clock; a session with no clock returns nothing, because an anchor the user
/// cannot be shown a time for is not an offer.
///
/// Returned newest-first and capped at [limit]: this feeds a short list under a
/// time picker, not an audit log.
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
    for (var n = 1; n <= 4; n++) {
      final v = probeValue(s, n);
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
            label: 'Probe $n went above '
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
