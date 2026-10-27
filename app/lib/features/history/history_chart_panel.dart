import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../prototype/fixtures.dart';
import '../../prototype/formatters.dart';
import '../../app/bridge_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/probe_chart.dart';

/// The interactive chart surface used by History and the dedicated full-screen
/// chart view. It owns pan/zoom/cursor state so both views share one
/// implementation while remaining independent screens.
class HistoryChartPanel extends StatefulWidget {
  const HistoryChartPanel({
    super.key,
    required this.controller,
    required this.fixture,
    this.expanded = false,
    this.historical = false,
  });

  final BridgeController controller;
  final HistoryFixture fixture;

  /// Fills the available height instead of using the inline 300 px height.
  final bool expanded;

  /// A past cook uses `Recorded` and never labels the right edge `Now`.
  final bool historical;

  @override
  State<HistoryChartPanel> createState() => HistoryChartPanelState();
}

class HistoryChartPanelState extends State<HistoryChartPanel> {
  double _viewStart = 0;
  double _viewEnd = 1;
  double _scaleStartStart = 0;
  double _scaleStartEnd = 1;
  double _scaleStartFocalX = 0;
  DateTime? _cursorTime;

  BridgeController get controller => widget.controller;

  bool get _panned => _viewStart > 0.001 || _viewEnd < 0.999;

  void resetViewport() {
    if (!mounted) return;
    setState(() {
      _viewStart = 0;
      _viewEnd = 1;
      _cursorTime = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fixture = widget.fixture;
    final chart = widget.expanded
        ? Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final plot = historyChartPlotRect(size);
                return _chartStack(context, fixture, plot);
              },
            ),
          )
        : SizedBox(
            height: 300,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final plot = historyChartPlotRect(size);
                return _chartStack(context, fixture, plot);
              },
            ),
          );

    return Column(
      children: [
        chart,
        const SizedBox(height: 8),
        _chartLegend(context, fixture),
        const SizedBox(height: 2),
        _chartControls(context),
      ],
    );
  }

  Widget _chartStack(BuildContext context, HistoryFixture fixture, Rect plot) {
    return Stack(
      children: [
        Positioned.fill(child: _chartGestureLayer(context, fixture, plot)),
        if (_cursorTime != null) _buildTooltip(context, fixture, plot),
      ],
    );
  }

  Widget _chartGestureLayer(
    BuildContext context,
    HistoryFixture fixture,
    Rect plot,
  ) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && plot.width > 0) {
          final fraction = ((event.localPosition.dx - plot.left) / plot.width)
              .clamp(0.0, 1.0);
          _zoomAt(event.scrollDelta.dy > 0 ? 1.12 : 0.89, fraction);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _setCursor(details.localPosition, plot),
        onDoubleTap: resetViewport,
        onScaleStart: (details) {
          _scaleStartStart = _viewStart;
          _scaleStartEnd = _viewEnd;
          _scaleStartFocalX = details.localFocalPoint.dx;
        },
        onScaleUpdate: (details) => _updateViewport(details, plot),
        child: HistoryChart(
          fixture: fixture,
          units: controller.units,
          colors: ProbeColors.of(context),
          visibleProbe: controller.historyProbe,
          viewStart: _viewStart,
          viewEnd: _viewEnd,
          cursorTime: _cursorTime,
          use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
          latestIsNow: !widget.historical,
        ),
      ),
    );
  }

  Widget _chartLegend(BuildContext context, HistoryFixture fixture) {
    final probes = controller.historyProbe == null
        ? [1, 2, 3, 4]
        : [controller.historyProbe!];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final probe in probes)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: ProbeColors.forIndex(context, probe - 1),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'P$probe',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _latestLabel(
                      ProbeRangeStats.fromSeries(fixture.series[probe - 1]),
                    ),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _latestLabel(ProbeRangeStats stats) {
    if (stats.last == null) return '—';
    return '${controller.valueFor(stats.last)}°';
  }

  Widget _chartControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.touch_app_outlined, size: 14, color: scheme.outline),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Drag to pan · pinch to zoom',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        _ChartControlButton(
          key: const Key('history.zoom.out'),
          icon: Icons.remove,
          tooltip: 'Zoom out',
          onPressed: () => _zoomAt(1.25, 0.5),
        ),
        _ChartControlButton(
          key: const Key('history.zoom.in'),
          icon: Icons.add,
          tooltip: 'Zoom in',
          onPressed: () => _zoomAt(0.8, 0.5),
        ),
        _ChartControlButton(
          key: const Key('history.zoom.fit'),
          icon: Icons.fit_screen_outlined,
          tooltip: 'Fit range',
          onPressed: resetViewport,
        ),
        if (_panned)
          TextButton(
            key: const Key('history.zoom.now'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: resetViewport,
            child: Text(widget.historical ? 'Fit range' : 'Now'),
          ),
      ],
    );
  }

  void _zoomAt(double factor, double focalFraction) {
    final oldSpan = _viewEnd - _viewStart;
    final newSpan = (oldSpan * factor).clamp(0.02, 1.0);
    final ratio = newSpan / oldSpan;
    final newStart = focalFraction - (focalFraction - _viewStart) * ratio;
    final clampedStart = newStart.clamp(0.0, 1 - newSpan);
    setState(() {
      _viewStart = clampedStart;
      _viewEnd = clampedStart + newSpan;
      _cursorTime = null;
    });
  }

  void _setCursor(Offset position, Rect plot) {
    if (!plot.contains(position)) {
      setState(() => _cursorTime = null);
      return;
    }
    final fraction = ((position.dx - plot.left) / plot.width).clamp(0.0, 1.0);
    final fixture = widget.fixture;
    final start = fixture.start.add(
      Duration(
        milliseconds:
            (fixture.end.difference(fixture.start).inMilliseconds *
                    (_viewStart + (fraction * (_viewEnd - _viewStart))))
                .round(),
      ),
    );
    setState(() => _cursorTime = start);
  }

  void _updateViewport(ScaleUpdateDetails details, Rect plot) {
    if (plot.width <= 0) return;
    final oldSpan = _scaleStartEnd - _scaleStartStart;
    final newSpan = (oldSpan / math.max(0.01, details.scale)).clamp(0.02, 1.0);
    final startFocal = ((_scaleStartFocalX - plot.left) / plot.width).clamp(
      0.0,
      1.0,
    );
    final currentFocal = ((details.localFocalPoint.dx - plot.left) / plot.width)
        .clamp(0.0, 1.0);
    final ratio = newSpan / oldSpan;
    var newStart = currentFocal - (startFocal - _scaleStartStart) * ratio;
    newStart = newStart.clamp(0.0, 1 - newSpan);
    setState(() {
      _viewStart = newStart;
      _viewEnd = newStart + newSpan;
      _cursorTime = null;
    });
  }

  Widget _buildTooltip(
    BuildContext context,
    HistoryFixture fixture,
    Rect plot,
  ) {
    final cursor = _cursorTime!;
    final totalMs = fixture.end.difference(fixture.start).inMilliseconds;
    final fraction = (cursor.difference(fixture.start).inMilliseconds / totalMs)
        .clamp(0.0, 1.0);
    final x = plot.left + plot.width * fraction;
    final alignLeft = x > plot.center.dx;
    final probes = controller.historyProbe == null
        ? [1, 2, 3, 4]
        : [controller.historyProbe!];
    final rows = <Widget>[];
    for (final probe in probes) {
      final series = fixture.series[probe - 1];
      ChartPoint? nearest;
      for (final point in series.points) {
        if (point.valueF == null) continue;
        if (nearest == null ||
            point.time.difference(cursor).inMilliseconds.abs() <
                nearest.time.difference(cursor).inMilliseconds.abs()) {
          nearest = point;
        }
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: ProbeColors.forIndex(context, probe - 1),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'P$probe',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                nearest?.valueF == null
                    ? 'No reading'
                    : controller.tempFor(nearest!.valueF),
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }
    return Positioned(
      top: 8,
      left: alignLeft ? null : x + 10,
      right: alignLeft ? 8 : null,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 172,
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      clockLabel(
                        cursor,
                        use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
                      ),
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _cursorTime = null),
                    child: Icon(
                      Icons.close,
                      size: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartControlButton extends StatelessWidget {
  const _ChartControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
    );
  }
}
