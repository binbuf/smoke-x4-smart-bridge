/// N0.7 / N3.5 — the root widget.
///
/// N3 applies the three theme axes here: `themeMode` (system/light/dark),
/// `displayProfile` (standard/daylight) and `density`
/// (compact/comfortable), plus `reducedMotion`. The shell (N4) passes the
/// values from `AppSettings`; until then the defaults match
/// `AppSettings.defaults`.
///
/// The liveness pulse is **not** owned here: a repeating controller at the root
/// would make `pumpAndSettle` unusable for every golden. `SmokePulseScope` is
/// the seam; N4 mounts one controller beside the shell chrome.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/design.dart';
import 'router.dart';

class SmokeApp extends StatelessWidget {
  const SmokeApp({
    super.key,
    this.themeMode = ThemeMode.system,
    this.profile = SmokeProfile.standard,
    this.density = SmokeDensity.compact,
    this.reducedMotion = false,
    this.router,
  });

  final ThemeMode themeMode;
  final SmokeProfile profile;
  final SmokeDensity density;
  final bool reducedMotion;

  /// Overrides the shared [appRouter]. Tests pass a fresh router so navigation
  /// does not leak between tests.
  final GoRouter? router;

  @override
  Widget build(BuildContext context) {
    final light = SmokeThemeData.light(
      profile: profile,
      density: density,
      reducedMotion: reducedMotion,
    );
    final dark = SmokeThemeData.dark(
      profile: profile,
      density: density,
      reducedMotion: reducedMotion,
    );
    return MaterialApp.router(
      title: 'Smoke Bridge',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: themeMode,
      routerConfig: router ?? appRouter,
    );
  }
}
