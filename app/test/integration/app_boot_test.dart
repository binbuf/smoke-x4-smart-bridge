/// N0.7 — the assembled app boots inside a `ProviderScope` and lands on the
/// placeholder route. This is what fails if the router or package wiring
/// regresses.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/smoke_app.dart';

void main() {
  testWidgets('SmokeApp boots to the placeholder route', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SmokeApp()));
    await tester.pumpAndSettle();

    expect(find.text('Smoke X4'), findsOneWidget);
  });
}
