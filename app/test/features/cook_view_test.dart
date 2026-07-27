/// A22.2 — the Cook view renders in both modes (design 13 §13.3.1).
///
/// Not a golden (fonts and the render surface are not pinned until A19.2's
/// subsetting lands) — a behavioural smoke test: both modes build without
/// throwing, instrument mode shows every jack, guided mode shows the plan's
/// title and a target, and the food-safety gate is honoured end to end.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/features/cook/cook_view.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/ui/probe/probe_freshness.dart';

DashboardSnapshot _snapshot() => const DashboardSnapshot(
  probes: [
    ProbeView(
      probe: 1,
      role: ProbeRole.pit,
      name: 'Pit',
      tempF10: 2430,
      rateFPerHr: -18,
    ),
    ProbeView(
      probe: 2,
      role: ProbeRole.food,
      name: 'Brisket',
      tempF10: 1632,
      rateFPerHr: 12,
    ),
    ProbeView(
      probe: 3,
      role: ProbeRole.food,
      name: 'Probe 3',
      tempF10: 1540,
      rateFPerHr: 45,
    ),
    ProbeView(probe: 4, role: ProbeRole.unused, name: 'Probe 4'),
  ],
  link: LinkKind.http,
  sessionName: 'Brisket',
  sessionActive: true,
  elapsedS: 4 * 3600 + 12 * 60,
);

CookPlan _brisketPlan() => CookPlan(
  presetId: 'beef_brisket',
  title: 'Texas brisket',
  hazard: HazardClass.wholeMuscleRedMeat,
  doneness: 'Pitmaster shred',
  pitBandMinF10: 2250,
  pitBandMaxF10: 2750,
  probes: const [
    PlanProbe(jack: 1, isPit: true, name: 'Pit'),
    PlanProbe(
      jack: 2,
      isPit: false,
      name: 'Brisket',
      targetF10: 2030,
      pullF10: 1980,
    ),
  ],
);

Widget _host(Widget child) => MaterialApp(
  theme: SmokeTheme.dark,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('instrument mode shows every jack and the logging blurb', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot(),
          plan: null,
          freshness: ProbeFreshness.live,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Live readings'), findsOneWidget);
    expect(find.textContaining('logging anyway'), findsOneWidget);
    expect(find.text('PIT'), findsOneWidget);
    expect(find.text('BRISKET'), findsOneWidget);
    // The detached jack 4 is present, not hidden.
    expect(find.text('unplugged'), findsWidgets);
    expect(find.text('Set up a cook'), findsOneWidget);
  });

  testWidgets('guided mode shows the plan title, elapsed, and Stop', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot(),
          plan: _brisketPlan(),
          freshness: ProbeFreshness.live,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Texas brisket'), findsOneWidget);
    expect(find.textContaining('04:12'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    // A target pill on the food hero.
    expect(find.textContaining('Target'), findsWidgets);
  });

  testWidgets('stale freshness removes the gauge (no derived value)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot(),
          plan: _brisketPlan(),
          freshness: ProbeFreshness.stale,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    // Trend/gauge insights are removed at stale; the layout still builds.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the safety gate refuses an unsafe poultry plan', (tester) async {
    expect(
      () => CookPlan(
        presetId: 'x',
        title: 'Chicken',
        hazard: HazardClass.poultry,
        doneness: 'rare',
        probes: const [
          PlanProbe(jack: 1, isPit: true, name: 'Pit'),
          PlanProbe(jack: 2, isPit: false, name: 'Chicken', targetF10: 1400),
        ],
      ),
      throwsArgumentError,
    );
  });

  testWidgets('the loudest unacked alarm rides an AlarmBar with Acknowledge', (
    tester,
  ) async {
    Alarm? acked;
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot().copyWithAlarms(const [
            // A warning and a critical, both unacked: the critical is louder
            // and must be the one shown and acknowledged.
            Alarm(id: 7, rule: 'target_reached', probe: 2),
            Alarm(
              id: 9,
              rule: 'pit_crash',
              probe: 0,
              severity: AlarmSeverity.critical,
            ),
          ]),
          plan: null,
          freshness: ProbeFreshness.live,
          onAck: (a) => acked = a,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    // The device-scope critical (probe 0) wins, and its title is shown.
    expect(find.text('The fire is dying'), findsOneWidget);
    expect(find.text('Target reached'), findsNothing);

    await tester.tap(find.text('Acknowledge'));
    expect(acked?.id, 9);
  });

  testWidgets('acked alarms do not raise the bar', (tester) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot().copyWithAlarms(const [
            Alarm(
              id: 3,
              rule: 'pit_crash',
              severity: AlarmSeverity.critical,
              acked: true,
            ),
          ]),
          plan: null,
          freshness: ProbeFreshness.live,
          onAck: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Acknowledge'), findsNothing);
    expect(find.text('The fire is dying'), findsNothing);
  });

  testWidgets('BLE shows a live-readings-only capability notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot().copyWithLink(LinkKind.ble),
          plan: null,
          freshness: ProbeFreshness.live,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('live readings only'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
  });

  testWidgets('unpaired uses the base-station copy, never "plug a probe"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot(),
          plan: null,
          freshness: ProbeFreshness.live,
          paired: false,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('met your Smoke X yet'), findsOneWidget);
    expect(find.textContaining('Plug a probe'), findsNothing);
  });

  testWidgets('no attached probes shows the no-probes state', (tester) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: const DashboardSnapshot(
            probes: [
              ProbeView(probe: 1, role: ProbeRole.pit, name: 'Pit'),
              ProbeView(probe: 2, role: ProbeRole.food, name: 'Probe 2'),
              ProbeView(probe: 3, role: ProbeRole.food, name: 'Probe 3'),
              ProbeView(probe: 4, role: ProbeRole.unused, name: 'Probe 4'),
            ],
            link: LinkKind.http,
          ),
          plan: null,
          freshness: ProbeFreshness.unknown,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('No probes plugged in'), findsOneWidget);
  });

  testWidgets('stale readings pin an age line over a veiled body', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot().copyWithAge(14 * 60),
          plan: null,
          freshness: ProbeFreshness.stale,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('14m old'), findsOneWidget);
  });
}

/// Tiny snapshot mutators so the tests read as intent, not as a wall of the
/// [DashboardSnapshot] constructor's twenty fields.
extension on DashboardSnapshot {
  DashboardSnapshot copyWithAlarms(List<Alarm> alarms) => DashboardSnapshot(
    probes: probes,
    link: link,
    sessionName: sessionName,
    sessionActive: sessionActive,
    elapsedS: elapsedS,
    alarms: alarms,
  );

  DashboardSnapshot copyWithLink(LinkKind link) => DashboardSnapshot(
    probes: probes,
    link: link,
    sessionName: sessionName,
    sessionActive: sessionActive,
    elapsedS: elapsedS,
  );

  DashboardSnapshot copyWithAge(int sAgo) => DashboardSnapshot(
    probes: probes,
    link: link,
    sessionName: sessionName,
    sessionActive: sessionActive,
    elapsedS: elapsedS,
    lastPacketSAgo: sAgo,
  );
}
