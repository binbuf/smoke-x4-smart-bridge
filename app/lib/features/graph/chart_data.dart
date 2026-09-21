/// N7.1–N7.12 — the fl_chart mapping for [CookChart].
///
/// One function turns the N1.14 render model plus the view window into a
/// [LineChartData]. Keeping it out of the widget lets the invariants be
/// asserted directly, without a rendered frame:
///
///  * **Runs are separate segments.** A `FlSpot.nullSpot` sits between N1.14's
///    runs, so a dropout is a gap, never a straight line across it.
///  * **Area fill is 10%** ([chartAreaFillAlpha]), comfortably under the 16%
///    ceiling.
///  * **Target lines are labelled on the line** (fl_chart's
///    [HorizontalLineLabel]).
///  * **The pit band is a horizontal range annotation.**
///  * **Marks and "now" are vertical lines.**
///  * **Hue is never the only identity channel**: every bar carries the jack's
///    stroke pattern as well ([seriesDashArray]).
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';
import 'graph_format.dart';

/// The area fill under each visible series. The ceiling is 16%.
const double chartAreaFillAlpha = 0.10;

/// The series that will actually draw a bar — non-empty after windowing.
///
/// The tooltip indexes bars by `barIndex`, so it must use this same list.
List<GraphSeriesMeta> chartBarSeries(
  ChartSeriesModel model,
  List<GraphSeriesMeta> series,
) {
  final out = <GraphSeriesMeta>[];
  for (final meta in series) {
    for (final probe in model.series) {
      if (probe.jack == meta.jack) {
        if (!probe.isEmpty) {
          out.add(meta);
        }
        break;
      }
    }
  }
  return out;
}

/// The full chart description for one window.
LineChartData buildCookChartData({
  required ChartSeriesModel model,
  required GraphDomain domain,
  required TempUnit unit,
  required SmokeTokens tokens,
  required List<GraphSeriesMeta> series,
  required List<GraphTarget> targets,
  required GraphBand? band,
  required List<GraphMark> marks,
  int? isolatedJack,
  BaseTouchCallback<LineTouchResponse>? touchCallback,
}) {
  final bounds = graphYBounds(model, unit);
  final yInterval = (bounds.max - bounds.min) / 4;
  final xInterval = domain.span / 4;

  final bars = <LineChartBarData>[];
  for (final meta in chartBarSeries(model, series)) {
    ProbeSeries? probe;
    for (final candidate in model.series) {
      if (candidate.jack == meta.jack) {
        probe = candidate;
        break;
      }
    }
    if (probe == null) {
      continue;
    }
    final dim = isolatedJack != null && isolatedJack != meta.jack.n;
    final color = dim ? tokens.chromeDim : tokens.series(meta.jack.n);
    final spots = <FlSpot>[];
    for (var r = 0; r < probe.runs.length; r++) {
      if (r > 0) {
        spots.add(FlSpot.nullSpot);
      }
      for (final point in probe.runs[r].points) {
        spots.add(FlSpot(point.t / 60, displayTemp(point.f, unit)));
      }
    }
    bars.add(
      LineChartBarData(
        spots: spots,
        color: color,
        barWidth: seriesWidth(meta.isPit ? ProbeRole.pit : ProbeRole.food),
        isStrokeCapRound: true,
        isStrokeJoinRound: true,
        dashArray: seriesDashArray(meta.jack.n),
        belowBarData: BarAreaData(
          show: !dim,
          color: tokens.tint(color, chartAreaFillAlpha),
        ),
        dotData: FlDotData(
          show: !dim,
          checkToShowDot: (spot, bar) =>
              !spot.isNull() && spot == bar.spots.last,
          getDotPainter: (spot, percent, bar, index) =>
              FlDotCirclePainter(radius: 3, color: color),
        ),
      ),
    );
  }

  return LineChartData(
    minX: domain.xMin,
    maxX: domain.xMax,
    minY: bounds.min,
    maxY: bounds.max,
    clipData: const FlClipData.all(),
    borderData: FlBorderData(show: false),
    gridData: FlGridData(
      drawVerticalLine: false,
      horizontalInterval: yInterval,
      getDrawingHorizontalLine: (value) =>
          FlLine(color: tokens.hairline, strokeWidth: 1),
    ),
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          interval: yInterval,
          minIncluded: false,
          maxIncluded: false,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              '${value.round()}',
              style: SmokeText.monoSmall.copyWith(
                fontSize: 8.5,
                color: tokens.textMuted,
              ),
            ),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: xInterval,
          minIncluded: false,
          maxIncluded: false,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              fmtClock(domain.timeAt(value)),
              style: SmokeText.monoSmall.copyWith(
                fontSize: 8.5,
                color: tokens.textMuted,
              ),
            ),
          ),
        ),
      ),
    ),
    rangeAnnotations: RangeAnnotations(
      horizontalRangeAnnotations: <HorizontalRangeAnnotation>[
        if (band != null)
          HorizontalRangeAnnotation(
            y1: band.min,
            y2: band.max,
            color: tokens.tint(tokens.warning, 0.08),
          ),
      ],
    ),
    extraLinesData: ExtraLinesData(
      horizontalLines: <HorizontalLine>[
        for (final target in targets)
          HorizontalLine(
            y: target.value,
            color: tokens.tint(tokens.series(target.jack.n), 0.65),
            strokeWidth: 1,
            dashArray: const <int>[4, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              padding: const EdgeInsets.only(right: 2, bottom: 2),
              style: SmokeText.monoSmall.copyWith(
                fontSize: 8.5,
                color: tokens.series(target.jack.n),
              ),
              labelResolver: (line) => target.label,
            ),
          ),
      ],
      verticalLines: <VerticalLine>[
        for (final mark in marks)
          VerticalLine(
            x: mark.xMin,
            color: tokens.tint(tokens.warning, 0.45),
            strokeWidth: 1,
            dashArray: const <int>[2, 3],
          ),
        if (domain.nowVisible)
          VerticalLine(
            x: domain.nowMin,
            color: tokens.tint(tokens.textHi, 0.5),
            strokeWidth: 1,
          ),
      ],
    ),
    lineBarsData: bars,
    lineTouchData: LineTouchData(
      handleBuiltInTouches: false,
      touchCallback: touchCallback,
      touchSpotThreshold: 24,
    ),
  );
}
