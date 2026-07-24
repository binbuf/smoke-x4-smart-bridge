/// The data shapes M4 is pinned against (M4 plan, A15).
///
/// The outline names them and they are not negotiable: **no probes, all
/// detached, mid-gap, alarm active, 15 h of data, 54 days of data.** They
/// live here rather than in each test file so the golden suite, the
/// widget tests and the domain tests are all looking at the *same*
/// cook — a shape that only exists in one test is a shape nobody
/// maintains.
library;

import 'dart:math';

import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';

/// A plausible brisket: pit settling around 250 °F, food climbing through
/// a stall. Deterministic — same seed, same cook, every run.
List<Sample> syntheticCook({
  required int hours,
  int periodS = 30,
  int probes = 2,
  int seed = 42,
}) {
  final rng = Random(seed);
  final n = (hours * 3600) ~/ periodS;
  final out = <Sample>[];
  for (var i = 0; i < n; i++) {
    final t = i * periodS;
    final hoursIn = t / 3600.0;
    final pit = 250 + sin(hoursIn * 1.7) * 8 + (rng.nextDouble() - 0.5) * 3;
    // Rises, stalls between 150 and 165, then rises again.
    final food = hoursIn < 4
        ? 60 + hoursIn * 24
        : hoursIn < 9
        ? 156 + (hoursIn - 4) * 1.4
        : min(203.0, 163 + (hoursIn - 9) * 6);
    out.add(
      Sample(
        t: t,
        tempsF10: [
          (pit * 10).round(),
          if (probes > 1) (food * 10).round() else null,
          if (probes > 2) ((food - 6) * 10).round() else null,
          if (probes > 3) ((food - 14) * 10).round() else null,
          // Pad to four slots regardless of how many are attached.
          ...List<int?>.filled((4 - probes).clamp(0, 3), null),
        ].take(4).toList(),
        rssi: -70,
      ),
    );
  }
  return out;
}

/// The same cook with a hole punched in it. A 30-minute dropout must look
/// like a 30-minute dropout (08 §8.7), and this is what proves it.
List<Sample> withGap(
  List<Sample> samples, {
  required int fromT,
  required int toT,
}) => [
  for (final s in samples)
    if (s.t <= fromT || s.t >= toT) s,
];

/// Four jacks, all empty. The invariant this project has enforced end to
/// end since M0 — and the golden that catches the day `—` becomes `0`.
List<Sample> allDetached({int hours = 1, int periodS = 30}) => [
  for (var i = 0; i < (hours * 3600) ~/ periodS; i++)
    Sample(t: i * periodS, tempsF10: const [null, null, null, null]),
];

const List<Probe> pitAndFood = [
  Probe(
    n: 1,
    name: 'Pit',
    role: ProbeRole.pit,
    targetF10: 2500,
    alarmEnabled: true,
    alarmMinF10: 2250,
    alarmMaxF10: 2750,
  ),
  Probe(n: 2, name: 'Brisket', role: ProbeRole.food, targetF10: 2030),
  Probe(n: 3, name: 'Point', role: ProbeRole.food),
  Probe(n: 4, name: 'Flat', role: ProbeRole.food),
];

BridgeStatus statusFor({
  bool sessionActive = true,
  int? activeSessionId = 27,
  List<Alarm> alarms = const [],
  int? socPct,
  bool baseLost = false,
}) => BridgeStatus(
  deviceId: 'LMXC[\\',
  model: 'heltec-v3',
  fw: '1.0.0',
  uptimeS: 51230,
  paired: true,
  numProbes: 4,
  lastPacketSAgo: baseLost ? 740 : 12,
  baseLost: baseLost,
  sessionActive: sessionActive,
  activeSessionId: sessionActive ? activeSessionId : null,
  storageFreePct: 91,
  socPct: socPct,
  alarms: alarms,
);

LiveState liveFor(List<Sample> samples, {List<Probe> probes = pitAndFood}) =>
    LiveState(
      t: samples.isEmpty ? 0 : samples.last.t,
      unixMs: samples.isEmpty ? null : _sessionStartMs + samples.last.t * 1000,
      tempsF10: samples.isEmpty
          ? const [null, null, null, null]
          : samples.last.tempsF10,
      probes: probes,
    );

const int _sessionStartMs = 1784755815000;

CookSession sessionFor(List<Sample> samples, {String name = 'Brisket'}) =>
    CookSession(
      id: 27,
      name: name,
      startedUnixMs: _sessionStartMs,
      sampleCount: samples.length,
      probes: pitAndFood,
    );

/// Builds the snapshot for a named shape, so every suite renders the
/// same thing.
DashboardSnapshot snapshotFor(
  List<Sample> samples, {
  List<Probe> probes = pitAndFood,
  LinkKind link = LinkKind.http,
  List<Alarm> alarms = const [],
  List<Mark> marks = const [],
  bool fullHistory = true,
  int? socPct,
  bool baseLost = false,
  bool sessionActive = true,
}) => buildDashboard(
  status: statusFor(
    alarms: alarms,
    socPct: socPct,
    baseLost: baseLost,
    sessionActive: sessionActive,
  ),
  live: liveFor(samples, probes: probes),
  history: samples,
  link: link,
  marks: marks,
  address: 'http://10.50.50.38',
  fullHistory: fullHistory,
  session: sessionFor(samples),
);
