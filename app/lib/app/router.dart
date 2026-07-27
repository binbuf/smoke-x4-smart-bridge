/// App navigation (go_router) — A1.2, filled in by M4, made shell-first by A24.1.
///
/// `/` is now the [AppShell] (design 13 §13.3.2): the four-tab primary
/// experience, which boots the connection race once and decides — via its
/// shared [ShellSession] — whether this phone has ever met a bridge (A9.5),
/// sending it to `/setup` if not. The older flat routes (`/onboarding`,
/// `/setup`, `/sessions`, `/settings`, `/cook`) stay registered so their tests
/// and deep links keep working; the shell is simply the front door now.
library;

import 'package:go_router/go_router.dart';

import '../features/cook/cook_preview_route.dart';
import '../features/onboarding/onboarding.dart';
import '../features/sessions/sessions_route.dart';
import '../features/settings/settings_route.dart';
import '../features/setup/setup_route.dart';
import '../features/shell/app_shell.dart';

/// Route paths, kept in one place so features never hardcode strings.
abstract final class AppRoutes {
  static const String home = '/';

  /// A8 (M3). The deliberate §12.6-rule-1 exception: the only Flutter
  /// screen before M4, because the M3 exit gate is undemonstrable
  /// without it. Superseded by [setup]; kept so its tests still pass.
  static const String onboarding = '/onboarding';

  /// A23 (design 13 §13.5.1). The guided three-hop setup flow that replaces
  /// [onboarding] — where the dashboard now sends an unprovisioned phone.
  static const String setup = '/setup';

  /// A11 (M4).
  static const String sessions = '/sessions';

  /// A12 (M4).
  static const String settings = '/settings';

  /// A22 (M8). The premium Cook view wired live; superseded by the shell's
  /// Cook tab but kept registered so its route and tests still resolve.
  static const String cook = '/cook';
}

/// Build a fresh router. Tests create one per pump; the app holds a single
/// instance in [appRouter].
GoRouter createRouter() => GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const AppShell(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      name: 'onboarding',
      builder: (context, state) => const OnboardingRoute(),
    ),
    GoRoute(
      path: AppRoutes.setup,
      name: 'setup',
      builder: (context, state) => const SetupRoute(),
    ),
    GoRoute(
      path: AppRoutes.sessions,
      name: 'sessions',
      builder: (context, state) => const SessionsRoute(),
      routes: [
        GoRoute(
          path: ':id',
          name: 'session-detail',
          builder: (context, state) => SessionDetailRoute(
            sessionId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.settings,
      name: 'settings',
      builder: (context, state) => const SettingsRoute(),
    ),
    GoRoute(
      path: AppRoutes.cook,
      name: 'cook',
      builder: (context, state) => const CookPreviewRoute(),
    ),
  ],
);

/// The app's router instance.
final GoRouter appRouter = createRouter();
