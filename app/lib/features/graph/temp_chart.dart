/// The one chart used by both Graph and History.
///
/// A reception hole is drawn as a **break**, never a straight line across it:
/// the series is split into contiguous segments at every null reading and at
/// every gap wider than 2.5× the session's own cadence. A detached probe simply
/// has no line, which is why a dropped probe cannot be read as `0 °F`.
///
/// A long cook draws in one frame because every visible run is decimated to a
/// pixel budget before it reaches the chart (see `chart_data.dart`); the window
/// pans and pinches, and the window presets and jump-to-now make the newest
/// readings one tap away. The viewport *rules* live outside this widget, so
/// they are unit-testable without a gesture.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../design/primitives.dart';
import '../../design/tokens.dart';
import '../../domain/domain.dart';
import 'chart_data.dart';

class TempChart extends StatefulWidget {
  const TempChart({
    super.key,
    required this.samples,
    this.unit = TempUnit.fahrenheit,
    this.height = 280,
  });

  final List<Sample> samples;
  final TempUnit unit;
  final double height;

  @override
  State<TempChart> createState() => _TempChartState();
}

class _TempChartState extends State<TempChart> {
  late List<List<List<FlSpot>>> _segments;
  late ChartViewport _viewport;

  ChartViewport? _gestureBase;
  double _gestureFocus = 0;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant TempChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.samples, widget.samples)) {
      _rebuild();
    }
  }

  /// Rebuild the run-split once per sample list; gestures then only clip and
  /// decimate, so a pan costs no more than the visible window.
  void _rebuild() {
    _segments = buildSegments(widget.samples);
    final x = _boundsX(widget.samples);
    _viewport = ChartViewport.full(x.minX, x.maxX);
  }

  double _xAtPixel(double dx, double width, ChartViewport vp) {
    if (width <= 0) {
      return vp.min;
    }
    return vp.min + (dx / width).clamp(0.0, 1.0) * vp.span;
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _segments.any((perJack) => perJack.isNotEmpty);
    if (!hasData) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'No readings in this range.',
            style: TextStyle(color: SmokePalette.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    final y = boundsY(widget.samples);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ViewportControls(
          viewport: _viewport,
          onWindow: (minutes) =>
              setState(() => _viewport = _viewport.window(minutes)),
          onFull: () => setState(
            () => _viewport = ChartViewport.full(
              _viewport.fullMin,
              _viewport.fullMax,
            ),
          ),
          onNow: () => setState(() => _viewport = _viewport.jumpToEnd()),
        ),
        const SizedBox(height: SmokeSpace.sm),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final budget = (width * 2).round().clamp(32, 4000);
              final chart = _chart(width, budget, y);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (d) {
                  _gestureBase = _viewport;
                  _gestureFocus = _xAtPixel(
                    d.localFocalPoint.dx,
                    width,
                    _viewport,
                  );
                },
                onScaleUpdate: (d) {
                  final base = _gestureBase;
                  if (base == null) {
                    return;
                  }
                  final zoomed = base.zoom(d.horizontalScale, _gestureFocus);
                  final nowFocus = _xAtPixel(
                    d.localFocalPoint.dx,
                    width,
                    zoomed,
                  );
                  setState(() => _viewport = zoomed.pan(_gestureFocus - nowFocus));
                },
                onScaleEnd: (_) => _gestureBase = null,
                child: chart,
              );
            },
          ),
        ),
        const SizedBox(height: SmokeSpace.md),
        Wrap(
          spacing: SmokeSpace.lg,
          runSpacing: SmokeSpace.sm,
          children: [
            for (var jack = 0; jack < 4; jack++)
              if (_segments[jack].isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SeriesDot(jack: jack + 1),
                    const SizedBox(width: SmokeSpace.xs + 2),
                    Text(
                      'Probe ${jack + 1}',
                      style: const TextStyle(
                        color: SmokePalette.textBody,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
          ],
        ),
      ],
    );
  }

  Widget _chart(
    double width,
    int budget,
    ({double minY, double maxY}) y,
  ) {
    final viewport = _viewport;
    final bars = <LineChartBarData>[];
    for (var jack = 0; jack < 4; jack++) {
      for (final run in _segments[jack]) {
        final visible = clipToViewport(run, viewport.min, viewport.max);
        if (visible.isEmpty) {
          continue;
        }
        bars.add(
          LineChartBarData(
            spots: decimate(visible, budget),
            color: SmokePalette.forJack(jack + 1),
            dotData: FlDotData(show: visible.length == 1),
            barWidth: 1.5,
          ),
        );
      }
    }

    final spanX = viewport.span;
    final ticks = (width / 90).floor().clamp(2, 6);
    return LineChart(
      LineChartData(
        minX: viewport.min,
        maxX: viewport.max,
        minY: y.minY,
        maxY: y.maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              const FlLine(color: SmokePalette.hairline, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(right: SmokeSpace.sm),
                child: Text(
                  _axisTemp(v, widget.unit),
                  style: const TextStyle(
                    color: SmokePalette.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: spanX <= 0 ? 1 : spanX / ticks,
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(top: SmokeSpace.sm),
                child: Text(
                  _axisTime(v),
                  style: const TextStyle(
                    color: SmokePalette.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ),
        lineBarsData: bars,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => SmokePalette.cardRaised,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  _valueLabel(s.y, widget.unit),
                  TextStyle(
                    color: s.bar.color ?? SmokePalette.textHi,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The window presets and the jump-to-newest action. They are the whole point
/// of "scale to a real cook": a fifteen-hour session is readable at "All" and
/// inspectable at "15m".
class _ViewportControls extends StatelessWidget {
  const _ViewportControls({
    required this.viewport,
    required this.onWindow,
    required this.onFull,
    required this.onNow,
  });

  final ChartViewport viewport;
  final void Function(double minutes) onWindow;
  final VoidCallback onFull;
  final VoidCallback onNow;

  static const _windows = <(String, double)>[
    ('15m', 15),
    ('1h', 60),
    ('6h', 360),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = <String>{
      if (viewport.isFull)
        'All'
      else
        for (final (label, minutes) in _windows)
          if ((viewport.span - minutes).abs() < 0.5 &&
              (viewport.max - viewport.fullMax).abs() < 0.5)
            label,
    };
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: [
              for (final (label, _) in _windows)
                ButtonSegment(value: label, label: Text(label)),
              const ButtonSegment(value: 'All', label: Text('All')),
            ],
            selected: selected,
            onSelectionChanged: (choice) {
              if (choice.isEmpty) {
                return;
              }
              final label = choice.first;
              if (label == 'All') {
                onFull();
                return;
              }
              final minutes = _windows
                  .firstWhere((w) => w.$1 == label)
                  .$2;
              onWindow(minutes);
            },
          ),
        ),
        IconButton(
          tooltip: 'Jump to newest',
          onPressed: viewport.isFull ? null : onNow,
          icon: const Icon(Icons.last_page, size: 20),
        ),
      ],
    );
  }
}

// ── labels ───────────────────────────────────────────────────────────

String _axisTemp(double f, TempUnit unit) {
  final v = unit == TempUnit.fahrenheit ? f : (f - 32) * 5 / 9;
  return '${v.round()}°';
}

String _axisTime(double minutes) {
  if (minutes >= 60) {
    final h = minutes / 60;
    return h == h.roundToDouble()
        ? '${h.round()}h'
        : '${h.toStringAsFixed(1)}h';
  }
  return '${minutes.round()}m';
}

String _valueLabel(double f, TempUnit unit) {
  final v = unit == TempUnit.fahrenheit ? f : (f - 32) * 5 / 9;
  return '${v.toStringAsFixed(1)}${unit.suffix}';
}

({double minX, double maxX}) _boundsX(List<Sample> samples) {
  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  for (final s in samples) {
    final x = s.t / 60;
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
  }
  if (minX == double.infinity) {
    return (minX: 0, maxX: 1);
  }
  return (minX: minX, maxX: maxX);
}
