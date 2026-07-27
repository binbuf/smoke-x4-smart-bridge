/// A24.1 — the app shell: four branches over one live session (design 13
/// §13.3), now adaptive and branch-stacked.
///
/// The shell boots the connection race **once** (via [ShellSession]), publishes
/// it through [ShellScope], and frames whichever branch is showing. Branch
/// state survives switching because `StatefulShellRoute.indexedStack` keeps all
/// four `Navigator`s mounted — History keeps its scroll position and its pushed
/// detail page, and the Cook chart keeps its viewport, when you flick to Bridge
/// and back (§13.3.3).
///
/// **Chrome is uniform (§13.5.7).** [SystemStatusBar] and the shared [AlarmBar]
/// ride above **every** branch, including Cook. Previously Cook drew its own
/// chip and bar inside `CookView` while the other three got the shell's, so the
/// transport indicator changed position, container and scroll behaviour with
/// the tab, and a ringing alarm raised two bars. `CookView.showChrome` (the
/// one-line flag its own doc comment asked for) closes that seam.
///
/// **Adaptive (§13.3).** Bottom [NavigationBar] on compact; [NavigationRail]
/// from 600 dp, extended past 1240 dp. The destinations and their indices never
/// change — only the chrome carrying them — which is what keeps this a layout
/// change and not an IA change. The status bar rides the rail's footer on wide
/// windows so two chips do not span seven inches. On a half-open foldable the
/// content is inset clear of the crease.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/connection.dart';
import '../../app/router.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart';
import '../../ui/ui.dart';
import '../alarms/alerts_tab.dart';
import '../bridge/bridge_tab.dart';
import '../cook/cook_tab.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../sessions/sessions_route.dart';
import 'connection_sheet.dart';
import 'refresh_banner.dart';
import 'shell_scope.dart';
import 'shell_session.dart';
import 'system_status_bar.dart';

/// The four destinations, in branch order. One table, read by both the bar and
/// the rail, so the two can never drift.
const List<NavigationDestination> _destinations = [
  NavigationDestination(
    icon: Icon(Icons.local_fire_department_outlined),
    selectedIcon: Icon(Icons.local_fire_department_rounded),
    label: 'Cook',
  ),
  NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
  NavigationDestination(
    icon: Icon(Icons.notifications_outlined),
    selectedIcon: Icon(Icons.notifications_rounded),
    // "Alarms" collided with the *device's* alarm rules, and this branch's
    // real job is whether this phone will actually wake you.
    label: 'Alerts',
  ),
  NavigationDestination(
    icon: Icon(Icons.router_outlined),
    selectedIcon: Icon(Icons.router_rounded),
    label: 'Bridge',
  ),
];

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.session,
    this.navigationShell,
    this.initialIndex = 0,
  });

  /// Injected by tests with a seeded [ShellSession]. Null in production, where
  /// the shell builds and owns one from the ambient `AppEnv`.
  final ShellSession? session;

  /// The router's branch container. Present in the app; null when a test
  /// mounts the shell directly, which then falls back to a local
  /// [IndexedStack] over the same four widgets. The tabs themselves are
  /// identical either way — they read the session from [ShellScope], not from
  /// a constructor — so the fallback exercises the shipping widgets.
  final StatefulNavigationShell? navigationShell;

  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final ShellSession _session;

  /// Dispose the session only if we created it — a test that injected one owns
  /// its lifetime.
  late final bool _ownsSession;

  /// Only used on the no-router fallback path.
  late int _localIndex;

  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    _localIndex = widget.initialIndex;
    _session = widget.session ?? ShellSession();
    _ownsSession = widget.session == null;
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
    // This is one of the two places §13.3.4 still permits `context.go` — it is
    // the setup gate, not an in-branch navigation.
    if (_session.launch is LaunchNeedsOnboarding && !_redirected) {
      _redirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go(AppRoutes.setup);
        }
      });
      return;
    }
    setState(() {});
  }

  int get _index => widget.navigationShell?.currentIndex ?? _localIndex;

  void _select(int i) {
    final shell = widget.navigationShell;
    if (shell == null) {
      setState(() => _localIndex = i);
      return;
    }
    // `initialLocation: true` when re-tapping the current tab pops that
    // branch back to its root — the standard "tap the tab you are on to go
    // home" gesture, and the way out of a pushed History detail without
    // reaching for back.
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  /// The single loudest alarm still ringing — highest severity, device-scope
  /// (`probe == 0`) included.
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

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final window = context.window;
    final snapshot = _session.snapshot;

    // The chip shows a retry count only while a background Wi-Fi (re)connect
    // is actually running — a healthy link reads clean.
    final live = _session.liveLink;
    final retry = live != null && live.upgrading && live.attempt > 0
        ? live.attempt
        : null;
    final topAlarm = snapshot == null ? null : _topAlarm(snapshot);

    final statusBar = SystemStatusBar(
      link: snapshot?.link ?? LinkKind.offline,
      netMode: snapshot?.netMode,
      freshness: _session.freshness,
      socPct: snapshot?.socPct,
      charging: snapshot?.charging ?? false,
      batteryKnown: snapshot?.batteryKnown ?? false,
      attempt: retry,
      onTap: () => unawaited(showConnectionSheet(context, _session)),
    );

    final body = Column(
      children: [
        // Above everything: a failed pull-to-refresh must be able to say so on
        // every branch, including Cook.
        RefreshBanner(
          failure: _session.refreshFailure,
          busy: _session.refreshing,
          onRetry: () => unawaited(_session.refresh()),
          onDismiss: _session.dismissRefreshFailure,
        ),
        // The status bar rides the top of the *content* on every width.
        //
        // It briefly lived in the rail footer, on the theory that a full-width
        // strip carrying two chips wastes a tablet's width. On the device that
        // backfired: the transport chip is ~150 dp of text, and an
        // `IntrinsicWidth` rail sized itself to fit it — a 160 dp navigation
        // rail, twice its natural width, stealing exactly the space the
        // supporting pane was meant to gain. Beside the rail it costs nothing.
        statusBar,
        AlarmBar(
          alarm: topAlarm,
          celsius: _session.celsius,
          onAck: topAlarm == null
              ? null
              : () => unawaited(_session.ackAlarm(topAlarm.id)),
        ),
        Expanded(child: _branchBody()),
      ],
    );

    return ShellScope(
      session: _session,
      activeIndex: _index,
      child: Scaffold(
        backgroundColor: t.bg,
        body: window.usesRail
            ? Row(
                children: [
                  _rail(window),
                  // Nothing may land in the crease of a book-posture fold.
                  SizedBox(width: window.hingeIsVertical ? window.hingeGap : 0),
                  Expanded(child: body),
                ],
              )
            : body,
        bottomNavigationBar: window.usesRail
            ? null
            : NavigationBar(
                backgroundColor: t.surface,
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: _destinations,
              ),
      ),
    );
  }

  Widget _branchBody() {
    final shell = widget.navigationShell;
    if (shell != null) {
      return shell;
    }
    // No router above us (a direct-mount test). Same four widgets, same
    // ShellScope, so what is exercised is what ships.
    return IndexedStack(
      index: _localIndex,
      children: const [
        CookTab(),
        SessionsRoute(embedded: true),
        AlertsTab(),
        BridgeTab(),
      ],
    );
  }

  /// Navigation only. Anything else in here widens the rail (see the
  /// [SystemStatusBar] note above) and eats the width the content just gained.
  Widget _rail(SmokeWindow window) {
    final t = context.tokens;
    return NavigationRail(
      backgroundColor: t.surface,
      selectedIndex: _index,
      onDestinationSelected: _select,
      extended: window.railExtended,
      labelType: window.railExtended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      destinations: [
        for (final d in _destinations)
          NavigationRailDestination(
            icon: d.icon,
            selectedIcon: d.selectedIcon,
            label: Text(d.label),
          ),
      ],
    );
  }
}
