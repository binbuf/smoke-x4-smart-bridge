/// N4.3 — the route table.
///
/// Five bottom-nav destinations plus History and Cook detail nested under
/// Settings, all rendered inside the persistent [AppShell] (`ShellRoute`).
/// Named overlays travel as a query parameter on any destination (`?overlay=`),
/// which is what makes them deep-linkable; `AppShell` reads the location and
/// the router only has to move.
library;

import 'package:go_router/go_router.dart';

import '../design/gallery.dart';
import '../features/shell/destinations.dart';
import '../features/shell/shell.dart';

final GoRouter appRouter = createAppRouter();

/// Builds a fresh router. Tests use this so navigation in one test cannot leak
/// into the next through the shared [appRouter] instance.
GoRouter createAppRouter() => GoRouter(
  initialLocation: '/live',
  routes: <RouteBase>[
    ShellRoute(
      builder: (context, state, child) => AppShell(
        location: state.uri.toString(),
        child: child,
        onLocation: (location) => context.go(location),
      ),
      routes: <RouteBase>[
        GoRoute(
          path: '/live',
          builder: (context, state) => const LiveDestination(),
        ),
        GoRoute(
          path: '/temps',
          builder: (context, state) => const TempsDestination(),
        ),
        GoRoute(
          path: '/timeline',
          builder: (context, state) => const TimelineDestination(),
        ),
        GoRoute(
          path: '/graph',
          builder: (context, state) => const GraphDestination(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsDestination(),
          routes: <RouteBase>[
            GoRoute(
              path: 'history',
              builder: (context, state) => const HistoryDestination(),
              routes: <RouteBase>[
                GoRoute(
                  path: ':id',
                  builder: (context, state) =>
                      CookDetailDestination(id: state.pathParameters['id']),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    // N3's exit gate: the component gallery, reachable for manual review. N16
    // may keep it behind a debug flag.
    GoRoute(
      path: '/design',
      builder: (context, state) => const DesignGallery(),
    ),
  ],
);
