/// A9.6 — the dashboard screen (design 08 §8.6).
///
/// Header · tiles · chart · controls, laid out with §8.6's emphasis: the
/// pit and the primary food probe get the space, secondary probes collapse
/// to compact tiles. It must survive a 320 dp phone in portrait and a text
/// scale of 1.3 without overflowing, because that is the phone somebody
/// will actually be holding in the dark.
///
/// [DashboardView] is a pure projection of a [DashboardSnapshot] and takes
/// callbacks — no providers, no transports, no futures. That is what lets
/// A15 pin it at seven data shapes without standing up a connection.
library;

import 'package:flutter/material.dart';

import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../chart/chart_viewport.dart';
import '../chart/cook_chart.dart';
import '../../data/transport/bridge_transport.dart';
import 'dashboard_snapshot.dart';
import 'header_strip.dart';
import 'probe_tile.dart';
import 'session_controls.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({
    required this.snapshot,
    required this.viewport,
    required this.onViewport,
    this.onControl,
    this.onExport,
    this.onCrosshair,
    this.crosshairT,
    this.celsius = false,
    this.controlsEnabled = true,
    this.controlsDisabledReason = '',
    super.key,
  });

  final DashboardSnapshot snapshot;
  final ChartViewport viewport;
  final ValueChanged<ChartViewport> onViewport;
  final Future<void> Function(ControlCommand)? onControl;
  final VoidCallback? onExport;
  final ValueChanged<int?>? onCrosshair;
  final int? crosshairT;
  final bool celsius;
  final bool controlsEnabled;
  final String controlsDisabledReason;

  @override
  Widget build(BuildContext context) {
    final probeConfig = [
      for (final p in snapshot.probes)
        Probe(n: p.probe, name: p.name, role: p.role, targetF10: p.targetF10),
    ];
    final model = buildChartSeries(
      snapshot.samples,
      fromT: viewport.minX,
      toT: viewport.maxX,
    );

    return ListView(
      key: const Key('dashboard-view'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        DashboardHeader(snapshot: snapshot),
        const SizedBox(height: 12),
        if (!snapshot.anyAttached)
          const _NoProbes()
        else ...[
          if (snapshot.headlinePit != null)
            HeadlineProbeTile(view: snapshot.headlinePit!, celsius: celsius),
          if (snapshot.headlinePit != null && snapshot.headlineFood != null)
            const SizedBox(height: 10),
          if (snapshot.headlineFood != null)
            HeadlineProbeTile(view: snapshot.headlineFood!, celsius: celsius),
          if (snapshot.secondary.isNotEmpty) ...[
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, c) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in snapshot.secondary)
                    SizedBox(
                      width: c.maxWidth < 360
                          ? c.maxWidth
                          : (c.maxWidth - 10) / 2,
                      child: CompactProbeTile(view: p, celsius: celsius),
                    ),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 16),
        ChartControls(viewport: viewport, onViewport: onViewport),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: CookChart(
            model: model,
            viewport: viewport,
            probes: probeConfig,
            marks: snapshot.marks,
            startedUnixMs: snapshot.startedUnixMs,
            crosshairT: crosshairT,
            onCrosshair: onCrosshair,
            onViewport: onViewport,
            fullHistory: snapshot.fullHistory,
          ),
        ),
        if (crosshairT != null) ...[
          const SizedBox(height: 8),
          CrosshairReadout(
            readings: crosshairAt(model, crosshairT!),
            atT: crosshairT!,
            startedUnixMs: snapshot.startedUnixMs,
            probes: probeConfig,
          ),
        ],
        const SizedBox(height: 16),
        SessionControls(
          snapshot: snapshot,
          onControl: onControl ?? (_) async {},
          onExport: onExport,
          enabled: controlsEnabled && onControl != null,
          disabledReason: controlsDisabledReason,
        ),
      ],
    );
  }
}

/// Not an error state: an unpaired bridge, or four empty jacks, is a
/// perfectly normal thing for this screen to be looking at.
class _NoProbes extends StatelessWidget {
  const _NoProbes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('dashboard-no-probes'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.sensors,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('No probes plugged in', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Plug a probe into the base station and it will appear here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
