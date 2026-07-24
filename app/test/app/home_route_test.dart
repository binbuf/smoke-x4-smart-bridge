/// A9.5/A9.6 — the home route is the dashboard now.
///
/// A1.2's `HomePlaceholderScreen` is gone: `/` builds [DashboardRoute],
/// which decides whether this phone has ever met a bridge and routes to
/// the wizard if not. Mounted with no [AppEnv] installed — the case a
/// bare widget test hits — it must render its chrome and its connecting
/// state rather than throwing, which is what this file pins.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/router.dart';
import 'package:smoke_bridge/app/theme.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_route.dart';

Widget _appWith(ThemeData theme) =>
    MaterialApp.router(theme: theme, routerConfig: createRouter());

Future<void> _expectDashboardChrome(
  WidgetTester tester,
  Brightness brightness,
) async {
  expect(find.byType(DashboardRoute), findsOneWidget);
  expect(find.text('Smoke Bridge'), findsOneWidget);
  // The two doors out of the dashboard (A11, A12).
  expect(find.byKey(const Key('nav-sessions')), findsOneWidget);
  expect(find.byKey(const Key('nav-settings')), findsOneWidget);
  final context = tester.element(find.byType(DashboardRoute));
  expect(Theme.of(context).brightness, brightness);
}

void main() {
  testWidgets('home route renders under the dark (default) theme', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(SmokeTheme.dark));
    await tester.pump();
    await _expectDashboardChrome(tester, Brightness.dark);
  });

  testWidgets('home route renders under the light theme', (tester) async {
    await tester.pumpWidget(_appWith(SmokeTheme.light));
    await tester.pump();
    await _expectDashboardChrome(tester, Brightness.light);
  });

  testWidgets('with no environment it waits rather than throwing', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(SmokeTheme.dark));
    await tester.pump();
    expect(find.byKey(const Key('dashboard-connecting')), findsOneWidget);
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
