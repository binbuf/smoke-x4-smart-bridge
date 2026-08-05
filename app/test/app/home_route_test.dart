/// A24.1 — the home route is the app shell now.
///
/// `/` used to build `DashboardRoute`; it now builds [AppShell], the three-tab
/// primary experience (design 13 §13.3, newapp §B.2). Mounted with no [AppEnv]
/// installed —
/// the case a bare widget test hits — the shell must render its tabs and its
/// connecting state rather than throwing, which is what this file pins. The
/// theme assertions below still exercise `app/theme.dart`'s `SmokeTheme`
/// directly, unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/router.dart';
import 'package:smoke_bridge/app/theme.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';

Widget _appWith(ThemeData theme) =>
    MaterialApp.router(theme: theme, routerConfig: createRouter());

Future<void> _expectShellChrome(
  WidgetTester tester,
  Brightness brightness,
) async {
  expect(find.byType(AppShell), findsOneWidget);
  // The three branches (§13.3.3, §B.2). `findsWidgets` rather than
  // `findsOneWidget` because the shell is adaptive: a rail may render a label
  // per destination in a different tree shape than the bar does.
  for (final tab in ['Live', 'Cooks', 'Device']) {
    expect(find.text(tab), findsWidgets, reason: 'nav destination "$tab"');
  }
  final context = tester.element(find.byType(AppShell));
  expect(Theme.of(context).brightness, brightness);
}

void main() {
  testWidgets('home route renders the shell under the dark (default) theme', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(SmokeTheme.dark));
    await tester.pump();
    await _expectShellChrome(tester, Brightness.dark);
  });

  testWidgets('home route renders the shell under the light theme', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(SmokeTheme.light));
    await tester.pump();
    await _expectShellChrome(tester, Brightness.light);
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

  testWidgets('with no environment it waits rather than throwing', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(SmokeTheme.dark));
    await tester.pump();
    // No AppEnv: the reader shows its connecting spinner, no exception.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('themes demand generous touch targets', (tester) async {
    for (final theme in [SmokeTheme.dark, SmokeTheme.light]) {
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.visualDensity, VisualDensity.standard);
    }
  });

  test('the headline temperature style is still the huge one', () {
    // A9.2 relies on this: "the two numbers that matter are enormous".
    expect(SmokeTheme.dark.textTheme.displayLarge?.fontSize, 88);
  });
}
