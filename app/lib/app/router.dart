/// App navigation (go_router) — A1.2, filled in by M4.
///
/// The placeholder home screen A1.2 shipped is gone: `/` is now the
/// dashboard, and the dashboard is what decides whether this phone has
/// ever met a bridge (A9.5) and sends it to the wizard if not.
library;

import 'package:go_router/go_router.dart';

import '../features/dashboard/dashboard_route.dart';
import '../features/onboarding/onboarding.dart';
import '../features/sessions/sessions_route.dart';
import '../features/settings/settings_route.dart';

/// Route paths, kept in one place so features never hardcode strings.
abstract final class AppRoutes {
  static const String home = '/';

  /// A8 (M3). The deliberate §12.6-rule-1 exception: the only Flutter
  /// screen before M4, because the M3 exit gate is undemonstrable
  /// without it.
  static const String onboarding = '/onboarding';

  /// A11 (M4).
  static const String sessions = '/sessions';

  /// A12 (M4).
  static const String settings = '/settings';
}

/// Build a fresh router. Tests create one per pump; the app holds a single
/// instance in [appRouter].
GoRouter createRouter() => GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const DashboardRoute(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      name: 'onboarding',
      builder: (context, state) => const OnboardingRoute(),
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
  ],
);

/// The app's router instance.
final GoRouter appRouter = createRouter();
