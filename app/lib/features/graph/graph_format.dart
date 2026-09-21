/// N7 — the Graph screen's pure projections.
///
/// Formatting, the view window and the render-model arithmetic only: no Flutter,
/// no repository. Kept out of the widgets so the prototype's exact
/// `graphDomain`/`graphSeries` behaviour and the chart invariants can be
/// unit-tested without a binding.
///
/// The rules this file holds:
///
///  * **`app.js` `graphDomain` is reproduced exactly** — range chips pick a base
///    span, zoom divides it (never below 2 minutes) and pan walks the window
///    back from "now".
///  * **Series are built from a real sample grid.** The mock carries a 12-point
///    `spark` per probe, not a sample stream, so [buildGraphSamples] resamples
///    it onto one aligned time grid (all jacks share a `t`, like the bridge)
///    before [buildGraphSeries] hands it to N1.14. That keeps run-splitting
///    before decimation, gap honesty and the min/max envelope intact.
///  * **Detached and unused probes contribute no points at all (I3).**
library;

import '../../data/content/catalog.dart';
import '../../data/model/cook_state.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';

/// The four range chips.
enum GraphRange {
  m15,
  h1,
  h6,
  all;

  /// The chip label (`15m` / `1h` / `6h` / `all`).
  String get label => switch (this) {
    GraphRange.m15 => '15m',
    GraphRange.h1 => '1h',
    GraphRange.h6 => '6h',
    GraphRange.all => 'all',
  };

  /// The base span in minutes, or null for "everything so far".
  double? get minutes => switch (this) {
    GraphRange.m15 => 15,
    GraphRange.h1 => 60,
    GraphRange.h6 => 360,
    GraphRange.all => null,
  };
}

const Object _unset = Object();

/// The Graph screen's view state: range chip, zoom, pan and the isolated jack.
///
/// This is the whole of the prototype's `state.chartRange`, `state.graph` and
/// `state.isolatedProbe`, in one value object. It is shared by the inline chart
/// and the fullscreen host so the two can never show different windows.
class GraphViewState {
  const GraphViewState({
    this.range = GraphRange.all,
    this.zoom = 1,
    this.pan = 0,
    this.isolatedJack,
  });

  final GraphRange range;

  /// 1 = full span; up to 40 (the prototype's cap).
  final double zoom;

  /// Minutes the window has been walked back from "now".
  final double pan;

  /// The one jack shown at full strength, or null for "show all".
  final int? isolatedJack;

  static const GraphViewState initial = GraphViewState();

  /// Whether the Reset-view link should be offered.
  bool get canReset => zoom > 1 || pan > 0;

  GraphViewState copyWith({
    GraphRange? range,
    double? zoom,
    double? pan,
    Object? isolatedJack = _unset,
  }) => GraphViewState(
    range: range ?? this.range,
    zoom: zoom ?? this.zoom,
    pan: pan ?? this.pan,
    isolatedJack: identical(isolatedJack, _unset)
        ? this.isolatedJack
        : isolatedJack as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is GraphViewState &&
      other.range == range &&
      other.zoom == zoom &&
      other.pan == pan &&
      other.isolatedJack == isolatedJack;

  @override
  int get hashCode => Object.hash(range, zoom, pan, isolatedJack);
}

/// The x-window the chart draws, in minutes since the cook started.
class GraphDomain {
  const GraphDomain({
    required this.startedMs,
    required this.elapsedMin,
    required this.xMin,
    required this.xMax,
    required this.nowMin,
  });

  /// Wall-clock anchor of `x = 0`; never null (the prototype falls back to
  /// `now - 60 min` for a cook that was never started).
  final int startedMs;

  /// The whole session so far, in minutes.
  final double elapsedMin;

  final double xMin;
  final double xMax;

  /// Where "now" sits in the same minute space.
  final double nowMin;

  double get span => xMax - xMin;

  /// Whether the now cursor is inside the visible window.
  bool get nowVisible => nowMin >= xMin && nowMin <= xMax;

  /// The wall-clock time of a minute offset into the session.
  DateTime timeAt(double minutes) => DateTime.fromMillisecondsSinceEpoch(
    startedMs + (minutes * 60000).round(),
  );
}

/// The prototype's `graphDomain()`, exactly.
GraphDomain graphDomain({
  required int? startedAtMs,
  required int nowMs,
  required GraphViewState view,
}) {
  final started = startedAtMs ?? (nowMs - 60 * 60000);
  final rawElapsed = (nowMs - started) / 60000;
  final elapsed = rawElapsed < 5 ? 5.0 : rawElapsed;
  final base = view.range.minutes ?? elapsed;
  final zoom = view.zoom <= 0 ? 1.0 : view.zoom;
  final span = (base / zoom) < 2 ? 2.0 : base / zoom;
  final viewEnd = (elapsed - view.pan) > span ? elapsed - view.pan : span;
  final xMin = (viewEnd - span) < 0 ? 0.0 : viewEnd - span;
  final xMax = (xMin + span) > elapsed ? elapsed : xMin + span;
  return GraphDomain(
    startedMs: started,
    elapsedMin: elapsed,
    xMin: xMin,
    xMax: xMax,
    nowMin: elapsed,
  );
}

/// One attached probe's chart identity.
class GraphSeriesMeta {
  const GraphSeriesMeta({
    required this.jack,
    required this.label,
    required this.isPit,
  });

  final ProbeJack jack;

  /// The legend/tooltip name (the cook's cut name, `Grate · jack 4`, …).
  final String label;

  /// The grate line is drawn thicker (N7.3).
  final bool isPit;
}

/// A labelled target line, in display units.
class GraphTarget {
  const GraphTarget({
    required this.jack,
    required this.value,
    required this.label,
  });

  final ProbeJack jack;

  /// Display-unit value (already converted from canonical °F).
  final double value;
  final String label;
}

/// The shaded pit band, in display units.
class GraphBand {
  const GraphBand({required this.min, required this.max});

  final double min;
  final double max;
}

/// A mark's vertical line.
class GraphMark {
  const GraphMark({
    required this.xMin,
    required this.label,
    required this.kind,
  });

  final double xMin;
  final String label;
  final MarkKind kind;
}

/// One probe's High/Avg/Low over the visible window.
class GraphStat {
  const GraphStat({required this.jack, this.highF10, this.avgF10, this.lowF10});

  final ProbeJack jack;

  /// Canonical tenths-°F; null when the probe had no readings in the window.
  final int? highF10;
  final int? avgF10;
  final int? lowF10;

  bool get hasReadings => highF10 != null;
}

/// The stroke pattern for a jack: P1 solid, P2 dashed, P3 dotted, P4 dash-dot.
///
/// Hue is never the only identity channel (research notes §9.3), so this is the
/// second channel and it is exactly the prototype's `legendSwatch` pattern.
List<int>? seriesDashArray(int jack) => switch (jack) {
  1 => null,
  2 => const <int>[7, 4],
  3 => const <int>[2, 4],
  _ => const <int>[9, 3, 2, 3],
};

/// The legend swatch's dash pattern (logical pixels).
List<double>? seriesDash(ProbeJack jack) => seriesDashArray(
  jack.n,
)?.map((final int v) => v.toDouble()).toList(growable: false);

/// The pit line is thicker than a food line (prototype `s.width`).
double seriesWidth(ProbeRole role) => role == ProbeRole.pit ? 2.6 : 2.0;

/// The narrowest sample cadence the chart resamples to.
const int graphMinCadenceS = 30;

/// The cap on the resampled grid, so a 15-hour cook still pans smoothly.
const int graphMaxSamples = 1200;

/// The resample cadence for a session [elapsedS] long: 30 s, widened so the
/// grid never exceeds [graphMaxSamples].
int graphCadenceS(int elapsedS) {
  if (elapsedS <= graphMinCadenceS * graphMaxSamples) {
    return graphMinCadenceS;
  }
  return (elapsedS / graphMaxSamples).ceil();
}

/// Resamples the probes' `spark` onto one aligned session-seconds grid.
///
/// Every jack shares a `t`, which is what a real bridge stream looks like and
/// what keeps N1.14's cadence-derived gap threshold honest. Detached/unused
/// probes leave `null` in their slot, never a fabricated zero (I3).
List<Sample> buildGraphSamples({
  required List<ProbeState> probes,
  required CookState cook,
  required int nowMs,
}) {
  final start = cook.startedAtMs ?? (nowMs - 60 * 60000);
  final rawElapsed = ((nowMs - start) / 1000).round();
  final elapsedS = rawElapsed.clamp(60, 48 * 3600);
  final cadence = graphCadenceS(elapsedS);
  final count = (elapsedS ~/ cadence) + 1;
  final out = <Sample>[];
  for (var i = 0; i < count; i++) {
    final t = count <= 1 ? 0 : (i * elapsedS / (count - 1)).round();
    final temps = <int?>[null, null, null, null];
    for (final probe in probes) {
      if (!isLiveProbe(probe)) {
        continue;
      }
      final value = _sampleValue(probe, i, count);
      if (value != null) {
        temps[probe.jack.n - 1] = value;
      }
    }
    out.add(Sample(t: t, tempsF10: temps));
  }
  return out;
}

/// The probe's reading at grid position [index], interpolated through its
/// `spark` (or its low/current endpoints when there is no spark).
int? _sampleValue(ProbeState probe, int index, int count) {
  final spark = probe.spark;
  final u = count <= 1 ? 0.0 : index / (count - 1);
  if (spark.isNotEmpty) {
    if (spark.length == 1) {
      return spark.first;
    }
    final scaled = u * (spark.length - 1);
    final i0 = scaled.floor().clamp(0, spark.length - 2);
    final frac = scaled - i0;
    return (spark[i0] + (spark[i0 + 1] - spark[i0]) * frac).round();
  }
  final lo = probe.lowF10;
  final hi = probe.tempF10;
  if (lo == null && hi == null) {
    return null;
  }
  final a = (lo ?? hi)!;
  final b = (hi ?? lo)!;
  return (a + (b - a) * u).round();
}

/// Builds the N1.14 render model for [domain] over [samples].
ChartSeriesModel buildGraphSeries({
  required List<Sample> samples,
  required GraphDomain domain,
  required List<ProbeJack> probes,
}) => buildChartSeries(
  samples,
  fromT: (domain.xMin * 60).round(),
  toT: (domain.xMax * 60).round(),
  probes: probes,
);

/// The y-gauge bounds, in display units: the prototype's `floor((lo-8)/25)*25`
/// / `ceil((hi+8)/25)*25` over the window's series extent.
({double min, double max}) graphYBounds(ChartSeriesModel model, TempUnit unit) {
  final lo = model.minF;
  final hi = model.maxF;
  if (lo == null || hi == null) {
    // The prototype's empty-chart default: 32–220 °F.
    return (
      min: _floor25(displayTemp(32, unit) - 8),
      max: _ceil25(displayTemp(220, unit) + 8),
    );
  }
  final min = _floor25(displayTemp(lo, unit) - 8);
  var max = _ceil25(displayTemp(hi, unit) + 8);
  if (max <= min) {
    max = min + 25;
  }
  return (min: min, max: max);
}

double _floor25(double v) => (v / 25).floorToDouble() * 25;
double _ceil25(double v) => (v / 25).ceilToDouble() * 25;

/// A canonical °F value in [unit] (the only conversion point).
double displayTemp(double f, TempUnit unit) =>
    TempValue.ofF10((f * 10).round()).toDisplay(unit)!;

/// The attached probes' chart identities, in jack order.
List<GraphSeriesMeta> graphSeriesMeta({
  required List<ProbeState> probes,
  required CookState cook,
  required CatalogTable catalog,
}) => <GraphSeriesMeta>[
  for (final probe in probes)
    if (isLiveProbe(probe))
      GraphSeriesMeta(
        jack: probe.jack,
        label: probeName(probe, cook, catalog),
        isPit: probe.role == ProbeRole.pit,
      ),
];

/// The target lines for every attached probe that has one.
List<GraphTarget> graphTargets({
  required List<ProbeState> probes,
  required TempUnit unit,
}) => <GraphTarget>[
  for (final probe in probes)
    if (isLiveProbe(probe) && probe.targetF10 != null)
      GraphTarget(
        jack: probe.jack,
        value: displayTemp(probe.targetF10! / 10, unit),
        label: '${fmtTemp0(probe.targetF10, unit)}${unit.suffix}',
      ),
];

/// The shaded pit band, or null when the cook has no band.
GraphBand? graphPitBand(CookState cook, TempUnit unit) {
  final min = cook.pitBandMinF10;
  final max = cook.pitBandMaxF10;
  if (min == null || max == null) {
    return null;
  }
  return GraphBand(
    min: displayTemp(min / 10, unit),
    max: displayTemp(max / 10, unit),
  );
}

/// The marks that fall inside [domain], as vertical lines.
List<GraphMark> graphMarks({
  required List<Mark> marks,
  required GraphDomain domain,
}) => <GraphMark>[
  for (final mark in marks)
    if (mark.t / 60 >= domain.xMin && mark.t / 60 <= domain.xMax)
      GraphMark(
        xMin: mark.t / 60,
        label: mark.text.isEmpty ? mark.kind.name : mark.text,
        kind: mark.kind,
      ),
];

/// High/Avg/Low per probe over the visible window.
///
/// High and Low come from N1.13's [cookStats] over the window samples; the
/// average is folded here because [ProbeStats] deliberately does not carry one.
List<GraphStat> graphWindowStats({
  required List<Sample> samples,
  required GraphDomain domain,
  required List<ProbeJack> probes,
}) {
  final fromT = (domain.xMin * 60).round();
  final toT = (domain.xMax * 60).round();
  final window = <Sample>[
    for (final sample in samples)
      if (sample.t >= fromT && sample.t <= toT) sample,
  ];
  final stats = cookStats(window).probes;
  final out = <GraphStat>[];
  for (final jack in probes) {
    ProbeStats? match;
    for (final stat in stats) {
      if (stat.jack == jack) {
        match = stat;
        break;
      }
    }
    if (match == null || match.samples == 0) {
      out.add(GraphStat(jack: jack));
      continue;
    }
    var sum = 0.0;
    var n = 0;
    for (final sample in window) {
      final value = sample.tempFor(jack);
      if (value != null) {
        sum += value / 10;
        n++;
      }
    }
    out.add(
      GraphStat(
        jack: jack,
        highF10: match.peakF == null ? null : (match.peakF! * 10).round(),
        avgF10: n == 0 ? null : ((sum / n) * 10).round(),
        lowF10: match.minF == null ? null : (match.minF! * 10).round(),
      ),
    );
  }
  return out;
}

/// The hint under the chart: the zoom factor, or how to zoom.
String graphZoomHint(GraphViewState view) => view.zoom > 1
    ? '${view.zoom.toStringAsFixed(1)}× zoom'
    : 'Pinch or scroll to zoom · drag to pan';

/// The legend's current-value cell (`164.2° F`), or `—` (I3).
String legendValue(ProbeState probe, TempUnit unit) =>
    probe.tempF10 == null ? '—' : TempValue.ofF10(probe.tempF10!).format(unit);
