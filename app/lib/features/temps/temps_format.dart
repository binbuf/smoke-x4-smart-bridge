/// N6 — the Temps screen's pure projections.
///
/// Formatting, grouping and the phase/trend arithmetic only: no Flutter, no
/// repository. Kept out of the widgets so the exact strings the prototype
/// renders and the I3/I4 gates can be unit-tested without a binding.
///
/// The two grouping rules come straight from `app.js` `viewTemps`:
/// * an **attached, in-use** probe gets a big card ([attachedProbes]);
/// * a **detached or unused** probe gets a row in "Not attached"
///   ([detachedProbes]) and must never render a numeric temperature (I3).
library;

import '../../data/content/catalog.dart';
import '../../data/model/catalog_entry.dart';
import '../../data/model/cook_state.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';

/// Attached, in-use probes — the ones that get a big [TempCard].
List<ProbeState> attachedProbes(List<ProbeState> probes) => <ProbeState>[
  for (final probe in probes)
    if (probe.attached && probe.role != ProbeRole.unused) probe,
];

/// Detached or unused probes — the "Not attached" section.
///
/// A probe that is plugged in but re-roled to `unused` belongs here too: the
/// device cannot tell a role from the plug, and an unused jack reads nothing.
List<ProbeState> detachedProbes(List<ProbeState> probes) => <ProbeState>[
  for (final probe in probes)
    if (!probe.attached || probe.role == ProbeRole.unused) probe,
];

/// The probe state for [jack], or a detached default when the snapshot omits it.
ProbeState probeFor(List<ProbeState> probes, ProbeJack jack) {
  for (final probe in probes) {
    if (probe.jack == jack) {
      return probe;
    }
  }
  return ProbeState(jack: jack);
}

/// The catalog cut assigned to [jack] in this cook, or null when none is.
CatalogEntry? cookEntryFor(
  CookState cook,
  CatalogTable catalog,
  ProbeJack jack,
) {
  for (final item in cook.items) {
    if (item.jack == jack) {
      return catalog.byId(item.presetId);
    }
  }
  return null;
}

/// The header's update word. The prototype: connected → `live`, else `stale`.
String updatedWord({required bool connected}) => connected ? 'live' : 'stale';

/// The card's freshness word. Reproduces the prototype's ladder exactly,
/// including the `stale` rung reading as `—` (it is the *frozen* rung that the
/// card calls "Stale").
String probeFreshnessWord(Freshness freshness) => switch (freshness) {
  Freshness.live => 'Live',
  Freshness.aging => 'Aging',
  Freshness.frozen => 'Stale',
  Freshness.stale || Freshness.unknown => '—',
};

/// The four phase-track labels (N6.8).
const List<String> kProbePhases = <String>[
  'Approaching',
  'Pull now',
  'Resting',
  'Ready',
];

/// The active phase index for the track, 0..3.
///
/// Reproduces `app.js` `phaseTrack` exactly: a reading at or above the target
/// jumps straight to [kProbePhases]'s `Ready`, so `Resting` is never the
/// current phase on this ladder. The pull crossing (or the target when there is
/// no pull) selects `Pull now`.
int probePhaseIndex({
  required int? tempF10,
  required int? pullF10,
  required int? targetF10,
}) {
  if (tempF10 == null || targetF10 == null) {
    return 0;
  }
  final pull = pullF10 ?? targetF10;
  if (tempF10 >= targetF10) {
    return 3;
  }
  if (tempF10 >= pull) {
    return 1;
  }
  return 0;
}

/// The trend chip's direction and label, in the prototype's exact strings.
///
/// A null rate renders the flat `stale` chip. Rates are shown in °F/hr (storage
/// is canonical °F and the prototype never converts a rate); the card only
/// calls this behind the I4 gate.
({TrendDirection direction, String label}) trendFor(double? rateFPerHr) {
  if (rateFPerHr == null) {
    return (direction: TrendDirection.flat, label: 'stale');
  }
  if (rateFPerHr.abs() < 0.6) {
    return (direction: TrendDirection.flat, label: '~0° F/hr');
  }
  return (
    direction: rateFPerHr > 0 ? TrendDirection.up : TrendDirection.down,
    label: '${rateFPerHr.abs().toStringAsFixed(1)}° F/hr',
  );
}

/// `201° F` / `94° C`, or `—` when absent (I3). The prototype's `fmtTemp(f, 0)`.
String fmtTempUnit(int? f10, TempUnit unit) {
  if (f10 == null) {
    return '—';
  }
  return '${fmtTemp0(f10, unit)}${unit.suffix}';
}

/// One cell in a card's meta grid.
typedef TempMetaCell = ({String label, String value});

/// The meta cells for a probe card, in the prototype's order (N6.4).
///
/// * grate → `Pit band` + `Status` (In band / Out);
/// * food with a target → `Target`, `Pull at`, `ETA`;
/// * always → `High`, `Avg`.
///
/// The ETA passes the I4 gate: a stale/frozen reading removes it rather than
/// greyed it, and a stalled live probe says `Stalled` instead.
List<TempMetaCell> tempMetaCells({
  required ProbeState probe,
  required CookState cook,
  required TempUnit unit,
  required bool isGrate,
}) {
  final cells = <TempMetaCell>[];
  if (isGrate) {
    final min = cook.pitBandMinF10;
    final max = cook.pitBandMaxF10;
    cells.add((
      label: 'Pit band',
      value: min == null || max == null
          ? '—'
          : '${fmtTemp0(min, unit)}–${fmtTemp0(max, unit)}°',
    ));
    final temp = probe.tempF10;
    final inBand =
        temp != null &&
        min != null &&
        max != null &&
        temp >= min &&
        temp <= max;
    cells.add((label: 'Status', value: inBand ? 'In band' : 'Out'));
  } else if (probe.targetF10 != null) {
    final canShow = probe.freshness.showsDerived;
    cells.add((label: 'Target', value: fmtTempUnit(probe.targetF10, unit)));
    cells.add((label: 'Pull at', value: fmtTempUnit(probe.pullF10, unit)));
    final eta = fmtEta(canShow ? probe.etaMin : null);
    cells.add((
      label: 'ETA',
      value: eta ?? (probe.stalled && canShow ? 'Stalled' : '—'),
    ));
  }
  cells.add((label: 'High', value: fmtTempUnit(probe.peakF10, unit)));
  cells.add((label: 'Avg', value: fmtTempUnit(probe.avgF10, unit)));
  return cells;
}

/// The pull temperature to advertise for [doneness] on [entry], tenths °F.
///
/// Uses the domain's floor-clamped [pullTempFor], so a "pull at X" notice never
/// invites a user below a protein's safe minimum (I12).
int pullForDoneness(CatalogEntry entry, Doneness doneness) => pullTempFor(
  targetF10: doneness.targetF10,
  carryoverF10: entry.carryoverF10,
  hazard: entry.hazard,
);

/// The doneness rung the probe is currently targeting, falling back to the
/// cut's default when the stored target does not match any rung.
Doneness selectedDoneness(CatalogEntry entry, int? targetF10) {
  for (final doneness in entry.doneness) {
    if (doneness.targetF10 == targetF10) {
      return doneness;
    }
  }
  return entry.defaultDoneness;
}
