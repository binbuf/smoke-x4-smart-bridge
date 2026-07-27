/// The root widget: MaterialApp.router + themes + error boundary.
library;

import 'package:flutter/material.dart';

import '../design/theme.dart' as design;
import 'error_boundary.dart';
import 'router.dart';

/// Root of the widget tree, mounted inside a `ProviderScope` by
/// `bootstrap.dart`.
class SmokeBridgeApp extends StatelessWidget {
  const SmokeBridgeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Smoke Bridge',
    // Dark-only ships (design 14 §14.3, decision U4): a white bar behind the
    // app in a dark yard is worse than a high-contrast dark one, so **both**
    // slots are the design theme — OS-light chrome can never leak a white
    // scaffold behind the shell.
    themeMode: ThemeMode.dark,
    theme: design.SmokeTheme.dark,
    darkTheme: design.SmokeTheme.dark,
    routerConfig: appRouter,
    builder: (context, child) =>
        ErrorBoundary(child: child ?? const SizedBox.shrink()),
  );
}
