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
import 'package:smoke_bridge/ui/probe/food_avatar.dart';
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
  probes: [
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
  testWidgets('instrument mode shows every jack under a trust line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot(),
          plan: null,
          freshness: ProbeFreshness.live,
          onSetupCook: () {},
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Live readings'), findsOneWidget);
    // §16.6 — the reader answers "can I trust it" on every frame, not only
    // once it has gone stale. The old subtitle explained the recording model
    // ("logging anyway"); that belongs to the empty state, not to the one line
    // under the title on the screen whose job is freshness.
    expect(find.text('Updated just now.'), findsOneWidget);
    expect(find.text('PIT'), findsOneWidget);
    expect(find.text('BRISKET'), findsOneWidget);
    // The detached jack 4 is present, not hidden.
    expect(find.text('unplugged'), findsWidgets);
    // §16.6 — the cook affordance lives in the action row, as a verb naming
    // the outcome, not as a button competing with the screen title.
    expect(find.text('Set a target'), findsOneWidget);
  });

  testWidgets('an older reading says how old, in the masthead', (tester) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot().copyWithAge(75),
          plan: null,
          freshness: ProbeFreshness.aging,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Updated 1m ago.'), findsOneWidget);
  });

  testWidgets('under a minute is counted in seconds, not rounded away', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot().copyWithAge(40),
          plan: null,
          freshness: ProbeFreshness.aging,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Updated 40s ago.'), findsOneWidget);
  });

  testWidgets('guided mode shows the plan title, elapsed, and End cook', (
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
    expect(find.text('End cook'), findsOneWidget);
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
        probes: [
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

  testWidgets('BLE without full history shows the capability notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CookView(
          snapshot: _snapshot().copyWithLink(
            LinkKind.ble,
            fullHistory: false,
          ),
          plan: null,
          freshness: ProbeFreshness.live,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('live readings only'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
  });

  testWidgets('BLE on v1.1 firmware claims no such limit', (tester) async {
    // The notice is gated on the **capability**, not on the lane. From v1.1
    // Bluetooth carries whole cooks, and `BleTransport` reports that from the
    // device's own capability bits — so "live readings only" over a link that
    // is doing full history is the app being wrong about the device.
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
    expect(find.textContaining('live readings only'), findsNothing);
    // …and the link is still named, because that is a fact either way.
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
          // Reachable AND current: only then may the app speak for the base
          // station. `unknown` freshness means we have never had a reading,
          // which says nothing about what is plugged in.
          freshness: ProbeFreshness.live,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('No probes plugged in'), findsOneWidget);
  });

  testWidgets('an unreachable bridge never claims the jacks are empty', (
    tester,
  ) async {
    // Found on the bench, on real hardware. The reader rendered "No probes
    // plugged in — Plug a probe into the base station" two lines under its own
    // masthead saying "Can't reach your bridge. Last seen 3 minutes ago", on a
    // cooker that had four probes connected and reading.
    //
    // Whether a probe is plugged in is a fact about the *base station*, and
    // the only way to hold it is to have asked the bridge and been answered.
    // With no link there is no answer, so there is nothing to say — the
    // situation above already names the cause. §16.4 rule 9: absent is not
    // zero, and it is not "empty" either.
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
            link: LinkKind.offline,
          ),
          plan: null,
          freshness: ProbeFreshness.unknown,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('No probes plugged in'), findsNothing);
    // The jacks themselves still render, in place — §16.6.
    expect(find.text('PIT'), findsOneWidget);
  });

  testWidgets('a stale link stops speaking for the base station too', (
    tester,
  ) async {
    // A link can be up while the stream is dead — the exact failure this app
    // exists to catch. A jack that stopped reporting an hour ago says nothing
    // about what is plugged in this minute.
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
            link: LinkKind.ble,
          ),
          plan: null,
          freshness: ProbeFreshness.stale,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('No probes plugged in'), findsNothing);
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

  // ── §17.5 — the register scales with live state ─────────────────────

  group('the reader is warm until something claims a temperature', () {
    /// Nothing plugged in, no cook. §17.5's licensed state, exactly.
    DashboardSnapshot empty() => const DashboardSnapshot(
      probes: [
        ProbeView(probe: 1, role: ProbeRole.pit, name: 'Pit'),
        ProbeView(probe: 2, role: ProbeRole.food, name: 'Probe 2'),
        ProbeView(probe: 3, role: ProbeRole.food, name: 'Probe 3'),
        ProbeView(probe: 4, role: ProbeRole.food, name: 'Probe 4'),
      ],
      link: LinkKind.http,
      readingAtUnixMs: 1,
    );

    Future<void> pump(WidgetTester tester, DashboardSnapshot s) async {
      await tester.pumpWidget(
        _host(
          CookView(
            snapshot: s,
            plan: null,
            freshness: ProbeFreshness.live,
            onSetupCook: () {},
          ),
        ),
      );
      // Long enough for the identity tween to land; `pumpAndSettle` never
      // returns here because `PulseDot` breathes forever by design (§14.4.1).
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('an empty reader carries the warm cluster, not a grey glyph', (
      tester,
    ) async {
      await pump(tester, empty());
      expect(find.byKey(const Key('reader-warm-empty')), findsOneWidget);
      // The words did not change — they were written against §16.4 and warmth
      // is not a licence to rewrite reviewed copy.
      expect(find.text('No probes plugged in'), findsOneWidget);
      // Five category circles at full strength, plus one avatar per jack.
      final avatars = tester
          .widgetList<FoodAvatar>(find.byType(FoodAvatar))
          .toList();
      expect(avatars.where((a) => a.vivid).length, greaterThanOrEqualTo(9));
      expect(avatars.every((a) => a.vivid), isTrue);
    });

    testWidgets('one jack reporting cools the whole screen', (tester) async {
      // §17.5's designed moment. The rule is not "is the link up" — it is
      // "is anything here claiming a temperature".
      await pump(tester, empty());
      expect(find.byKey(const Key('reader-warm-empty')), findsOneWidget);

      await pump(
        tester,
        DashboardSnapshot(
          probes: [
            const ProbeView(
              probe: 1,
              role: ProbeRole.pit,
              name: 'Pit',
              tempF10: 2430,
            ),
            ...empty().probes.skip(1),
          ],
          link: LinkKind.http,
          readingAtUnixMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      expect(find.byKey(const Key('reader-warm-empty')), findsNothing);
      expect(
        tester
            .widgetList<FoodAvatar>(find.byType(FoodAvatar))
            .every((a) => a.vivid),
        isFalse,
      );
    });

    testWidgets('a cook with nothing plugged in stays disciplined', (
      tester,
    ) async {
      // A plan on screen means the app is watching, even with four empty
      // jacks — so the register goes with it and the notice is the grey one.
      await tester.pumpWidget(
        _host(
          CookView(
            snapshot: empty(),
            plan: _brisketPlan(),
            freshness: ProbeFreshness.live,
            onSetupCook: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('reader-warm-empty')), findsNothing);
      expect(find.text('No probes plugged in'), findsOneWidget);
    });
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

  DashboardSnapshot copyWithLink(LinkKind link, {bool fullHistory = true}) =>
      DashboardSnapshot(
        probes: probes,
        link: link,
        sessionName: sessionName,
        sessionActive: sessionActive,
        elapsedS: elapsedS,
        fullHistory: fullHistory,
      );

  DashboardSnapshot copyWithAge(int sAgo) => DashboardSnapshot(
    probes: probes,
    link: link,
    sessionName: sessionName,
    sessionActive: sessionActive,
    elapsedS: elapsedS,
    // The age the *reader* states is how long ago the reading reached this
    // phone, not the device's count of its base station's silence. Seeded as
    // an absolute instant because that is what the snapshot carries.
    readingAtUnixMs: DateTime.now().millisecondsSinceEpoch - sAgo * 1000,
  );
}
