/// A24.1 — the app shell: **three** branches over one live session (design 13
/// §13.3), re-shaped to the newapp §B.2 IA.
///
/// The shell boots the connection race **once** (via [ShellSession]), publishes
/// it through [ShellScope], and frames whichever branch is showing. Branch
/// state survives switching because `StatefulShellRoute.indexedStack` keeps all
/// four `Navigator`s mounted — History keeps its scroll position and its pushed
/// detail page, and the Cook chart keeps its viewport, when you flick to Bridge
/// and back (§13.3.3).
///
/// **Chrome is uniform (§13.5.7).** [SystemStatusBar] and the shared [AlarmBar]
/// ride above **every** branch, including the reader. Previously the reader drew
/// its own chip and bar inside `CookView` while the others got the shell's, so
/// the transport indicator changed position, container and scroll behaviour
/// with the tab, and a ringing alarm raised two bars. `CookView.showChrome`
/// closes that seam.
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
import '../bridge/bridge_tab.dart';
import '../cooks/cooks_tab.dart';
import '../dashboard/dashboard_snapshot.dart';
import '../live/live_tab.dart';
import 'connection_sheet.dart';
import 'refresh_banner.dart';
import 'shell_scope.dart';
import 'shell_session.dart';
import 'system_status_bar.dart';

/// The three destinations, in branch order. One table, read by both the bar and
/// the rail, so the two can never drift.
const List<NavigationDestination> _destinations = [
  NavigationDestination(
    icon: Icon(Icons.thermostat_outlined),
    selectedIcon: Icon(Icons.thermostat_rounded),
    // The product sentence, in one word: this is the reader.
    label: 'Live',
  ),
  NavigationDestination(
    icon: Icon(Icons.outdoor_grill_outlined),
    selectedIcon: Icon(Icons.outdoor_grill_rounded),
    label: 'Cooks',
  ),
  NavigationDestination(
    icon: Icon(Icons.router_outlined),
    selectedIcon: Icon(Icons.router_rounded),
    label: 'Device',
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

    final topAlarm = snapshot == null ? null : _topAlarm(snapshot);

    final statusBar = SystemStatusBar(
      link: snapshot?.link ?? LinkKind.offline,
      netMode: snapshot?.netMode,
      freshness: _session.freshness,
      socPct: snapshot?.socPct,
      charging: snapshot?.charging ?? false,
      batteryKnown: snapshot?.batteryKnown ?? false,
      onTap: () => unawaited(showConnectionSheet(context, _session)),
    );

    // ── the chrome stack ────────────────────────────────────────────────
    //
    // Four things can ride above the content, and before the §H.2 pass they
    // piled up as three full-bleed strips in arrival order — refresh, status,
    // alarm — which is neither a rhythm nor a ranking. Now:
    //
    //  1. the **status bar is the bezel**: full-bleed, on `surface`, with the
    //     one hairline seam in the stack, and it carries the safe-area inset
    //     for everything below it (a banner mounted above it used to render
    //     under the notch);
    //  2. **notices float**, inset on the 4 dp gutter over `bg`, as slabs with
    //     the 14 %/35 % chrome treatment. A slab under a bezel reads as a
    //     decision; a third full-width band reads as an accident;
    //  3. **rank is explicit and the alarm wins.** The alarm is about the
    //     cook; a failed refresh is about the app's own plumbing. When both
    //     are up the refresh banner **compacts to one line** — §16.3's "one
    //     situation at a time" honoured without discarding the second fact;
    //  4. every reveal goes through the shared `ChromeSlot`, so the two
    //     notices cannot drift apart and reduced motion turns both off in one
    //     place.
    final chrome = <Widget>[
      statusBar,
      AlarmBar(
        alarm: topAlarm,
        celsius: _session.celsius,
        inset: true,
        onAck: topAlarm == null
            ? null
            : () => unawaited(_session.ackAlarm(topAlarm.id)),
      ),
      RefreshBanner(
        failure: _session.refreshFailure,
        busy: _session.refreshing,
        compact: topAlarm != null,
        onRetry: () => unawaited(_session.refresh()),
        onDismiss: _session.dismissRefreshFailure,
      ),
    ];

    final body = Column(
      // The status bar rides the top of the *content* on every width.
      //
      // It briefly lived in the rail footer, on the theory that a full-width
      // strip carrying two chips wastes a tablet's width. On the device that
      // backfired: the transport chip is ~150 dp of text, and an
      // `IntrinsicWidth` rail sized itself to fit it — a 160 dp navigation
      // rail, twice its natural width, stealing exactly the space the
      // supporting pane was meant to gain. Beside the rail it costs nothing.
      children: [...chrome, Expanded(child: _branchBody())],
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
      children: const [LiveTab(), CooksTab(), BridgeTab()],
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
