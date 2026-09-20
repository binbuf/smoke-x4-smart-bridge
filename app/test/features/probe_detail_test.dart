/// `/live/probe/:jack`, state by state (design 16 §16.6, §16.7; newapp §C.2).
///
/// The route had **no tests at all**, which is most of why it drifted into
/// being the weakest screen in the app: an unconditional stale veil over a live
/// reading, an unknown age printed as `00:00:00`, a hero temperature that took
/// the OS text scale, a chart frozen at the moment you opened it, and one
/// dead-end empty state standing in for the whole ladder.
///
/// So this is §16.7's list, on this screen: **empty · loading · partial ·
/// stale · offline · error**, plus the three rules the reader's own suite
/// guards — never scale a temperature, every derived value disappears when
/// stale, absent is never zero — and the widths and text scale it must survive.
///
/// Behavioural, not pixel goldens: what is pinned is *what the screen says and
/// which elements exist*.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/food_glyph.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/design/typography.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/features/chart/cook_chart.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/live/probe_detail_route.dart';
import 'package:smoke_bridge/features/shell/shell_scope.dart';
import 'package:smoke_bridge/features/shell/shell_session.dart';
import 'package:smoke_bridge/ui/insight/insight_banner.dart';
import 'package:smoke_bridge/ui/probe/animated_temp.dart';
import 'package:smoke_bridge/ui/probe/food_avatar.dart';
import 'package:smoke_bridge/ui/probe/jack_badge.dart';
import 'package:smoke_bridge/ui/probe/temp_readout.dart';
import 'package:smoke_bridge/ui/state/stale_veil.dart';
import 'package:smoke_bridge/ui/state/states.dart';

// ── fixtures ──────────────────────────────────────────────────────────

/// A reading that arrived [ageS] seconds ago on the phone's clock — the fact
/// the freshness ladder actually runs on.
DashboardSnapshot _snap({
  int? ageS = 5,
  int? tempF10 = 2542,
  EtaResult? foodEta,
  bool foodStalled = false,
  double? rateFPerHr = 18,
  List<Sample> samples = const [
    Sample(t: 0, tempsF10: [2400, 1600, null, null]),
    Sample(t: 30, tempsF10: [2542, 1632, null, null]),
  ],
}) => DashboardSnapshot(
  probes: [
    ProbeView(
      probe: 1,
      role: ProbeRole.pit,
      name: 'Pit',
      tempF10: tempF10,
      rateFPerHr: rateFPerHr,
    ),
    ProbeView(
      probe: 2,
      role: ProbeRole.food,
      name: 'Brisket',
      tempF10: 1632,
      targetF10: 2030,
      eta: foodEta,
      stalled: foodStalled,
    ),
    const ProbeView(probe: 3, role: ProbeRole.food, name: 'Point'),
    const ProbeView(probe: 4, role: ProbeRole.food, name: 'Flat'),
  ],
  link: LinkKind.http,
  samples: samples,
  readingAtUnixMs: ageS == null
      ? null
      : DateTime.now().millisecondsSinceEpoch - ageS * 1000,
);

CookPlan _plan() => CookPlan(
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

/// The route under a seeded shell — the production composition, with no
/// radio, socket or database behind it.
Future<void> _pump(
  WidgetTester tester, {
  DashboardSnapshot? snapshot,
  CookPlan? plan,
  int jack = 1,
  Size size = const Size(400, 1400),
  double textScale = 1,
  bool withShell = true,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final route = ProbeDetailRoute(jack: jack);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        theme: SmokeTheme.dark,
        home: withShell
            ? ShellScope(
                session: ShellSession.seeded(snapshot: snapshot, plan: plan),
                activeIndex: 0,
                child: route,
              )
            : route,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

/// The hero reading, and only it.
///
/// A bare `find.textContaining('254')` used to be unambiguous. It is not any
/// more: §17.3 B added FireBoard's High / Avg / Low for the window on screen,
/// and over this fixture's two samples the pit's high **is** its current
/// reading. Two `254.2`s on one screen is the feature working — the hero says
/// where the probe is, the strip says what it has been doing — so the finder
/// got narrower rather than the screen getting quieter.
Finder get _heroReading => find.descendant(
  of: find.byType(TempReadout),
  matching: find.textContaining('254'),
);

void main() {
  // ── the ladder (§16.7) ──────────────────────────────────────────────

  group('the state ladder', () {
    testWidgets('loading — the reader for this jack, not a dead end', (
      tester,
    ) async {
      // No snapshot: the cache has not answered yet. That is a *reading*
      // state, not an empty one, and the old screen answered it with "Open
      // this from the live screen once the bridge is connected" — advice to
      // do the thing the user had just done, about a screen that renders
      // without a connection.
      await _pump(tester);
      expect(find.byKey(const Key('probe-detail')), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No readings yet.'), findsOneWidget);
      expect(find.textContaining('once the bridge is connected'), findsNothing);
      // Absent is the em dash, never 0 (§16.4 rule 9).
      expect(find.text('—'), findsOneWidget);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data, isNot('0'));
        expect(text.data, isNot('0.0'));
      }
    });

    testWidgets('no shell above it renders the same shape', (tester) async {
      // A direct-mount test, the lab, a cold deep link: there is no session
      // to read and inventing one would dial a radio from a widget.
      await _pump(tester, withShell: false);
      expect(find.byKey(const Key('probe-detail')), findsOneWidget);
      expect(find.text('Probe 1'), findsWidgets);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('empty — a jack this hardware does not have', (tester) async {
      // The one genuinely empty state, and the only one the empty state is
      // for. A path parameter is a string a user can type.
      await _pump(tester, jack: 7, snapshot: _snap());
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No such probe'), findsOneWidget);
      expect(find.byKey(const Key('probe-detail')), findsNothing);
    });

    testWidgets('partial — a reading, no history recorded on this phone', (
      tester,
    ) async {
      await _pump(tester, snapshot: _snap(samples: const []));
      expect(find.byType(CookChart), findsNothing);
      expect(find.byKey(const Key('probe-detail-no-history')), findsOneWidget);
      // The reading is still the hero: the chart is the thing that is missing.
      expect(_heroReading, findsOneWidget);
    });

    testWidgets('live — no veil, and the age reads as a reassurance', (
      tester,
    ) async {
      await _pump(tester, snapshot: _snap());
      // The veil is the app's honesty spine. Applied to a five-second-old
      // reading it dims the number to 55 %, desaturates the card and pins an
      // EMPTY advisory over it — which teaches a reader to ignore the one
      // component that must never be ignored.
      expect(find.byType(StaleVeil), findsNothing);
      expect(find.text('Updated just now.'), findsOneWidget);
      // …and the derived values are all present.
      expect(find.textContaining('°/hr'), findsOneWidget);
    });

    testWidgets('stale — veiled, aged in words, derived values REMOVED', (
      tester,
    ) async {
      // 5 minutes: past the ladder's 90 s `stale` rung and short of its 600 s
      // `frozen` one.
      await _pump(tester, snapshot: _snap(ageS: 5 * 60));
      expect(find.byType(StaleVeil), findsOneWidget);
      expect(find.text('Readings are 5m old.'), findsOneWidget);
      // `formatElapsed` printed a clock — 00:05:00 — where the whole app says
      // "5m", and it is not the reader's format either.
      expect(find.textContaining('00:'), findsNothing);
      // §16.7: derived values disappear rather than greying.
      expect(find.textContaining('°/hr'), findsNothing);
      // The veil already carries the age; the card must not repeat it.
      expect(find.textContaining('Updated'), findsNothing);
    });

    testWidgets('frozen — the stronger words, and still no zero', (
      tester,
    ) async {
      await _pump(tester, snapshot: _snap(ageS: 4 * 3600));
      expect(find.text('No readings for 4h.'), findsOneWidget);
      expect(find.textContaining('°/hr'), findsNothing);
    });

    testWidgets('an unknown age is a sentence, never 00:00:00', (tester) async {
      // §16.4 rule 9, and the bug it is written against: the old label was
      // `formatElapsed(lastPacketSAgo ?? 0)`, so "we do not know how old this
      // is" rendered as "Last reading 00:00:00 ago" — a device fact printed
      // from a default, which is the §16.6 prohibition restated.
      await _pump(
        tester,
        snapshot: DashboardSnapshot(
          probes: _snap().probes,
          link: LinkKind.offline,
          baseLost: true,
        ),
      );
      expect(find.text('No recent readings.'), findsOneWidget);
      expect(find.textContaining('00:00:00'), findsNothing);
    });

    testWidgets('offline — the last reading stays on screen', (tester) async {
      // Losing the link is not new data. The numbers are exactly as old as
      // they were a moment ago and the screen goes on answering its question.
      await _pump(tester, snapshot: _snap().disconnected());
      expect(_heroReading, findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('error — a detached probe reads "—", never 0', (tester) async {
      await _pump(
        tester,
        snapshot: _snap(tempF10: null, rateFPerHr: null, samples: const []),
      );
      expect(find.text('—'), findsOneWidget);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data, isNot('0'));
        expect(text.data, isNot('0.0'));
      }
    });
  });

  // ── the rules that are easiest to break by accident ─────────────────

  group('the temperature is never scaled', () {
    testWidgets('the hero goes through TempReadout, at a fixed 96 pt', (
      tester,
    ) async {
      await _pump(tester, snapshot: _snap());
      expect(find.byType(TempReadout), findsOneWidget);
      expect(SmokeType.heroTemp.fontSize, 96);
      for (final temp in tester.widgetList<AnimatedTemp>(
        find.byType(AnimatedTemp),
      )) {
        expect(temp.style.fontSize, 96.0);
      }
      // The unit letter travels with the number: `254.2°` and `254.2°F` are
      // different claims on a screen that can be switched to °C.
      expect(find.text('°F'), findsOneWidget);
    });

    testWidgets('200 % text scale grows the words, not the number', (
      tester,
    ) async {
      await _pump(
        tester,
        snapshot: _snap(),
        plan: _plan(),
        size: const Size(360, 2000),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      for (final temp in tester.widgetList<AnimatedTemp>(
        find.byType(AnimatedTemp),
      )) {
        // Unscaled: [TempReadout] wraps it in `withNoTextScaling`, so the
        // glyph is the same 96 pt it is at 100 %.
        expect(temp.style.fontSize, 96.0);
      }
      expect(find.text('Role'), findsOneWidget);
    });
  });

  group('every width', () {
    for (final width in [360.0, 600.0, 840.0]) {
      testWidgets('renders clean at ${width.round()} dp', (tester) async {
        await _pump(
          tester,
          snapshot: _snap(),
          plan: _plan(),
          size: Size(width, 1600),
        );
        expect(tester.takeException(), isNull);
        expect(_heroReading, findsOneWidget);
      });
    }
  });

  // ── §17.3 — identity, and the window statistics ─────────────────────

  group('identity leads the card', () {
    testWidgets('the jack badge and the food avatar, not the name again', (
      tester,
    ) async {
      await _pump(tester, jack: 2, snapshot: _snap(), plan: _plan());
      // The AppBar already carries "Brisket"; the header carries what a title
      // cannot — which jack, and what is on it.
      expect(find.byType(JackBadge), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      final avatar = tester.widget<FoodAvatar>(find.byType(FoodAvatar));
      expect(avatar.glyph, FoodGlyph.brisket);
      expect(
        avatar.vivid,
        isFalse,
        reason: 'a plan is running — §17.5 says this screen is watching',
      );
    });

    testWidgets('an unplugged jack with no cook is allowed to be warm', (
      tester,
    ) async {
      // §17.5: nothing here is claiming a temperature, so the guard has
      // nothing to guard.
      await _pump(
        tester,
        jack: 1,
        snapshot: _snap(tempF10: null, rateFPerHr: null, samples: const []),
      );
      expect(tester.widget<FoodAvatar>(find.byType(FoodAvatar)).vivid, isTrue);
    });
  });

  group('High / Avg / Low for the window on screen (§17.3 B)', () {
    testWidgets('three statistics, labelled with the span they cover', (
      tester,
    ) async {
      await _pump(tester, snapshot: _snap(), plan: _plan());
      expect(find.byKey(const Key('probe-window-stats')), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('AVG'), findsOneWidget);
      expect(find.text('LOW'), findsOneWidget);
      // The span, not the chip: a card headed "6H" over a window the user has
      // panned away from now would be a small lie.
      expect(find.textContaining('ON SCREEN ·'), findsOneWidget);
      // Two samples at 240.0 and 254.2 — the mean is computed, not guessed.
      expect(find.text('247.1°'), findsOneWidget);
    });

    testWidgets('they survive staleness, because they are not a claim about '
        'now', (tester) async {
      // §16.7 removes *derived* values when a reading goes stale, because a
      // derived value inherits "this is true now". A high over a stated window
      // does not make that claim, and the label is what keeps it honest.
      await _pump(tester, snapshot: _snap(ageS: 3000), plan: _plan());
      expect(find.byType(StaleVeil), findsOneWidget);
      expect(find.byKey(const Key('probe-window-stats')), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
    });

    testWidgets('a jack that recorded nothing says so in a sentence', (
      tester,
    ) async {
      // Absent is a sentence, never a row of dashes and never a 0.
      await _pump(tester, jack: 3, snapshot: _snap());
      expect(find.byKey(const Key('probe-window-stats')), findsOneWidget);
      expect(find.text('HIGH'), findsNothing);
      expect(
        find.text(
          'Nothing recorded for this probe in the stretch on screen.',
        ),
        findsOneWidget,
      );
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const Key('probe-window-stats')),
          matching: find.byType(Text),
        ),
      )) {
        expect(text.data, isNot('0'));
        expect(text.data, isNot('0.0°'));
      }
    });
  });

  // ── the chart (§C.2) ────────────────────────────────────────────────

  group('the chart', () {
    testWidgets('follows new samples instead of freezing at mount', (
      tester,
    ) async {
      // The screen's one question is "what is this probe doing over time".
      // `_viewport ??= …` answered it once, at mount, and then stopped: the
      // "Now" pill never appeared and `clipData` hid every sample that
      // arrived after you opened the screen.
      // A seeded session is immutable, so a *new* one lands in the scope —
      // the same thing a real snapshot arriving does, and the route's State
      // (which holds the viewport) survives it either way.
      late StateSetter rebuild;
      var snapshot = _snap();
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return ShellScope(
                session: ShellSession.seeded(snapshot: snapshot),
                activeIndex: 0,
                child: const ProbeDetailRoute(jack: 1),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final before = tester.widget<CookChart>(find.byType(CookChart)).viewport;
      expect(before.sessionToT, 30);

      rebuild(() {
        snapshot = _snap(
          samples: const [
            Sample(t: 0, tempsF10: [2400, 1600, null, null]),
            Sample(t: 30, tempsF10: [2542, 1632, null, null]),
            Sample(t: 900, tempsF10: [2551, 1700, null, null]),
          ],
        );
      });
      await tester.pump(const Duration(seconds: 1));
      final after = tester.widget<CookChart>(find.byType(CookChart)).viewport;
      expect(after.sessionToT, 900);
      expect(after.maxX, 900, reason: 'it is still following');
    });
  });

  // ── copy (§16.4) ────────────────────────────────────────────────────

  group('copy', () {
    testWidgets('a pit with a band says band, not "Target: Not set"', (
      tester,
    ) async {
      await _pump(tester, snapshot: _snap(), plan: _plan());
      expect(find.text('Target band'), findsOneWidget);
      expect(find.text('225°–275°'), findsOneWidget);
    });

    testWidgets('an ETA range answers under its label, once', (tester) async {
      await _pump(
        tester,
        jack: 2,
        snapshot: _snap(
          foodEta: const EtaRange(
            Duration(hours: 2),
            Duration(hours: 2, minutes: 30),
          ),
        ),
      );
      expect(find.text('Ready in'), findsOneWidget);
      expect(find.text('2h – 2h 30m'), findsOneWidget);
      // "Ready in · ETA 2h – 2h 30m" said the same word twice.
      expect(find.textContaining('ETA'), findsNothing);
    });

    testWidgets('an ETA refusal states its reason, and is not a value', (
      tester,
    ) async {
      await _pump(
        tester,
        jack: 2,
        snapshot: _snap(
          foodEta: const EtaUnavailable(EtaUnavailableReason.slopeTooFlat),
        ),
      );
      expect(
        find.text('No estimate — the temperature is holding steady.'),
        findsOneWidget,
      );
      // §D.5: a refusal is an answer, but never the answer to "Ready in".
      expect(find.text('Ready in'), findsNothing);
      // …and it is never rendered as the value of a row in the facts table.
      expect(find.text('Estimate'), findsNothing);
    });

    testWidgets('a pit outside its band says so in words', (tester) async {
      // §16.5's colour rule: a status hue always travels with an icon AND a
      // word. The reader's gauge goes amber and red on this exact condition.
      await _pump(
        tester,
        snapshot: _snap(tempF10: 2900),
        plan: _plan(),
      );
      expect(find.text('Pit is above the band'), findsOneWidget);
      expect(find.text('225°–275°'), findsWidgets);
    });

    testWidgets('the alarms card does not promise a section it cannot open', (
      tester,
    ) async {
      await _pump(tester, snapshot: _snap());
      expect(find.byKey(const Key('probe-detail-alarms')), findsOneWidget);
      // It pushes `/device/alarms`, which takes no probe argument.
      expect(find.textContaining('that probe'), findsNothing);
      expect(
        find.text('Every rule on this bridge, in one editor.'),
        findsOneWidget,
      );
    });

    testWidgets('a stall is one strip, not a row and a strip', (tester) async {
      await _pump(tester, jack: 2, snapshot: _snap(foodStalled: true));
      expect(find.text('Stalled'), findsOneWidget);
      expect(
        tester
            .widgetList<InsightBanner>(find.byType(InsightBanner))
            .where((b) => b.kind == InsightKind.stall)
            .length,
        1,
      );
      // It used to be both: a strip on the reader and a "Stall — In a stall,
      // the estimate is paused" row in this screen's facts table.
      expect(find.text('Stall'), findsNothing);
    });
  });
}
