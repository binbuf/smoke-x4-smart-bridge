/// The root widget: MaterialApp.router + themes + error boundary.
library;

import 'package:flutter/material.dart';

import '../design/theme.dart' as design;
import 'app_env.dart';
import 'error_boundary.dart';
import 'router.dart';

/// Which screen profile is in force (newapp §H.3).
///
/// **There is still no light theme, and that is not an oversight.** A white
/// screen outdoors at night is worse than a high-contrast dark one, and a
/// fourteen-hour cook ends in the dark far more often than it ends at noon.
/// What §H.3 asks for is the *other* problem — direct sunlight — and the answer
/// to that is not white either: the eye adapts to the field, not to the page.
/// So `SmokeTokens.daylight` keeps the same near-black surfaces, lifts the
/// whole ink ramp, thickens the hairlines and **switches every glow off**,
/// because a bloom in sunlight is a smear.
///
/// The token architecture was built for exactly this (design 14 §14.3.3),
/// which is why this is a preference and not a rewrite: the profile swaps a
/// `ThemeExtension` and not a single call site knows it happened.
enum ThemeProfile {
  dark,
  daylight,

  /// Follow the platform's own light/dark signal — the nearest thing to an
  /// ambient-light reading an app gets without a plugin, and it tracks the
  /// same thing a user is reacting to when they reach for the switch.
  auto;

  static ThemeProfile fromName(String? name) =>
      ThemeProfile.values.where((p) => p.name == name).firstOrNull ??
      ThemeProfile.dark;

  String get label => switch (this) {
    ThemeProfile.dark => 'Dark',
    ThemeProfile.daylight => 'Daylight',
    ThemeProfile.auto => 'Auto',
  };

  String get blurb => switch (this) {
    ThemeProfile.dark => 'The default. Built for a yard at 3 a.m.',
    ThemeProfile.daylight =>
      'Higher contrast and no glows, for reading in direct sun.',
    ThemeProfile.auto => 'Daylight while your phone is in its light mode.',
  };
}

/// Root of the widget tree, mounted inside a `ProviderScope` by
/// `bootstrap.dart`.
class SmokeBridgeApp extends StatefulWidget {
  const SmokeBridgeApp({super.key, this.profile});

  /// Test and Lab seam. Null reads the stored preference.
  final ThemeProfile? profile;

  @override
  State<SmokeBridgeApp> createState() => SmokeBridgeAppState();

  /// Lets a settings row change the profile without a relaunch.
  static void setProfile(BuildContext context, ThemeProfile profile) {
    context.findAncestorStateOfType<SmokeBridgeAppState>()?.apply(profile);
  }
}

class SmokeBridgeAppState extends State<SmokeBridgeApp> {
  late ThemeProfile _profile =
      widget.profile ??
      ThemeProfile.fromName(AppEnv.instance?.prefs.themeProfile);

  void apply(ThemeProfile profile) {
    if (profile != _profile) {
      setState(() => _profile = profile);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Smoke Bridge',
    // Both slots are filled deliberately, and **neither is Material's light
    // theme**: OS-light chrome must never leak a white scaffold behind the
    // shell (design 14 §14.3, decision U4). `auto` is the only profile that
    // lets the platform choose, and even then it chooses between this app's
    // two dark-surfaced profiles.
    themeMode: switch (_profile) {
      ThemeProfile.dark => ThemeMode.dark,
      ThemeProfile.daylight => ThemeMode.light,
      ThemeProfile.auto => ThemeMode.system,
    },
    theme: design.SmokeTheme.daylight,
    darkTheme: design.SmokeTheme.dark,
    routerConfig: appRouter,
    builder: (context, child) =>
        ErrorBoundary(child: child ?? const SizedBox.shrink()),
  );
}
