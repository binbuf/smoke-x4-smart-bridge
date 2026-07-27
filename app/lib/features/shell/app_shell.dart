/// A24.1 — the app shell: four tabs over one live session (design 13 §13.3).
///
/// This makes the new UI the primary app. `/` renders [AppShell]; the shell
/// boots the connection race **once** (via [ShellSession]) and hands the one
/// [DashboardSnapshot] to whichever tab is showing. Tab state survives switching
/// because the bodies live in an [IndexedStack] — all four stay mounted, so
/// History keeps its scroll position and the Cook chart keeps its viewport when
/// you flick to Bridge and back (§13.3.3).
///
/// **Chrome (§13.5.7).** A [SystemStatusBar] (transport + freshness) and a shared
/// [AlarmBar] (the highest unacked alarm, acked through the one session) ride
/// above every tab — *except Cook*, which carries its own equivalent chrome
/// inside [CookView] and would otherwise double it (two alarm bars, two haptic
/// buzzes). So on the Cook tab the shell chrome yields to CookView's; on the
/// other three the shell owns it. Every tab therefore shows a transport
/// indicator and an alarm strip, with exactly one of each. (A one-line
/// `showChrome` flag on CookView would let the shell own chrome uniformly; that
/// widget is another agent's file, so this is the honest seam for now.)
///
/// **Cook body.** Promotes `cook_preview_route.dart`'s body — the snapshot, a
/// local [CookPlan] opened through `showCookSetupSheet`, the shared freshness,
/// `onAck`/`onSetupCook`/`onStop`, and the [CookChart] below. The chart is kept
/// bounded (an [Expanded] `CookView` with the chart pinned under it) rather than
/// nested in a sliver, because `CookView` is itself a `ListView` and cannot take
/// the unbounded height a `SliverToBoxAdapter` would hand it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/connection.dart';
import '../../app/router.dart';
import '../../design/design.dart';
import '../../domain/analysis/analysis.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';
import '../chart/chart_viewport.dart';
import '../chart/cook_chart.dart';
import '../cook/cook_setup_sheet.dart';
import '../cook/cook_view.dart';
import '../bridge/bridge_tab.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../sessions/sessions_route.dart';
// AlarmsTab is still the branded placeholder (its real three-tier build is
// pending); BridgeTab is the real device screen (A24.3).
import 'connection_sheet.dart';
import 'placeholder_tabs.dart' show AlarmsTab;
import 'refresh_banner.dart';
import 'shell_session.dart';
import 'system_status_bar.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.session, this.initialIndex = 0});

  /// Injected by tests with a seeded [ShellSession]. Null in production, where
  /// the shell builds and owns one from the ambient `AppEnv`.
  final ShellSession? session;
  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final ShellSession _session;

  /// Dispose the session only if we created it — a test that injected one owns
  /// its lifetime.
  late final bool _ownsSession;

  late int _index;

  /// Cook-tab UI state, local to the shell (§13.3.1): null → instrument mode.
  CookPlan? _plan;
  ChartViewport? _viewport;

  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _session = widget.session ?? ShellSession();
    _ownsSession = widget.session == null;
    _viewport = _viewportFor(_session.snapshot);
    _session.addListener(_onSession);
    if (_ownsSession) {
      unawaited(_session.start());
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    if (_ownsSession) {
      _session.dispose();
    }
    super.dispose();
  }

  void _onSession() {
    if (!mounted) {
      return;
    }
    // A9.5/§13.3.2: a phone that has never met a bridge goes to guided setup.
    if (_session.launch is LaunchNeedsOnboarding && !_redirected) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go(AppRoutes.setup);
        }
      });
      return;
    }
    setState(() => _viewport = _viewportFor(_session.snapshot, _viewport));
  }

  /// Initialise, then keep extending, the chart viewport as samples arrive —
  /// the same rule `cook_preview_route.dart:85` used.
  ChartViewport? _viewportFor(DashboardSnapshot? s, [ChartViewport? current]) {
    if (s == null) {
      return current;
    }
    final toT = s.samples.isEmpty ? 60 : s.samples.last.t;
    if (current == null) {
      return ChartViewport.forSession(
        fromT: s.samples.isEmpty ? 0 : s.samples.first.t,
        toT: toT,
      );
    }
    return current.extendTo(toT);
  }

  /// The single loudest alarm still ringing — highest severity, device-scope
  /// (`probe == 0`) included. Mirrors `cook_view.dart:84`.
  Alarm? _topAlarm(DashboardSnapshot s) {
    Alarm? best;
    for (final a in s.alarms) {
      if (a.acked) {
        continue;
      }
      if (best == null || a.severity.index > best.severity.index) {
        best = a;
      }
    }
    return best;
  }

  Future<void> _setupCook() async {
    final plan = await showCookSetupSheet(context);
    if (plan != null && mounted) {
      setState(() => _plan = plan);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final snapshot = _session.snapshot;
    // The chip shows a retry count only while a background Wi-Fi (re)connect is
    // actually running — a healthy link reads clean.
    final live = _session.liveLink;
    final retry = live != null && live.upgrading && live.attempt > 0
        ? live.attempt
        : null;
    // Cook (index 0) carries its own chrome inside CookView; the shell yields
    // to it there and owns the chrome on every other tab.
    final showChrome = _index != 0;
    final topAlarm = snapshot == null ? null : _topAlarm(snapshot);

    return Scaffold(
      backgroundColor: t.bg,
      body: Column(
        children: [
          // Above everything, and outside `showChrome`: Cook owns its own
          // chrome, so without this it would be the one tab where a failed
          // pull-to-refresh said nothing at all.
          RefreshBanner(
            failure: _session.refreshFailure,
            busy: _session.refreshing,
            onRetry: () => unawaited(_session.refresh()),
            onDismiss: _session.dismissRefreshFailure,
          ),
          if (showChrome) ...[
            SystemStatusBar(
              link: snapshot?.link ?? LinkKind.offline,
              netMode: snapshot?.netMode,
              freshness: _session.freshness,
              socPct: snapshot?.socPct,
              charging: snapshot?.charging ?? false,
              batteryKnown: snapshot?.batteryKnown ?? false,
              attempt: retry,
              onTap: () => unawaited(showConnectionSheet(context, _session)),
            ),
            AlarmBar(
              alarm: topAlarm,
              onAck: topAlarm == null
                  ? null
                  : () => unawaited(_session.ackAlarm(topAlarm.id)),
            ),
          ],
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                _cookTab(context),
                const SessionsRoute(),
                const AlarmsTab(),
                // The shared session lights up the tab's live state — link,
                // mode, health, and the last-known framing when offline
                // (A24.10). Without it the tab could only echo stale prefs.
                // `active` gates its signal poll: all four tabs stay mounted
                // in the IndexedStack, and a radio read behind three other
                // screens is battery spent on nothing.
                BridgeTab(session: _session, active: _index == 3),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: t.surface,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.local_fire_department_outlined),
            selectedIcon: Icon(Icons.local_fire_department_rounded),
            label: 'Cook',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: 'Alarms',
          ),
          NavigationDestination(
            icon: Icon(Icons.router_outlined),
            selectedIcon: Icon(Icons.router_rounded),
            label: 'Bridge',
          ),
        ],
      ),
    );
  }

  /// Makes a screen-sized, non-scrolling branch pullable. An empty state is
  /// exactly where "try the bridge again, now" matters most, and a widget
  /// that does not scroll cannot be pulled.
  Widget _pullable(Widget child) => RefreshIndicator(
    onRefresh: _session.refresh,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    ),
  );

  Widget _cookTab(BuildContext context) {
    final snapshot = _session.snapshot;
    if (snapshot == null) {
      return SafeArea(
        bottom: false,
        child: switch (_session.launch) {
          LaunchOffline() => _pullable(
            const EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Can’t reach your bridge',
              message:
                  'Saved cooks are still here. Pull down to try again — the '
                  'app also reconnects on its own when the bridge is back.',
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      );
    }

    final probeConfig = [
      for (final p in snapshot.probes)
        Probe(n: p.probe, name: p.name, role: p.role, targetF10: p.targetF10),
    ];
    final viewport = _viewport;
    final showChart = snapshot.samples.isNotEmpty && viewport != null;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: CookView(
              snapshot: snapshot,
              plan: _plan,
              freshness: _session.freshness,
              paired: snapshot.paired,
              onSetupCook: _setupCook,
              onStop: _plan == null ? null : () => setState(() => _plan = null),
              // The highest unacked alarm rides CookView's own AlarmBar off
              // snapshot.alarms; silencing it acks the exact id on the device.
              onAck: (alarm) => unawaited(_session.ackAlarm(alarm.id)),
              onRefresh: _session.refresh,
            ),
          ),
          if (showChart)
            Padding(
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
                    model: buildChartSeries(
                      snapshot.samples,
                      fromT: viewport.minX,
                      toT: viewport.maxX,
                    ),
                    viewport: viewport,
                    probes: probeConfig,
                    marks: snapshot.marks,
                    startedUnixMs: snapshot.startedUnixMs,
                    onViewport: (v) => setState(() => _viewport = v),
                    fullHistory: snapshot.fullHistory,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
