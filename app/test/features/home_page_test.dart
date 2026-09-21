/// N0.7 — the placeholder route renders, themed, with no bridge or network.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/features/home/home_page.dart';

import '../support/load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('HomePage renders the placeholder title in the display font', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: SmokeTheme.dark, home: const HomePage()),
    );

    expect(find.text('Smoke X4'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Smoke X4'));
    expect(title.style?.fontFamily, SmokeTheme.displayFont);
  });

  testWidgets(
    'the scaffold background is the app surface, not Material black',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: SmokeTheme.dark, home: const HomePage()),
      );

      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.scaffoldBackgroundColor, SmokeTheme.background);
    },
  );
}
