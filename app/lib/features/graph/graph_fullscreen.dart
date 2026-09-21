/// N7.11 — the fullscreen graph body.
///
/// Mounted by the shell's [ShellFullscreenGraphHost] above the overlay stack.
/// It reads the same [graphViewProvider] and [graphModelProvider] as the inline
/// destination, so the fullscreen chart is the inline chart for the same window
/// (the exit gate), plus the pan back/forward, zoom and reset controls the
/// prototype's `renderFullGraph` puts in its header.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/design.dart';
import '../shell/app_bar.dart';
import 'cook_chart.dart';
import 'graph_format.dart';
import 'graph_model.dart';

class GraphFullscreenBody extends ConsumerWidget {
  const GraphFullscreenBody({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final model = ref.watch(graphModelProvider);
    final view = ref.watch(graphViewProvider);
    final notifier = ref.read(graphViewProvider.notifier);

    if (model == null) {
      return Center(
        child: Text(
          'Waiting for the first snapshot.',
          style: SmokeText.body.copyWith(color: tokens.textBody),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Graph',
                    key: const ValueKey<String>('shell-graph-title'),
                    style: SmokeText.title.copyWith(color: tokens.textHi),
                  ),
                  Text(
                    view.zoom > 1
                        ? '${view.zoom.toStringAsFixed(1)}×'
                        : 'full range',
                    key: const ValueKey<String>('graph-fullscreen-zoom'),
                    style: SmokeText.sub.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ShellIconButton(
                  key: const ValueKey<String>('graph-pan-back'),
                  glyph: SmokeGlyph.arrowLeft,
                  label: 'Pan back',
                  onTap: () => notifier.panBy(model.domain.span * 0.4),
                ),
                ShellIconButton(
                  key: const ValueKey<String>('graph-fullscreen-zoom-out'),
                  glyph: SmokeGlyph.zoomOut,
                  label: 'Zoom out',
                  onTap: () => notifier.zoomBy(1 / 1.5),
                ),
                ShellIconButton(
                  key: const ValueKey<String>('graph-fullscreen-zoom-in'),
                  glyph: SmokeGlyph.zoomIn,
                  label: 'Zoom in',
                  onTap: () => notifier.zoomBy(1.5),
                ),
                ShellIconButton(
                  key: const ValueKey<String>('graph-pan-fwd'),
                  glyph: SmokeGlyph.arrowRight,
                  label: 'Pan forward',
                  onTap: () => notifier.panBy(-model.domain.span * 0.4),
                ),
                ShellIconButton(
                  key: const ValueKey<String>('graph-fullscreen-reset'),
                  glyph: SmokeGlyph.refresh,
                  label: 'Reset',
                  onTap: notifier.reset,
                ),
                ShellIconButton(
                  key: const ValueKey<String>('shell-graph-exit'),
                  glyph: SmokeGlyph.compress,
                  label: 'Exit fullscreen',
                  onTap: onDismiss,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: CookChart(
            key: const ValueKey<String>('graph-fullscreen-chart'),
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
        const SizedBox(height: 12),
        SeriesLegend(
          key: const ValueKey<String>('graph-fullscreen-legend'),
          entries: <SeriesLegendEntry>[
            for (final meta in model.meta)
              SeriesLegendEntry(
                label: meta.label,
                color: tokens.series(meta.jack.n),
                value: legendValue(model.probeFor(meta.jack), model.unit),
                dash: seriesDash(meta.jack),
              ),
          ],
          isolated: _labelForJack(model.meta, view.isolatedJack),
          onIsolate: (label) => notifier.isolate(
            label == null ? null : _jackForLabel(model.meta, label),
          ),
        ),
      ],
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
