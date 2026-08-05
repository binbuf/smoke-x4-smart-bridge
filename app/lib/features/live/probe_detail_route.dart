/// `/live/probe/:jack` — per-probe detail (newapp §C.2).
///
/// **The chevron used to go nowhere.** `ProbeStripRow` drew one unconditionally
/// and `onProbeTap` was never passed, so every probe row on the reader looked
/// tappable, rippled when tapped, and did nothing — which is worse than a row
/// that does not look tappable at all. This is where it goes.
///
/// It answers one question: *"what is this one probe doing over time, and what
/// should it alarm on?"* — the big current reading and its trend, the chart with
/// its window chips and crosshair, this probe's role and target, and its alarm
/// rules with inline edit.
///
/// **§C.2's open question, settled: the chart affordances converge.** Window
/// chips, the "Now" pill and the crosshair existed only in History; the live
/// chart had gestures and no controls. Two different chart experiences for the
/// same data is a seam a user feels and cannot name. This screen uses the same
/// [CookChart] + [ChartControls] pair History does, over the live samples.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';
import '../chart/chart_viewport.dart';
import '../chart/cook_chart.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../shell/shell_scope.dart';

class ProbeDetailRoute extends StatefulWidget {
  const ProbeDetailRoute({required this.jack, super.key});

  final int jack;

  @override
  State<ProbeDetailRoute> createState() => _ProbeDetailRouteState();
}

class _ProbeDetailRouteState extends State<ProbeDetailRoute> {
  ChartViewport? _viewport;
  int? _crosshairT;

  @override
  Widget build(BuildContext context) {
    final session = ShellScope.maybeOf(context);
    final snapshot = session?.snapshot;
    final t = context.tokens;
    final probe = snapshot?.probes
        .where((p) => p.probe == widget.jack)
        .firstOrNull;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: Text(probe?.name ?? 'Probe ${widget.jack}')),
      body: SafeArea(
        child: snapshot == null || probe == null
            ? const EmptyState(
                icon: Icons.sensors_off_rounded,
                title: 'No live readings',
                message:
                    'Open this from the live screen once the bridge is '
                    'connected.',
              )
            : _body(context, session!, snapshot, probe),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    dynamic session,
    DashboardSnapshot snapshot,
    ProbeView probe,
  ) {
    final t = context.tokens;
    final celsius = session.celsius as bool;
    final freshness = session.freshness as ProbeFreshness;
    final plan = session.plan as CookPlan?;
    final planProbe = plan?.probes
        .where((p) => p.jack == widget.jack)
        .firstOrNull;

    _viewport ??= ChartViewport.forSession(
      fromT: snapshot.samples.isEmpty ? 0 : snapshot.samples.first.t,
      toT: snapshot.samples.isEmpty ? 60 : snapshot.samples.last.t,
      window: ChartWindow.all,
    );
    final viewport = _viewport!;
    // One model, shared by the chart and the crosshair readout, so the two can
    // never disagree about what is under the finger.
    final model = buildChartSeries(
      snapshot.samples,
      fromT: viewport.minX,
      toT: viewport.maxX,
      probes: [widget.jack],
    );

    return ListView(
      key: const Key('probe-detail'),
      padding: const EdgeInsets.all(SmokeTokens.s4),
      children: [
        // The hero number, under the same freshness rule as the reader: a
        // stale reading is veiled and its derived values are REMOVED, not
        // greyed, wherever it appears.
        StaleVeil(
          ageLabel: freshness.showsDerived
              ? ''
              : 'Last reading '
                    '${formatElapsed(snapshot.lastPacketSAgo ?? 0)} ago',
          frozen: freshness == ProbeFreshness.frozen,
          child: SmokeCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(bottom: 14, right: 10),
                  decoration: BoxDecoration(
                    color: ProbePalette.hue(widget.jack),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    formatTemp(probe.tempF10, celsius: celsius),
                    style: SmokeType.bigTemp.copyWith(color: t.textHi),
                  ),
                ),
                if (probe.rateFPerHr != null && freshness.showsDerived)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      formatRate(probe.rateFPerHr),
                      style: SmokeType.bodySm.copyWith(color: t.textBody),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: SmokeTokens.s3),

        // §C.2 — the converged chart: the live series with History's controls.
        SmokeCard(
          child: Column(
            children: [
              ChartControls(
                viewport: viewport,
                onViewport: (v) => setState(() => _viewport = v),
              ),
              const SizedBox(height: SmokeTokens.s2),
              SizedBox(
                height: 240,
                child: CookChart(
                  model: model,
                  viewport: viewport,
                  probes: [
                    Probe(
                      n: widget.jack,
                      name: probe.name,
                      role: probe.role,
                      targetF10: probe.targetF10,
                    ),
                  ],
                  marks: snapshot.marks,
                  startedUnixMs: snapshot.startedUnixMs,
                  celsius: celsius,
                  onViewport: (v) => setState(() => _viewport = v),
                  onCrosshair: (v) => setState(() => _crosshairT = v),
                  fullHistory: snapshot.fullHistory,
                ),
              ),
              if (_crosshairT != null)
                CrosshairReadout(
                  readings: crosshairAt(model, _crosshairT!),
                  atT: _crosshairT!,
                  startedUnixMs: snapshot.startedUnixMs,
                  probes: [
                    Probe(n: widget.jack, name: probe.name, role: probe.role),
                  ],
                  celsius: celsius,
                ),
            ],
          ),
        ),
        const SizedBox(height: SmokeTokens.s3),

        // What this probe is for, and what it will alarm on.
        SmokeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'THIS PROBE',
                style: SmokeType.label.copyWith(color: t.textMuted),
              ),
              const SizedBox(height: SmokeTokens.s2),
              _row(t, 'Role', _roleLabel(probe.role)),
              _row(
                t,
                'Target',
                probe.targetF10 == null
                    // Absent ≠ zero, all the way to the pixels.
                    ? 'Not set'
                    : formatSetpoint(probe.targetF10, celsius: celsius),
              ),
              if (planProbe?.pullF10 != null)
                _row(
                  t,
                  'Pull at',
                  formatSetpoint(planProbe!.pullF10, celsius: celsius),
                ),
              if (probe.eta != null && freshness.showsDerived)
                _row(t, 'Estimate', formatEta(probe.eta)),
              if (probe.stalled && freshness.showsDerived)
                _row(t, 'Stall', 'In a stall — the estimate is paused'),
            ],
          ),
        ),
        const SizedBox(height: SmokeTokens.s3),

        // The rules live in one editor, and this is a link to that probe's
        // section rather than a second, divergent editing surface.
        SmokeCard(
          key: const Key('probe-detail-alarms'),
          onTap: () => context.push(AppRoutes.deviceAlarms),
          child: Row(
            children: [
              Icon(Icons.notifications_outlined, color: t.textBody),
              const SizedBox(width: SmokeTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alarm rules',
                      style: SmokeType.title.copyWith(color: t.textHi),
                    ),
                    Text(
                      'What this probe should wake you for.',
                      style: SmokeType.bodySm.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.chromeDim),
            ],
          ),
        ),
      ],
    );
  }

  String _roleLabel(ProbeRole r) => switch (r) {
    ProbeRole.pit => 'Pit',
    ProbeRole.food => 'Food',
    ProbeRole.ambient => 'Ambient',
    ProbeRole.unused => 'Not used',
  };

  Widget _row(SmokeTokens t, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
        ),
        Text(value, style: SmokeType.body.copyWith(color: t.textHi)),
      ],
    ),
  );
}
