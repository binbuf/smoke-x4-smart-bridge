/// N7 — the Graph screen's pure projections.
///
/// Pins the prototype's exact `graphDomain` arithmetic, the stroke identity,
/// the resample grid, run-splitting before decimation, the y-gauge bounds, the
/// labelled targets, the pit band, the window stats and the I3 rule that a
/// detached jack contributes nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/model/cook_state.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/graph/graph_format.dart';

const int _now = 1700000000000;
const int _hourMs = 60 * 60 * 1000;

ProbeState _probe({
  required ProbeJack jack,
  ProbeRole role = ProbeRole.food,
  bool attached = true,
  Freshness freshness = Freshness.live,
  int? tempF10,
  int? targetF10,
  int? lowF10,
  int? peakF10,
  int? avgF10,
  List<int> spark = const <int>[],
}) => ProbeState(
  jack: jack,
  role: role,
  attached: attached,
  freshness: freshness,
  tempF10: tempF10,
  targetF10: targetF10,
  lowF10: lowF10,
  peakF10: peakF10,
  avgF10: avgF10,
  spark: spark,
);

void main() {
  group('graphDomain reproduces the prototype', () {
    final start = _now - 4 * _hourMs; // 240 minutes

    test('all range is the whole session', () {
      final domain = graphDomain(
        startedAtMs: start,
        nowMs: _now,
        view: GraphViewState.initial,
      );
      expect(domain.elapsedMin, 240);
      expect(domain.xMin, 0);
      expect(domain.xMax, 240);
      expect(domain.nowMin, 240);
      expect(domain.nowVisible, isTrue);
    });

    test('1h range is the trailing hour', () {
      final domain = graphDomain(
        startedAtMs: start,
        nowMs: _now,
        view: const GraphViewState(range: GraphRange.h1),
      );
      expect(domain.span, 60);
      expect(domain.xMin, 180);
      expect(domain.xMax, 240);
    });

    test('zoom divides the base span, never below two minutes', () {
      final domain = graphDomain(
        startedAtMs: start,
        nowMs: _now,
        view: const GraphViewState(range: GraphRange.h1, zoom: 2),
      );
      expect(domain.span, 30);
      expect(domain.xMin, 210);
      expect(domain.xMax, 240);
    });

    test('pan walks the window back from now', () {
      final domain = graphDomain(
        startedAtMs: start,
        nowMs: _now,
        view: const GraphViewState(range: GraphRange.h1, pan: 30),
      );
      expect(domain.xMin, 150);
      expect(domain.xMax, 210);
      expect(domain.nowVisible, isFalse);
    });

    test('a range wider than the session clamps to the session', () {
      final domain = graphDomain(
        startedAtMs: _now - 10 * 60 * 1000,
        nowMs: _now,
        view: const GraphViewState(range: GraphRange.m15),
      );
      expect(domain.elapsedMin, 10);
      expect(domain.xMin, 0);
      expect(domain.xMax, 10);
    });

    test('a cook that never started gets a trailing hour', () {
      final domain = graphDomain(
        startedAtMs: null,
        nowMs: _now,
        view: GraphViewState.initial,
      );
      expect(domain.elapsedMin, 60);
      expect(domain.startedMs, _now - _hourMs);
    });
  });

  group('series identity (N7.3)', () {
    test('the four stroke patterns', () {
      expect(seriesDashArray(1), isNull);
      expect(seriesDashArray(2), <int>[7, 4]);
      expect(seriesDashArray(3), <int>[2, 4]);
      expect(seriesDashArray(4), <int>[9, 3, 2, 3]);
      expect(seriesDash(ProbeJack.two), <double>[7, 4]);
    });

    test('the pit line is thicker', () {
      expect(
        seriesWidth(ProbeRole.pit),
        greaterThan(seriesWidth(ProbeRole.food)),
      );
    });

    test('the hint names the zoom factor only when zoomed', () {
      expect(graphZoomHint(GraphViewState.initial), contains('Pinch'));
      expect(graphZoomHint(const GraphViewState(zoom: 2.5)), '2.5× zoom');
      expect(const GraphViewState(zoom: 2).canReset, isTrue);
      expect(const GraphViewState(pan: 1).canReset, isTrue);
      expect(GraphViewState.initial.canReset, isFalse);
    });
  });

  group('sample grid (N7.2)', () {
    test('resamples the spark onto one aligned grid', () {
      final cook = CookState(active: true, startedAtMs: _now - 4 * _hourMs);
      final samples = buildGraphSamples(
        probes: <ProbeState>[
          _probe(
            jack: ProbeJack.one,
            tempF10: 1642,
            lowF10: 580,
            spark: <int>[700, 1642],
          ),
          _probe(
            jack: ProbeJack.four,
            role: ProbeRole.pit,
            tempF10: 2486,
            spark: <int>[2520, 2486],
          ),
        ],
        cook: cook,
        nowMs: _now,
      );

      expect(samples.first.t, 0);
      expect(samples.last.t, 4 * 3600);
      expect(samples.length, lessThanOrEqualTo(1201));
      expect(samples.first.tempFor(ProbeJack.one), 700);
      expect(samples.last.tempFor(ProbeJack.one), 1642);
      expect(samples.first.tempFor(ProbeJack.four), 2520);
      // A jack with no probe contributes nothing at all (I3).
      expect(samples.first.tempFor(ProbeJack.two), isNull);
      expect(samples.first.tempFor(ProbeJack.three), isNull);
      // The grid is strictly increasing.
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i].t, greaterThan(samples[i - 1].t));
      }
    });

    test('the cadence widens so a long cook never exceeds the cap', () {
      expect(graphCadenceS(14400), graphMinCadenceS);
      final long = graphCadenceS(40000);
      expect(long, greaterThan(graphMinCadenceS));
      expect((40000 / long).ceil(), lessThanOrEqualTo(graphMaxSamples));
    });

    test('detached probes are skipped entirely', () {
      final samples = buildGraphSamples(
        probes: <ProbeState>[
          _probe(jack: ProbeJack.one, attached: false),
          _probe(jack: ProbeJack.two, role: ProbeRole.unused, attached: false),
        ],
        cook: CookState(active: true, startedAtMs: _now - 3600 * 1000),
        nowMs: _now,
      );
      for (final sample in samples) {
        expect(sample.tempsF10.every((value) => value == null), isTrue);
      }
    });
  });

  group('series builder (N7.2)', () {
    GraphDomain domainFor(double elapsedMin) => GraphDomain(
      startedMs: 0,
      elapsedMin: elapsedMin,
      xMin: 0,
      xMax: elapsedMin,
      nowMin: elapsedMin,
    );

    test('runs split at a gap before decimation', () {
      final samples = <Sample>[
        const Sample(t: 0, tempsF10: <int?>[1000]),
        const Sample(t: 60, tempsF10: <int?>[1100]),
        const Sample(t: 120, tempsF10: <int?>[1200]),
        const Sample(t: 6000, tempsF10: <int?>[1300]),
        const Sample(t: 6060, tempsF10: <int?>[1400]),
        const Sample(t: 6120, tempsF10: <int?>[1500]),
      ];
      final model = buildGraphSeries(
        samples: samples,
        domain: domainFor(102),
        probes: <ProbeJack>[ProbeJack.one],
      );
      expect(model.series.single.runs.length, 2);
      expect(model.series.single.rawCount, 6);
    });

    test('a wide range decimates and keeps the envelope', () {
      final samples = <Sample>[
        for (var i = 0; i < 2000; i++)
          Sample(t: i * 30, tempsF10: <int?>[1000 + (i % 50)]),
      ];
      final model = buildGraphSeries(
        samples: samples,
        domain: domainFor(1000),
        probes: <ProbeJack>[ProbeJack.one],
      );
      final series = model.series.single;
      expect(series.rawCount, 2000);
      expect(series.points.length, lessThan(2000));
      expect(series.envelope, isNotEmpty);
    });
  });

  group('y-gauge (N7.1)', () {
    test('rounds the window extent out to 25s', () {
      const model = ChartSeriesModel(
        series: <ProbeSeries>[],
        gaps: <Gap>[],
        fromT: 0,
        toT: 0,
        minF: 58,
        maxF: 261,
      );
      final f = graphYBounds(model, TempUnit.fahrenheit);
      expect(f.min, 50);
      expect(f.max, 275);

      final c = graphYBounds(model, TempUnit.celsius);
      expect(c.min, 0);
      expect(c.max, 150);
    });
  });

  group('overlays (N7.5–N7.8)', () {
    test('targets only for attached probes that have one', () {
      final targets = graphTargets(
        probes: <ProbeState>[
          _probe(jack: ProbeJack.one, tempF10: 1642, targetF10: 2010),
          _probe(jack: ProbeJack.two, tempF10: 1724),
          _probe(jack: ProbeJack.three, attached: false, targetF10: 1600),
        ],
        unit: TempUnit.fahrenheit,
      );
      expect(targets.length, 1);
      expect(targets.single.jack, ProbeJack.one);
      expect(targets.single.value, 201);
      expect(targets.single.label, '201° F');
    });

    test('the pit band is converted to display units', () {
      const cook = CookState(pitBandMinF10: 2250, pitBandMaxF10: 2750);
      final f = graphPitBand(cook, TempUnit.fahrenheit);
      expect(f!.min, 225);
      expect(f.max, 275);
      expect(graphPitBand(const CookState(), TempUnit.fahrenheit), isNull);
    });

    test('marks are filtered to the window', () {
      final domain = GraphDomain(
        startedMs: 0,
        elapsedMin: 100,
        xMin: 50,
        xMax: 100,
        nowMin: 100,
      );
      final marks = graphMarks(
        marks: const <Mark>[
          Mark(t: 10 * 60, kind: MarkKind.note, text: 'early'),
          Mark(t: 70 * 60, kind: MarkKind.wrapped, text: 'wrap'),
          Mark(t: 90 * 60, kind: MarkKind.spritz),
        ],
        domain: domain,
      );
      expect(marks.length, 2);
      expect(marks.first.xMin, 70);
      expect(marks.first.label, 'wrap');
      expect(marks.last.label, 'spritz');
    });
  });

  group('window statistics (N7.14)', () {
    test('high/avg/low over the window', () {
      final samples = <Sample>[
        const Sample(t: 0, tempsF10: <int?>[1000, null, null, null]),
        const Sample(t: 60, tempsF10: <int?>[1200, null, null, null]),
        const Sample(t: 120, tempsF10: <int?>[1100, null, null, null]),
      ];
      final domain = GraphDomain(
        startedMs: 0,
        elapsedMin: 2,
        xMin: 0,
        xMax: 2,
        nowMin: 2,
      );
      final stats = graphWindowStats(
        samples: samples,
        domain: domain,
        probes: <ProbeJack>[ProbeJack.one, ProbeJack.two],
      );
      expect(stats.first.highF10, 1200);
      expect(stats.first.avgF10, 1100);
      expect(stats.first.lowF10, 1000);
      expect(stats.last.hasReadings, isFalse);
    });
  });
}
