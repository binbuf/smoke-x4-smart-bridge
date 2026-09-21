/// N7 — the Graph destination.
///
/// Range chips, the zoom/pan bar, the multi-series [CookChart], the tap-to-
/// isolate legend, the window statistics table and the actions. It owns no
/// business state: the view window lives in [graphViewProvider] (shared with
/// the fullscreen host) and the data comes from [graphModelProvider].
///
/// Invariants encoded here:
/// * **I3** — a detached probe has no series and no stats row; its legend entry
///   is absent rather than a zero.
/// * **I4** — the legend's current value still reads the live snapshot, so a
///   frozen probe shows its last reading but the derived stats come from the
///   window samples.
/// * **I14** — no ember primary action on this surface.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';
import '../shell/app_bar.dart';
import '../shell/phone_frame.dart';
import '../shell/shell.dart';
import '../shell/shell_screen.dart';
import 'cook_chart.dart';
import 'graph_format.dart';
import 'graph_model.dart';

class GraphPage extends ConsumerWidget {
  const GraphPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(snapshotProvider).value;
    final model = ref.watch(graphModelProvider);
    if (snapshot == null) {
      return const LoadingState(
        title: 'Reading the bridge',
        copy: 'Waiting for the first snapshot.',
        actionLabel: 'Retry',
        onAction: _noop,
      );
    }
    if (model == null || model.attachedJacks.isEmpty) {
      return ShellScrollHost(
        resetToken: ShellScreen.graph,
        child: EmptyState(
          key: const ValueKey<String>('graph-empty'),
          title: 'No probes attached',
          copy:
              'Plug a probe into the Smoke X4 and its line will appear here '
              'with targets, marks and window statistics.',
          actionLabel: 'View temps',
          onAction: () =>
              ShellScope.maybeOf(context)?.openScreen(ShellScreen.temps),
        ),
      );
    }
    return _GraphBody(model: model);
  }
}

void _noop() {}

class _GraphBody extends ConsumerWidget {
  const _GraphBody({required this.model});

  final GraphModel model;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final scope = ShellScope.maybeOf(context);
    final view = ref.watch(graphViewProvider);
    final notifier = ref.read(graphViewProvider.notifier);

    final isolatedLabel = _labelForJack(model.meta, view.isolatedJack);

    return ShellScrollHost(
      resetToken: ShellScreen.graph,
      child: Column(
        key: const ValueKey<String>('graph-page'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilterChips<GraphRange>(
                  key: const ValueKey<String>('graph-range'),
                  options: <SmokeSegment<GraphRange>>[
                    for (final range in GraphRange.values)
                      SmokeSegment<GraphRange>(
                        value: range,
                        label: range.label,
                      ),
                  ],
                  value: view.range,
                  onChanged: notifier.setRange,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ShellIconButton(
                    key: const ValueKey<String>('graph-zoom-out'),
                    glyph: SmokeGlyph.zoomOut,
                    label: 'Zoom out',
                    onTap: () => notifier.zoomBy(1 / 1.5),
                  ),
                  ShellIconButton(
                    key: const ValueKey<String>('graph-zoom-in'),
                    glyph: SmokeGlyph.zoomIn,
                    label: 'Zoom in',
                    onTap: () => notifier.zoomBy(1.5),
                  ),
                  ShellIconButton(
                    key: const ValueKey<String>('graph-fullscreen'),
                    glyph: SmokeGlyph.expand,
                    label: 'Fullscreen',
                    onTap: () => scope?.toggleFullGraph(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SmokeCard(
            padding: const EdgeInsets.fromLTRB(12, 14, 10, 8),
            child: SizedBox(
              height: 220,
              child: CookChart(
                key: const ValueKey<String>('graph-chart'),
                model: model.series,
                domain: model.domain,
                unit: model.unit,
                series: model.meta,
                targets: model.targets,
                band: model.band,
                marks: model.marks,
                isolatedJack: view.isolatedJack,
                onZoomFactor: notifier.zoomBy,
                onPanMinutes: notifier.panBy,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SeriesLegend(
            key: const ValueKey<String>('graph-legend'),
            entries: <SeriesLegendEntry>[
              for (final meta in model.meta)
                SeriesLegendEntry(
                  label: meta.label,
                  color: tokens.series(meta.jack.n),
                  value: legendValue(model.probeFor(meta.jack), model.unit),
                  dash: seriesDash(meta.jack),
                ),
            ],
            isolated: isolatedLabel,
            onIsolate: (label) => notifier.isolate(
              label == null ? null : _jackForLabel(model.meta, label),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  graphZoomHint(view),
                  key: const ValueKey<String>('graph-zoom-hint'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 11,
                    color: tokens.textMuted,
                  ),
                ),
              ),
              if (view.canReset)
                TextButton(
                  key: const ValueKey<String>('graph-reset'),
                  onPressed: notifier.reset,
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.textHi,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Reset view',
                    style: SmokeText.label.copyWith(color: tokens.textHi),
                  ),
                ),
            ],
          ),
          const SectionLabel(label: 'Window statistics'),
          SmokeCard(
            key: const ValueKey<String>('graph-stats'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < model.stats.length; i++)
                  _StatRow(
                    stat: model.stats[i],
                    name: _nameForJack(model, model.stats[i].jack),
                    unit: model.unit,
                    last: i == model.stats.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('graph-add-mark'),
                  label: 'Add mark',
                  icon: SmokeGlyph.bookmark,
                  onPressed: () => scope?.openOverlay(DevOverlay.mark),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('graph-share'),
                  label: 'Share',
                  icon: SmokeGlyph.share,
                  variant: SmokeButtonVariant.ghost,
                  onPressed: () =>
                      scope?.showToast('Opening share sheet — graph'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _nameForJack(GraphModel model, ProbeJack jack) {
    for (final meta in model.meta) {
      if (meta.jack == jack) {
        return meta.label;
      }
    }
    return 'Probe ${jack.n}';
  }
}

/// One probe's High/Avg/Low row.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.stat,
    required this.name,
    required this.unit,
    required this.last,
  });

  final GraphStat stat;
  final String name;
  final TempUnit unit;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Container(
      key: ValueKey<String>('graph-stat-${stat.jack.n}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: tokens.hairline)),
      ),
      child: Row(
        children: <Widget>[
          JackBadge(jack: stat.jack.n),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SmokeText.bodyStrong.copyWith(
                fontSize: 12.5,
                color: tokens.textHi,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _StatCell(label: 'High', value: _fmt(stat.highF10)),
          const SizedBox(width: 10),
          _StatCell(label: 'Avg', value: _fmt(stat.avgF10)),
          const SizedBox(width: 10),
          _StatCell(label: 'Low', value: _fmt(stat.lowF10)),
        ],
      ),
    );
  }

  String _fmt(int? f10) =>
      f10 == null ? '—' : '${fmtTemp0(f10, unit)}${unit.suffix}';
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return SizedBox(
      width: 52,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: SmokeText.labelSm.copyWith(
              fontSize: 9,
              letterSpacing: 0.4,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SmokeText.monoSmall.copyWith(
              fontSize: 11,
              color: tokens.textHi,
            ),
          ),
        ],
      ),
    );
  }
}

String? _labelForJack(List<GraphSeriesMeta> meta, int? jack) {
  if (jack == null) {
    return null;
  }
  for (final entry in meta) {
    if (entry.jack.n == jack) {
      return entry.label;
    }
  }
  return null;
}

int? _jackForLabel(List<GraphSeriesMeta> meta, String label) {
  for (final entry in meta) {
    if (entry.label == label) {
      return entry.jack.n;
    }
  }
  return null;
}
