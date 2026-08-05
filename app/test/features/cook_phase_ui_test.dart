/// The guided four-phase progression, on screen (newapp §D.5).
///
/// The domain is covered in `test/domain/cook_phase_test.dart`. What is pinned
/// here is that the **rendering keeps the same three promises**:
///
///  1. the pull button appears only when there is something to pull, and its
///     absence is what stops the app inferring a pull it was never told about;
///  2. the rest countdown says "estimate" on screen, not just in the model;
///  3. the phase is a **mark, never a colour** — green is transport health, and
///     a phase that recoloured the card would collide with it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/ui/ui.dart';

const int _epoch = 1700000000000;

CookPlan _plan() => CookPlan(
  presetId: 'beef_brisket',
  title: 'Brisket',
  hazard: HazardClass.wholeMuscleRedMeat,
  doneness: 'Tender',
  probes: [
    PlanProbe(jack: 1, isPit: true, name: 'Pit'),
    PlanProbe(
      jack: 2,
      isPit: false,
      name: 'Brisket',
      targetF10: 2030,
      pullF10: 1950,
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  required int tempF10,
  int? pulledAtUnixMs,
  int nowUnixMs = _epoch,
  VoidCallback? onPulled,
}) async {
  final plan = _plan();
  final probe = ProbeView(
    probe: 2,
    role: ProbeRole.food,
    name: 'Brisket',
    tempF10: tempF10,
    targetF10: 2030,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: SmokeTheme.dark,
      home: Scaffold(
        body: ProbeHeroCard(
          view: probe,
          plan: plan,
          freshness: ProbeFreshness.live,
          phase: cookPhaseFor(
            tempF10: tempF10,
            targetF10: 2030,
            pullF10: 1950,
            nowUnixMs: nowUnixMs,
            pulledAtUnixMs: pulledAtUnixMs,
          ),
          onPulled: onPulled,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('approaching shows the phase and offers nothing to tap', (
    tester,
  ) async {
    await _pump(tester, tempF10: 1600, onPulled: () {});
    expect(find.byKey(const Key('phase-approaching')), findsOneWidget);
    expect(
      find.byKey(const Key('phase-pulled')),
      findsNothing,
      reason: 'there is nothing to pull yet',
    );
    expect(find.textContaining('Pull at'), findsOneWidget);
  });

  testWidgets('reaching the pull temperature asks for the one fact the app '
      'may not infer', (tester) async {
    var pulled = false;
    await _pump(tester, tempF10: 1960, onPulled: () => pulled = true);

    expect(find.byKey(const Key('phase-pullNow')), findsOneWidget);
    expect(find.textContaining('off the heat'), findsOneWidget);

    await tester.tap(find.byKey(const Key('phase-pulled')));
    await tester.pump();
    expect(pulled, isTrue);
  });

  testWidgets('with no handler there is no button — never a dead control', (
    tester,
  ) async {
    await _pump(tester, tempF10: 1960);
    expect(find.byKey(const Key('phase-pulled')), findsNothing);
  });

  testWidgets('a probe past target still says pull until the user says so', (
    tester,
  ) async {
    await _pump(tester, tempF10: 2100, onPulled: () {});
    expect(
      find.byKey(const Key('phase-pullNow')),
      findsOneWidget,
      reason:
          'a cooling probe could be a pull, a lid, or a probe knocked into '
          'the fire — the app does not guess',
    );
  });

  testWidgets('resting counts down and says it is an estimate', (tester) async {
    await _pump(
      tester,
      tempF10: 1960,
      pulledAtUnixMs: _epoch,
      nowUnixMs: _epoch + 5 * 60 * 1000,
      onPulled: () {},
    );
    expect(find.byKey(const Key('phase-resting')), findsOneWidget);
    expect(find.textContaining('left'), findsOneWidget);
    expect(
      find.textContaining('estimate'),
      findsOneWidget,
      reason:
          'carryover is not measurable from one interior point, and this app '
          'does not present a physics guess as a reading',
    );
    // The pull already happened; asking again would be nonsense.
    expect(find.byKey(const Key('phase-pulled')), findsNothing);
  });

  testWidgets('a reading that reached target ends the rest early', (
    tester,
  ) async {
    await _pump(
      tester,
      tempF10: 2030,
      pulledAtUnixMs: _epoch,
      nowUnixMs: _epoch + 60 * 1000,
      onPulled: () {},
    );
    expect(find.byKey(const Key('phase-ready')), findsOneWidget);
    expect(find.textContaining('estimate'), findsNothing);
  });

  testWidgets('the phase is a mark, never a colour', (tester) async {
    // Green is transport health. A phase that recoloured the card would make
    // "ready" and "connected" the same signal (§14.6).
    await _pump(tester, tempF10: 2030, pulledAtUnixMs: _epoch, onPulled: () {});
    final containers = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>();
    for (final d in containers) {
      expect(
        d.color,
        isNot(StatusPalette.positive),
        reason: 'the positive hue is reserved for transport health',
      );
    }
  });

  testWidgets('without a phase the card is exactly what it was', (
    tester,
  ) async {
    final plan = _plan();
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: Scaffold(
          body: ProbeHeroCard(
            view: const ProbeView(
              probe: 2,
              role: ProbeRole.food,
              name: 'Brisket',
              tempF10: 1600,
              targetF10: 2030,
            ),
            plan: plan,
            freshness: ProbeFreshness.live,
          ),
        ),
      ),
    );
    await tester.pump();
    for (final phase in CookPhase.values) {
      expect(find.byKey(Key('phase-${phase.name}')), findsNothing);
    }
  });

  testWidgets('a stale probe shows no phase at all', (tester) async {
    // Derived values are REMOVED when stale, not greyed — the freshness ladder
    // applies to the progression exactly as it applies to the ETA.
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: Scaffold(
          body: ProbeHeroCard(
            view: const ProbeView(
              probe: 2,
              role: ProbeRole.food,
              name: 'Brisket',
              tempF10: 1960,
              targetF10: 2030,
            ),
            plan: _plan(),
            freshness: ProbeFreshness.stale,
            phase: cookPhaseFor(
              tempF10: 1960,
              targetF10: 2030,
              pullF10: 1950,
              nowUnixMs: _epoch,
            ),
            onPulled: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('phase-pullNow')), findsNothing);
    expect(find.byKey(const Key('phase-pulled')), findsNothing);
  });
}
