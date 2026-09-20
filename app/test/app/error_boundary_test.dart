/// A1.2 — an uncaught exception surfaces in the readable error boundary,
/// never the framework's default grey/red ErrorWidget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/error_boundary.dart';
import 'package:smoke_bridge/design/theme.dart';

/// Throws during build, like any real bug would.
class _Bomb extends StatelessWidget {
  const _Bomb();

  @override
  Widget build(BuildContext context) =>
      throw StateError('boom: probe exploded');
}

void main() {
  testWidgets('a widget throwing during build surfaces the error boundary UI', (
    tester,
  ) async {
    // The binding verifies ErrorWidget.builder is restored at the END of
    // the test body — before addTearDown callbacks run — so restore
    // inline via try/finally rather than addTearDown.
    final defaultBuilder = ErrorWidget.builder;
    ErrorWidget.builder = appErrorWidgetBuilder;
    try {
      await tester.pumpWidget(
        MaterialApp(theme: SmokeTheme.dark, home: const _Bomb()),
      );

      // The framework still reports the exception; consume it so the test
      // does not fail on the report itself.
      expect(tester.takeException(), isA<StateError>());

      // Our readable screen replaced the default ErrorWidget…
      expect(find.byType(AppErrorScreen), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      // …showing the message and a stack snippet.
      expect(find.textContaining('boom: probe exploded'), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.textContaining('_Bomb.build'), findsOneWidget);
    } finally {
      ErrorWidget.builder = defaultBuilder;
    }
  });

  testWidgets('a fatal zone report overlays the app with the error screen', (
    tester,
  ) async {
    addTearDown(AppErrors.clearFatal);

    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: const ErrorBoundary(child: Scaffold(body: Text('healthy'))),
      ),
    );
    expect(find.text('healthy'), findsOneWidget);

    // What bootstrap's runZonedGuarded handler does with an uncaught
    // async error.
    AppErrors.reportFatal(StateError('boom: async'), StackTrace.current);
    await tester.pump();

    expect(find.byType(AppErrorScreen), findsOneWidget);
    expect(find.textContaining('boom: async'), findsOneWidget);

    // Dismiss restores the app.
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(find.text('healthy'), findsOneWidget);
    expect(find.byType(AppErrorScreen), findsNothing);
  });
}
