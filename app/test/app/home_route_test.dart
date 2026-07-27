/// A24.1 — the home route is the app shell now.
///
/// `/` used to build `DashboardRoute`; it now builds [AppShell], the four-tab
/// primary experience (design 13 §13.3). Mounted with no [AppEnv] installed —
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
  // The four tabs (§13.3.3).
  for (final tab in ['Cook', 'History', 'Alarms', 'Bridge']) {
    expect(find.text(tab), findsOneWidget, reason: 'nav tab "$tab"');
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

  testWidgets('with no environment it waits rather than throwing', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(SmokeTheme.dark));
    await tester.pump();
    // No AppEnv: the Cook tab shows its connecting spinner, no exception.
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
