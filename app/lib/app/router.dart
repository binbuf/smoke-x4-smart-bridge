/// App navigation (go_router) — A1.2 · M4 · A24.1, re-shaped to the newapp §B.2
/// information architecture.
///
/// **The branch-stack rules are unchanged and still load-bearing.** A
/// [StatefulShellRoute.indexedStack] with one `Navigator` per branch, so a
/// pushed detail keeps the nav bar, keeps the shell mounted, keeps the live
/// connection alive, and returns to its list with the scroll intact.
/// `context.go` stays banned outside `redirect` and the setup gate; re-tapping
/// the active tab pops it to root. §13.3.4's rules survive the IA change
/// because they were never about *which* tabs existed.
///
/// **What changed, and why (§B.1).** Four tabs, two of which were not places a
/// user spends fourteen hours:
///
///  * `/alerts` was a **permissions verdict plus a test button** promoted to a
///    primary destination. A verdict is not somewhere you live. It is now a
///    persistent banner on the two screens that matter ([DeliveryBanner]) and a
///    one-time gate in setup; its test button moved to `/device/alarms`, beside
///    the rules it tests.
///  * `/bridge` was device management. It absorbs settings, alarm rules, network
///    mode and power and becomes `/device` — the "control everything" home a
///    one-button device needs.
///  * `/cook` (singular, the live reader) splits from `/cooks` (plural, the
///    session system). This is the mental-model shift of §D: **the live screen
///    is not a cook** — a cook is an annotation you may attach to the recording,
///    and naming them the same thing is what made "end cook" read as "stop
///    recording".
///
/// So: three branches, and the reader is the landing.
///
/// ```
/// /            → /live
/// /setup                                    above the shell
/// Tab 1  /live                              THE READER
///          /live/probe/:jack
/// Tab 2  /cooks
///          /cooks/:id
///          /cooks/:id/edit
/// Tab 3  /device
///          /device/alarms
///          /device/settings/:section
/// ```
///
/// Every path the old tree served still resolves, because a deep link a user
/// saved or a notification already posted must not land on a 404 (§I.0's
/// "legacy redirects that no longer point anywhere real" is about deleting the
/// ones that dangle, not about breaking the ones that work).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/alarms/alarm_rules_route.dart';
import '../features/bridge/bridge_tab.dart';
import '../features/cooks/cook_detail_route.dart';
import '../features/cooks/cooks_tab.dart';
import '../features/live/live_tab.dart';
import '../features/live/probe_detail_route.dart';
import '../features/settings/settings_route.dart';
import '../features/settings/settings_screen.dart' show SettingsSection;
import '../features/setup/setup_route.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/shell_session.dart';

/// Route paths, kept in one place so features never hardcode strings.
abstract final class AppRoutes {
  /// Redirects to [live].
  static const String home = '/';

  /// A23 (design 13 §13.5.1). The guided setup flow — a gate **above** the
  /// shell, never a tab.
  static const String setup = '/setup';

  // ── the three branches (§B.2) ────────────────────────────────────────

  /// The reader. Default landing, and the only screen that must render before
  /// any transport connects (§B.3).
  static const String live = '/live';

  /// Session annotations over the continuous recording.
  static const String cooks = '/cooks';

  /// The device: status, connection mode, alarms, settings, power.
  static const String device = '/device';

  /// The alarm-rule editor, both tiers (§G.2). Reachable from `/device`, and
  /// the home of the test-alarm button `/alerts` used to own.
  static const String deviceAlarms = '/device/alarms';

  /// `/device/settings/:section`.
  static const String deviceSettings = '/device/settings';

  static String probeDetail(int jack) => '$live/probe/$jack';
  static String cookDetail(int id) => '$cooks/$id';
  static String cookEdit(int id) => '$cooks/$id/edit';
  static String settingsSection(SettingsSection s) =>
      '$deviceSettings/${s.name.toLowerCase()}';

  // ── superseded paths, kept resolving ────────────────────────────────

  static const String cook = '/cook';
  static const String history = '/history';
  static const String alerts = '/alerts';
  static const String bridge = '/bridge';
  static const String sessions = '/sessions';
  static const String settings = '/settings';

  /// The branch index for each root path, so `goBranch`-style navigation and
  /// the shell's own initial index agree on one table.
  static const List<String> branchPaths = [live, cooks, device];
}

/// Slug ↔ settings section, for `/device/settings/:section`.
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

/// Superseded paths → their branch. A **top-level** redirect rather than
/// per-route ones: a `redirect` on a parent `GoRoute` also fires for its
/// sub-routes, so `/sessions/:id` was being swallowed by `/sessions`'s own
/// redirect and losing its id.
String? legacyRedirect(String path) {
  if (path == AppRoutes.home || path == AppRoutes.cook) {
    return AppRoutes.live;
  }
  // The verdict is a banner now, so its old destination lands on the rules it
  // was always really about.
  if (path == AppRoutes.alerts) {
    return AppRoutes.deviceAlarms;
  }
  if (path == AppRoutes.settings) {
    return AppRoutes.device;
  }
  const settingsPrefix = '${AppRoutes.settings}/';
  if (path.startsWith(settingsPrefix)) {
    return '${AppRoutes.deviceSettings}/${path.substring(settingsPrefix.length)}';
  }
  if (path == AppRoutes.bridge) {
    return AppRoutes.device;
  }
  const bridgePrefix = '${AppRoutes.bridge}/';
  if (path.startsWith(bridgePrefix)) {
    final slug = path.substring(bridgePrefix.length);
    // `/bridge/alarms` was the URL-only alarm page nobody could reach.
    return slug == 'alarms'
        ? AppRoutes.deviceAlarms
        : '${AppRoutes.deviceSettings}/$slug';
  }
  if (path == AppRoutes.history || path == AppRoutes.sessions) {
    return AppRoutes.cooks;
  }
  for (final prefix in const ['${AppRoutes.history}/', '${AppRoutes.sessions}/']) {
    if (path.startsWith(prefix)) {
      return '${AppRoutes.cooks}/${path.substring(prefix.length)}';
    }
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
  initialLocation: AppRoutes.live,
  redirect: (context, state) => legacyRedirect(state.uri.path),
  routes: [
    // ── above the shell ───────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.setup,
      name: 'setup',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const SetupRoute(),
    ),

    // ── the shell: three branches, three stacks ───────────────────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell, session: session),
      branches: [
        // Tab 1 — the reader.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.live,
              name: 'live',
              builder: (context, state) => const LiveTab(),
              routes: [
                GoRoute(
                  path: 'probe/:jack',
                  name: 'probe-detail',
                  builder: (context, state) => ProbeDetailRoute(
                    jack: int.tryParse(state.pathParameters['jack'] ?? '') ?? 1,
                  ),
                ),
              ],
            ),
          ],
        ),
        // Tab 2 — cooks as annotations.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.cooks,
              name: 'cooks',
              builder: (context, state) => const CooksTab(),
              routes: [
                GoRoute(
                  path: ':id',
                  name: 'cook-detail',
                  builder: (context, state) => CookDetailRoute(
                    cookId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
                  ),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      name: 'cook-edit',
                      builder: (context, state) => CookEditRoute(
                        cookId:
                            int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        // Tab 3 — the device.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.device,
              name: 'device',
              builder: (context, state) => const BridgeTab(),
              routes: [
                GoRoute(
                  path: 'alarms',
                  name: 'device-alarms',
                  builder: (context, state) => const AlarmRulesRoute(),
                ),
                GoRoute(
                  path: 'settings/:section',
                  name: 'device-settings',
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
  ],
);

/// The app's router instance.
final GoRouter appRouter = createRouter();
