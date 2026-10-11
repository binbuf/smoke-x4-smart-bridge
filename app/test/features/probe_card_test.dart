/// The probe row's honest three-way distinction: a present reading, a detached
/// jack ("unplugged"), and a bridge that has said nothing at all ("no reading").
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/live/probe_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('a present reading formats in the chosen unit', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ProbeCard(
          jack: ProbeJack.one,
          f10: 724,
          unit: TempUnit.fahrenheit,
          freshness: Freshness.live,
        ),
      ),
    );
    expect(find.text('72.4° F'), findsOneWidget);
  });

  testWidgets('a detached jack reads "unplugged", never 0', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ProbeCard(
          jack: ProbeJack.three,
          f10: null,
          unit: TempUnit.fahrenheit,
          freshness: Freshness.live,
        ),
      ),
    );
    expect(find.text('unplugged'), findsOneWidget);
    expect(find.textContaining('0'), findsNothing);
  });

  testWidgets('no snapshot reads "no reading", not "unplugged"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ProbeCard(
          jack: ProbeJack.one,
          f10: null,
          unit: TempUnit.fahrenheit,
          freshness: Freshness.unknown,
          hasReading: false,
        ),
      ),
    );
    expect(find.text('no reading'), findsOneWidget);
    expect(find.text('unplugged'), findsNothing);
  });
}
