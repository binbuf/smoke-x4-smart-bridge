/// The root widget: MaterialApp.router + themes + error boundary.
library;

import 'package:flutter/material.dart';

import 'error_boundary.dart';
import 'router.dart';
import 'theme.dart';

/// Root of the widget tree, mounted inside a `ProviderScope` by
/// `bootstrap.dart`.
class SmokeBridgeApp extends StatelessWidget {
  const SmokeBridgeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Smoke Bridge',
    // Dark-first (design 08 §8.7): dark is the default until the settings
    // screen (M4) adds a user-facing theme choice. The light theme exists
    // and is exercised by tests.
    themeMode: ThemeMode.dark,
    theme: SmokeTheme.light,
    darkTheme: SmokeTheme.dark,
    routerConfig: appRouter,
    builder: (context, child) =>
        ErrorBoundary(child: child ?? const SizedBox.shrink()),
  );
}
