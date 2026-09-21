/// N0.7 / N4 — the assembled app boots inside a `ProviderScope` and lands on
/// the Live destination inside the real shell chrome. This is what fails if the
/// router, the shell or the package wiring regresses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/router.dart';
import 'package:smoke_bridge/app/smoke_app.dart';
import 'package:smoke_bridge/features/shell/shell.dart';

void main() {
  testWidgets('SmokeApp boots to the Live destination in the shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The repeating liveness pulse would make `pumpAndSettle` hang.
          shellPulseEnabledProvider.overrideWithValue(false),
        ],
        child: SmokeApp(router: createAppRouter()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('live-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('shell-nav-live')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('shell-appbar-title')),
      findsNothing,
    );
  });
}
