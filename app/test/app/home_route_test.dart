/// A1.2 — the placeholder home route renders under BOTH themes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/router.dart';
import 'package:smoke_bridge/app/theme.dart';

Widget _appWith(ThemeData theme) =>
    MaterialApp.router(theme: theme, routerConfig: createRouter());

void _expectHomePlaceholder(WidgetTester tester, Brightness brightness) {
  expect(find.byType(HomePlaceholderScreen), findsOneWidget);
  // App name.
  expect(find.text('Smoke Bridge'), findsOneWidget);
  // Connection placeholder.
  expect(find.text('Not connected'), findsOneWidget);
  // The two headline temperature slots, in the theme's display type.
  expect(find.text('––°'), findsNWidgets(2));
  final context = tester.element(find.byType(HomePlaceholderScreen));
  final theme = Theme.of(context);
  expect(theme.brightness, brightness);
  final headline = tester.widget<Text>(find.text('––°').first);
  expect(headline.style?.fontSize, SmokeTheme.headlineTemp.fontSize);
}

void main() {
  testWidgets('home route renders under the dark (default) theme', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(SmokeTheme.dark));
    await tester.pumpAndSettle();
    _expectHomePlaceholder(tester, Brightness.dark);
  });

  testWidgets('home route renders under the light theme', (tester) async {
    await tester.pumpWidget(_appWith(SmokeTheme.light));
    await tester.pumpAndSettle();
    _expectHomePlaceholder(tester, Brightness.light);
  });

  testWidgets('themes demand generous touch targets', (tester) async {
    for (final theme in [SmokeTheme.dark, SmokeTheme.light]) {
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.visualDensity, VisualDensity.standard);
    }
  });
}
