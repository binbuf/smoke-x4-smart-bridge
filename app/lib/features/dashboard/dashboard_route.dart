/// The composition root for the dashboard: the one place the real
/// database, the real connection race and the real transport are wired
/// to A9's projection.
///
/// Everything it assembles is tested against fakes elsewhere — this file
/// holds only the wiring, which is why it is a widget and not a library
/// (the same shape `onboarding_route.dart` took in M3).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_env.dart';
import '../../app/bridge_session.dart';
import '../../app/connection.dart';
import '../../app/router.dart';
import '../../data/transport/bridge_transport.dart';
import '../chart/chart_viewport.dart';
import '../sessions/export.dart';
import 'dashboard_screen.dart';
import 'dashboard_snapshot.dart';

class DashboardRoute extends StatefulWidget {
  const DashboardRoute({super.key});

  @override
  State<DashboardRoute> createState() => _DashboardRouteState();
}

class _DashboardRouteState extends State<DashboardRoute> {
  AppConnection? _connection;
  BridgeSession? _session;
  LaunchState _launch = const LaunchConnecting();
  DashboardSnapshot? _snapshot;
  ChartViewport? _viewport;
  int? _crosshairT;
  StreamSubscription<DashboardSnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final env = AppEnv.instance;
    if (env == null) {
      return; // not bootstrapped (a widget test mounting the router bare)
    }
    final connection = env.newConnection();
    _connection = connection;
    final state = await connection.start();
    if (!mounted) {
      return;
    }
    setState(() => _launch = state);
    if (state is LaunchNeedsOnboarding) {
      context.go(AppRoutes.onboarding);
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smoke Bridge'),
        actions: [
          IconButton(
            key: const Key('nav-sessions'),
            icon: const Icon(Icons.history),
            onPressed: () => context.go(AppRoutes.sessions),
          ),
          IconButton(
            key: const Key('nav-settings'),
            icon: const Icon(Icons.settings),
            onPressed: () => context.go(AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (_launch) {
          LaunchNeedsOnboarding() => const SizedBox.shrink(),
          LaunchConnecting() => const Center(
            key: Key('dashboard-connecting'),
            child: CircularProgressIndicator(),
          ),
          LaunchOffline() when snapshot == null => const _OfflineEmpty(),
          _ when snapshot == null => const Center(
            key: Key('dashboard-loading'),
            child: CircularProgressIndicator(),
          ),
          _ => DashboardView(
            snapshot: snapshot,
            viewport: _viewport ?? ChartViewport.forSession(fromT: 0, toT: 60),
            onViewport: (v) => setState(() => _viewport = v),
            crosshairT: _crosshairT,
            onCrosshair: (t) => setState(() => _crosshairT = t),
            onControl: _session == null ? null : _control,
            onExport: _export,
            controlsEnabled: _session != null,
            controlsDisabledReason: _session == null
                ? 'Not connected to the bridge.'
                : '',
          ),
        },
      ),
    );
  }

  Future<void> _control(ControlCommand cmd) async {
    final s = _session;
    if (s == null) {
      return;
    }
    await s.control(cmd);
  }

  Future<void> _export() async {
    final env = AppEnv.instance;
    final session = _session;
    final repo = session?.sessions;
    final id = _snapshot?.sessionId;
    if (env == null || repo == null || id == null) {
      return;
    }
    final all = await repo.sessions();
    final cook = all.where((s) => s.id == id).firstOrNull;
    if (cook == null) {
      return;
    }
    final where = await exportSessionCsv(
      session: cook,
      samples: await repo.samples(id),
      sink: env.exportSink,
    );
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Exported $where')));
    }
  }
}

class _OfflineEmpty extends StatelessWidget {
  const _OfflineEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('dashboard-offline-empty'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('Cannot reach the bridge', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Saved cooks are still here. The app will reconnect on its '
              'own when the bridge is back.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('dashboard-offline-sessions'),
              onPressed: () => context.go(AppRoutes.sessions),
              child: const Text('Open saved cooks'),
            ),
          ],
        ),
      ),
    );
  }
}
