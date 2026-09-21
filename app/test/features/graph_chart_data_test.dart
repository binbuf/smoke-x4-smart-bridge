/// N7.1–N7.12 — the fl_chart data builder's invariants.
///
/// These are the rules the epic says must not regress, asserted on the
/// [LineChartData] directly: area fill ≤16%, on-line target labels, the pit
/// band, mark and now verticals, stroke identity, the pit's thicker line, the
/// null spot between runs and the isolation dim.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/graph/chart_data.dart';
import 'package:smoke_bridge/features/graph/graph_format.dart';

GraphDomain _domain(double elapsedMin) => GraphDomain(
  startedMs: 0,
  elapsedMin: elapsedMin,
  xMin: 0,
  xMax: elapsedMin,
  nowMin: elapsedMin,
);

const List<GraphSeriesMeta> _meta = <GraphSeriesMeta>[
  GraphSeriesMeta(jack: ProbeJack.one, label: 'Brisket', isPit: false),
  GraphSeriesMeta(jack: ProbeJack.two, label: 'Ribs', isPit: false),
  GraphSeriesMeta(jack: ProbeJack.four, label: 'Grate', isPit: true),
];

ChartSeriesModel _model() => buildGraphSeries(
  samples: const <Sample>[
    Sample(t: 0, tempsF10: <int?>[1000, 900, null, 2000]),
    Sample(t: 60, tempsF10: <int?>[1100, 950, null, 2100]),
    Sample(t: 120, tempsF10: <int?>[1200, 1000, null, 2200]),
  ],
  domain: _domain(2),
  probes: <ProbeJack>[ProbeJack.one, ProbeJack.two, ProbeJack.four],
);

LineChartData _data({
  int? isolatedJack,
  List<GraphTarget> targets = const <GraphTarget>[],
  GraphBand? band,
  List<GraphMark> marks = const <GraphMark>[],
}) => buildCookChartData(
  model: _model(),
  domain: _domain(2),
  unit: TempUnit.fahrenheit,
  tokens: SmokeTokens.dark(),
  series: _meta,
  targets: targets,
  band: band,
  marks: marks,
  isolatedJack: isolatedJack,
);

void main() {
  test('area fill is at most 16% and off for a dimmed series', () {
    expect(chartAreaFillAlpha, lessThanOrEqualTo(0.16));
    final data = _data();
    for (final bar in data.lineBarsData) {
      expect(bar.belowBarData.show, isTrue);
      expect(bar.belowBarData.color!.a, lessThanOrEqualTo(0.16));
    }

    final dimmed = _data(isolatedJack: ProbeJack.one.n);
    expect(
      dimmed.lineBarsData.first.belowBarData.color!.a,
      lessThanOrEqualTo(0.16),
    );
    expect(dimmed.lineBarsData[1].belowBarData.show, isFalse);
    expect(dimmed.lineBarsData[1].color, SmokeTokens.dark().chromeDim);
  });

  test('stroke identity and the pit line width', () {
    final data = _data();
    expect(data.lineBarsData[0].dashArray, isNull);
    expect(data.lineBarsData[1].dashArray, <int>[7, 4]);
    expect(data.lineBarsData[2].dashArray, <int>[9, 3, 2, 3]);
    expect(
      data.lineBarsData[2].barWidth,
      greaterThan(data.lineBarsData[0].barWidth),
    );
  });

  test('a gap becomes a null spot, never a straight line', () {
    final model = buildGraphSeries(
      samples: const <Sample>[
        Sample(t: 0, tempsF10: <int?>[1000]),
        Sample(t: 60, tempsF10: <int?>[1100]),
        Sample(t: 120, tempsF10: <int?>[1200]),
        Sample(t: 6000, tempsF10: <int?>[1300]),
        Sample(t: 6060, tempsF10: <int?>[1400]),
        Sample(t: 6120, tempsF10: <int?>[1500]),
      ],
      domain: _domain(102),
      probes: <ProbeJack>[ProbeJack.one],
    );
    final data = buildCookChartData(
      model: model,
      domain: _domain(102),
      unit: TempUnit.fahrenheit,
      tokens: SmokeTokens.dark(),
      series: const <GraphSeriesMeta>[
        GraphSeriesMeta(jack: ProbeJack.one, label: 'Brisket', isPit: false),
      ],
      targets: const <GraphTarget>[],
      band: null,
      marks: const <GraphMark>[],
    );
    expect(
      data.lineBarsData.single.spots.where((spot) => spot.isNull()).length,
      1,
    );
  });

  test('target lines are labelled on the line', () {
    final data = _data(
      targets: const <GraphTarget>[
        GraphTarget(jack: ProbeJack.one, value: 201, label: '201° F'),
      ],
    );
    final line = data.extraLinesData.horizontalLines.single;
    expect(line.y, 201);
    expect(line.label.show, isTrue);
    expect(line.label.labelResolver(line), '201° F');
  });

  test('the pit band is a horizontal range annotation', () {
    final data = _data(band: const GraphBand(min: 225, max: 275));
    final band = data.rangeAnnotations.horizontalRangeAnnotations.single;
    expect(band.y1, 225);
    expect(band.y2, 275);
  });

  test('marks and now are vertical lines inside the window', () {
    final data = _data(
      marks: const <GraphMark>[
        GraphMark(xMin: 1, label: 'wrap', kind: MarkKind.wrapped),
      ],
    );
    expect(data.extraLinesData.verticalLines.length, 2);
    expect(data.extraLinesData.verticalLines.first.x, 1);
    expect(data.extraLinesData.verticalLines.last.x, 2);
  });

  test('the y-gauge has four gridlines in display units', () {
    final data = _data();
    final interval = (data.maxY - data.minY) / 4;
    expect(data.gridData.horizontalInterval, interval);
    expect(data.minY, 75);
    expect(data.maxY, 250);
  });
}
