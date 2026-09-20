/// A9.1 — the dashboard as a pure projection (design 08 §8.6, 09 §9.3).
///
/// **Four sources of truth meet on this screen** — the drift cache, the
/// live push stream, `GET /status`, and the app-tier analysis — and the
/// obvious way to build it is a widget that subscribes to all four and
/// reconciles them in `build()`. That is untestable, and it is where
/// "sometimes it shows the old temperature" comes from. So the
/// reconciliation is a pure function into one immutable snapshot, tested
/// with no widget tree, and the widgets render the snapshot and nothing
/// else — the same shape A8.1 gave the wizard, for the same reason.
///
/// Every analysis call here is an existing A2 function. This file calls
/// them; it does not re-derive them.
library;

import 'package:flutter/foundation.dart';

import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';

/// One probe, as the dashboard needs it: identity, configuration, and
/// everything the analysis layer can say about it right now.
@immutable
class ProbeView {
  const ProbeView({
    required this.probe,
    required this.role,
    required this.name,
    this.tempF10,
    this.targetF10,
    this.rateFPerHr,
    this.eta,
    this.stalled = false,
    this.alarm,
    this.recent = const [],
  });

  /// 1..4 — the physical jack, and the identity the palette follows.
  final int probe;
  final ProbeRole role;

  /// Never empty: falls back to "Probe 3" so a tile always has a label.
  final String name;

  /// **Null = detached. Never 0.** The invariant this project has held
  /// end to end since M0, restated at the last layer before pixels.
  final int? tempF10;
  final int? targetF10;

  /// °F/hr, or null when the window was too short or spanned a gap
  /// (09 §9.4 returns null rather than a number computed from bad data).
  final double? rateFPerHr;

  /// Null when no target is set; otherwise the §9.4 answer *including*
  /// its refusals — "stalled", "not at this pit temperature".
  final EtaResult? eta;
  final bool stalled;

  /// The device's alarm for this probe, if one is latched.
  final Alarm? alarm;

  /// The tile's sparkline window.
  final List<ValuePoint> recent;

  bool get attached => tempF10 != null;
  bool get targetReached =>
      tempF10 != null && targetF10 != null && tempF10! >= targetF10!;
}

/// How the bridge is reachable, for the header chip.
enum LinkKind { http, ble, offline }

@immutable
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.probes,
    required this.link,
    this.sessionName = '',
    this.sessionActive = false,
    this.sessionId,
    this.elapsedS = 0,
    this.startedUnixMs,
    this.address = '',
    this.netMode,
    this.socPct,
    this.charging = false,
    this.batteryKnown = false,
    this.baseLost = false,
    this.lastPacketSAgo,
    this.readingAtUnixMs,
    this.fullHistory = true,
    this.paired = true,
    this.alarms = const [],
    this.marks = const [],
    this.samples = const [],
  });

  /// Always four entries, in jack order — a probe that vanishes from the
  /// grid reads as an app bug, not as an unplugged jack.
  final List<ProbeView> probes;
  final LinkKind link;
  final String sessionName;
  final bool sessionActive;
  final int? sessionId;
  final int elapsedS;

  /// Null while the bridge had no clock; the header shows elapsed time
  /// rather than an epoch date.
  final int? startedUnixMs;

  /// Empty on the BLE lane — there is no address to speak to (A6.5).
  final String address;

  /// `'ap'` (hosting its own network) or `'sta'` (joined yours) while on
  /// Wi-Fi; null on BLE/offline. Lets the header chip name *which* Wi-Fi
  /// mode instead of a generic label (05 §5.7). Inferred from the address
  /// (`192.168.4.1` = hosting) until a `net` push refines it.
  final String? netMode;

  /// Null until F12 (M5) gives `soc_pct` something true to say. [socPct]
  /// null with [batteryKnown] false means "this device cannot report a
  /// battery", which is not the same as "the battery is empty" — and a
  /// `0%` on an MVP screenshot is a bug report against the hardware.
  final int? socPct;
  final bool charging;
  final bool batteryKnown;

  /// The distinct failure only the header can state: the *bridge* is
  /// reachable but the *base station* is not.
  final bool baseLost;

  /// The **device's** count of how long the base station has been silent —
  /// base→bridge, not bridge→phone. It is a genuine fact and it drives the
  /// base-lost copy, but it is NOT how old the number on screen is: it is
  /// read from `/status`, which is re-read only on alarm/session/pairing
  /// frames, and it is null on the BLE lane, which has no `/status` at all.
  final int? lastPacketSAgo;

  /// **The phone's** wall clock when the newest reading on screen actually
  /// arrived — the only honest answer to "how old is this number?".
  ///
  /// This is what the freshness ladder (13 §13.6.1) runs on. Measuring on the
  /// phone's clock rather than the device's is what makes the ladder work on
  /// every lane, with or without a device RTC, and what makes it *advance*:
  /// a snapshot that stops being rebuilt still ages, because the age is
  /// computed against `now` at read time rather than baked in here.
  ///
  /// Null means genuinely unknown — a cache read from a bridge whose clock
  /// was never set, so `samples.unix_ms` is NULL (§E.7 forbids inventing
  /// one). Unknown renders as [ProbeFreshness.unknown], never as live.
  final int? readingAtUnixMs;

  /// Drives A10.5's "full history needs Wi-Fi" notice. False on HTTP-less
  /// transports **and on a bridge whose firmware predates ble-gatt §5.10** —
  /// from v1.1 Bluetooth carries whole cooks, so this tracks the device's
  /// capability rather than the transport's name.
  final bool fullHistory;

  /// Whether the bridge is paired to a Smoke X base. Defaults to `true` so an
  /// offline/cache snapshot with no `/status` does not cry wolf; a live
  /// `status.paired == false` drives the "hasn't met your Smoke X yet" state
  /// (13 §13.5.2) — the exact case a fresh or re-flashed bridge presents.
  final bool paired;

  final List<Alarm> alarms;
  final List<Mark> marks;

  /// The cached history behind the chart.
  final List<Sample> samples;

  /// The two headline slots §8.6's layout is built around: the pit, and
  /// the primary food probe. Either may be null — a cook with no
  /// pit-role probe is legal and must render.
  ProbeView? get headlinePit =>
      probes.where((p) => p.role == ProbeRole.pit && p.attached).firstOrNull ??
      probes.where((p) => p.role == ProbeRole.pit).firstOrNull;

  ProbeView? get headlineFood =>
      probes.where((p) => p.role == ProbeRole.food && p.attached).firstOrNull ??
      probes.where((p) => p.role == ProbeRole.food).firstOrNull;

  /// Everything not in a headline slot, in jack order.
  List<ProbeView> get secondary {
    final big = {headlinePit?.probe, headlineFood?.probe};
    return [
      for (final p in probes)
        if (!big.contains(p.probe)) p,
    ];
  }

  bool get anyAttached => probes.any((p) => p.attached);
  bool get anyUnacked => alarms.any((a) => !a.acked);

  /// The same readings, re-stated as unreachable.
  ///
  /// Losing the link is not new data — it is the same numbers with a
  /// different answer to "can I trust this?". [ShellSession] emits this when
  /// the supervisor runs out of lanes, because otherwise the snapshot keeps
  /// its old [link] and the chip goes on claiming live Wi-Fi, with a
  /// breathing pulse dot, above numbers nobody is refreshing — while the
  /// masthead two lines down says the bridge cannot be reached. A screen
  /// that contradicts itself is worse than either statement alone.
  ///
  /// [readingAtUnixMs] is deliberately untouched: the reading is exactly as
  /// old as it was a moment ago, and the ladder ages it from here.
  DashboardSnapshot disconnected() => DashboardSnapshot(
    probes: probes,
    link: LinkKind.offline,
    sessionName: sessionName,
    sessionActive: sessionActive,
    sessionId: sessionId,
    elapsedS: elapsedS,
    startedUnixMs: startedUnixMs,
    // The address is kept: it is where the bridge *was*, which is what the
    // reconciler compares against to notice it has moved. Only the mode is
    // dropped, because "hosting" and "joined" are claims about a live link.
    address: address,
    netMode: null,
    socPct: socPct,
    charging: charging,
    batteryKnown: batteryKnown,
    baseLost: baseLost,
    lastPacketSAgo: lastPacketSAgo,
    readingAtUnixMs: readingAtUnixMs,
    fullHistory: fullHistory,
    paired: paired,
    alarms: alarms,
    marks: marks,
    samples: samples,
  );
}

/// The window the tile sparkline and the rate-of-change use.
const int dashboardRecentWindowS = 3600;

/// Builds the snapshot. Pure: every input is a value, and the same inputs
/// always produce the same screen.
DashboardSnapshot buildDashboard({
  required BridgeStatus? status,
  required LiveState? live,
  required List<Sample> history,
  required LinkKind link,
  List<Mark> marks = const [],
  String address = '',
  bool fullHistory = true,

  /// The explicit Wi-Fi mode from a `net` push, or null to infer it from
  /// the address. Only meaningful on the HTTP link.
  String? netMode,

  /// The cached session header. `BridgeStatus` carries the active id but
  /// not the name, and the cache has both — so the caller passes it
  /// rather than this function guessing.
  CookSession? session,

  /// The phone's wall clock when the newest reading arrived. The caller
  /// owns this because only the caller knows whether the values came off
  /// the wire just now or out of drift from last night; this function stays
  /// a pure projection and never reads a clock.
  int? readingAtUnixMs,
}) {
  // The live push is fresher than the cache by construction, so it wins
  // for the current values; the cache is what the chart and the analysis
  // windows read. Merging them here — once — is why no widget has to.
  final samples = _merge(history, live);
  final config = _config(live, status);
  final nowT = live?.t ?? (samples.isNotEmpty ? samples.last.t : 0);

  // Only Wi-Fi has an AP/STA distinction; a net push is authoritative, and
  // absent one the AP's fixed 192.168.4.1 is a reliable tell.
  final resolvedNetMode = link != LinkKind.http
      ? null
      : (netMode ?? (address == 'http://192.168.4.1' ? 'ap' : 'sta'));

  final views = <ProbeView>[];
  for (var n = 1; n <= 4; n++) {
    final cfg = config.where((p) => p.n == n).firstOrNull;
    final series = <TempPoint>[
      for (final s in samples)
        (t: s.t, f: probeValue(s, n) == null ? null : probeValue(s, n)! / 10.0),
    ];
    final recentWindow = <ValuePoint>[
      for (final p in series)
        if (p.t > nowT - dashboardRecentWindowS && p.f != null)
          (t: p.t, f: p.f!),
    ];

    final temp = live != null && n <= live.tempsF10.length
        ? live.tempsF10[n - 1]
        : (samples.isNotEmpty ? probeValue(samples.last, n) : null);

    final role = cfg?.role ?? ProbeRole.unused;
    final rate = series.isEmpty ? null : rateOfChange(series, atT: nowT);

    var stalled = false;
    if (role == ProbeRole.food && series.isNotEmpty) {
      final detector = StallDetector();
      for (final p in series) {
        stalled = detector.add(p.t, p.f);
      }
    }

    EtaResult? eta;
    final target = cfg?.targetF10;
    if (target != null && role == ProbeRole.food && series.isNotEmpty) {
      final pitCfg = config.where((p) => p.role == ProbeRole.pit).firstOrNull;
      final pitSeries = pitCfg == null
          ? const <TempPoint>[]
          : <TempPoint>[
              for (final s in samples)
                (
                  t: s.t,
                  f: probeValue(s, pitCfg.n) == null
                      ? null
                      : probeValue(s, pitCfg.n)! / 10.0,
                ),
            ];
      eta = etaToTarget(
        food: series,
        pit: pitSeries,
        targetF: target / 10.0,
        stalled: stalled,
      );
    }

    views.add(
      ProbeView(
        probe: n,
        role: role,
        name: (cfg?.name ?? '').isEmpty ? 'Probe $n' : cfg!.name,
        tempF10: temp,
        targetF10: target,
        rateFPerHr: rate,
        eta: eta,
        stalled: stalled,
        alarm: status?.alarms.where((a) => a.probe == n).firstOrNull,
        recent: recentWindow,
      ),
    );
  }

  return DashboardSnapshot(
    probes: views,
    link: link,
    sessionName: session?.name ?? '',
    sessionActive: status?.sessionActive ?? false,
    sessionId: status?.activeSessionId ?? session?.id,
    elapsedS: nowT,
    startedUnixMs:
        session?.startedUnixMs ??
        (live?.unixMs == null ? null : live!.unixMs! - nowT * 1000),
    address: address,
    netMode: resolvedNetMode,
    socPct: status?.socPct,
    charging: status?.charging ?? false,
    batteryKnown: status?.socPct != null,
    baseLost: status?.baseLost ?? false,
    lastPacketSAgo: status?.lastPacketSAgo,
    readingAtUnixMs: readingAtUnixMs,
    fullHistory: fullHistory,
    // Unknown (no /status, e.g. the BLE lane or a cache read) stays paired so
    // the UI does not cry wolf; a real status.paired == false surfaces the
    // "hasn't met your Smoke X yet" state.
    paired: status?.paired ?? true,
    alarms: status?.alarms ?? const [],
    marks: marks,
    samples: samples,
  );
}

/// Appends the live window to the cached history without duplicating a
/// `t` the cache already holds — the cache is authoritative for what it
/// has, the push is authoritative for what comes after.
List<Sample> _merge(List<Sample> history, LiveState? live) {
  if (live == null || live.recent.isEmpty) {
    return history;
  }
  if (history.isEmpty) {
    return live.recent;
  }
  final lastT = history.last.t;
  return [
    ...history,
    for (final s in live.recent)
      if (s.t > lastT) s,
  ];
}

/// Probe configuration, with the device's own convention as the fallback
/// for transports that cannot report it (BLE's 16-byte `live_state`):
/// **jack 1 is the pit**, the rest are food. The same assumption the OLED
/// makes, so the two screens never disagree.
List<Probe> _config(LiveState? live, BridgeStatus? status) {
  if (live != null && live.probes.isNotEmpty) {
    return live.probes;
  }
  final n = status?.numProbes ?? 4;
  return [
    for (var i = 1; i <= (n < 1 ? 4 : n); i++)
      Probe(n: i, role: i == 1 ? ProbeRole.pit : ProbeRole.food),
  ];
}
