/// N7 — the Graph screen's Riverpod seam.
///
/// The view state ([GraphViewState]) is shared by the inline chart and the
/// fullscreen host, so "the fullscreen chart matches the inline chart for the
/// same window" is true by construction, not by copying state.
///
/// The model is split in two so panning and zooming never resample the cook:
/// [graphSamplesProvider] resamples once per snapshot, and [graphModelProvider]
/// only re-windows the cached grid.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/content/catalog.dart';
import '../../data/model/cook_state.dart';
import '../../data/providers.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';
import 'graph_format.dart';

/// The Graph screen's clock. Overridable so the window is deterministic in
/// tests and goldens; read once per build, no ticker.
final graphNowProvider = Provider<DateTime>((ref) => DateTime.now());

/// The view state, with the prototype's exact mutations.
class GraphViewNotifier extends Notifier<GraphViewState> {
  @override
  GraphViewState build() => GraphViewState.initial;

  /// A range chip resets the zoom and pan (prototype `graph-range`).
  void setRange(GraphRange range) =>
      state = state.copyWith(range: range, zoom: 1, pan: 0);

  /// Zoom in/out, capped at 1–40×. Dropping back to 1× also clears the pan.
  void zoomBy(double factor) {
    final zoom = (state.zoom * factor).clamp(1.0, 40.0);
    state = state.copyWith(zoom: zoom, pan: zoom <= 1 ? 0 : state.pan);
  }

  /// Walk the window back by [delta] minutes; never past "now".
  void panBy(double delta) {
    final pan = state.pan + delta;
    state = state.copyWith(pan: pan < 0 ? 0 : pan);
  }

  /// Back to the full span.
  void reset() => state = state.copyWith(zoom: 1, pan: 0);

  /// Isolate one jack, or clear with null.
  void isolate(int? jack) => state = state.copyWith(isolatedJack: jack);

  /// Toggle isolation for [jack] (tap the legend entry).
  void toggleIsolate(int jack) =>
      isolate(state.isolatedJack == jack ? null : jack);
}

final graphViewProvider = NotifierProvider<GraphViewNotifier, GraphViewState>(
  GraphViewNotifier.new,
);

/// The resampled sample grid for the current snapshot. Depends only on the
/// snapshot and the clock, so pan/zoom do not rebuild it.
final graphSamplesProvider = Provider<List<Sample>?>((ref) {
  final snapshot = ref.watch(snapshotProvider).value;
  if (snapshot == null) {
    return null;
  }
  final now = ref.watch(graphNowProvider);
  return buildGraphSamples(
    probes: snapshot.probes,
    cook: snapshot.cook,
    nowMs: now.millisecondsSinceEpoch,
  );
});

/// Everything the chart, the legend and the stats table need for one window.
class GraphModel {
  const GraphModel({
    required this.series,
    required this.samples,
    required this.domain,
    required this.meta,
    required this.targets,
    required this.band,
    required this.marks,
    required this.stats,
    required this.probes,
    required this.cook,
    required this.unit,
    required this.catalog,
  });

  final ChartSeriesModel series;
  final List<Sample> samples;
  final GraphDomain domain;
  final List<GraphSeriesMeta> meta;
  final List<GraphTarget> targets;
  final GraphBand? band;
  final List<GraphMark> marks;
  final List<GraphStat> stats;
  final List<ProbeState> probes;
  final CookState cook;
  final TempUnit unit;
  final CatalogTable catalog;

  /// The attached, in-use jacks — the chart's series set.
  List<ProbeJack> get attachedJacks => <ProbeJack>[
    for (final probe in probes)
      if (isLiveProbe(probe)) probe.jack,
  ];

  /// The probe state for [jack], or a detached default (I3).
  ProbeState probeFor(ProbeJack jack) {
    for (final probe in probes) {
      if (probe.jack == jack) {
        return probe;
      }
    }
    return ProbeState(jack: jack);
  }
}

final graphModelProvider = Provider<GraphModel?>((ref) {
  final snapshot = ref.watch(snapshotProvider).value;
  final samples = ref.watch(graphSamplesProvider);
  if (snapshot == null || samples == null) {
    return null;
  }
  final unit = ref.watch(settingsProvider).value?.units ?? TempUnit.fahrenheit;
  final view = ref.watch(graphViewProvider);
  final now = ref.watch(graphNowProvider);
  final catalog = ref.watch(bridgeRepositoryProvider).catalog;
  final cook = snapshot.cook;
  final probes = snapshot.probes;
  final jacks = <ProbeJack>[
    for (final probe in probes)
      if (isLiveProbe(probe)) probe.jack,
  ];
  final domain = graphDomain(
    startedAtMs: cook.startedAtMs,
    nowMs: now.millisecondsSinceEpoch,
    view: view,
  );
  return GraphModel(
    series: buildGraphSeries(samples: samples, domain: domain, probes: jacks),
    samples: samples,
    domain: domain,
    meta: graphSeriesMeta(probes: probes, cook: cook, catalog: catalog),
    targets: graphTargets(probes: probes, unit: unit),
    band: graphPitBand(cook, unit),
    marks: graphMarks(marks: snapshot.marks, domain: domain),
    stats: graphWindowStats(samples: samples, domain: domain, probes: jacks),
    probes: probes,
    cook: cook,
    unit: unit,
    catalog: catalog,
  );
});
