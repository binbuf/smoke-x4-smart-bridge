/// The strips under a hero number, and the two rules they were breaking
/// (design 16 §16.4, §16.5, §16.7; newapp §D.5).
///
/// Three separate faults, all of them the same shape — **a claim the reading
/// no longer supports, or a hue with no word beside it.**
///
///  * "Ready in · ETA unavailable — holding steady": a refusal rendered as the
///    *value* of a label promising a duration, because one formatter returned
///    both answers and refusals and the guard against it (`eta != noValue`)
///    could never fire.
///  * "✓ Reached 203°" surviving into `frozen`, four hours after the last
///    reading, while the gauge that derived it had already been removed.
///  * A pit leaving its band turning the gauge arc amber and its dot red, with
///    **no `InsightKind.band` call site anywhere in the app** — a status hue
///    carrying a verdict entirely on its own.
///
/// Plus the layout fault that would have hidden all three at 200 %: the strip
/// itself could not survive a long string.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/core/format.dart';
import 'package:smoke_bridge/design/status_palette.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/ui/insight/insight_banner.dart';
import 'package:smoke_bridge/ui/probe/probe_freshness.dart';
import 'package:smoke_bridge/ui/probe/probe_hero_card.dart';
import 'package:smoke_bridge/ui/probe/probe_pills.dart';

// ── fixtures ──────────────────────────────────────────────────────────

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

ProbeView _food({
  int? tempF10 = 1632,
  EtaResult? eta,
  bool stalled = false,
  double? rateFPerHr = 12,
}) => ProbeView(
  probe: 2,
  role: ProbeRole.food,
  name: 'Brisket',
  tempF10: tempF10,
  targetF10: 2030,
  rateFPerHr: rateFPerHr,
  eta: eta,
  stalled: stalled,
);

ProbeView _pit({int? tempF10 = 2430}) => ProbeView(
  probe: 1,
  role: ProbeRole.pit,
  name: 'Pit',
  tempF10: tempF10,
  rateFPerHr: 18,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(400, 900),
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        theme: SmokeTheme.dark,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  // ── the ETA (§D.5, §16.4 rules 3 and 5) ─────────────────────────────

  group('an ETA answer', () {
    testWidgets('is a duration under its own label, with "ETA" said once', (
      tester,
    ) async {
      await _pump(
        tester,
        ProbeHeroCard(
          view: _food(
            eta: const EtaRange(
              Duration(hours: 2),
              Duration(hours: 2, minutes: 30),
            ),
          ),
          plan: _plan(),
          freshness: ProbeFreshness.live,
        ),
      );
      expect(find.text('Ready in'), findsOneWidget);
      expect(find.text('2h – 2h 30m'), findsOneWidget);
      // It used to read "Ready in · ETA 2h – 2h 30m".
      expect(find.textContaining('ETA'), findsNothing);
    });

    testWidgets('a single-valued range does not print a range', (tester) async {
      await _pump(
        tester,
        ProbeHeroCard(
          view: _food(
            eta: const EtaRange(Duration(hours: 3), Duration(hours: 3)),
          ),
          plan: _plan(),
          freshness: ProbeFreshness.live,
        ),
      );
      expect(find.text('3h'), findsOneWidget);
    });
  });

  group('an ETA refusal', () {
    // §D.5: "it refuses with a stated reason". Every one of these was
    // previously rendered as the value of "Ready in".
    const cases = {
      EtaUnavailableReason.slopeTooFlat:
          'No estimate — the temperature is holding steady.',
      EtaUnavailableReason.targetAtOrAbovePit:
          'No estimate — the pit is not hotter than the target.',
      EtaUnavailableReason.insufficientHistory:
          'No estimate yet — not enough history.',
      EtaUnavailableReason.notApproaching:
          'No estimate — the temperature is falling.',
      EtaUnavailableReason.stalled: 'No estimate while it is in a stall.',
    };

    for (final entry in cases.entries) {
      testWidgets('${entry.key.name} states its reason as a sentence', (
        tester,
      ) async {
        await _pump(
          tester,
          ProbeHeroCard(
            view: _food(eta: EtaUnavailable(entry.key)),
            plan: _plan(),
            freshness: ProbeFreshness.live,
          ),
        );
        expect(find.text(entry.value), findsOneWidget);
        // The label IS the reason. It is never a value handed to a label
        // that promised a duration.
        expect(find.text('Ready in'), findsNothing);
      });
    }

    test('every reason is one sentence, ends in a full stop, no jargon', () {
      for (final reason in EtaUnavailableReason.values) {
        final s = formatEtaRefusal(EtaUnavailable(reason));
        expect(s, endsWith('.'));
        // §16.4 rule 5 — sentence case, one idea. Two full stops is two ideas.
        expect('.'.allMatches(s).length, 1, reason: s);
        // §16.4 rule 3 — no jargon, and no acronym the label already said.
        expect(s, isNot(contains('ETA')));
      }
    });

    test('an answer never carries the word its label does', () {
      expect(
        formatEtaSpan(
          const EtaRange(Duration(hours: 1), Duration(hours: 1, minutes: 30)),
        ),
        '1h – 1h 30m',
      );
    });
  });

  group('a stall', () {
    testWidgets('says what it costs, not only what it is', (tester) async {
      await _pump(
        tester,
        ProbeHeroCard(
          view: _food(stalled: true),
          plan: _plan(),
          freshness: ProbeFreshness.live,
        ),
      );
      expect(find.text('Stalled'), findsOneWidget);
      // The estimate that was on this strip a moment ago is gone; the strip
      // says so rather than leaving a disappearance to be noticed.
      expect(find.text('Estimate paused'), findsOneWidget);
    });
  });

  // ── "Reached" is derived, and dies with its reading (§16.7) ─────────

  group('the reached pill', () {
    testWidgets('says so while the reading is live', (tester) async {
      await _pump(
        tester,
        ProbeHeroCard(
          view: _food(tempF10: 2050),
          plan: _plan(),
          freshness: ProbeFreshness.live,
        ),
      );
      expect(find.textContaining('Reached'), findsOneWidget);
    });

    for (final freshness in [ProbeFreshness.stale, ProbeFreshness.frozen]) {
      testWidgets('does not outlive the reading at ${freshness.name}', (
        tester,
      ) async {
        await _pump(
          tester,
          ProbeHeroCard(
            view: _food(tempF10: 2050),
            plan: _plan(),
            freshness: freshness,
          ),
        );
        // §16.7 — every derived value disappears when stale rather than
        // greying, and "Reached" is a comparison of a temperature against a
        // target, which makes it as derived as the ring that was already
        // being removed beside it. It asserted, in the present tense, from a
        // four-hour-old number.
        expect(find.textContaining('Reached'), findsNothing);
        // The target itself is configuration, not a derived value, so it
        // stays — the pill drops back to saying what was asked for.
        final pills = tester.widgetList<TargetPill>(find.byType(TargetPill));
        expect(pills.single.reached, isFalse);
        expect(find.textContaining('Target'), findsOneWidget);
      });
    }
  });

  // ── the band verdict (§16.5's colour rule) ──────────────────────────

  group('the pit band', () {
    testWidgets('in the band says nothing at all', (tester) async {
      await _pump(
        tester,
        ProbeHeroCard(
          view: _pit(),
          plan: _plan(),
          freshness: ProbeFreshness.live,
        ),
      );
      expect(find.textContaining('the band'), findsNothing);
    });

    testWidgets('above the band carries an icon AND a word', (tester) async {
      await _pump(
        tester,
        ProbeHeroCard(
          view: _pit(tempF10: 2900),
          plan: _plan(),
          freshness: ProbeFreshness.live,
        ),
      );
      final strip = find.byType(InsightBanner);
      expect(find.text('Pit is above the band'), findsOneWidget);
      expect(
        find.descendant(of: strip, matching: find.byType(Icon)),
        findsOneWidget,
      );
      // The band it left, so the verdict is checkable rather than absolute.
      expect(find.text('225°–275°'), findsOneWidget);
    });

    testWidgets('below the band says below', (tester) async {
      await _pump(
        tester,
        ProbeHeroCard(
          view: _pit(tempF10: 1800),
          plan: _plan(),
          freshness: ProbeFreshness.live,
        ),
      );
      expect(find.text('Pit is below the band'), findsOneWidget);
    });

    testWidgets('a stale pit says nothing — the verdict is derived too', (
      tester,
    ) async {
      await _pump(
        tester,
        ProbeHeroCard(
          view: _pit(tempF10: 2900),
          plan: _plan(),
          freshness: ProbeFreshness.stale,
        ),
      );
      expect(find.textContaining('the band'), findsNothing);
    });
  });

  // ── the strip survives its own copy (§16.7) ─────────────────────────

  group('InsightBanner', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('does not overflow at ${scale}x on a 360 dp phone', (
        tester,
      ) async {
        await _pump(
          tester,
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                InsightBanner(
                  kind: InsightKind.eta,
                  label: 'No estimate — the temperature is holding steady.',
                ),
                SizedBox(height: 8),
                InsightBanner(
                  kind: InsightKind.eta,
                  label: 'Ready in',
                  trailing: '2h – 2h 30m',
                ),
                SizedBox(height: 8),
                InsightBanner(
                  kind: InsightKind.band,
                  label: 'Pit is above the band',
                  trailing: '225°–275°',
                ),
              ],
            ),
          ),
          size: const Size(360, 900),
          textScale: scale,
        );
        // A trailing beside an `Expanded` label is a non-flex child of a Row:
        // laid out against unbounded width, so it never wrapped and never
        // ellipsised — it overflowed, and the strip carrying this app's
        // honesty rendered as a yellow-and-black bar.
        expect(tester.takeException(), isNull);
        expect(find.text('Ready in'), findsOneWidget);
        expect(find.text('2h – 2h 30m'), findsOneWidget);
      });
    }

    testWidgets('the words are ink, never the hue (§16.5)', (tester) async {
      await _pump(
        tester,
        const InsightBanner(
          kind: InsightKind.band,
          label: 'Pit is above the band',
          trailing: '225°–275°',
        ),
      );
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.style?.color, isNot(StatusPalette.warning));
        expect(text.style?.color, isNot(StatusPalette.critical));
      }
    });
  });
}
