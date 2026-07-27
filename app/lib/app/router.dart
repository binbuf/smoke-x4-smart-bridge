/// App navigation (go_router) — A1.2 · M4 · A24.1, and now the branch-stack
/// rewrite design 13 §13.3.2 specified and A20.4 never landed.
///
/// **What was wrong.** The shell was a bare `IndexedStack` under a single `/`
/// route, and every in-tab navigation was a root-level `context.go`. Opening a
/// cook from History therefore unmounted [AppShell] — which disposes the
/// `ShellSession`, killing the live link — replaced the tab bar with a
/// full-screen route, and left the user's only way back a chain of back arrows
/// that terminated at `/`, rebuilding the shell on the *Cook* tab. One tap cost
/// the tab bar, the connection, the tab and the scroll position. §13.3.4 states
/// the rule this violated: *"`context.go` is banned outside `redirect` and the
/// setup→shell transition; every in-branch navigation is `context.push`."*
///
/// **What this is.** A [StatefulShellRoute.indexedStack] with one branch per
/// tab. Each branch owns its own `Navigator`, so:
///
///  * `/history/:id` **pushes inside the History branch** — the nav bar stays,
///    the shell stays mounted, the session stays connected, and system back
///    returns to the list with its scroll intact;
///  * every branch keeps its stack when you leave and come back (§13.3.3);
///  * `/setup` and `/recover` sit **above** the shell on the root navigator, so
///    the transport chip and nav bar cannot render behind an unprovisioned
///    device.
///
/// **The settings fold.** `/settings` was reachable only from the connection
/// sheet's "Reach it directly by address" — so probes, units, alarm rules and
/// Home Assistant had no discoverable entry point at all. Its sections are now
/// `/bridge/:section` inside the Bridge branch (§13.3.2's tree), and the old
/// flat paths redirect there so existing deep links and tests still resolve.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/alarms/alerts_tab.dart';
import '../features/bridge/bridge_tab.dart';
import '../features/cook/cook_preview_route.dart';
import '../features/cook/cook_tab.dart';
import '../features/onboarding/onboarding.dart';
import '../features/sessions/sessions_route.dart';
import '../features/settings/settings_route.dart';
import '../features/settings/settings_screen.dart' show SettingsSection;
import '../features/setup/setup_route.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/shell_session.dart';

/// Route paths, kept in one place so features never hardcode strings.
abstract final class AppRoutes {
  /// Redirects to [cook]. Kept because deep links, tests and
  /// `context.go(AppRoutes.home)` call sites all still name it.
  static const String home = '/';

  /// A8 (M3). The deliberate §12.6-rule-1 exception: the only Flutter
  /// screen before M4. Superseded by [setup]; kept so its tests still pass.
  static const String onboarding = '/onboarding';

  /// A23 (design 13 §13.5.1). The guided three-hop setup flow — a gate
  /// **above** the shell, never a tab.
  static const String setup = '/setup';

  // ── the four branches (§13.3.3) ──────────────────────────────────────

  static const String cook = '/cook';
  static const String history = '/history';
  static const String alerts = '/alerts';
  static const String bridge = '/bridge';

  /// Legacy flat paths, now redirects into the branches above.
  static const String sessions = '/sessions';
  static const String settings = '/settings';

  /// The branch index for each root path, so `goBranch`-style navigation and
  /// the shell's own initial index agree on one table.
  static const List<String> branchPaths = [cook, history, alerts, bridge];
}

/// Slug ↔ settings section, for `/bridge/:section`. Only the sections that
/// belong to the *device* are addressable here: alarm rules moved to the
/// Alerts branch, and power lives in the Bridge tab's own danger zone.
SettingsSection? settingsSectionForSlug(String slug) {
  for (final s in SettingsSection.values) {
    if (s.name.toLowerCase() == slug.toLowerCase()) {
      return s;
    }
  }
  return null;
}

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// Legacy flat paths → their branch. A **top-level** redirect rather than
/// per-route ones: a `redirect` on a parent `GoRoute` also fires for its
/// sub-routes, so `/sessions/:id` was being swallowed by `/sessions`'s own
/// redirect and losing its id.
String? _legacyRedirect(String path) {
  if (path == AppRoutes.home) {
    return AppRoutes.cook;
  }
  if (path == AppRoutes.settings || path.startsWith('${AppRoutes.settings}/')) {
    return AppRoutes.bridge;
  }
  if (path == AppRoutes.sessions) {
    return AppRoutes.history;
  }
  const sessionsPrefix = '${AppRoutes.sessions}/';
  if (path.startsWith(sessionsPrefix)) {
    return '${AppRoutes.history}/${path.substring(sessionsPrefix.length)}';
  }
  return null;
}

/// Build a fresh router. Tests create one per pump; the app holds a single
/// instance in [appRouter].
///
/// [session] is a test seam: a seeded [ShellSession] the shell uses instead of
/// booting one. Without it a router test would start the real connection race
/// — a BLE scan on a platform with no `flutter_blue_plus`, and timers that
/// outlive the widget tree.
GoRouter createRouter({ShellSession? session}) => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: AppRoutes.cook,
  redirect: (context, state) => _legacyRedirect(state.uri.path),
  routes: [
    // ── above the shell ───────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.setup,
      name: 'setup',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const SetupRoute(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      name: 'onboarding',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const OnboardingRoute(),
    ),

    // ── the shell: four branches, four stacks ─────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell, session: session),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.cook,
              name: 'cook',
              builder: (context, state) => const CookTab(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.history,
              name: 'history',
              builder: (context, state) => const SessionsRoute(embedded: true),
              routes: [
                GoRoute(
                  path: ':id',
                  name: 'session-detail',
                  // Pushed **inside** the History branch: the nav bar stays,
                  // the shell stays mounted, back returns to the list.
                  builder: (context, state) => SessionDetailRoute(
                    sessionId:
                        int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
                    embedded: true,
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.alerts,
              name: 'alerts',
              builder: (context, state) => const AlertsTab(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.bridge,
              name: 'bridge',
              builder: (context, state) => const BridgeTab(),
              routes: [
                GoRoute(
                  path: ':section',
                  name: 'bridge-section',
                  builder: (context, state) => SettingsRoute(
                    initialSection: settingsSectionForSlug(
                      state.pathParameters['section'] ?? '',
                    ),
                    embedded: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),

    // ── kept registered so its tests and deep links still resolve ─────
    GoRoute(
      path: '/cook-preview',
      name: 'cook-preview',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const CookPreviewRoute(),
    ),
  ],
);

/// The app's router instance.
final GoRouter appRouter = createRouter();
