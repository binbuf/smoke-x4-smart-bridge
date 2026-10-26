import 'package:flutter/material.dart';

import '../../prototype/fixtures.dart';
import '../../prototype/formatters.dart';
import '../../prototype/prototype_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';
import 'history_chart_panel.dart';
import 'history_full_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.controller,
    this.title = 'History',
    this.showPastCooks = true,
    this.showFullscreenAction = true,
    this.historical = false,
    this.gapOverride,
  });

  final PrototypeController controller;
  final String title;
  final bool showPastCooks;
  final bool showFullscreenAction;
  final bool historical;
  final bool? gapOverride;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<HistoryChartPanelState> _chartKey =
      GlobalKey<HistoryChartPanelState>();

  PrototypeController get controller => widget.controller;

  bool get _hasActiveFilters =>
      controller.historyProbe != null ||
      controller.historyRange != HistoryRange.twentyFourHours ||
      controller.historyCustomRange != null;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _resetViewport() => _chartKey.currentState?.resetViewport();

  void _resetFilters() {
    controller
      ..setHistoryProbe(null)
      ..setHistoryRange(HistoryRange.twentyFourHours);
    _resetViewport();
  }

  HistoryFixture _fixture() {
    return buildHistoryFixture(
      controller.historyRange,
      empty: !controller.historyHasData,
      oneProbe: controller.historyOneProbe,
      estimated: controller.historyEstimated,
      missingFromBridge: controller.historyMissingFromBridge,
      hasGap: widget.gapOverride ?? true,
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
                  if (controller.historyHasData && widget.showPastCooks) ...[
                    const SizedBox(height: 14),
                    _pastCooksCard(context),
                  ],
                  if (controller.historyMissingFromBridge) ...[
                    const SizedBox(height: 12),
                    InlineNotice(
                      icon: Icons.link_off,
                      title: 'Some readings were lost before they reached your phone',
                      message: 'The Bridge overwrote this part of its history before it reached your phone. The readings can’t be recovered, so the chart leaves this period blank.',
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
    final rangeLabel = controller.historyRange == HistoryRange.custom
        ? 'Custom'
        : historyChipLabel(controller.historyRange);
    final probeLabel = controller.historyProbe == null
        ? 'All probes'
        : 'P${controller.historyProbe}';

    return SectionCard(
      key: const Key('history.filters'),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Row(
        children: [
          if (!widget.historical) ...[
            Expanded(
              child: _FilterMenuButton<HistoryRange>(
                key: const Key('history.range.menu'),
                icon: Icons.schedule_outlined,
                label: rangeLabel,
                tooltip: 'History range',
                items: _rangeMenuItems(context),
                onSelected: _selectRange,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: _FilterMenuButton<int>(
              key: const Key('history.filter.menu'),
              icon: Icons.linear_scale,
              label: probeLabel,
              tooltip: 'Filter by probe',
              items: _probeMenuItems(context, fixture),
              onSelected: (value) {
                controller.setHistoryProbe(value == 0 ? null : value);
                _resetViewport();
              },
            ),
          ),
          if (_hasActiveFilters && !widget.historical)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                key: const Key('history.filters.reset'),
                tooltip: 'Reset filters',
                onPressed: _resetFilters,
                icon: const Icon(Icons.restart_alt, size: 19),
              ),
            ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<HistoryRange>> _rangeMenuItems(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final range in const [
        HistoryRange.oneHour,
        HistoryRange.sixHours,
        HistoryRange.twentyFourHours,
        HistoryRange.twoDays,
        HistoryRange.custom,
      ])
        PopupMenuItem<HistoryRange>(
          key: Key('history.range.${historyRangeKey(range)}'),
          value: range,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      range == HistoryRange.custom
                          ? 'Custom range…'
                          : historyRangeLabel(range),
                    ),
                    if (range == HistoryRange.custom)
                      Text(
                        'Any date and time',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (controller.historyRange == range)
                Icon(Icons.check, size: 18, color: scheme.primary),
            ],
          ),
        ),
    ];
  }

  List<PopupMenuEntry<int>> _probeMenuItems(
    BuildContext context,
    HistoryFixture fixture,
  ) {
    final scheme = Theme.of(context).colorScheme;
    PopupMenuItem<int> item(int value, String label, Color? color) {
      final hasData = value == 0 || fixture.seriesHasValues(value - 1);
      return PopupMenuItem<int>(
        key: Key('history.filter.${value == 0 ? 'all' : 'p$value'}'),
        value: value,
        enabled: hasData,
        child: Row(
          children: [
            if (color != null)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: hasData ? color : color.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              )
            else
              Icon(
                Icons.layers_outlined,
                size: 16,
                color: hasData ? scheme.onSurfaceVariant : scheme.outline,
              ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: hasData ? null : TextStyle(color: scheme.outline),
              ),
            ),
            if (!hasData)
              Text(
                'No data',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: scheme.outline),
              ),
            if (controller.historyProbe == (value == 0 ? null : value)) ...[
              const SizedBox(width: 8),
              Icon(Icons.check, size: 18, color: scheme.primary),
            ],
          ],
        ),
      );
    }

    return [
      item(0, 'All probes', null),
      for (var i = 1; i <= 4; i++)
        item(i, 'P$i', ProbeColors.forIndex(context, i - 1)),
    ];
  }

  Future<void> _selectRange(HistoryRange range) async {
    if (range == HistoryRange.custom) {
      final initial =
          controller.historyCustomRange ?? controller.entireHistoryRange;
      if (controller.historyCustomRange == null) {
        controller.setHistoryCustomRange(initial);
      }
      _resetViewport();
      await _pickCustomRange(initial);
      return;
    }
    controller.setHistoryRange(range);
    _resetViewport();
  }

  Widget _chartCard(BuildContext context, HistoryFixture fixture) {
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
    final probeCount = controller.historyProbe == null ? 4 : 1;
    final dataProbeCount = controller.historyProbe == null
        ? fixture.series
              .where(
                (series) => series.points.any((point) => point.valueF != null),
              )
              .length
        : (fixture.seriesHasValues(controller.historyProbe! - 1) ? 1 : 0);
    final probeMeta = dataProbeCount == probeCount
        ? '$probeCount ${probeCount == 1 ? 'probe' : 'probes'}'
        : '$dataProbeCount of $probeCount ${probeCount == 1 ? 'probe' : 'probes'}';
    final metaLead = noData
        ? 'No readings'
        : widget.historical
        ? 'Recorded history'
        : controller.lastSyncedLabel;

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
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 7,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        metaLead,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      Text(
                        '·',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.outline),
                      ),
                      Text(
                        probeMeta,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (fixture.estimated)
                        Text(
                          '· times estimated',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: StatusColors.aging(context),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'How to read this chart',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showChartHelp(context),
              icon: const Icon(Icons.help_outline, size: 19),
            ),
            if (widget.showFullscreenAction)
              IconButton(
                tooltip: 'Full-screen chart',
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HistoryFullScreenScreen(
                      controller: controller,
                      historical: widget.historical,
                      gapOverride: widget.gapOverride,
                    ),
                  ),
                ),
                icon: const Icon(Icons.open_in_full, size: 19),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (noData || noProbeData)
          SizedBox(
            height: 300,
            child: EmptyState(
              icon: Icons.show_chart,
              title: noData ? 'No readings yet' : 'No readings in this range',
              message: noData
                  ? 'The Bridge records whenever it’s on and paired with the Smoke X4.'
                  : 'Probe ${controller.historyProbe} has no readings in this range. Try another range or show all probes.',
              action: () {
                if (noData) {
                  controller.setTab(AppTab.live);
                } else {
                  controller.setHistoryProbe(null);
                  _resetViewport();
                }
              },
              actionLabel: noData ? 'View Live' : 'Show all probes',
            ),
          )
        else
          HistoryChartPanel(
            key: _chartKey,
            controller: controller,
            fixture: fixture,
            historical: widget.historical,
          ),
      ],
    );

    return SectionCard(
      key: const Key('history.chart'),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: chart,
    );
  }

  Widget _summaryCard(BuildContext context, HistoryFixture fixture) {
    final probes = controller.historyProbe == null
        ? [1, 2, 3, 4]
        : [controller.historyProbe!];
    final stats = probes
        .map((probe) => ProbeRangeStats.fromSeries(fixture.series[probe - 1]))
        .toList();
    final activeCook = currentCookSession();
    final cookReference = activeCook ?? latestCookSession();
    switch (controller.historySort) {
      case HistorySort.probe:
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
      case HistorySort.highestMax:
        stats.sort((a, b) {
          if (a.max == null && b.max == null) return 0;
          if (a.max == null) return 1;
          if (b.max == null) return -1;
          return b.max!.compareTo(a.max!);
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
      case HistorySort.sinceCookStart:
        bool readingInCook(ProbeRangeStats stat) =>
            stat.lastSampleAt != null &&
            (cookReference == null ||
                !stat.lastSampleAt!.isBefore(cookReference.start));
        stats.sort((a, b) {
          final aInCook = readingInCook(a);
          final bInCook = readingInCook(b);
          if (aInCook != bInCook) return aInCook ? -1 : 1;
          if (a.lastSampleAt == null && b.lastSampleAt == null) {
            return a.probe.compareTo(b.probe);
          }
          if (a.lastSampleAt == null) return 1;
          if (b.lastSampleAt == null) return -1;
          return b.lastSampleAt!.compareTo(a.lastSampleAt!);
        });
        break;
    }

    return SectionCard(
      key: const Key('history.summary'),
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
              Text(
                controller.unitsLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<HistorySort>(
                tooltip: 'Sort summary',
                initialValue: controller.historySort,
                onSelected: controller.setHistorySort,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: HistorySort.probe,
                    child: Text('Probe order'),
                  ),
                  const PopupMenuItem(
                    value: HistorySort.hottest,
                    child: Text('Hottest'),
                  ),
                  const PopupMenuItem(
                    value: HistorySort.highestMax,
                    child: Text('Highest'),
                  ),
                  const PopupMenuItem(
                    value: HistorySort.recent,
                    child: Text('Latest reading'),
                  ),
                  PopupMenuItem(
                    value: HistorySort.sinceCookStart,
                    enabled: cookReference != null,
                    child: Text(
                      cookReference == null
                          ? 'Since cook start (no cook detected)'
                          : 'Since cook start',
                    ),
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
          if (controller.historySort == HistorySort.sinceCookStart) ...[
            const SizedBox(height: 6),
            Text(
              _cookSortDetail(activeCook, cookReference),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          const _SummaryHeader(),
          const SizedBox(height: 2),
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
      case HistorySort.probe:
        return 'Probe order';
      case HistorySort.hottest:
        return 'Hottest';
      case HistorySort.highestMax:
        return 'Highest';
      case HistorySort.recent:
        return 'Latest reading';
      case HistorySort.sinceCookStart:
        return 'Since cook start';
    }
  }

  String _cookSortDetail(CookSession? activeCook, CookSession? cookReference) {
    if (cookReference == null) {
      return 'No cook detected in this history.';
    }
    final elapsed = durationShort(fixtureNow.difference(cookReference.start));
    if (activeCook != null) {
      return 'Cook started $elapsed ago · in progress';
    }
    return 'Last cook started $elapsed ago';
  }

  Widget _pastCooksCard(BuildContext context) {
    final cooks = buildCookSessions();
    final scheme = Theme.of(context).colorScheme;
    final visible = cooks.take(3).toList();
    return SectionCard(
      key: const Key('history.cooks'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cooks',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Grouped automatically from your readings',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('history.cooks.open'),
                onPressed: () => _showCookSheet(context),
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final cook in visible)
            _CookTile(
              cook: cook,
              selected: _isCookSelected(cook),
              current: isCookInProgress(cook),
              onTap: () => _openPastCook(context, cook),
            ),
        ],
      ),
    );
  }

  bool _isCookSelected(CookSession cook) {
    final range = controller.historyCustomRange;
    if (range == null) return false;
    return range.start.difference(cook.start).inMinutes.abs() < 1 &&
        range.end.difference(cook.end).inMinutes.abs() < 1;
  }

  void _openPastCook(BuildContext context, CookSession cook) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PastCookScreen(controller: controller, cook: cook),
      ),
    );
  }

  void _showCookSheet(BuildContext context) {
    final cooks = buildCookSessions();
    final hostContext = context;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cooks',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cooks are grouped automatically from your readings. Choose one to open its history.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      for (final cook in cooks)
                        _CookTile(
                          cook: cook,
                          selected: _isCookSelected(cook),
                          current: isCookInProgress(cook),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _openPastCook(hostContext, cook);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickCustomRange(DateTimeRange initial) async {
    final picked = await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CustomRangeSheet(
        initialRange: initial,
        memoryRange: controller.entireHistoryRange,
        use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
      ),
    );
    if (picked == null) return;
    controller.setHistoryCustomRange(picked);
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
              text: 'Drag to pan. Pinch or scroll to zoom. Double-tap to fit the full range.',
            ),
            const _HelpRow(
              icon: Icons.local_fire_department_outlined,
              text: 'Use Cooks to jump to a recorded cook, or choose Custom range to set exact dates and times.',
            ),
            const _HelpRow(
              icon: Icons.linear_scale,
              text: 'A gap means no reading was recorded. The chart doesn’t connect across it.',
            ),
            const _HelpRow(
              icon: Icons.straighten,
              text: 'All probes share one scale. Choose one probe to see more detail.',
            ),
            const _HelpRow(
              icon: Icons.schedule,
              text: 'Times estimated means the Bridge’s clock wasn’t set when these readings were recorded, so the times are approximate.',
            ),
          ],
        ),
      ),
    );
  }
}

class PastCookScreen extends StatefulWidget {
  const PastCookScreen({
    super.key,
    required this.controller,
    required this.cook,
  });

  final PrototypeController controller;
  final CookSession cook;

  @override
  State<PastCookScreen> createState() => _PastCookScreenState();
}

class _PastCookScreenState extends State<PastCookScreen> {
  late final PrototypeController _history;

  @override
  void initState() {
    super.initState();
    final source = widget.controller;
    _history = PrototypeController()
      ..units = source.units
      ..historyRange = HistoryRange.custom
      ..historyCustomRange = DateTimeRange(
        start: widget.cook.start,
        end: widget.cook.end,
      )
      ..historyProbe = null
      ..historySort = source.historySort
      ..historyHasData = source.historyHasData
      ..historyOneProbe = source.historyOneProbe
      ..historyEstimated = source.historyEstimated
      ..historyMissingFromBridge = false;
  }

  @override
  void dispose() {
    _history.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: prototypeAppBar(context, widget.controller, 'Cook'),
      body: HistoryScreen(
        key: const Key('pastCook.history'),
        controller: _history,
        historical: true,
        showPastCooks: false,
        showFullscreenAction: false,
        gapOverride: widget.cook.hasGap,
      ),
    );
  }
}

class _FilterMenuButton<T> extends StatelessWidget {
  const _FilterMenuButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.items,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final List<PopupMenuEntry<T>> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => items,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: scheme.onSurfaceVariant),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 19,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomRangeSheet extends StatefulWidget {
  const _CustomRangeSheet({
    required this.initialRange,
    required this.memoryRange,
    required this.use24Hour,
  });

  final DateTimeRange initialRange;
  final DateTimeRange memoryRange;
  final bool use24Hour;

  @override
  State<_CustomRangeSheet> createState() => _CustomRangeSheetState();
}

class _CustomRangeSheetState extends State<_CustomRangeSheet> {
  late DateTime _start;
  late DateTime _end;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = widget.initialRange.start;
    _end = widget.initialRange.end;
  }

  bool get _valid => _end.isAfter(_start);

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(
        widget.memoryRange.start.year,
        widget.memoryRange.start.month,
        widget.memoryRange.start.day,
      ),
      lastDate: widget.memoryRange.end,
      helpText: start ? 'Start date' : 'End date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final next = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
      if (start) {
        _start = next;
      } else {
        _end = next;
      }
      _validate();
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: start ? 'Start time' : 'End time',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final next = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
      if (start) {
        _start = next;
      } else {
        _end = next;
      }
      _validate();
    });
  }

  void _validate() {
    if (_start.isBefore(widget.memoryRange.start) ||
        _end.isAfter(widget.memoryRange.end)) {
      _error = 'Choose a range within your saved history.';
    } else if (!_valid) {
      _error = 'End time must be after start time.';
    } else {
      _error = null;
    }
  }

  void _applyPreset(DateTimeRange range) {
    setState(() {
      _start = range.start;
      _end = range.end;
      _validate();
    });
  }

  void _apply() {
    _validate();
    if (_error != null) {
      setState(() {});
      return;
    }
    Navigator.of(context).pop(DateTimeRange(start: _start, end: _end));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final memory = widget.memoryRange;
    final today = DateTime(memory.end.year, memory.end.month, memory.end.day);
    final yesterdayStart = today.subtract(const Duration(days: 1));
    final yesterdayEnd = today.subtract(const Duration(minutes: 1));
    final presets = <(String, DateTimeRange)>[
      ('All saved history', memory),
      ('Today', DateTimeRange(start: today, end: memory.end)),
      ('Yesterday', DateTimeRange(start: yesterdayStart, end: yesterdayEnd)),
      (
        'Last 6 hours',
        DateTimeRange(
          start: memory.end.subtract(const Duration(hours: 6)),
          end: memory.end,
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Custom range', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Choose a start and end time. It starts with all the history saved on your phone.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${shortDateWithYear(_start)} · ${clockLabel(_start, use24Hour: widget.use24Hour)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${shortDateWithYear(_end)} · ${clockLabel(_end, use24Hour: widget.use24Hour)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _valid
                        ? '${durationLong(_end.difference(_start))} of history'
                        : 'End time must be after start time',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _valid ? scheme.onSurfaceVariant : scheme.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _RangeField(
              label: 'Start',
              value: _start,
              use24Hour: widget.use24Hour,
              onPickDate: () => _pickDate(start: true),
              onPickTime: () => _pickTime(start: true),
            ),
            const SizedBox(height: 8),
            _RangeField(
              label: 'End',
              value: _end,
              use24Hour: widget.use24Hour,
              onPickDate: () => _pickDate(start: false),
              onPickTime: () => _pickTime(start: false),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Quick picks',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in presets)
                  ActionChip(
                    label: Text(preset.$1),
                    onPressed: () => _applyPreset(preset.$2),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeField extends StatelessWidget {
  const _RangeField({
    required this.label,
    required this.value,
    required this.use24Hour,
    required this.onPickDate,
    required this.onPickTime,
  });

  final String label;
  final DateTime value;
  final bool use24Hour;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onPickDate,
            icon: const Icon(Icons.calendar_month_outlined, size: 17),
            label: Text(
              shortDateWithYear(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: onPickTime,
          child: Text(clockLabel(value, use24Hour: use24Hour)),
        ),
      ],
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    );
    return Row(
      children: [
        SizedBox(width: 64, child: Text('Probe', style: style)),
        Expanded(child: Text('Latest', style: style)),
        SizedBox(
          width: 54,
          child: Text('Min', style: style, textAlign: TextAlign.right),
        ),
        SizedBox(
          width: 54,
          child: Text('Max', style: style, textAlign: TextAlign.right),
        ),
        const SizedBox(width: 20),
      ],
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
    final hasData = stat.last != null;
    return Semantics(
      button: true,
      selected: selected,
      label: hasData
          ? 'Probe ${stat.probe}, latest ${controller.tempFor(stat.last)}, lowest ${controller.tempFor(stat.min)}, highest ${controller.tempFor(stat.max)}'
          : 'Probe ${stat.probe}, no data in this range',
      child: InkWell(
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
              SizedBox(
                width: 64,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: hasData ? color : color.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'P${stat.probe}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: hasData
                    ? Text(
                        '${controller.valueFor(stat.last)}°',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      )
                    : Text(
                        'No data',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  hasData ? '${controller.valueFor(stat.min)}°' : '—',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  hasData ? '${controller.valueFor(stat.max)}°' : '—',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 20,
                child: Icon(
                  selected ? Icons.check : Icons.chevron_right,
                  size: 16,
                  color: selected ? color : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CookTile extends StatelessWidget {
  const _CookTile({
    required this.cook,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  final CookSession cook;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 2),
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.18)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _monthLabel(cook.start.month),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            Text(
              '${cook.start.day}',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
            ),
          ],
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              dayLabel(cook.start),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (current) ...[
            const SizedBox(width: 8),
            Pill(label: 'In progress', color: StatusColors.live(context)),
          ],
        ],
      ),
      subtitle: Text(
        '${timeRangeLabel(cook.start, cook.end, use24Hour: use24Hour)}\n'
        '${durationShort(cook.duration)} · ${cook.probes} probes'
        '${cook.hasGap ? ' · missing readings' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
      ),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.chevron_right,
        size: 20,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }

  String _monthLabel(int month) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return months[month - 1];
  }
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
