/// A24.1 — the home route is the app shell now.
///
/// `/` used to build `DashboardRoute`; it now builds [AppShell], the three-tab
/// primary experience (design 13 §13.3, newapp §B.2). Mounted with no [AppEnv]
/// installed —
/// the case a bare widget test hits — the shell must render its tabs and its
/// connecting state rather than throwing, which is what this file pins. The
/// theme assertions below exercise `design/theme.dart`'s `SmokeTheme` — the
/// one the app actually builds with. They used to point at a second
/// `SmokeTheme` in `app/theme.dart`, a pre-redesign Material theme nothing
/// shipped, so they pinned values no screen rendered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/router.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/design/tokens.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';

Widget _appWith(ThemeData theme) =>
    MaterialApp.router(theme: theme, routerConfig: createRouter());

Future<void> _expectShellChrome(
  WidgetTester tester,
  SmokeTokens expected,
) async {
  expect(find.byType(AppShell), findsOneWidget);
  // The three branches (§13.3.3, §B.2). `findsWidgets` rather than
  // `findsOneWidget` because the shell is adaptive: a rail may render a label
  // per destination in a different tree shape than the bar does.
  for (final tab in ['Live', 'Cooks', 'Device']) {
    expect(find.text(tab), findsWidgets, reason: 'nav destination "$tab"');
  }
  final context = tester.element(find.byType(AppShell));
  // The profile is identified by its *tokens*, not by Material brightness.
  //
  // Daylight is a high-contrast profile — lifted ink, glows off — over the
  // same dark surfaces (§H.3 keeps dark as the default and 14 §14.3.3 calls
  // it "the daylight contrast profile"). Both profiles are therefore
  // `Brightness.dark`. This used to assert `Brightness.light`, which passed
  // only because it was pointed at `app/theme.dart`'s genuine Material light
  // theme — a theme nothing shipped.
  expect(Theme.of(context).extension<SmokeTokens>(), same(expected));
}

void main() {
  testWidgets('home route renders the shell under the dark (default) theme', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(SmokeTheme.dark));
    await tester.pump();
    await _expectShellChrome(tester, SmokeTokens.dark);
  });

  testWidgets('home route renders the shell under the daylight profile', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(SmokeTheme.daylight));
    await tester.pump();
    await _expectShellChrome(tester, SmokeTokens.daylight);
  });

  testWidgets('/ redirects into the reader', (tester) async {
    final router = createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: SmokeTheme.dark, routerConfig: router),
    );
    await tester.pump();
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRoutes.live);
  });

  testWidgets('with no environment it renders rather than throwing', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(SmokeTheme.dark));
    await tester.pump();

    // This used to assert a `CircularProgressIndicator`. §16.6 removed it on
    // purpose: the reader renders from cache on its very first frame, with
    // freshness computed from stored timestamps, and **never a full-screen
    // spinner** — a spinner is the one thing the screen may not show, because
    // it hides the last known temperatures behind the fact that a socket has
    // not opened yet.
    //
    // The intent of the test was never the spinner; it was "a bare widget
    // test with no AppEnv must not crash". That is what it asserts now.
    expect(tester.takeException(), isNull);
    expect(find.byType(AppShell), findsOneWidget);
    // Still navigable: the shell is framing something, not an error page.
    for (final tab in ['Live', 'Cooks', 'Device']) {
      expect(find.text(tab), findsWidgets, reason: tab);
    }
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason:
          'the reader must not fall back to a spinner — that is the '
          'regression §16.6 and §B.3 both exist to prevent',
    );
  });

  testWidgets('themes demand generous touch targets', (tester) async {
    for (final theme in [SmokeTheme.dark, SmokeTheme.daylight]) {
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.visualDensity, VisualDensity.standard);
    }
  });

  test('the headline temperature style is still the huge one', () {
    // A9.2 relies on this: "the two numbers that matter are enormous".
    // 96 pt, per §H.1's "never scale a temperature" and §16.5's hero
    // row. The old assertion said 88 — the value in `app/theme.dart`, the
    // pre-redesign theme nothing ships — so it pinned a number no screen
    // had rendered since.
    expect(SmokeTheme.dark.textTheme.displayLarge?.fontSize, 96);
  });
}
