import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../prototype/fixtures.dart';
import '../../prototype/formatters.dart';
import '../../prototype/prototype_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/probe_chart.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.controller,
    this.fullScreen = false,
  });

  final PrototypeController controller;
  final bool fullScreen;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  double _viewStart = 0;
  double _viewEnd = 1;
  double _scaleStartStart = 0;
  double _scaleStartEnd = 1;
  double _scaleStartFocalX = 0;
  DateTime? _cursorTime;

  PrototypeController get controller => widget.controller;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _panned => _viewStart > 0.001 || _viewEnd < 0.999;

  void _resetViewport() {
    setState(() {
      _viewStart = 0;
      _viewEnd = 1;
      _cursorTime = null;
    });
  }

  HistoryFixture _fixture() {
    return buildHistoryFixture(
      controller.historyRange,
      empty: !controller.historyHasData,
      oneProbe: controller.historyOneProbe,
      estimated: controller.historyEstimated,
      missingFromBridge: controller.historyMissingFromBridge,
      customStart: controller.historyCustomRange?.start,
      customEnd: controller.historyCustomRange?.end,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final fixture = _fixture();
        if (widget.fullScreen) {
          return Scaffold(
            appBar: prototypeAppBar(
              context,
              controller,
              'History',
              actions: [ConnectionStatusChip(controller: controller)],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  children: [
                    _filters(context, fixture),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _chartCard(context, fixture, expanded: true),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return ListView(
          controller: _scrollController,
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _filters(context, fixture),
                  const SizedBox(height: 10),
                  _chartCard(context, fixture),
                  const SizedBox(height: 14),
                  _summaryCard(context, fixture),
                  if (_showDays(fixture)) ...[
                    const SizedBox(height: 14),
                    _daysCard(context, fixture),
                  ],
                  if (controller.historyMissingFromBridge) ...[
                    const SizedBox(height: 12),
                    InlineNotice(
                      icon: Icons.link_off,
                      title: 'Some history was overwritten',
                      message: 'The bridge reused this time range before it synced. The gap is permanent; the chart does not draw a straight line across it.',
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _filters(BuildContext context, HistoryFixture fixture) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final range in HistoryRange.values)
                if (range != HistoryRange.custom)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(historyChipLabel(range)),
                      selected: controller.historyRange == range,
                      onSelected: (_) {
                        controller.setHistoryRange(range);
                        _resetViewport();
                      },
                    ),
                  ),
              if (controller.historyRange == HistoryRange.custom)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    label: const Text('CUSTOM'),
                    selected: true,
                    onSelected: (_) => _pickCustomRange(fixture),
                  ),
                ),
              IconButton.filledTonal(
                tooltip: 'Custom date range',
                visualDensity: VisualDensity.compact,
                onPressed: () => _pickCustomRange(fixture),
                icon: const Icon(Icons.calendar_month_outlined, size: 19),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _probeChip(context, fixture, null, 'All'),
              for (var i = 0; i < 4; i++)
                _probeChip(context, fixture, i + 1, 'P${i + 1}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _probeChip(
    BuildContext context,
    HistoryFixture fixture,
    int? probe,
    String label,
  ) {
    final selected = controller.historyProbe == probe;
    final hasData = probe == null || fixture.seriesHasValues(probe - 1);
    final color = probe == null
        ? Theme.of(context).colorScheme.primary
        : ProbeColors.forIndex(context, probe - 1);
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        avatar: probe == null
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: hasData ? color : color.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              ),
        label: Text(label),
        selected: selected,
        onSelected: hasData
            ? (_) {
                controller.setHistoryProbe(probe);
                _resetViewport();
              }
            : null,
      ),
    );
  }

  Widget _chartCard(
    BuildContext context,
    HistoryFixture fixture, {
    bool expanded = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final window = historyWindowLabel(
      controller.historyRange,
      fixture.start,
      fixture.end,
      use24Hour: use24Hour,
    );
    final noData = !fixture.hasValues;
    final noProbeData =
        controller.historyProbe != null &&
        !fixture.seriesHasValues(controller.historyProbe! - 1);
    final chart = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    window,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        controller.isOffline ? 'Saved 2h ago' : 'Saved 2m ago',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (fixture.estimated) ...[
                        const SizedBox(width: 8),
                        Text(
                          'estimated time',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: StatusColors.aging(context),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Chart help',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showChartHelp(context),
              icon: const Icon(Icons.help_outline, size: 19),
            ),
            IconButton(
              tooltip: 'Full-screen chart',
              visualDensity: VisualDensity.compact,
              onPressed: widget.fullScreen
                  ? () => Navigator.of(context).pop()
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HistoryScreen(
                          controller: controller,
                          fullScreen: true,
                        ),
                      ),
                    ),
              icon: Icon(
                widget.fullScreen ? Icons.close_fullscreen : Icons.open_in_full,
                size: 19,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (noData || noProbeData)
          expanded
              ? Expanded(
                  child: EmptyState(
                    icon: Icons.show_chart,
                    title: noData ? 'No readings yet' : 'No data in this range',
                    message: noData
                        ? 'The bridge records whenever it is on and synced with the Smoke X4.'
                        : 'P${controller.historyProbe} has no readings in this range. Try another range or show all probes.',
                    action: () {
                      if (noData) {
                        controller.setTab(AppTab.live);
                      } else {
                        controller.setHistoryProbe(null);
                        _resetViewport();
                      }
                    },
                    actionLabel: noData ? 'Go to Live' : 'Show all probes',
                  ),
                )
              : SizedBox(
                  height: 300,
                  child: EmptyState(
                    icon: Icons.show_chart,
                    title: noData ? 'No readings yet' : 'No data in this range',
                    message: noData
                        ? 'The bridge records whenever it is on and synced with the Smoke X4.'
                        : 'P${controller.historyProbe} has no readings in this range. Try another range or show all probes.',
                    action: () {
                      if (noData) {
                        controller.setTab(AppTab.live);
                      } else {
                        controller.setHistoryProbe(null);
                        _resetViewport();
                      }
                    },
                    actionLabel: noData ? 'Go to Live' : 'Show all probes',
                  ),
                )
        else
          expanded
              ? Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final plot = historyChartPlotRect(
                              Size(constraints.maxWidth, constraints.maxHeight),
                            );
                            return _chartGestureLayer(context, fixture, plot);
                          },
                        ),
                      ),
                      if (_cursorTime != null) _buildTooltip(context, fixture),
                    ],
                  ),
                )
              : SizedBox(
                  height: 300,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final plot = historyChartPlotRect(
                              Size(constraints.maxWidth, constraints.maxHeight),
                            );
                            return _chartGestureLayer(context, fixture, plot);
                          },
                        ),
                      ),
                      if (_cursorTime != null) _buildTooltip(context, fixture),
                    ],
                  ),
                ),
        if (_panned)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 36),
                ),
                onPressed: _resetViewport,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Now'),
              ),
            ),
          ),
      ],
    );

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: chart,
    );
  }

  Widget _chartGestureLayer(
    BuildContext context,
    HistoryFixture fixture,
    Rect plot,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _setCursor(details.localPosition, plot),
      onDoubleTap: _resetViewport,
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
      ),
    );
  }

  void _setCursor(Offset position, Rect plot) {
    if (!plot.contains(position)) {
      setState(() => _cursorTime = null);
      return;
    }
    final fraction = ((position.dx - plot.left) / plot.width).clamp(0.0, 1.0);
    final fixture = _fixture();
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

  Widget _buildTooltip(BuildContext context, HistoryFixture fixture) {
    final cursor = _cursorTime!;
    final plotWidth =
        MediaQuery.sizeOf(context).width - (widget.fullScreen ? 104 : 88);
    final totalMs = fixture.end.difference(fixture.start).inMilliseconds;
    final fraction = (cursor.difference(fixture.start).inMilliseconds / totalMs)
        .clamp(0.0, 1.0);
    final x = plotWidth * fraction;
    final alignLeft = x > plotWidth * 0.52;
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

  Widget _summaryCard(BuildContext context, HistoryFixture fixture) {
    final probes = controller.historyProbe == null
        ? [1, 2, 3, 4]
        : [controller.historyProbe!];
    final stats = probes
        .map((probe) => ProbeRangeStats.fromSeries(fixture.series[probe - 1]))
        .toList();
    switch (controller.historySort) {
      case HistorySort.jack:
        stats.sort((a, b) => a.probe.compareTo(b.probe));
        break;
      case HistorySort.hottest:
        stats.sort((a, b) {
          if (a.last == null && b.last == null) return 0;
          if (a.last == null) return 1;
          if (b.last == null) return -1;
          return b.last!.compareTo(a.last!);
        });
        break;
      case HistorySort.largestChange:
        stats.sort((a, b) {
          final aChange = a.change?.abs() ?? -1;
          final bChange = b.change?.abs() ?? -1;
          return bChange.compareTo(aChange);
        });
        break;
      case HistorySort.recent:
        stats.sort((a, b) {
          if (a.lastSampleAt == null && b.lastSampleAt == null) return 0;
          if (a.lastSampleAt == null) return 1;
          if (b.lastSampleAt == null) return -1;
          return b.lastSampleAt!.compareTo(a.lastSampleAt!);
        });
        break;
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Summary',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              PopupMenuButton<HistorySort>(
                tooltip: 'Sort summary',
                initialValue: controller.historySort,
                onSelected: controller.setHistorySort,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: HistorySort.jack,
                    child: Text('Jack order'),
                  ),
                  PopupMenuItem(
                    value: HistorySort.hottest,
                    child: Text('Hottest first'),
                  ),
                  PopupMenuItem(
                    value: HistorySort.largestChange,
                    child: Text('Largest change'),
                  ),
                  PopupMenuItem(
                    value: HistorySort.recent,
                    child: Text('Most recent'),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _sortLabel(controller.historySort),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final stat in stats)
            _SummaryRow(
              stat: stat,
              controller: controller,
              selected: controller.historyProbe == stat.probe,
              onTap: () {
                controller.setHistoryProbe(
                  controller.historyProbe == stat.probe ? null : stat.probe,
                );
                _resetViewport();
              },
            ),
        ],
      ),
    );
  }

  String _sortLabel(HistorySort sort) {
    switch (sort) {
      case HistorySort.jack:
        return 'Jack order';
      case HistorySort.hottest:
        return 'Hottest';
      case HistorySort.largestChange:
        return 'Largest change';
      case HistorySort.recent:
        return 'Most recent';
    }
  }

  bool _showDays(HistoryFixture fixture) {
    final span = fixture.end.difference(fixture.start);
    return controller.historyRange == HistoryRange.sevenDays ||
        controller.historyRange == HistoryRange.all ||
        (controller.historyRange == HistoryRange.custom && span.inDays >= 2);
  }

  Widget _daysCard(BuildContext context, HistoryFixture fixture) {
    final days = _daySummaries(fixture);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Days',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: controller.toggleDaysSort,
                child: Text(
                  controller.daysNewestFirst ? 'Newest first' : 'Oldest first',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final day in days)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(_dayLabel(day.day)),
              subtitle: Text(
                '${commaInt(day.readings)} readings · ${day.probes} probes${day.hasGap ? ' · 1 gap' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                controller.setHistoryCustomRange(
                  DateTimeRange(
                    start: DateTime(day.day.year, day.day.month, day.day.day),
                    end: DateTime(
                      day.day.year,
                      day.day.month,
                      day.day.day,
                      23,
                      59,
                      59,
                    ),
                  ),
                );
                _resetViewport();
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  List<_DaySummary> _daySummaries(HistoryFixture fixture) {
    final probes = controller.historyProbe == null
        ? [1, 2, 3, 4]
        : [controller.historyProbe!];
    final map = <DateTime, _DaySummary>{};
    for (final probe in probes) {
      for (final point in fixture.series[probe - 1].points) {
        if (point.valueF == null) continue;
        final day = DateTime(point.time.year, point.time.month, point.time.day);
        final summary = map.putIfAbsent(
          day,
          () => _DaySummary(day: day, readings: 0, probes: 0, hasGap: false),
        );
        map[day] = _DaySummary(
          day: day,
          readings: summary.readings + 1,
          probes: summary.probes + 1,
          hasGap: summary.hasGap,
        );
      }
    }
    final days = map.values.toList();
    // Each probe contributes a point per bucket; report days, not raw sums.
    final normalized = <DateTime, _DaySummary>{};
    for (final day in days) {
      normalized[day.day] = _DaySummary(
        day: day.day,
        readings: day.readings,
        probes: probes.length,
        hasGap: _dayHasGap(day.day, fixture),
      );
    }
    final result = normalized.values.toList();
    result.sort(
      (a, b) => controller.daysNewestFirst
          ? b.day.compareTo(a.day)
          : a.day.compareTo(b.day),
    );
    return result;
  }

  bool _dayHasGap(DateTime day, HistoryFixture fixture) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return fixture.gapStart.isBefore(end) && fixture.gapEnd.isAfter(start);
  }

  String _dayLabel(DateTime day) {
    final today = DateTime(2026, 10, 25);
    final normalized = DateTime(day.year, day.month, day.day);
    if (normalized == today) return 'Today';
    if (normalized == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    return shortDateWithYear(day);
  }

  Future<void> _pickCustomRange(HistoryFixture fixture) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2026, 10, 25),
      initialDateRange:
          controller.historyCustomRange ??
          DateTimeRange(start: fixture.start, end: fixture.end),
      helpText: 'History range',
      saveText: 'Show range',
    );
    if (picked == null) return;
    controller.setHistoryCustomRange(
      DateTimeRange(
        start: DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        ),
      ),
    );
    _resetViewport();
  }

  void _showChartHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reading the chart',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const _HelpRow(
              icon: Icons.touch_app_outlined,
              text: 'Tap the chart to inspect the nearest reading.',
            ),
            const _HelpRow(
              icon: Icons.open_with,
              text: 'Drag to pan. Pinch to zoom. Double-tap to reset.',
            ),
            const _HelpRow(
              icon: Icons.linear_scale,
              text:
                  'A gap means the bridge has no reading for that time. '
                  'The line never bridges a gap.',
            ),
            const _HelpRow(
              icon: Icons.straighten,
              text:
                  'The chart shares one temperature scale when all probes are '
                  'visible, and fits the selected probe when you filter.',
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.stat,
    required this.controller,
    required this.selected,
    required this.onTap,
  });

  final ProbeRangeStats stat;
  final PrototypeController controller;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ProbeColors.forIndex(context, stat.probe - 1);
    final last = stat.last;
    final change = stat.change;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: last == null ? color.withValues(alpha: 0.35) : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 26,
              child: Text(
                'P${stat.probe}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: last == null
                  ? Text(
                      'No data in this range',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                controller.tempFor(last),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            if (change != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  deltaLabel(change, controller.units),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: change.abs() < 0.05
                                            ? scheme.onSurfaceVariant
                                            : change > 0
                                            ? StatusColors.live(context)
                                            : StatusColors.aging(context),
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${controller.valueFor(stat.min)}–${controller.valueFor(stat.max)}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ],
                    ),
            ),
            if (last != null) const SizedBox(width: 2),
            Icon(
              selected ? Icons.check : Icons.chevron_right,
              size: 18,
              color: selected ? color : scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _DaySummary {
  const _DaySummary({
    required this.day,
    required this.readings,
    required this.probes,
    required this.hasGap,
  });

  final DateTime day;
  final int readings;
  final int probes;
  final bool hasGap;
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
