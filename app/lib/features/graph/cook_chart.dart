/// N7.1–N7.12 — the multi-series `CookChart`.
///
/// The widget is deliberately dumb: it draws whatever [buildCookChartData]
/// describes and reports gestures back to the caller. That is what lets the
/// inline Graph destination and the fullscreen host be **the same chart** for
/// the same window (N7.16) and lets N12's history detail reuse it with a
/// different [ChartSeriesModel].
///
/// Crosshair: fl_chart's built-in touch is disabled and its `touchCallback`
/// feeds this widget's own tip. That is what makes "the nearest **real**
/// sample" observable and testable — the tip is a widget in the tree, not paint
/// on the canvas.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';
import 'chart_data.dart';
import 'graph_format.dart';

class CookChart extends StatefulWidget {
  const CookChart({
    super.key,
    required this.model,
    required this.domain,
    required this.unit,
    required this.series,
    required this.targets,
    required this.band,
    required this.marks,
    this.isolatedJack,
    this.onZoomFactor,
    this.onPanMinutes,
  });

  final ChartSeriesModel model;
  final GraphDomain domain;
  final TempUnit unit;
  final List<GraphSeriesMeta> series;
  final List<GraphTarget> targets;
  final GraphBand? band;
  final List<GraphMark> marks;

  /// The one jack at full strength; the rest are dimmed.
  final int? isolatedJack;

  /// Multiply the current zoom by this factor (scroll wheel / pinch).
  final ValueChanged<double>? onZoomFactor;

  /// Add this many minutes to the pan (drag; positive walks the window back).
  final ValueChanged<double>? onPanMinutes;

  @override
  State<CookChart> createState() => _CookChartState();
}

class _CookChartState extends State<CookChart> {
  List<LineBarSpot> _touched = const <LineBarSpot>[];
  Offset? _tipAt;
  double _width = 0;
  double _pinchStart = 1;

  void _clear() {
    if (_touched.isNotEmpty) {
      setState(() {
        _touched = const <LineBarSpot>[];
        _tipAt = null;
      });
    }
  }

  void _pan(double dx) {
    if (dx == 0 || _width <= 0 || widget.onPanMinutes == null) {
      return;
    }
    widget.onPanMinutes!(-(dx / _width) * widget.domain.span);
  }

  void _onTouch(FlTouchEvent event, LineTouchResponse? response) {
    if (event is FlPanUpdateEvent) {
      _pan(event.details.delta.dx);
      _clear();
      return;
    }
    if (event is FlPanEndEvent ||
        event is FlPanCancelEvent ||
        event is FlPointerExitEvent ||
        event is FlTapCancelEvent ||
        event is FlLongPressEnd) {
      _clear();
      return;
    }
    final spots = response?.lineBarSpots;
    final position = event.localPosition;
    if (spots == null || spots.isEmpty || position == null) {
      _clear();
      return;
    }
    setState(() {
      _touched = List<LineBarSpot>.of(spots);
      _tipAt = position;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final data = buildCookChartData(
          model: widget.model,
          domain: widget.domain,
          unit: widget.unit,
          tokens: tokens,
          series: widget.series,
          targets: widget.targets,
          band: widget.band,
          marks: widget.marks,
          isolatedJack: widget.isolatedJack,
          touchCallback: _onTouch,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) => _pinchStart = 1,
          onScaleUpdate: (details) {
            if (details.pointerCount >= 2 && details.scale > 0) {
              final factor = details.scale / _pinchStart;
              if ((factor - 1).abs() > 0.001) {
                widget.onZoomFactor?.call(factor);
              }
              _pinchStart = details.scale;
            } else {
              _pan(details.focalPointDelta.dx);
            }
          },
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && widget.onZoomFactor != null) {
                widget.onZoomFactor!(event.scrollDelta.dy < 0 ? 1.2 : 1 / 1.2);
              }
            },
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: LineChart(data, duration: Duration.zero),
                ),
                if (_touched.isNotEmpty && _tipAt != null)
                  _CrosshairTip(
                    domain: widget.domain,
                    unit: widget.unit,
                    tokens: tokens,
                    bars: chartBarSeries(widget.model, widget.series),
                    spots: _touched,
                    anchor: _tipAt!,
                    chartWidth: _width,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The custom crosshair tip: the wall-clock time and each touched bar's nearest
/// real reading (never an interpolated value, never a fabricated zero).
class _CrosshairTip extends StatelessWidget {
  const _CrosshairTip({
    required this.domain,
    required this.unit,
    required this.tokens,
    required this.bars,
    required this.spots,
    required this.anchor,
    required this.chartWidth,
  });

  final GraphDomain domain;
  final TempUnit unit;
  final SmokeTokens tokens;
  final List<GraphSeriesMeta> bars;
  final List<LineBarSpot> spots;
  final Offset anchor;
  final double chartWidth;

  @override
  Widget build(BuildContext context) {
    const width = 168.0;
    final left = (anchor.dx + 10).clamp(
      0.0,
      (chartWidth - width).clamp(0.0, 4000.0),
    );
    return Positioned(
      left: left,
      top: 8,
      child: Container(
        key: const ValueKey<String>('graph-crosshair'),
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.cardRaised,
          borderRadius: BorderRadius.circular(tokens.radii.control),
          border: Border.all(color: tokens.hairlineStrong),
          boxShadow: tokens.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              fmtClock(domain.timeAt(spots.first.x)),
              style: SmokeText.monoSmall.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: 4),
            for (final spot in spots)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        spot.barIndex < bars.length
                            ? bars[spot.barIndex].label
                            : 'Probe',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SmokeText.labelSm.copyWith(
                          fontSize: 11,
                          color: tokens.textBody,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      TempValue.ofF10((spot.y * 10).round()).format(unit),
                      style: SmokeText.monoSmall.copyWith(color: tokens.textHi),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
