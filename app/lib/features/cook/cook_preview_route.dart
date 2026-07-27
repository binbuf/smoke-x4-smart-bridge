/// A22.4 — the live premium Cook view, as a self-contained route.
///
/// This is the M8 UI wired to the real bridge for end-to-end testing before the
/// full shell (W5/W6) replaces the router. It boots its own connection race and
/// [BridgeSession] — the same pattern `DashboardRoute` uses — streams the live
/// [DashboardSnapshot], and renders it through [CookView] and the proven
/// [CookChart]. The new design theme is applied **locally** so the rest of the
/// app (and its golden tests) are untouched.
///
/// Instrument mode shows every probe live with no cook started (the owner's
/// requirement). "Set up a cook" opens the preset sheet and switches to guided
/// mode — big pit and food gauges that fill toward their targets.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_env.dart';
import '../../app/bridge_session.dart';
import '../../app/connection.dart';
import '../../data/transport/bridge_transport.dart';
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';
import '../chart/chart_viewport.dart';
import '../chart/cook_chart.dart';
import '../dashboard/dashboard_snapshot.dart';
import 'cook_setup_sheet.dart';
import 'cook_view.dart';

class CookPreviewRoute extends StatefulWidget {
  const CookPreviewRoute({super.key});

  @override
  State<CookPreviewRoute> createState() => _CookPreviewRouteState();
}

class _CookPreviewRouteState extends State<CookPreviewRoute> {
  AppConnection? _connection;
  BridgeSession? _session;
  LaunchState _launch = const LaunchConnecting();
  DashboardSnapshot? _snapshot;
  ChartViewport? _viewport;
  CookPlan? _plan;
  StreamSubscription<DashboardSnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final env = AppEnv.instance;
    if (env == null) {
      return;
    }
    final connection = env.newConnection();
    _connection = connection;
    final state = await connection.start();
    if (!mounted) {
      return;
    }
    setState(() => _launch = state);
    if (state is! LaunchConnected) {
      return;
    }
    final session = BridgeSession(
      db: env.db,
      transport: state.transport,
      link: state.link,
      address: state.address,
    );
    _session = session;
    _sub = session.snapshots.listen((s) {
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = s;
        _viewport = _viewport == null
            ? ChartViewport.forSession(
                fromT: s.samples.isEmpty ? 0 : s.samples.first.t,
                toT: s.samples.isEmpty ? 60 : s.samples.last.t,
              )
            : _viewport!.extendTo(s.samples.isEmpty ? 60 : s.samples.last.t);
      });
    });
    await session.start();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_session?.dispose());
    unawaited(_connection?.dispose());
    super.dispose();
  }

  /// Freshness from the live packet age (13 §13.6.1), so a stale reading is
  /// visibly stale rather than a frozen number under a green chip.
  ProbeFreshness _freshness(DashboardSnapshot s) {
    if (s.baseLost) {
      return ProbeFreshness.frozen;
    }
    final age = s.lastPacketSAgo;
    if (age == null) {
      return s.anyAttached ? ProbeFreshness.live : ProbeFreshness.unknown;
    }
    if (age <= 45) return ProbeFreshness.live;
    if (age <= 90) return ProbeFreshness.aging;
    if (age <= 600) return ProbeFreshness.stale;
    return ProbeFreshness.frozen;
  }

  Future<void> _setupCook() async {
    final plan = await showCookSetupSheet(context);
    if (plan != null && mounted) {
      setState(() => _plan = plan);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SmokeTheme.dark,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Cook'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            ),
          ),
          body: SafeArea(child: _body(context)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return switch (_launch) {
        LaunchOffline() => const EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Can’t reach your bridge',
          message:
              'Saved cooks are still here. The app reconnects on its own when '
              'the bridge is back.',
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }

    final probeConfig = [
      for (final p in snapshot.probes)
        Probe(n: p.probe, name: p.name, role: p.role, targetF10: p.targetF10),
    ];
    final model = buildChartSeries(
      snapshot.samples,
      fromT: _viewport?.minX ?? 0,
      toT: _viewport?.maxX ?? 60,
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: CookView(
            snapshot: snapshot,
            plan: _plan,
            freshness: _freshness(snapshot),
            paired: snapshot.paired,
            onSetupCook: _setupCook,
            onStop: _plan == null ? null : () => setState(() => _plan = null),
            // The highest unacked alarm rides CookView's AlarmBar off
            // snapshot.alarms; silencing it acks the exact id on the device.
            onAck: (alarm) => unawaited(
              _session?.control(ControlCommand.ackAlarm(alarmId: alarm.id)) ??
                  Future<void>.value(),
            ),
          ),
        ),
        if (snapshot.samples.isNotEmpty && _viewport != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SmokeTokens.s4,
                0,
                SmokeTokens.s4,
                SmokeTokens.s4,
              ),
              child: SmokeCard(
                child: SizedBox(
                  height: 240,
                  child: CookChart(
                    model: model,
                    viewport: _viewport!,
                    probes: probeConfig,
                    marks: snapshot.marks,
                    startedUnixMs: snapshot.startedUnixMs,
                    onViewport: (v) => setState(() => _viewport = v),
                    fullHistory: snapshot.fullHistory,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
