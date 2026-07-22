/// The sim's scenario matrix (T3.5) — every case that is painful or
/// impossible to produce on real hardware. `long` is 54 days of samples,
/// which no one is going to cook.
library;

import 'dart:io';

import 'package:cookgen/cookgen.dart' as cg;

import 'state.dart';

const simScenarios = [
  'stall',
  'lid-open',
  'base-lost',
  'flaky',
  'unpaired',
  'detached',
  'celsius',
  'storage-full',
  'ota',
  'long',
];

/// Builds the state for a named scenario. [dropPct] feeds `flaky`,
/// [afterS] feeds `base-lost`.
SimState scenarioState(
  String name, {
  double speed = 1,
  int seed = 42,
  int probes = 4,
  double? dropPct,
  int? afterS,
  NowMs? nowMs,
}) {
  cg.GeneratedCook cook;
  var paired = true;
  var storageFull = false;
  int? baseLostAfterS;

  switch (name) {
    case 'stall' || 'lid-open' || 'detached' || 'celsius':
      cook = cg.generateScenario(name, seed: seed, probes: probes);
    case 'flaky':
      cook = cg.generateScenario(
        'flat',
        seed: seed,
        hours: 4,
        probes: probes,
        dropoutPct: dropPct ?? 10,
      );
    case 'base-lost':
      final cutoff = afterS ?? 2 * 3600;
      cook = cg.generateScenario(
        'flat',
        seed: seed,
        hours: (cutoff / 3600) + 1,
        probes: probes,
      );
      baseLostAfterS = cutoff;
    case 'unpaired':
      cook = cg.generateScenario('flat', seed: seed, hours: 1, probes: probes);
      paired = false;
    case 'storage-full':
      cook = cg.generateScenario('brisket-18h', seed: seed, probes: probes);
      storageFull = true;
    case 'ota':
      // A closed short cook so OTA is not refused for an active session.
      cook = cg.generateScenario('flat', seed: seed, hours: 1, probes: probes);
      return SimState(
        cook: cook,
        scenario: name,
        speed: speed,
        nowMs: nowMs ?? _pastEnd(cook),
      );
    case 'long':
      cook = cg.generateScenario('long', seed: seed, probes: probes);
    default:
      throw ArgumentError.value(
        name,
        'scenario',
        'unknown — expected one of $simScenarios',
      );
  }

  return SimState(
    cook: cook,
    scenario: name,
    speed: speed,
    paired: paired,
    storageFull: storageFull,
    baseLostAfterS: baseLostAfterS,
    nowMs: nowMs,
  );
}

/// A clock whose first reading (taken at SimState construction as the start
/// time) sits a whole cook in the past — so the session is already replayed.
NowMs _pastEnd(cg.GeneratedCook cook) {
  final endMs = (cook.samples.isEmpty ? 0 : cook.samples.last.t + 60) * 1000;
  var first = true;
  return () {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (first) {
      first = false;
      return now - endMs;
    }
    return now;
  };
}

/// Loads a cook from a `.smk` path, trying the path as given, then relative
/// to `protocol/`, then the repo root — so the documented
/// `--cook fixtures/brisket-18h.smk` works from the repo root.
cg.GeneratedCook loadCook(String path) {
  final candidates = [
    path,
    'protocol/$path',
    '${_repoRoot()}/protocol/$path',
    '${_repoRoot()}/$path',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) {
      final smk = cg.SmkFile.read(c);
      return cg.GeneratedCook(
        header: smk.header,
        samples: smk.samples,
        marks: smk.marks,
      );
    }
  }
  throw ArgumentError.value(path, 'cook', 'not found (tried $candidates)');
}

String _repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/protocol/records.yaml').existsSync()) {
    if (dir.parent.path == dir.path) {
      return '.';
    }
    dir = dir.parent;
  }
  return dir.path;
}
