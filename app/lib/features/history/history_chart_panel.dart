import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/formatters.dart';
import '../../app/view_state.dart';
import '../../domain/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/probe_chart.dart';

/// Loads a chart-only fixture for an arbitrary time window. History supplies
/// this so the chart can prefetch a margin around the visible viewport while
/// the user pans or pinches; Summary statistics still load from the committed
/// range through the normal view loader.
typedef HistoryChartRangeLoader = Future<HistoryFixture> Function(
  DateTimeRange range,
);

/// The interactive chart surface used by History and the dedicated full-screen
/// chart view.
///
/// The panel owns the absolute viewport, gesture state, scrub cursor and the
/// overview brush. A gesture is committed as a custom range only when it
/// settles, so a pinch frame never waits on SQLite. The dropdown therefore
/// follows the chart: as soon as the user changes the visible window, History
/// shows `Custom` and the Summary reloads for that exact window.
class HistoryChartPanel extends StatefulWidget {
  const HistoryChartPanel({
    super.key,
    required this.view,
    this.expanded = false,
    this.historical = false,
    this.loadRange,
    this.onRangeChanged,
    this.onGoLive,
    this.onProbeChanged,
  });

  final HistoryViewState view;

  /// Fills the available height instead of using the inline 300 px height.
  final bool expanded;

  /// A past cook uses `Recorded` and never labels the right edge `Now`.
  final bool historical;

  /// Optional data prefetch seam. When null the chart only paints the loaded
  /// fixture; gestures still commit a custom range.
  final HistoryChartRangeLoader? loadRange;

  /// Called after a pan, pinch, brush or double-tap settles. History commits
  /// this as a custom range so the Summary matches the visible window.
  final ValueChanged<DateTimeRange>? onRangeChanged;

  /// Resumes live-follow. History selects its normal live preset.
  final VoidCallback? onGoLive;

  /// Selects one probe, or null for all probes. The chart legend is the quick
  /// selector; the filter menu stays available for explicit access.
  final ValueChanged<int?>? onProbeChanged;

  @override
  State<HistoryChartPanel> createState() => HistoryChartPanelState();
}

class HistoryChartPanelState extends State<HistoryChartPanel>
    with SingleTickerProviderStateMixin {
  static const Duration _minimumSpan = Duration(seconds: 30);
  static const double _cursorHitSlop = 28;
  static const int _maxCachedFixtures = 8;

  final List<HistoryFixture> _fixtures = <HistoryFixture>[];
  final Set<String> _loadingRanges = <String>{};

  late DateTime _viewStart;
  late DateTime _viewEnd;
  late bool _followLatest;
  late final AnimationController _flingController;

  HistoryFixture? _overview;
  bool _overviewRequested = false;

  DateTime? _cursorTime;
  bool _scrubbing = false;

  /// The y-domain captured at gesture start. It prevents a prefetch or a
  /// viewport change from rescaling the chart while the user is scrolling.
  HistoryYDomain? _frozenYDomain;
  HistoryYDomain? _currentYDomain;
  Timer? _yDomainTimer;

  DateTime _gestureStartStart = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _gestureStartEnd = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _gestureStartFocal = Offset.zero;
  int _gesturePointerCount = 0;
  double _gestureScaleBaseline = 1;
  bool _gestureMoved = false;
  bool _gestureWasPinch = false;

  Offset? _doubleTapPosition;
  Timer? _prefetchTimer;
  Timer? _commitTimer;
  DateTimeRange? _lastCommittedRange;
  DateTimeRange? _prefetchRange;

  DateTime _flingFrom = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _flingTo = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _flingSpan = Duration.zero;

  HistoryViewState get view => widget.view;

  HistoryFixture get _paintFixture =>
      _bestFixtureFor(_viewStart, _viewEnd) ?? view.fixture;

  bool get _panned {
    final fixture = view.fixture;
    return _viewStart.difference(fixture.start).inSeconds.abs() > 1 ||
        _viewEnd.difference(fixture.end).inSeconds.abs() > 1;
  }

  bool get _canGoLive => !widget.historical && !_followLatest;

  @override
  void initState() {
    super.initState();
    _viewStart = view.fixture.start;
    _viewEnd = view.fixture.end;
    _followLatest = view.range.followsNewest;
    _fixtures.add(view.fixture);
    _flingController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 320),
          )
          ..addListener(_tickFling)
          ..addStatusListener(_onFlingStatus);
    _requestOverview();
  }

  @override
  void didUpdateWidget(covariant HistoryChartPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rememberFixture(view.fixture);

    if (oldWidget.view.units != view.units) {
      _yDomainTimer?.cancel();
      _frozenYDomain = null;
    }

    final rangeChanged =
        oldWidget.view.range != view.range ||
        !_sameRange(oldWidget.view.customRange, view.customRange);
    if (rangeChanged) {
      _commitTimer?.cancel();
      _prefetchTimer?.cancel();
      _yDomainTimer?.cancel();
      _frozenYDomain = null;
      _lastCommittedRange = null;
      _viewStart = view.fixture.start;
      _viewEnd = view.fixture.end;
      _followLatest = view.range.followsNewest;
      _cursorTime = null;
      _gestureMoved = false;
      _requestOverview();
      return;
    }

    final oldFixture = oldWidget.view.fixture;
    final newFixture = view.fixture;
    if (oldFixture.start != newFixture.start ||
        oldFixture.end != newFixture.end) {
      if (_followLatest && view.range.followsNewest) {
        final span = _viewEnd.difference(_viewStart);
        _viewEnd = newFixture.end;
        _viewStart = _viewEnd.subtract(span);
        if (_viewStart.isBefore(newFixture.start)) {
          _viewStart = newFixture.start;
          _viewEnd = _viewStart.add(span);
        }
      }
      final overview = _overview;
      if (overview != null &&
          newFixture.end.difference(overview.end).inMinutes.abs() > 10) {
        _overviewRequested = false;
        _requestOverview();
      }
    }
  }

  @override
  void dispose() {
    _prefetchTimer?.cancel();
    _commitTimer?.cancel();
    _yDomainTimer?.cancel();
    _flingController.dispose();
    super.dispose();
  }

  /// Fits the currently loaded range. Called when filters change or the user
  /// taps the fit control.
  void resetViewport() {
    if (!mounted) return;
    _flingController.stop();
    _prefetchTimer?.cancel();
    _commitTimer?.cancel();
    _yDomainTimer?.cancel();
    setState(() {
      _frozenYDomain = null;
      _viewStart = view.fixture.start;
      _viewEnd = view.fixture.end;
      _followLatest = view.range.followsNewest;
      _cursorTime = null;
      _gestureMoved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fixture = _paintFixture;
    final chart = widget.expanded
        ? Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return _chartStack(
                  context,
                  fixture,
                  historyChartPlotRect(size),
                );
              },
            ),
          )
        : SizedBox(
            height: 300,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return _chartStack(
                  context,
                  fixture,
                  historyChartPlotRect(size),
                );
              },
            ),
          );

    return Column(
      children: [
        chart,
        if (fixture.hasValues || (_overview?.hasValues ?? false)) ...[
          const SizedBox(height: 2),
          HistoryRangeBrush(
            key: const Key('history.overview'),
            fixture: _overview ?? fixture,
            viewStart: _viewStart,
            viewEnd: _viewEnd,
            colors: ProbeColors.of(context),
            visibleProbe: view.probe,
            use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
            onChanged: _onBrushChanged,
            onChangeEnd: (_) {
              _scheduleCommit();
              _releaseYDomainSoon();
            },
          ),
        ],
        const SizedBox(height: 6),
        _chartLegend(context),
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
        if (_gestureMoved)
          Positioned(
            top: 8,
            right: 10,
            child: _ViewportPill(
              label:
                  '${durationShort(_viewEnd.difference(_viewStart))} · Custom',
            ),
          ),
      ],
    );
  }

  Widget _chartGestureLayer(
    BuildContext context,
    HistoryFixture fixture,
    Rect plot,
  ) {
    final targetDomain =
        _frozenYDomain ??
        historyYDomainFor(fixture, visibleProbe: view.probe, units: view.units);
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
        onTapUp: (details) => _handleTap(context, details.localPosition, plot),
        onDoubleTapDown: (details) =>
            _doubleTapPosition = details.localPosition,
        onDoubleTap: () => _handleDoubleTap(plot),
        onLongPressStart: (details) =>
            _setCursorAt(details.localPosition, plot, scrub: true),
        onLongPressMoveUpdate: (details) =>
            _setCursorAt(details.localPosition, plot, scrub: true),
        onLongPressEnd: (_) {
          _scrubbing = false;
          _releaseYDomainSoon();
        },
        onScaleStart: (details) => _handleScaleStart(details, plot),
        onScaleUpdate: (details) => _handleScaleUpdate(details, plot),
        onScaleEnd: (details) => _handleScaleEnd(details, plot),
        child: TweenAnimationBuilder<HistoryYDomain>(
          key: ValueKey(view.units),
          tween: _YDomainTween(begin: targetDomain, end: targetDomain),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, domain, _) {
            _currentYDomain = domain;
            return HistoryChart(
              fixture: fixture,
              units: view.units,
              colors: ProbeColors.of(context),
              visibleProbe: view.probe,
              viewStart: _viewStart,
              viewEnd: _viewEnd,
              cursorTime: _cursorTime,
              use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
              latestIsNow: !widget.historical && view.endsAtNow,
              yMin: domain.min,
              yMax: domain.max,
            );
          },
        ),
      ),
    );
  }

  Widget _chartLegend(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final probes = const [1, 2, 3, 4];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (view.probe != null && widget.onProbeChanged != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _LegendChip(
                key: const Key('history.legend.all'),
                label: 'All',
                color: scheme.primary,
                selected: false,
                enabled: true,
                onTap: () => widget.onProbeChanged!(null),
              ),
            ),
          for (final probe in probes)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _LegendChip(
                key: Key('history.legend.p$probe'),
                label: 'P$probe',
                value: _visibleLatestLabel(probe),
                color: ProbeColors.forIndex(context, probe - 1),
                selected: view.probe == probe,
                enabled: _probeHasValues(probe),
                onTap: widget.onProbeChanged == null
                    ? null
                    : () => widget.onProbeChanged!(
                        view.probe == probe ? null : probe,
                      ),
              ),
            ),
        ],
      ),
    );
  }

  bool _probeHasValues(int probe) {
    final fixture = _paintFixture;
    if (probe < 1 || probe > fixture.series.length) return false;
    return fixture.series[probe - 1].points.any(
      (point) => point.valueF != null,
    );
  }

  String _visibleLatestLabel(int probe) {
    final fixture = _paintFixture;
    if (probe < 1 || probe > fixture.series.length) return '—';
    final points = <ChartPoint>[
      for (final point in fixture.series[probe - 1].points)
        if (!point.time.isBefore(_viewStart) && !point.time.isAfter(_viewEnd))
          point,
    ];
    final stats = ProbeRangeStats.fromSeries(ChartSeries(probe - 1, points));
    if (stats.last == null) return '—';
    return '${view.valueFor(stats.last)}°';
  }

  Widget _chartControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.touch_app_outlined, size: 14, color: scheme.outline),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            widget.expanded
                ? 'Drag to pan · pinch to zoom · hold to scrub'
                : 'Drag · pinch · hold to scrub',
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
        if (_canGoLive)
          TextButton(
            key: const Key('history.zoom.now'),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.onGoLive?.call();
              if (widget.onGoLive == null) resetViewport();
            },
            child: const Text('Live'),
          )
        else if (_panned && widget.historical)
          TextButton(
            key: const Key('history.zoom.now'),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: resetViewport,
            child: const Text('Fit range'),
          ),
      ],
    );
  }

  void _handleTap(BuildContext context, Offset position, Rect plot) {
    if (!plot.contains(position)) {
      if (_cursorTime != null) setState(() => _cursorTime = null);
      return;
    }
    final time = _timeFor(position, plot);
    final gap = _gapAt(time);
    if (gap != null) {
      _showGapSheet(context, gap);
      return;
    }
    _setCursorAt(position, plot);
  }

  void _handleDoubleTap(Rect plot) {
    final position = _doubleTapPosition;
    if (position == null || !plot.contains(position)) return;
    final span = _viewEnd.difference(_viewStart);
    if (span <= _minimumSpan * 2) {
      resetViewport();
      return;
    }
    final fraction = ((position.dx - plot.left) / plot.width).clamp(0.0, 1.0);
    _zoomAt(0.5, fraction);
    HapticFeedback.lightImpact();
    _scheduleCommit();
  }

  void _handleScaleStart(ScaleStartDetails details, Rect plot) {
    _flingController.stop();
    _prefetchTimer?.cancel();
    _commitTimer?.cancel();
    _yDomainTimer?.cancel();
    _gestureStartStart = _viewStart;
    _gestureStartEnd = _viewEnd;
    _gestureStartFocal = details.localFocalPoint;
    _gesturePointerCount = details.pointerCount;
    _gestureScaleBaseline = 1;
    _gestureMoved = false;
    _gestureWasPinch = details.pointerCount > 1;

    final cursor = _cursorTime;
    if (cursor != null) {
      final cursorX = _xFor(cursor, plot);
      _scrubbing =
          (details.localFocalPoint.dx - cursorX).abs() <= _cursorHitSlop;
    } else {
      _scrubbing = false;
    }
    if (!_scrubbing) {
      _frozenYDomain =
          _currentYDomain ??
          historyYDomainFor(
            _paintFixture,
            visibleProbe: view.probe,
            units: view.units,
          );
    }
    if (!_scrubbing && _cursorTime != null) {
      setState(() => _cursorTime = null);
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, Rect plot) {
    if (_scrubbing) {
      _setCursorAt(details.localFocalPoint, plot, scrub: true);
      return;
    }
    if (plot.width <= 0) return;

    if (details.pointerCount != _gesturePointerCount) {
      _gesturePointerCount = details.pointerCount;
      _gestureStartStart = _viewStart;
      _gestureStartEnd = _viewEnd;
      _gestureStartFocal = details.localFocalPoint;
      _gestureScaleBaseline = details.scale;
      _gestureWasPinch = details.pointerCount > 1;
    }

    final oldSpan = _gestureStartEnd.difference(_gestureStartStart);
    final dx = details.localFocalPoint.dx - _gestureStartFocal.dx;
    final scale = details.scale / _gestureScaleBaseline;
    final pinch = details.pointerCount > 1 || (scale - 1).abs() > 0.01;
    if (dx.abs() < 1.5 && !pinch) return;
    _gestureMoved = true;
    _gestureWasPinch = _gestureWasPinch || pinch;

    if (pinch) {
      final newSpan = _clampSpan(
        Duration(
          milliseconds: (oldSpan.inMilliseconds / math.max(0.01, scale))
              .round(),
        ),
      );
      final startFraction = ((_gestureStartFocal.dx - plot.left) / plot.width)
          .clamp(0.0, 1.0);
      final currentFraction =
          ((details.localFocalPoint.dx - plot.left) / plot.width).clamp(
            0.0,
            1.0,
          );
      final focalTime = _gestureStartStart.add(
        Duration(
          milliseconds: (oldSpan.inMilliseconds * startFraction).round(),
        ),
      );
      final newStart = focalTime.subtract(
        Duration(
          milliseconds: (newSpan.inMilliseconds * currentFraction).round(),
        ),
      );
      _setViewport(newStart, newStart.add(newSpan));
    } else {
      final shift = -dx / plot.width * oldSpan.inMilliseconds;
      final newStart = _gestureStartStart.add(
        Duration(milliseconds: shift.round()),
      );
      _setViewport(newStart, newStart.add(oldSpan));
    }
    _ensureData();
  }

  void _handleScaleEnd(ScaleEndDetails details, Rect plot) {
    if (_scrubbing) {
      _scrubbing = false;
      return;
    }
    if (!_gestureMoved) {
      _releaseYDomainSoon();
      return;
    }
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (!_gestureWasPinch && velocity.abs() > 240) {
      _startFling(velocity, plot);
    } else {
      _scheduleCommit();
      _releaseYDomainSoon();
    }
    HapticFeedback.lightImpact();
  }

  void _releaseYDomainSoon() {
    _yDomainTimer?.cancel();
    _yDomainTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _frozenYDomain = null);
    });
  }

  void _startFling(double velocity, Rect plot) {
    final span = _viewEnd.difference(_viewStart);
    final shiftMs = -velocity / plot.width * span.inMilliseconds * 0.18;
    final target = _clampViewport(
      _viewStart.add(Duration(milliseconds: shiftMs.round())),
      _viewEnd.add(Duration(milliseconds: shiftMs.round())),
    );
    _flingFrom = _viewStart;
    _flingTo = target.start;
    _flingSpan = span;
    _flingController.forward(from: 0);
  }

  void _tickFling() {
    if (!mounted) return;
    final curve = Curves.decelerate.transform(_flingController.value);
    final delta = _flingTo.difference(_flingFrom);
    final start = _flingFrom.add(
      Duration(milliseconds: (delta.inMilliseconds * curve).round()),
    );
    _setViewport(start, start.add(_flingSpan));
  }

  void _onFlingStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _ensureData();
      _scheduleCommit();
      _releaseYDomainSoon();
    }
  }

  void _onBrushChanged(DateTimeRange range) {
    _flingController.stop();
    _yDomainTimer?.cancel();
    _frozenYDomain ??=
        _currentYDomain ??
        historyYDomainFor(
          _paintFixture,
          visibleProbe: view.probe,
          units: view.units,
        );
    _setViewport(range.start, range.end);
    _ensureData();
  }

  void _zoomAt(double factor, double focalFraction) {
    final oldSpan = _viewEnd.difference(_viewStart);
    final newSpan = _clampSpan(
      Duration(milliseconds: (oldSpan.inMilliseconds * factor).round()),
    );
    final focalTime = _viewStart.add(
      Duration(milliseconds: (oldSpan.inMilliseconds * focalFraction).round()),
    );
    final newStart = focalTime.subtract(
      Duration(milliseconds: (newSpan.inMilliseconds * focalFraction).round()),
    );
    _setViewport(newStart, newStart.add(newSpan));
    _ensureData();
    _scheduleCommit();
  }

  Duration _clampSpan(Duration span) {
    final hard = _hardRange();
    final maxSpan = hard.end.difference(hard.start);
    var value = span;
    if (value < _minimumSpan) value = _minimumSpan;
    if (maxSpan > Duration.zero && value > maxSpan) value = maxSpan;
    if (value <= Duration.zero) value = _minimumSpan;
    return value;
  }

  DateTimeRange _hardRange() {
    if (widget.historical) {
      return DateTimeRange(start: view.fixture.start, end: view.fixture.end);
    }
    final entire = view.entireHistoryRange;
    var start = entire.start;
    var end = entire.end;
    if (view.fixture.start.isBefore(start)) start = view.fixture.start;
    if (view.fixture.end.isAfter(end)) end = view.fixture.end;
    if (end.isAfter(start)) {
      return DateTimeRange(start: start, end: end);
    }
    return DateTimeRange(start: view.fixture.start, end: view.fixture.end);
  }

  DateTimeRange _clampViewport(DateTime start, DateTime end) {
    final hard = _hardRange();
    final span = _clampSpan(end.difference(start));
    var nextStart = start;
    if (nextStart.isBefore(hard.start)) nextStart = hard.start;
    if (nextStart.add(span).isAfter(hard.end)) {
      nextStart = hard.end.subtract(span);
    }
    if (nextStart.isBefore(hard.start)) nextStart = hard.start;
    return DateTimeRange(start: nextStart, end: nextStart.add(span));
  }

  void _setViewport(DateTime start, DateTime end) {
    final next = _clampViewport(start, end);
    if (next.start == _viewStart && next.end == _viewEnd) return;
    setState(() {
      _viewStart = next.start;
      _viewEnd = next.end;
      final cursor = _cursorTime;
      if (cursor != null &&
          (cursor.isBefore(next.start) || cursor.isAfter(next.end))) {
        _cursorTime = null;
      }
      final fixtureEnd = view.fixture.end;
      _followLatest =
          view.range.followsNewest &&
          _viewEnd.difference(fixtureEnd).inSeconds.abs() <= 60;
    });
  }

  void _setCursorAt(Offset position, Rect plot, {bool scrub = false}) {
    if (!plot.contains(position)) return;
    var time = _timeFor(position, plot);
    final nearest = _nearestSampleTime(time);
    if (nearest != null &&
        nearest.difference(time).inMilliseconds.abs() <=
            _snapWindow(plot.width).inMilliseconds) {
      time = nearest;
    }
    final changed =
        _cursorTime?.microsecondsSinceEpoch != time.microsecondsSinceEpoch;
    setState(() {
      _cursorTime = time;
      _scrubbing = scrub;
    });
    if (changed) HapticFeedback.selectionClick();
  }

  DateTime? _nearestSampleTime(DateTime time) {
    DateTime? nearest;
    for (final series in _paintFixture.series) {
      if (view.probe != null && series.index + 1 != view.probe) continue;
      for (final point in series.points) {
        if (point.valueF == null) continue;
        if (point.time.isBefore(_viewStart) || point.time.isAfter(_viewEnd)) {
          continue;
        }
        if (nearest == null ||
            point.time.difference(time).inMilliseconds.abs() <
                nearest.difference(time).inMilliseconds.abs()) {
          nearest = point.time;
        }
      }
    }
    return nearest;
  }

  Duration _snapWindow(double width) {
    final span = _viewEnd.difference(_viewStart);
    final pixels = math.max(1.0, width);
    final raw = span.inMilliseconds / pixels * 8;
    return Duration(milliseconds: raw.round().clamp(3000, 120000).toInt());
  }

  DateTime _timeFor(Offset position, Rect plot) {
    final fraction = ((position.dx - plot.left) / plot.width).clamp(0.0, 1.0);
    return _viewStart.add(
      Duration(
        milliseconds:
            (_viewEnd.difference(_viewStart).inMilliseconds * fraction).round(),
      ),
    );
  }

  double _xFor(DateTime time, Rect plot) {
    final span = math.max(1, _viewEnd.difference(_viewStart).inMilliseconds);
    return plot.left +
        time.difference(_viewStart).inMilliseconds / span * plot.width;
  }

  HistoryGapBand? _gapAt(DateTime time) {
    for (final gap in _paintFixture.allGaps) {
      if (!time.isBefore(gap.start) && !time.isAfter(gap.end)) return gap;
    }
    return null;
  }

  void _showGapSheet(BuildContext context, HistoryGapBand gap) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.link_off, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      gap.reason.label,
                      style: Theme.of(sheetContext).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(gap.reason.explanation),
              const SizedBox(height: 10),
              Text(
                '${gapDurationLabel(gap.end.difference(gap.start))} · '
                '${absoluteRangeLabel(gap.start, gap.end, use24Hour: MediaQuery.alwaysUse24HourFormatOf(sheetContext))}',
                style: Theme.of(sheetContext).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTooltip(
    BuildContext context,
    HistoryFixture fixture,
    Rect plot,
  ) {
    final cursor = _cursorTime!;
    final totalMs = _viewEnd.difference(_viewStart).inMilliseconds;
    final fraction = (cursor.difference(_viewStart).inMilliseconds / totalMs)
        .clamp(0.0, 1.0);
    final x = plot.left + plot.width * fraction;
    final alignLeft = x > plot.center.dx;
    final probes = view.probe == null ? [1, 2, 3, 4] : [view.probe!];
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
                    : view.tempFor(nearest!.valueF),
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }
    final span = _viewEnd.difference(_viewStart);
    final timeLabel = span > const Duration(hours: 36)
        ? dateTimeLabel(
            cursor,
            use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
          )
        : clockLabel(
            cursor,
            use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    return Positioned(
      top: 8,
      left: alignLeft ? null : x + 10,
      right: alignLeft ? 8 : null,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 196,
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 5),
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
                      timeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'Close reading',
                      onPressed: () => setState(() => _cursorTime = null),
                      icon: const Icon(Icons.close, size: 16),
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

  void _requestOverview() {
    if (_overviewRequested || widget.loadRange == null) return;
    final range = view.entireHistoryRange;
    if (!range.end.isAfter(range.start)) return;
    if (range.start == view.fixture.start && range.end == view.fixture.end) {
      return;
    }
    _overviewRequested = true;
    unawaited(_loadOverview(range));
  }

  Future<void> _loadOverview(DateTimeRange range) async {
    try {
      final fixture = await widget.loadRange!(range);
      if (!mounted) return;
      setState(() => _overview = fixture);
    } catch (_) {
      _overviewRequested = false;
    }
  }

  void _rememberFixture(HistoryFixture fixture) {
    if (fixture.start == fixture.end) return;
    for (var i = 0; i < _fixtures.length; i++) {
      final existing = _fixtures[i];
      if (existing.start == fixture.start && existing.end == fixture.end) {
        _fixtures
          ..removeAt(i)
          ..add(fixture);
        return;
      }
    }
    _fixtures.add(fixture);
    if (_fixtures.length > _maxCachedFixtures) {
      _fixtures.removeAt(0);
    }
  }

  HistoryFixture? _bestFixtureFor(DateTime start, DateTime end) {
    HistoryFixture? best;
    Duration? bestSpan;
    for (final fixture in _fixtures) {
      if (fixture.start.isAfter(start) || fixture.end.isBefore(end)) continue;
      final span = fixture.end.difference(fixture.start);
      if (bestSpan == null || span <= bestSpan) {
        best = fixture;
        bestSpan = span;
      }
    }
    if (best != null) return best;

    final overview = _overview;
    if (overview != null &&
        !overview.start.isAfter(start) &&
        !overview.end.isBefore(end)) {
      return overview;
    }

    // No cached window fully covers the viewport. Prefer the fixture with the
    // largest overlap so the chart keeps drawing every real point it has.
    var bestOverlap = Duration.zero;
    for (final fixture in _fixtures) {
      final overlapStart = fixture.start.isAfter(start) ? fixture.start : start;
      final overlapEnd = fixture.end.isBefore(end) ? fixture.end : end;
      final overlap = overlapEnd.difference(overlapStart);
      if (overlap >= bestOverlap) {
        bestOverlap = overlap;
        best = fixture;
      }
    }
    return best;
  }

  void _ensureData() {
    if (widget.loadRange == null) return;
    if (_fixtures.any(
      (fixture) =>
          !fixture.start.isAfter(_viewStart) && !fixture.end.isBefore(_viewEnd),
    )) {
      return;
    }
    final span = _viewEnd.difference(_viewStart);
    final margin = Duration(milliseconds: (span.inMilliseconds * 0.75).round());
    final hard = _hardRange();
    var start = _viewStart.subtract(margin);
    var end = _viewEnd.add(margin);
    if (start.isBefore(hard.start)) start = hard.start;
    if (end.isAfter(hard.end)) end = hard.end;
    if (!end.isAfter(start)) return;
    _schedulePrefetch(DateTimeRange(start: start, end: end));
  }

  void _schedulePrefetch(DateTimeRange range) {
    if (_fixtures.any(
      (fixture) =>
          !fixture.start.isAfter(range.start) &&
          !fixture.end.isBefore(range.end),
    )) {
      return;
    }
    if (_prefetchRange != null && _sameRange(_prefetchRange, range)) return;
    _prefetchRange = range;
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 120), () {
      final pending = _prefetchRange;
      if (pending == null) return;
      _prefetchRange = null;
      unawaited(_loadRange(pending));
    });
  }

  Future<void> _loadRange(DateTimeRange range) async {
    final loader = widget.loadRange;
    if (loader == null) return;
    final key = _rangeKey(range);
    if (!_loadingRanges.add(key)) return;
    try {
      final fixture = await loader(range);
      if (!mounted) return;
      setState(() => _rememberFixture(fixture));
    } catch (_) {
      // A prefetch is best-effort. The committed range still loads through
      // HistoryViewLoader and its error surface.
    } finally {
      _loadingRanges.remove(key);
    }
  }

  void _scheduleCommit() {
    if (widget.historical || widget.onRangeChanged == null) return;
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 140), _commitViewport);
  }

  void _commitViewport() {
    if (!mounted) return;
    final range = DateTimeRange(start: _viewStart, end: _viewEnd);
    if (_sameRange(
      range,
      DateTimeRange(start: view.fixture.start, end: view.fixture.end),
    )) {
      setState(() => _gestureMoved = false);
      return;
    }
    if (_sameRange(range, _lastCommittedRange)) {
      setState(() => _gestureMoved = false);
      return;
    }
    _lastCommittedRange = range;
    setState(() => _gestureMoved = false);
    widget.onRangeChanged?.call(range);
  }

  String _rangeKey(DateTimeRange range) =>
      '${range.start.millisecondsSinceEpoch}|${range.end.millisecondsSinceEpoch}';

  bool _sameRange(DateTimeRange? a, DateTimeRange? b) {
    if (a == null || b == null) return a == b;
    return a.start.millisecondsSinceEpoch == b.start.millisecondsSinceEpoch &&
        a.end.millisecondsSinceEpoch == b.end.millisecondsSinceEpoch;
  }
}

class _YDomainTween extends Tween<HistoryYDomain> {
  _YDomainTween({super.begin, super.end});

  @override
  HistoryYDomain lerp(double t) {
    final from = begin ?? end!;
    final to = end ?? begin!;
    return HistoryYDomain(
      from.min + (to.min - from.min) * t,
      from.max + (to.max - from.max) * t,
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

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.enabled,
    this.value,
    this.onTap,
  });

  final String label;
  final String? value;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = enabled;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      excludeSemantics: true,
      label: value == null ? label : '$label, $value',
      child: Material(
        color: selected
            ? color.withValues(alpha: 0.14)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: active ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? color.withValues(alpha: 0.55)
                    : scheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active ? color : color.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: active
                        ? scheme.onSurfaceVariant
                        : scheme.onSurfaceVariant.withValues(alpha: 0.45),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 5),
                  Text(
                    value!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: active
                          ? scheme.onSurface
                          : scheme.onSurface.withValues(alpha: 0.4),
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewportPill extends StatelessWidget {
  const _ViewportPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary),
        ),
      ),
    );
  }
}
