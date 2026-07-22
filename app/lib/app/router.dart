/// App navigation (go_router) — A1.2.
///
/// One placeholder home route for now. Feature routes (onboarding,
/// sessions, alarms, settings, debug) land with their milestones.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Route paths, kept in one place so features never hardcode strings.
abstract final class AppRoutes {
  static const String home = '/';
}

/// Build a fresh router. Tests create one per pump; the app holds a single
/// instance in [appRouter].
GoRouter createRouter() => GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const HomePlaceholderScreen(),
    ),
  ],
);

/// The app's router instance.
final GoRouter appRouter = createRouter();

/// Placeholder home screen: app name, a connection placeholder, and the two
/// headline temperature slots rendered in the theme's display type — so the
/// dark-first/large-type constraint is visible from the first commit.
/// Replaced by the real dashboard in M2.
class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Smoke Bridge')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Connection placeholder — becomes the live connection status
            // chip once the transport layer exists (A3).
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bluetooth_disabled,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Not connected',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // The two headline temperature slots (design 08 §8.7): empty
            // placeholders for now, but already in the huge display type.
            Text(
              '––°',
              style: theme.textTheme.displayLarge,
              semanticsLabel: 'Pit temperature unavailable',
            ),
            const SizedBox(height: 8),
            Text(
              'PIT',
              style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 3,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '––°',
              style: theme.textTheme.displayMedium,
              semanticsLabel: 'Food temperature unavailable',
            ),
            const SizedBox(height: 8),
            Text(
              'FOOD 1',
              style: theme.textTheme.labelLarge?.copyWith(
                letterSpacing: 3,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
