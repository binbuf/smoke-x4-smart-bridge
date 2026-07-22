/// Scenario presets (T2.2 / T2.3) — each painful or impossible to produce on
/// real hardware, each reproducible from a seed.
library;

import 'package:bridge_protocol/bridge_protocol.dart';

import 'smk_io.dart';
import 'thermal.dart';


const scenarioNames = [
  'brisket-18h',
  'stall',
  'lid-open',
  'detached',
  'celsius',
  'flat',
  'long',
];

/// Builds a scenario. [hours] and [dropoutPct] override the preset where it
/// makes sense (`long` uses [hours] directly — default 1296 h ≈ 54 days).
GeneratedCook generateScenario(
  String scenario, {
  int seed = 42,
  double? hours,
  double? dropoutPct,
  int probes = 4,
}) {
  final fourProbes = [
    const ProbeSpec(role: 1, startF: 68, name: 'Pit'),
    const ProbeSpec(role: 2, startF: 38, k: 0.16, name: 'Brisket'),
    if (probes >= 3)
      const ProbeSpec(role: 2, startF: 40, k: 0.22, name: 'Point')
    else
      const ProbeSpec(role: 0, startF: 0),
    if (probes >= 4)
      const ProbeSpec(role: 3, startF: 74, name: 'Ambient')
    else
      const ProbeSpec(role: 0, startF: 0),
  ];

  CookModel model;
  var marks = <MarkRec>[];
  var name = scenario;

  switch (scenario) {
    case 'brisket-18h':
      final durationS = ((hours ?? 18) * 3600).round();
      model = CookModel(
        seed: seed,
        durationS: durationS,
        probes: fourProbes,
        lidOpens: const [
          LidOpenEvent(atS: 4 * 3600, dropF: 38, recoverS: 540),
          LidOpenEvent(atS: 11 * 3600 + 900, dropF: 30, recoverS: 480),
        ],
        stalls: const [
          StallEvent(startS: 5 * 3600, durationS: 3 * 3600 + 600),
        ],
        detaches: const [
          // Ambient probe unplugged for ~40 min mid-cook.
          DetachEvent(probe: 3, fromS: 9 * 3600, toS: 9 * 3600 + 2400),
        ],
        dropoutPct: dropoutPct ?? 1,
      );
      name = 'Brisket 18h (synthetic)';
      marks = [
        _mark(4 * 3600 + 60, 2, 0, 'lid open'),
        _mark(8 * 3600 + 1800, 1, 2, 'wrapped'),
        _mark(11 * 3600 + 960, 2, 0, 'lid open'),
        _mark(16 * 3600, 0, 0, 'smells incredible'),
      ];

    case 'stall':
      final durationS = ((hours ?? 8) * 3600).round();
      // Faster-converging cuts so the food is inside the 140–180 °F band
      // when the 2 h stall window opens.
      final stallProbes = [
        fourProbes[0],
        const ProbeSpec(role: 2, startF: 38, k: 0.38, name: 'Brisket'),
        const ProbeSpec(role: 2, startF: 40, k: 0.45, name: 'Point'),
        fourProbes[3],
      ];
      model = CookModel(
        seed: seed,
        durationS: durationS,
        probes: stallProbes,
        stalls: [
          StallEvent(startS: 2 * 3600, durationS: 3 * 3600, plateauF: 158),
        ],
        dropoutPct: dropoutPct ?? 0,
      );
      name = 'Stall study';

    case 'lid-open':
      final durationS = ((hours ?? 3) * 3600).round();
      model = CookModel(
        seed: seed,
        durationS: durationS,
        probes: fourProbes,
        lidOpens: const [LidOpenEvent(atS: 3600, dropF: 40, recoverS: 600)],
        dropoutPct: dropoutPct ?? 0,
      );
      name = 'Lid open';
      marks = [_mark(3660, 2, 0, 'lid open')];

    case 'detached':
      final durationS = ((hours ?? 2) * 3600).round();
      model = CookModel(
        seed: seed,
        durationS: durationS,
        probes: fourProbes,
        detaches: const [
          DetachEvent(probe: 1, fromS: 1800, toS: 3600),
          DetachEvent(probe: 2, fromS: 5400, toS: 6000),
        ],
        dropoutPct: dropoutPct ?? 0,
      );
      name = 'Detach study';

    case 'celsius':
      final durationS = ((hours ?? 2) * 3600).round();
      model = CookModel(
        seed: seed,
        durationS: durationS,
        probes: fourProbes,
        celsiusSwitch: const CelsiusSwitchEvent(atS: 3600),
        dropoutPct: dropoutPct ?? 0,
      );
      name = 'Mid-cook °C switch';

    case 'flat':
      final durationS = ((hours ?? 1) * 3600).round();
      model = CookModel(
        seed: seed,
        durationS: durationS,
        probes: fourProbes,
        dropoutPct: dropoutPct ?? 0,
      );
      name = 'Flat hour';

    case 'long':
      // 54 days of samples — nobody is going to cook this (T3.5).
      final durationS = ((hours ?? 1296) * 3600).round();
      model = CookModel(
        seed: seed,
        durationS: durationS,
        probes: fourProbes,
        stalls: const [
          StallEvent(startS: 5 * 3600, durationS: 3 * 3600),
        ],
        dropoutPct: dropoutPct ?? 0.2,
      );
      name = 'The long haul';

    default:
      throw ArgumentError.value(scenario, 'scenario',
          'unknown — expected one of $scenarioNames');
  }

  final samples = toSampleRecs(model.run());
  final header = buildHeader(
    sessionId: 27,
    sampleCount: samples.length,
    markCount: marks.length,
    probes: fourProbes,
    name: name,
  );
  return GeneratedCook(header: header, samples: samples, marks: marks);
}

MarkRec _mark(int t, int kind, int probe, String text) => MarkRec(
      t: t,
      kind: kind,
      probe: probe,
      textRaw: utf8ToPadded(text, 24),
    );
