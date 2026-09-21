/// N2.14 — cook and probe state as the screens consume it.
library;

import '../../domain/domain.dart';

/// One item on the grill, tied to a jack.
///
/// N8 adds three Timeline fields: a per-item [timeline] (custom foods bypass
/// the catalog table, N9.18), and per-cook wrap/spritz reminder overrides. A
/// `null` override means "seed from the cut's expected timeline"; setup (N9)
/// writes the concrete values.
class CookItem {
  const CookItem({
    required this.presetId,
    required this.jack,
    required this.addedAtMs,
    this.styleId,
    this.timeline,
    this.wrapEnabled,
    this.spritzEnabled,
  });

  final String presetId;
  final ProbeJack jack;
  final int addedAtMs;
  final String? styleId;

  /// A per-item expected timeline (custom foods, N9.18). Null falls back to the
  /// catalog's timeline table for [presetId].
  final CookTimeline? timeline;

  /// Per-cook wrap reminder override; null seeds from [timeline]'s wrap step.
  final bool? wrapEnabled;

  /// Per-cook spritz reminder override; null seeds from the spritz cadence.
  final bool? spritzEnabled;

  CookItem copyWith({
    String? styleId,
    CookTimeline? timeline,
    bool? wrapEnabled,
    bool? spritzEnabled,
  }) => CookItem(
    presetId: presetId,
    jack: jack,
    addedAtMs: addedAtMs,
    styleId: styleId ?? this.styleId,
    timeline: timeline ?? this.timeline,
    wrapEnabled: wrapEnabled ?? this.wrapEnabled,
    spritzEnabled: spritzEnabled ?? this.spritzEnabled,
  );
}

/// The active (or empty) cook.
class CookState {
  const CookState({
    this.active = false,
    this.paused = false,
    this.name = '',
    this.startedAtMs,
    this.pitBandMinF10,
    this.pitBandMaxF10,
    this.grateTargetF10,
    this.styleId,
    this.items = const [],
  });

  final bool active;

  /// UI-only freeze of the displayed clock; never stops device recording (I2).
  final bool paused;

  final String name;
  final int? startedAtMs;

  /// Pit band, tenths °F. Null renders the pit gauge in sweep mode.
  final int? pitBandMinF10;
  final int? pitBandMaxF10;

  final int? grateTargetF10;
  final String? styleId;
  final List<CookItem> items;

  bool get hasItems => items.isNotEmpty;

  CookState copyWith({
    bool? active,
    bool? paused,
    String? name,
    Object? startedAtMs = _sentinel,
    Object? pitBandMinF10 = _sentinel,
    Object? pitBandMaxF10 = _sentinel,
    Object? grateTargetF10 = _sentinel,
    Object? styleId = _sentinel,
    List<CookItem>? items,
  }) => CookState(
    active: active ?? this.active,
    paused: paused ?? this.paused,
    name: name ?? this.name,
    startedAtMs: startedAtMs == _sentinel
        ? this.startedAtMs
        : startedAtMs as int?,
    pitBandMinF10: pitBandMinF10 == _sentinel
        ? this.pitBandMinF10
        : pitBandMinF10 as int?,
    pitBandMaxF10: pitBandMaxF10 == _sentinel
        ? this.pitBandMaxF10
        : pitBandMaxF10 as int?,
    grateTargetF10: grateTargetF10 == _sentinel
        ? this.grateTargetF10
        : grateTargetF10 as int?,
    styleId: styleId == _sentinel ? this.styleId : styleId as String?,
    items: items ?? this.items,
  );
}

const Object _sentinel = Object();

/// One probe's live + configured state.
///
/// Everything beyond [jack] is nullable/defaulted because a probe can be
/// detached, have no history, be moving too slowly to estimate or be stale.
/// **Absent is null, never zero (I3).**
class ProbeState {
  const ProbeState({
    required this.jack,
    this.role = ProbeRole.unused,
    this.attached = false,
    this.freshness = Freshness.unknown,
    this.tempF10,
    this.targetF10,
    this.pullF10,
    this.trendFPerHr,
    this.stalled = false,
    this.peakF10,
    this.lowF10,
    this.avgF10,
    this.etaMin,
    this.etaNote = '',
    this.spark = const [],
  });

  final ProbeJack jack;
  final ProbeRole role;
  final bool attached;
  final Freshness freshness;

  /// Current reading, tenths °F, or null when detached.
  final int? tempF10;

  final int? targetF10;

  /// Pull-early temperature, tenths °F.
  final int? pullF10;

  final double? trendFPerHr;
  final bool stalled;
  final int? peakF10;
  final int? lowF10;
  final int? avgF10;
  final int? etaMin;
  final String etaNote;

  /// Recent readings for the sparkline, tenths °F.
  final List<int> spark;

  /// The domain value object the widgets render; derived values obey the
  /// freshness gate.
  ProbeReading get reading => ProbeReading(
    jack: jack,
    attached: attached,
    temp: tempF10 == null
        ? const TempValue.absent()
        : TempValue.ofF10(tempF10!),
    freshness: freshness,
    trendFPerHr: freshness.showsDerived ? trendFPerHr : null,
    stalled: stalled,
    peakF10: peakF10,
    lowF10: lowF10,
    avgF10: avgF10,
    eta: freshness.showsDerived && etaMin != null
        ? EtaRange(Duration(minutes: etaMin!), Duration(minutes: etaMin!))
        : null,
    spark: spark,
  );

  ProbeState copyWith({
    ProbeRole? role,
    bool? attached,
    Freshness? freshness,
    Object? tempF10 = _sentinel,
    Object? targetF10 = _sentinel,
    Object? pullF10 = _sentinel,
    Object? trendFPerHr = _sentinel,
    bool? stalled,
    Object? peakF10 = _sentinel,
    Object? lowF10 = _sentinel,
    Object? avgF10 = _sentinel,
    Object? etaMin = _sentinel,
    String? etaNote,
    List<int>? spark,
  }) => ProbeState(
    jack: jack,
    role: role ?? this.role,
    attached: attached ?? this.attached,
    freshness: freshness ?? this.freshness,
    tempF10: tempF10 == _sentinel ? this.tempF10 : tempF10 as int?,
    targetF10: targetF10 == _sentinel ? this.targetF10 : targetF10 as int?,
    pullF10: pullF10 == _sentinel ? this.pullF10 : pullF10 as int?,
    trendFPerHr: trendFPerHr == _sentinel
        ? this.trendFPerHr
        : trendFPerHr as double?,
    stalled: stalled ?? this.stalled,
    peakF10: peakF10 == _sentinel ? this.peakF10 : peakF10 as int?,
    lowF10: lowF10 == _sentinel ? this.lowF10 : lowF10 as int?,
    avgF10: avgF10 == _sentinel ? this.avgF10 : avgF10 as int?,
    etaMin: etaMin == _sentinel ? this.etaMin : etaMin as int?,
    etaNote: etaNote ?? this.etaNote,
    spark: spark ?? this.spark,
  );
}

/// A detached probe — the "— / Unplugged" shape.
ProbeState detachedProbe(ProbeJack jack) => ProbeState(jack: jack);
