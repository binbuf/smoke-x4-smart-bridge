/// A22.5 / A22.6 — the UX scenario library (design 13 §13.6, 14 §14.12).
///
/// Scripted cook events, as pure data, so the UI can be reviewed and
/// regression-tested with **no bridge, no Smoke X, no device**. Each scenario
/// is a list of [LabFrame]s on a timeline; the interactive lab
/// (`lib/lab/cook_lab.dart`) plays them and the scenario test
/// (`test/lab/cook_scenarios_test.dart`) pumps every frame through the real
/// production widgets and asserts they render cleanly.
///
/// The frames build the exact types the app renders live — [DashboardSnapshot],
/// [CookPlan], [ProbeFreshness] — so what you review in the lab is what ships.
/// Nothing here is Flutter; it is a fake data source, not a fake UI.
///
/// A22.6 adds the states a review must not miss, each built from a **real Smoke
/// X4 capture** (2026-07-25) rather than invented numbers: the full 54-minute
/// cook replayed sample-by-sample, a BLE-degraded link, an offline cached view,
/// and a reconnect arc whose sparkline draws the outage as a real gap. The rates
/// and sparklines are derived the way the shipping dashboard derives them, so
/// the lab is fed the board's own bytes through the production math.
library;

import '../domain/analysis/analysis.dart';
import '../domain/entities/entities.dart';
import '../domain/plan/plan.dart';
import '../features/dashboard/dashboard_snapshot.dart';
import '../ui/probe/probe_freshness.dart';

/// One moment in a scenario: what the screen should show at time [atS].
class LabFrame {
  const LabFrame({
    required this.atS,
    required this.label,
    required this.snapshot,
    this.plan,
    this.freshness = ProbeFreshness.live,
  });

  /// Seconds into the scenario (also the cook's elapsed time).
  final int atS;

  /// A one-line caption shown in the lab so you know what event you're seeing.
  final String label;

  final DashboardSnapshot snapshot;
  final CookPlan? plan;
  final ProbeFreshness freshness;
}

/// A named, ordered set of frames.
class LabScenario {
  const LabScenario({
    required this.id,
    required this.title,
    required this.blurb,
    required this.frames,
  });

  final String id;
  final String title;
  final String blurb;
  final List<LabFrame> frames;

  int get durationS => frames.isEmpty ? 0 : frames.last.atS;

  /// The frame in effect at [t] seconds — the last one whose [LabFrame.atS] is
  /// at or before [t].
  LabFrame at(int t) {
    var current = frames.first;
    for (final f in frames) {
      if (f.atS <= t) {
        current = f;
      } else {
        break;
      }
    }
    return current;
  }
}

// ── builders ──────────────────────────────────────────────────────────

/// A synthetic recent-window sparkline that rises from [fromF10] to [toF10].
List<ValuePoint> _spark(int fromF10, int toF10, {int n = 12}) {
  return [
    for (var i = 0; i < n; i++)
      (t: i * 300, f: (fromF10 + (toF10 - fromF10) * (i / (n - 1))).toDouble()),
  ];
}

ProbeView _probe(
  int jack,
  ProbeRole role,
  String name, {
  int? tempF10,
  int? targetF10,
  double? rate,
  bool stalled = false,
  EtaResult? eta,
  Alarm? alarm,
  List<ValuePoint> recent = const [],
}) => ProbeView(
  probe: jack,
  role: role,
  name: name,
  tempF10: tempF10,
  targetF10: targetF10,
  rateFPerHr: rate,
  stalled: stalled,
  eta: eta,
  alarm: alarm,
  recent: recent,
);

DashboardSnapshot _snap(
  List<ProbeView> probes, {
  int elapsedS = 0,
  String name = 'Brisket',
  LinkKind link = LinkKind.http,
  bool baseLost = false,
  int? lastPacketSAgo = 4,
  List<Alarm> alarms = const [],
  bool fullHistory = true,
  int? socPct = 82,
}) => DashboardSnapshot(
  probes: probes,
  link: link,
  sessionName: name,
  sessionActive: true,
  elapsedS: elapsedS,
  baseLost: baseLost,
  lastPacketSAgo: lastPacketSAgo,
  alarms: alarms,
  fullHistory: fullHistory,
  socPct: socPct,
  batteryKnown: socPct != null,
);

CookPlan _brisket() => CookPlan(
  presetId: 'beef_brisket',
  title: 'Texas brisket — Pitmaster shred',
  hazard: HazardClass.wholeMuscleRedMeat,
  doneness: 'Pitmaster shred',
  pitBandMinF10: 2250,
  pitBandMaxF10: 2750,
  probes: [
    PlanProbe(jack: 1, isPit: true, name: 'Pit'),
    PlanProbe(
      jack: 2,
      isPit: false,
      name: 'Brisket',
      targetF10: 2030,
      pullF10: 1950,
    ),
  ],
);

// ── scenarios ───────────────────────────────────────────────────────────

/// The whole brisket arc, guided: cold start → climb → stall → target reached.
final LabScenario _brisketCook = LabScenario(
  id: 'brisket_cook',
  title: 'Brisket, start to finish (guided)',
  blurb:
      'Cold smoker → climb → the stall → pull. The gauges fill; the ring '
      'closes at target.',
  frames: [
    LabFrame(
      atS: 0,
      label: 'Just lit — pit climbing, meat cold',
      plan: _brisket(),
      snapshot: _snap([
        _probe(
          1,
          ProbeRole.pit,
          'Pit',
          tempF10: 1600,
          rate: 320,
          recent: _spark(700, 1600),
        ),
        _probe(
          2,
          ProbeRole.food,
          'Brisket',
          tempF10: 480,
          rate: 40,
          recent: _spark(400, 480),
        ),
      ], elapsedS: 12 * 60),
    ),
    LabFrame(
      atS: 90 * 60,
      label: 'Pit settled in the band, meat climbing',
      plan: _brisket(),
      snapshot: _snap([
        _probe(
          1,
          ProbeRole.pit,
          'Pit',
          tempF10: 2480,
          rate: -8,
          recent: _spark(2400, 2480),
        ),
        _probe(
          2,
          ProbeRole.food,
          'Brisket',
          tempF10: 1180,
          rate: 62,
          eta: const EtaRange(
            Duration(hours: 5),
            Duration(hours: 6, minutes: 30),
          ),
          recent: _spark(700, 1180),
        ),
      ], elapsedS: 90 * 60),
    ),
    LabFrame(
      atS: 5 * 3600,
      label: 'The stall — 160s, barely moving',
      plan: _brisket(),
      snapshot: _snap([
        _probe(
          1,
          ProbeRole.pit,
          'Pit',
          tempF10: 2460,
          rate: 4,
          recent: _spark(2450, 2470),
        ),
        _probe(
          2,
          ProbeRole.food,
          'Brisket',
          tempF10: 1620,
          rate: 3,
          stalled: true,
          recent: _spark(1590, 1620),
        ),
      ], elapsedS: 5 * 3600),
    ),
    LabFrame(
      atS: 9 * 3600,
      label: 'Pushed through — approaching target',
      plan: _brisket(),
      snapshot: _snap([
        _probe(
          1,
          ProbeRole.pit,
          'Pit',
          tempF10: 2510,
          rate: -6,
          recent: _spark(2480, 2510),
        ),
        _probe(
          2,
          ProbeRole.food,
          'Brisket',
          tempF10: 1980,
          rate: 22,
          eta: const EtaRange(Duration(minutes: 20), Duration(minutes: 45)),
          recent: _spark(1700, 1980),
        ),
      ], elapsedS: 9 * 3600),
    ),
    LabFrame(
      atS: 10 * 3600,
      label: 'Done — ring closed, "Reached"',
      plan: _brisket(),
      snapshot: _snap([
        _probe(
          1,
          ProbeRole.pit,
          'Pit',
          tempF10: 2495,
          rate: -4,
          recent: _spark(2480, 2495),
        ),
        _probe(
          2,
          ProbeRole.food,
          'Brisket',
          tempF10: 2035,
          rate: 8,
          recent: _spark(1980, 2035),
        ),
      ], elapsedS: 10 * 3600),
    ),
  ],
);

/// Instrument mode, no plan: four probes as an instrument. Owner's "see temps
/// without starting a cook".
final LabScenario _instrument = LabScenario(
  id: 'instrument',
  title: 'Instrument mode (no cook)',
  blurb:
      'Four probes, live, with no plan — including a detached jack shown in '
      'place, not hidden.',
  frames: [
    LabFrame(
      atS: 0,
      label: 'Watching probes',
      snapshot: _snap([
        _probe(
          1,
          ProbeRole.pit,
          'Pit',
          tempF10: 2430,
          rate: -18,
          recent: _spark(2380, 2430),
        ),
        _probe(
          2,
          ProbeRole.food,
          'Probe 2',
          tempF10: 1632,
          rate: 12,
          recent: _spark(1500, 1632),
        ),
        _probe(
          3,
          ProbeRole.food,
          'Probe 3',
          tempF10: 1540,
          rate: 45,
          recent: _spark(1200, 1540),
        ),
        _probe(4, ProbeRole.unused, 'Probe 4'),
      ], name: ''),
    ),
  ],
);

/// The safety arc: base goes silent, data ages to stale then frozen, then a
/// packet returns. Proves derived values are removed, not greyed.
final LabScenario _baseLost = LabScenario(
  id: 'base_lost',
  title: 'Base station lost → stale → frozen → back',
  blurb:
      'The most important safety flow: a stale number must never look live. '
      'Watch the veil, the removed gauges, and the return.',
  frames: [
    LabFrame(
      atS: 0,
      label: 'Live',
      plan: _brisket(),
      freshness: ProbeFreshness.live,
      snapshot: _snap(
        [
          _probe(
            1,
            ProbeRole.pit,
            'Pit',
            tempF10: 2470,
            rate: -6,
            recent: _spark(2440, 2470),
          ),
          _probe(
            2,
            ProbeRole.food,
            'Brisket',
            tempF10: 1710,
            rate: 18,
            recent: _spark(1600, 1710),
          ),
        ],
        elapsedS: 6 * 3600,
        lastPacketSAgo: 8,
      ),
    ),
    LabFrame(
      atS: 120,
      label: 'Aging — pulse stops, "updated 1m ago"',
      plan: _brisket(),
      freshness: ProbeFreshness.aging,
      snapshot: _snap(
        [
          _probe(
            1,
            ProbeRole.pit,
            'Pit',
            tempF10: 2470,
            rate: -6,
            recent: _spark(2440, 2470),
          ),
          _probe(
            2,
            ProbeRole.food,
            'Brisket',
            tempF10: 1710,
            rate: 18,
            recent: _spark(1600, 1710),
          ),
        ],
        elapsedS: 6 * 3600,
        lastPacketSAgo: 70,
      ),
    ),
    LabFrame(
      atS: 300,
      label: 'Stale — dimmed, derived values REMOVED',
      plan: _brisket(),
      freshness: ProbeFreshness.stale,
      snapshot: _snap(
        [
          _probe(
            1,
            ProbeRole.pit,
            'Pit',
            tempF10: 2470,
            recent: _spark(2440, 2470),
          ),
          _probe(
            2,
            ProbeRole.food,
            'Brisket',
            tempF10: 1710,
            recent: _spark(1600, 1710),
          ),
        ],
        elapsedS: 6 * 3600,
        lastPacketSAgo: 240,
      ),
    ),
    LabFrame(
      atS: 700,
      label: 'Frozen — base lost, "LAST", crimson',
      plan: _brisket(),
      freshness: ProbeFreshness.frozen,
      snapshot: _snap(
        [
          _probe(1, ProbeRole.pit, 'Pit', tempF10: 2470),
          _probe(2, ProbeRole.food, 'Brisket', tempF10: 1710),
        ],
        elapsedS: 6 * 3600,
        baseLost: true,
        lastPacketSAgo: 640,
      ),
    ),
    LabFrame(
      atS: 800,
      label: 'Back — a packet arrives, live again',
      plan: _brisket(),
      freshness: ProbeFreshness.live,
      snapshot: _snap(
        [
          _probe(
            1,
            ProbeRole.pit,
            'Pit',
            tempF10: 2455,
            rate: -10,
            recent: _spark(2440, 2455),
          ),
          _probe(
            2,
            ProbeRole.food,
            'Brisket',
            tempF10: 1724,
            rate: 16,
            recent: _spark(1710, 1724),
          ),
        ],
        elapsedS: 6 * 3600 + 15 * 60,
        lastPacketSAgo: 6,
      ),
    ),
  ],
);

/// An alarm fires and is acknowledged.
final LabScenario _alarm = LabScenario(
  id: 'alarm',
  title: 'Pit crash alarm → acknowledge',
  blurb:
      'The pit falls out of its band; the alarm bar drops in with one tap to '
      'silence.',
  frames: [
    LabFrame(
      atS: 0,
      label: 'Fire fading',
      plan: _brisket(),
      snapshot: _snap([
        _probe(
          1,
          ProbeRole.pit,
          'Pit',
          tempF10: 2180,
          rate: -140,
          recent: _spark(2500, 2180),
        ),
        _probe(
          2,
          ProbeRole.food,
          'Brisket',
          tempF10: 1650,
          rate: 10,
          recent: _spark(1600, 1650),
        ),
      ], elapsedS: 4 * 3600),
    ),
    LabFrame(
      atS: 60,
      label: 'Pit crash alarm — unacked',
      plan: _brisket(),
      snapshot: _snap(
        [
          _probe(
            1,
            ProbeRole.pit,
            'Pit',
            tempF10: 1780,
            rate: -160,
            alarm: const Alarm(
              id: 7,
              rule: 'pit_crash',
              probe: 1,
              valueF10: 1780,
              severity: AlarmSeverity.critical,
            ),
            recent: _spark(2500, 1780),
          ),
          _probe(
            2,
            ProbeRole.food,
            'Brisket',
            tempF10: 1655,
            rate: 8,
            recent: _spark(1600, 1655),
          ),
        ],
        elapsedS: 4 * 3600 + 1,
        alarms: const [
          Alarm(
            id: 7,
            rule: 'pit_crash',
            probe: 1,
            valueF10: 1780,
            severity: AlarmSeverity.critical,
          ),
        ],
      ),
    ),
    LabFrame(
      atS: 120,
      label: 'Acknowledged — recovering',
      plan: _brisket(),
      snapshot: _snap(
        [
          _probe(
            1,
            ProbeRole.pit,
            'Pit',
            tempF10: 1990,
            rate: 180,
            recent: _spark(1780, 1990),
          ),
          _probe(
            2,
            ProbeRole.food,
            'Brisket',
            tempF10: 1660,
            rate: 9,
            recent: _spark(1600, 1660),
          ),
        ],
        elapsedS: 4 * 3600 + 2,
        alarms: const [
          Alarm(
            id: 7,
            rule: 'pit_crash',
            probe: 1,
            valueF10: 1990,
            severity: AlarmSeverity.critical,
            acked: true,
          ),
        ],
      ),
    ),
  ],
);

/// Verbatim tenths-°F from the real Smoke X4 capture (2026-07-25,
/// `protocol/fixtures/live-x4-2026-07-25/recent_series.json`): 109 samples at a
/// 30 s step, four jacks, from the paired X4 `LMXC[\`. Jack 4 sat on the grate
/// (261.8–273.8 °F); jacks 1–3 hung off the grill (95–158 °F). Hard-coded so the
/// simulator reproduces the exact bytes the app rendered live, with no fixture
/// file at runtime.
const List<List<int>> _liveX4SeriesF10 = <List<int>>[
  [
    1086,
    1090,
    1081,
    1083,
    1065,
    1114,
    1093,
    1047,
    1052,
    1053,
    1044,
    1036,
    1026,
    1059,
    1049,
    1032,
    1019,
    1041,
    1082,
    1067,
    1059,
    1073,
    1067,
    1093,
    1065,
    1072,
    1061,
    1054,
    1074,
    1106,
    1095,
    1087,
    1062,
    1083,
    1053,
    1071,
    1106,
    1053,
    1046,
    1073,
    1083,
    1053,
    1065,
    1120,
    1147,
    1167,
    1082,
    1096,
    1106,
    1110,
    1084,
    1096,
    1061,
    1029,
    1047,
    1054,
    1098,
    1073,
    1067,
    1094,
    1065,
    1111,
    1130,
    1102,
    1130,
    1159,
    1154,
    1117,
    1092,
    1060,
    1020,
    1022,
    1038,
    1012,
    1006,
    993,
    976,
    1038,
    1008,
    1013,
    1032,
    980,
    1007,
    978,
    991,
    977,
    955,
    975,
    983,
    1001,
    977,
    963,
    956,
    980,
    999,
    978,
    997,
    977,
    964,
    954,
    980,
    985,
    964,
    968,
    969,
    965,
    953,
    952,
    973,
  ], // jack 1: pit, off the grill
  [
    1063,
    1139,
    1126,
    1111,
    1093,
    1123,
    1123,
    1081,
    1106,
    1130,
    1135,
    1076,
    1046,
    1076,
    1083,
    1106,
    1073,
    1080,
    1116,
    1098,
    1087,
    1086,
    1080,
    1106,
    1087,
    1139,
    1123,
    1078,
    1104,
    1136,
    1164,
    1124,
    1111,
    1117,
    1131,
    1169,
    1163,
    1099,
    1126,
    1169,
    1173,
    1129,
    1134,
    1169,
    1184,
    1172,
    1117,
    1145,
    1151,
    1167,
    1117,
    1114,
    1077,
    1053,
    1060,
    1104,
    1125,
    1108,
    1107,
    1143,
    1096,
    1150,
    1156,
    1147,
    1184,
    1185,
    1206,
    1174,
    1151,
    1098,
    1086,
    1053,
    1048,
    1035,
    1014,
    1004,
    1032,
    1067,
    1048,
    1049,
    1042,
    991,
    1001,
    979,
    996,
    993,
    974,
    995,
    996,
    1006,
    982,
    976,
    978,
    994,
    1001,
    983,
    1006,
    982,
    994,
    967,
    1006,
    985,
    995,
    995,
    995,
    1000,
    997,
    999,
    1002,
  ], // jack 2: food, off the grill
  [
    1226,
    1275,
    1253,
    1235,
    1229,
    1257,
    1268,
    1228,
    1239,
    1271,
    1317,
    1318,
    1295,
    1375,
    1362,
    1344,
    1340,
    1351,
    1389,
    1419,
    1400,
    1411,
    1384,
    1418,
    1442,
    1450,
    1446,
    1384,
    1398,
    1444,
    1480,
    1443,
    1502,
    1500,
    1545,
    1536,
    1511,
    1439,
    1460,
    1484,
    1490,
    1456,
    1502,
    1560,
    1547,
    1551,
    1452,
    1491,
    1554,
    1503,
    1460,
    1467,
    1429,
    1376,
    1407,
    1537,
    1505,
    1473,
    1475,
    1484,
    1508,
    1559,
    1571,
    1569,
    1581,
    1549,
    1536,
    1476,
    1440,
    1430,
    1408,
    1344,
    1321,
    1306,
    1279,
    1295,
    1366,
    1384,
    1338,
    1290,
    1259,
    1170,
    1196,
    1163,
    1162,
    1155,
    1136,
    1144,
    1144,
    1158,
    1132,
    1142,
    1139,
    1142,
    1144,
    1137,
    1123,
    1112,
    1122,
    1114,
    1136,
    1122,
    1127,
    1150,
    1160,
    1169,
    1175,
    1136,
    1123,
  ], // jack 3: food, off the grill
  [
    2713,
    2715,
    2713,
    2713,
    2711,
    2712,
    2708,
    2710,
    2704,
    2707,
    2703,
    2708,
    2709,
    2714,
    2713,
    2712,
    2715,
    2723,
    2721,
    2726,
    2730,
    2729,
    2726,
    2723,
    2717,
    2719,
    2718,
    2721,
    2719,
    2724,
    2722,
    2725,
    2723,
    2725,
    2725,
    2724,
    2724,
    2726,
    2726,
    2730,
    2733,
    2726,
    2722,
    2724,
    2733,
    2734,
    2734,
    2737,
    2738,
    2734,
    2735,
    2734,
    2732,
    2724,
    2719,
    2717,
    2715,
    2711,
    2707,
    2707,
    2704,
    2704,
    2701,
    2694,
    2692,
    2689,
    2684,
    2682,
    2685,
    2677,
    2671,
    2670,
    2658,
    2655,
    2647,
    2648,
    2644,
    2638,
    2635,
    2635,
    2633,
    2630,
    2625,
    2628,
    2627,
    2623,
    2620,
    2618,
    2622,
    2624,
    2626,
    2625,
    2620,
    2622,
    2624,
    2626,
    2628,
    2628,
    2633,
    2634,
    2628,
    2622,
    2622,
    2623,
    2624,
    2630,
    2627,
    2629,
    2623,
  ], // jack 4: on the grate
];

/// **The real cook, replayed.** One [LabFrame] per captured sample (t = i·30 s):
/// the growing recent-window sparkline and the per-sample rate are computed the
/// same way the shipping dashboard computes them — [rateOfChange] over the
/// 10-minute window, [dashboardRecentWindowS] for the spark — so what the lab
/// shows is what shipped, just fed from the board's own numbers instead of a
/// live link. Instrument mode: these are raw probes with no cook plan.
LabScenario _realX4() {
  const step = 30;
  const roles = [ProbeRole.pit, ProbeRole.food, ProbeRole.food, ProbeRole.food];
  const names = ['Probe 1', 'Probe 2', 'Probe 3', 'Probe 4 (grate)'];
  final n = _liveX4SeriesF10[0].length;

  final frames = <LabFrame>[];
  for (var i = 0; i < n; i++) {
    final nowT = i * step;
    final probes = <ProbeView>[];
    for (var j = 0; j < 4; j++) {
      final jack = _liveX4SeriesF10[j];
      // The window the dashboard keeps for the spark and the rate: valid points
      // inside the last hour. The whole 54-minute cook fits, so it grows one
      // sample at a time — exactly what the phone shows early in a cook.
      final recent = <ValuePoint>[
        for (var k = 0; k <= i; k++)
          if (k * step > nowT - dashboardRecentWindowS)
            (t: k * step, f: jack[k].toDouble()),
      ];
      probes.add(
        _probe(
          j + 1,
          roles[j],
          names[j],
          tempF10: jack[i],
          // The production rate: OLS over the 10-minute window, null until it
          // has enough real samples — no invented slope on a cold start.
          rate: rateOfChange(<TempPoint>[
            for (final v in recent) (t: v.t, f: v.f),
          ], atT: nowT),
          recent: recent,
        ),
      );
    }
    frames.add(
      LabFrame(
        atS: nowT,
        label:
            'Real cook · ${nowT ~/ 60} min in · '
            'grate ${(_liveX4SeriesF10[3][i] / 10).round()}°F',
        snapshot: _snap(probes, name: '', elapsedS: nowT, lastPacketSAgo: 4),
      ),
    );
  }
  return LabScenario(
    id: 'real_x4',
    title: '★ Real Smoke X4 — 54 min',
    blurb:
        'Your actual cook, replayed from the capture: probe 4 on the grate '
        '~265°F, probes 1–3 off the grill. Every rate and sparkline is derived '
        'the way the app derives them — real data, no live link.',
    frames: frames,
  );
}

/// **BLE-degraded link.** Connected over Bluetooth, where the 16-byte
/// `live_state` notify carries temperatures but not names, config, or history
/// (06 §6.2): probes fall back to jack numbers, jack 1 to "pit", and the chart
/// to a 2-hour preview. Instrument mode, real numbers — so a review sees what a
/// BLE session actually looks like: not an error, a capable but limited link.
LabScenario _bleDegraded() {
  const roles = [ProbeRole.pit, ProbeRole.food, ProbeRole.food, ProbeRole.food];
  const names = ['Probe 1', 'Probe 2', 'Probe 3', 'Probe 4'];

  LabFrame frameAt(int i, int atS, String label) {
    final start = i - 20 < 0 ? 0 : i - 20;
    final probes = <ProbeView>[];
    for (var j = 0; j < 4; j++) {
      final jack = _liveX4SeriesF10[j];
      final recent = <ValuePoint>[
        for (var k = start; k <= i; k++) (t: k * 30, f: jack[k].toDouble()),
      ];
      probes.add(
        _probe(
          j + 1,
          roles[j],
          names[j],
          tempF10: jack[i],
          rate: rateOfChange(<TempPoint>[
            for (final v in recent) (t: v.t, f: v.f),
          ], atT: i * 30),
          recent: recent,
        ),
      );
    }
    return LabFrame(
      atS: atS,
      label: label,
      snapshot: _snap(
        probes,
        name: '',
        elapsedS: i * 30,
        link: LinkKind.ble,
        fullHistory: false,
        lastPacketSAgo: 3,
      ),
    );
  }

  return LabScenario(
    id: 'ble_degraded',
    title: 'BLE link (degraded)',
    blurb:
        'Bluetooth only: names read as jack numbers and history is a two-hour '
        'preview, because the BLE live_state can carry neither. Not an error — a '
        'capable, limited link.',
    frames: [
      frameAt(40, 0, 'On BLE — probes are jack numbers'),
      frameAt(60, 300, 'Still streaming over BLE'),
    ],
  );
}

/// **Offline, on cache.** The app reopened with no bridge in range: it renders
/// the last cached readings and nothing pretends to be live. The freshness
/// ladder does the honest work — dimmed with derived values removed at [stale],
/// a `LAST` chip at [frozen] (13 §13.6.1). LinkKind.offline; guided, so the
/// removed gauges are visible. The numbers are captured tenths, read back cold.
LabScenario _offlineCached() {
  ProbeView pit(int f10) => _probe(1, ProbeRole.pit, 'Pit', tempF10: f10);
  ProbeView food(int f10) => _probe(2, ProbeRole.food, 'Brisket', tempF10: f10);
  return LabScenario(
    id: 'offline_cached',
    title: 'Offline — cached readings',
    blurb:
        'No bridge in range: the app shows the last cached numbers and refuses '
        'to fake liveness. Watch the dim, the removed gauges, and the LAST chip.',
    frames: [
      LabFrame(
        atS: 0,
        label: 'Reopened offline — cache is stale',
        plan: _brisket(),
        freshness: ProbeFreshness.stale,
        snapshot: _snap(
          [pit(2684), food(1581)],
          elapsedS: 3 * 3600,
          link: LinkKind.offline,
          fullHistory: false,
          lastPacketSAgo: 320,
        ),
      ),
      LabFrame(
        atS: 180,
        label: 'Cache frozen — "LAST", no live claim',
        plan: _brisket(),
        freshness: ProbeFreshness.frozen,
        snapshot: _snap(
          [pit(2684), food(1581)],
          elapsedS: 3 * 3600,
          link: LinkKind.offline,
          fullHistory: false,
          baseLost: true,
          lastPacketSAgo: 900,
        ),
      ),
    ],
  );
}

/// **Reconnect, with the gap drawn.** Live → the base goes silent (frozen,
/// base-lost) → a packet returns. The sparkline keeps the outage honest: the
/// pre-drop window and the post-reconnect window are separated by the real time
/// hole, so the line spans a visible gap instead of pretending the missing
/// minutes were flat. Instrument mode, because the spark is where the gap shows.
LabScenario _reconnect() {
  const roles = [ProbeRole.pit, ProbeRole.food, ProbeRole.food, ProbeRole.food];
  const names = ['Probe 1', 'Probe 2', 'Probe 3', 'Probe 4 (grate)'];

  // Two captured windows with a ten-minute hole between them: samples 0–20
  // stream live (t 0–600 s), the link drops, and samples 40–48 return at
  // t 1200 s, so the sparkline draws the outage rather than faking it flat.
  List<ValuePoint> live(int j) => <ValuePoint>[
    for (var k = 0; k <= 20; k++)
      (t: k * 30, f: _liveX4SeriesF10[j][k].toDouble()),
  ];
  List<ValuePoint> afterGap(int j) => <ValuePoint>[
    ...live(j),
    for (var m = 0; m < 9; m++)
      (t: 1200 + m * 30, f: _liveX4SeriesF10[j][40 + m].toDouble()),
  ];

  ProbeView p(
    int j, {
    required List<ValuePoint> recent,
    required int tempF10,
    double? rate,
  }) => _probe(
    j + 1,
    roles[j],
    names[j],
    tempF10: tempF10,
    rate: rate,
    recent: recent,
  );

  return LabScenario(
    id: 'reconnect',
    title: 'Reconnect (drawn gap)',
    blurb:
        'Live, then the base goes silent, then a packet returns. The sparkline '
        'draws the outage as a real gap — the missing minutes are never faked '
        'as a flat line.',
    frames: [
      LabFrame(
        atS: 0,
        label: 'Streaming — signal strong',
        snapshot: _snap(
          [
            for (var j = 0; j < 4; j++)
              p(
                j,
                recent: live(j),
                tempF10: _liveX4SeriesF10[j][20],
                rate: rateOfChange(<TempPoint>[
                  for (final v in live(j)) (t: v.t, f: v.f),
                ], atT: 600),
              ),
          ],
          name: '',
          elapsedS: 600,
          lastPacketSAgo: 4,
        ),
      ),
      LabFrame(
        atS: 700,
        label: 'Base station silent — readings frozen',
        freshness: ProbeFreshness.frozen,
        snapshot: _snap(
          [
            for (var j = 0; j < 4; j++)
              p(j, recent: live(j), tempF10: _liveX4SeriesF10[j][20]),
          ],
          name: '',
          elapsedS: 600,
          baseLost: true,
          lastPacketSAgo: 100,
        ),
      ),
      LabFrame(
        atS: 1200,
        label: 'Reconnected — the gap is drawn',
        snapshot: _snap(
          [
            for (var j = 0; j < 4; j++)
              p(j, recent: afterGap(j), tempF10: _liveX4SeriesF10[j][48]),
          ],
          name: '',
          elapsedS: 1440,
          lastPacketSAgo: 4,
        ),
      ),
    ],
  );
}

/// Every scenario, in the order the lab lists them. The real capture leads.
final List<LabScenario> labScenarios = [
  _realX4(),
  _brisketCook,
  _instrument,
  _bleDegraded(),
  _baseLost,
  _reconnect(),
  _offlineCached(),
  _alarm,
];
