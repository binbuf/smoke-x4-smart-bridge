/// The reader, state by state (design 16 §16.6, §16.7).
///
/// §16.7's definition of done is a list, and this is that list: **empty ·
/// loading · partial · stale · offline · error · permission-blocked**, plus the
/// three rules that are easiest to break by accident and hardest to notice —
/// the colour separation, "never scale a temperature", and "no `Duration`
/// literal under `lib/ui/`".
///
/// These are behavioural, not pixel goldens: what is pinned is *what the screen
/// says and which elements exist*, so a layout retune does not red-light and a
/// probe silently reading `0 °F` does.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/design/tokens.dart';
import 'package:smoke_bridge/design/series_palette.dart';
import 'package:smoke_bridge/design/status_palette.dart';
import 'package:smoke_bridge/design/typography.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/domain/situation/situation.dart';
import 'package:smoke_bridge/features/cook/cook_view.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/live/reader_actions.dart';
import 'package:smoke_bridge/features/live/situation_banner.dart';
import 'package:smoke_bridge/ui/probe/animated_temp.dart';
import 'package:smoke_bridge/ui/probe/probe_freshness.dart';
import 'package:smoke_bridge/ui/probe/probe_strip_row.dart';
import 'package:smoke_bridge/ui/probe/sparkline.dart';
import 'package:smoke_bridge/ui/probe/target_gauge.dart';

// ── fixtures ──────────────────────────────────────────────────────────

const List<ValuePoint> _recent = [
  (t: 0, f: 240.0),
  (t: 30, f: 241.5),
  (t: 60, f: 243.0),
];

DashboardSnapshot _reading({
  LinkKind link = LinkKind.http,
  int? sAgo,
  bool detached = false,
  List<Sample> samples = const [
    Sample(t: 0, tempsF10: [2400, 1600, null, null]),
    Sample(t: 30, tempsF10: [2430, 1632, null, null]),
  ],
}) => DashboardSnapshot(
  probes: [
    ProbeView(
      probe: 1,
      role: ProbeRole.pit,
      name: 'Pit',
      tempF10: detached ? null : 2430,
      rateFPerHr: detached ? null : 18,
      recent: detached ? const [] : _recent,
    ),
    ProbeView(
      probe: 2,
      role: ProbeRole.food,
      name: 'Brisket',
      tempF10: detached ? null : 1632,
      rateFPerHr: detached ? null : 12,
      recent: detached ? const [] : _recent,
    ),
    const ProbeView(probe: 3, role: ProbeRole.food, name: 'Point'),
    const ProbeView(probe: 4, role: ProbeRole.food, name: 'Flat'),
  ],
  link: link,
  // How long ago the reading reached this phone — the ladder's only input.
  readingAtUnixMs: sAgo == null
      ? null
      : DateTime.now().millisecondsSinceEpoch - sAgo * 1000,
  samples: samples,
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

Widget _host(Widget child) => MaterialApp(
  theme: SmokeTheme.dark,
  home: Scaffold(body: child),
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
      child: _host(child),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  // ── the ladder (§16.7) ──────────────────────────────────────────────

  group('the state ladder', () {
    testWidgets('empty — four detached jacks render IN PLACE, never as 0', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(detached: true, samples: const []),
          plan: null,
          // Live, because the notice speaks for the base station and may only
          // do so on a link that is actually current — see the bench
          // regression in cook_view_test.
          freshness: ProbeFreshness.live,
          showChrome: false,
        ),
      );

      // §16.6: the probes render in place. The explanation appears ABOVE them
      // — it does not replace them, because a jack that vanishes reads as an
      // app bug rather than as an empty jack.
      expect(find.byType(ProbeStripRow), findsNWidgets(4));
      expect(find.text('No probes plugged in'), findsOneWidget);
      expect(find.text('PIT'), findsOneWidget);
      expect(find.text('unplugged'), findsNWidgets(4));
      expect(find.text('—'), findsNWidgets(4));

      // The M0 invariant, at the last layer before pixels.
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data, isNot('0'));
        expect(text.data, isNot('0.0'));
      }
    });

    testWidgets('loading — the reader, not a spinner', (tester) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(
            link: LinkKind.offline,
            detached: true,
            samples: const [],
          ),
          plan: null,
          freshness: ProbeFreshness.unknown,
          showChrome: false,
        ),
      );
      // §B.3 — the layout is the same one the values will land into, so
      // nothing reflows and no number ever flickers out of a spinner.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ProbeStripRow), findsNWidgets(4));
      expect(find.text('No readings yet.'), findsOneWidget);
    });

    testWidgets('partial — a live jack and a dead one, side by side', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
        ),
      );
      expect(find.text('unplugged'), findsNWidgets(2));
      expect(find.text('—'), findsNWidgets(2));
      expect(find.textContaining('243'), findsOneWidget);
    });

    testWidgets('a fresh row draws its recent history and its rate', (
      tester,
    ) async {
      // The paired half of the staleness assertion below: it only means
      // something if these are here when the readings are current. Pumped
      // wide, because the row spends width on the number first and a
      // sparkline squeezed into 30 dp is decoration, not data.
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
        ),
        size: const Size(900, 900),
      );
      expect(find.byType(Sparkline), findsNWidgets(2));
      expect(find.textContaining('°/hr'), findsNWidgets(2));
    });

    testWidgets('stale — derived values are REMOVED, not greyed', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(sAgo: 14 * 60),
          plan: null,
          freshness: ProbeFreshness.stale,
          showChrome: false,
        ),
      );
      // The rows are still there with their readings…
      expect(find.byType(ProbeStripRow), findsNWidgets(4));
      // …and every value derived FROM those readings is gone.
      expect(find.byType(Sparkline), findsNothing);
      expect(find.textContaining('°/hr'), findsNothing);
      // The veil pins the age, and the masthead does not repeat it.
      expect(find.text('Readings are 14m old.'), findsOneWidget);
      expect(find.textContaining('Updated'), findsNothing);
    });

    testWidgets('offline — the last-seen rides the masthead, not a banner', (
      tester,
    ) async {
      const outOfRange = Situation(
        kind: SituationKind.bridgeOutOfRange,
        headline: 'Can’t reach your bridge',
        detail: 'Last seen 12 minutes ago. It is still recording on its own.',
        automatic: true,
      );
      await _pump(
        tester,
        CookView(
          snapshot: _reading(link: LinkKind.offline),
          plan: null,
          freshness: ProbeFreshness.live,
          situation: outOfRange,
          showChrome: false,
        ),
      );
      // §16.3 — this one deliberately raises no banner: the transport chip
      // already says offline, and two elements saying one thing is how people
      // learn to read neither. It still carries the last-seen, which is the
      // difference between a state and information.
      expect(find.byType(SituationBanner), findsNothing);
      expect(find.text('Can’t reach your bridge'), findsOneWidget);
      expect(find.textContaining('Last seen 12 minutes ago'), findsOneWidget);
      expect(find.byType(ProbeStripRow), findsNWidgets(4));
    });

    testWidgets('error — a situation names the cause and offers one action', (
      tester,
    ) async {
      var acted = 0;
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
          situation: const Situation(
            kind: SituationKind.bridgeWasReset,
            headline: 'This is a different bridge',
            detail: 'Your saved cooks stay on this phone either way.',
            actionLabel: 'Use this bridge instead',
          ),
          onSituationAction: () => acted++,
        ),
      );
      expect(find.text('This is a different bridge'), findsOneWidget);
      // Exactly one action (§16.4 rule 6).
      expect(find.byKey(const Key('situation-action')), findsOneWidget);
      await tester.tap(find.byKey(const Key('situation-action')));
      expect(acted, 1);
      // And it never covers the numbers.
      expect(find.byType(ProbeStripRow), findsNWidgets(4));
      expect(find.textContaining('243'), findsOneWidget);
    });

    testWidgets('permission-blocked — names the permission, not the API', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
          situation: reconcile(
            const SituationFacts(
              rememberedBridgeId: 'b',
              missingPermission: 'Nearby devices',
            ),
          ),
          onSituationAction: () {},
        ),
      );
      expect(find.text('Nearby devices is off'), findsOneWidget);
      expect(find.text('Allow Nearby devices'), findsOneWidget);
      expect(find.textContaining('BLUETOOTH_SCAN'), findsNothing);
    });
  });

  // ── the situation banner (§16.3) ────────────────────────────────────

  group('the situation banner', () {
    testWidgets('healthy renders nothing at all — never a green all-well bar', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
        ),
      );
      expect(find.byType(SituationBanner), findsNothing);
    });

    testWidgets('an automatic situation reports; it does not ask', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
          situation: const Situation(
            kind: SituationKind.bridgeHostingOwnNetwork,
            headline: 'Your bridge is hosting its own network',
            detail: 'Nothing has been lost — it has been recording all along.',
            actionLabel: 'Put it back on your Wi-Fi',
            automatic: true,
          ),
          onSituationAction: () {},
        ),
      );
      expect(
        find.text('Your bridge is hosting its own network'),
        findsOneWidget,
      );
      // §16.3 — act, then report. A banner offering to do a thing the app
      // could simply have done is an app making its problem the user's.
      expect(find.byKey(const Key('situation-action')), findsNothing);
    });

    testWidgets(
      'an unpaired base station is situation #8, not "plug a probe"',
      (tester) async {
        await _pump(
          tester,
          CookView(
            snapshot: _reading(),
            plan: null,
            freshness: ProbeFreshness.live,
            paired: false,
            showChrome: false,
            onPair: () {},
          ),
        );
        expect(find.textContaining('met your Smoke X yet'), findsOneWidget);
        expect(find.textContaining('Plug a probe'), findsNothing);
        expect(find.text('Pair the base station'), findsOneWidget);
      },
    );

    testWidgets('the banner is chrome: icon AND word, and the words are ink', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
          situation: const Situation(
            kind: SituationKind.bluetoothOff,
            headline: 'Bluetooth is off',
            detail: 'The bridge is still recording either way.',
          ),
        ),
      );
      final banner = find.byType(SituationBanner);
      expect(
        find.descendant(of: banner, matching: find.byType(Icon)),
        findsOneWidget,
      );
      final headline = tester.widget<Text>(
        find.descendant(of: banner, matching: find.text('Bluetooth is off')),
      );
      expect(headline.style?.color, SmokeTokens.dark.textHi);

      // Never green: green is transport health and nothing else.
      for (final box in tester.widgetList<Container>(
        find.descendant(of: banner, matching: find.byType(Container)),
      )) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration) {
          expect(decoration.color, isNot(StatusPalette.positive));
        }
      }
    });
  });

  // ── the action row (§16.6) ──────────────────────────────────────────

  group('the action row', () {
    testWidgets('all four, and the cook verb names the outcome', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
          onAddMark: () {},
          onSetupCook: () {},
          onExport: () {},
          onTestAlarm: () {},
        ),
      );
      expect(find.text('Mark'), findsOneWidget);
      expect(find.text('Set a target'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('Test alarm'), findsOneWidget);
    });

    testWidgets('a running cook flips the second slot to Edit cook', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: _plan(),
          freshness: ProbeFreshness.live,
          showChrome: false,
          nowUnixMs: 1,
          onSetupCook: () {},
        ),
        // Tall enough that the strip is built: a `ListView` does not lay out
        // what has never been on screen.
        size: const Size(400, 1800),
      );
      expect(find.text('Edit cook'), findsOneWidget);
      expect(find.text('Set a target'), findsNothing);
    });

    testWidgets('offline dims Mark and prints its reason on screen', (
      tester,
    ) async {
      var marks = 0;
      await _pump(
        tester,
        CookView(
          snapshot: _reading(link: LinkKind.offline),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
          onAddMark: () => marks++,
          onSetupCook: () {},
        ),
      );
      // §16.7 — no control is dead: absent, or disabled with its reason on
      // screen. It is still there, so it can come back when the link does.
      expect(find.text('Mark'), findsOneWidget);
      expect(find.textContaining('marking needs a connection'), findsOneWidget);
      await tester.tap(find.text('Mark'));
      expect(marks, 0);
    });

    testWidgets('nothing recorded dims Export, with its reason', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(samples: const []),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
          onExport: () {},
        ),
      );
      expect(find.text('Export'), findsOneWidget);
      expect(find.textContaining('no readings on this phone'), findsOneWidget);
    });

    testWidgets('with nothing wired the strip is absent, not four dead cells', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
        ),
      );
      expect(find.byType(ReaderActionRow), findsNothing);
    });
  });

  // ── the rules that are easiest to break by accident ─────────────────

  group('the colour rule', () {
    testWidgets('no series hue ever carries a word', (tester) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: _plan(),
          freshness: ProbeFreshness.live,
          nowUnixMs: 1,
          showChrome: false,
          onSetupCook: () {},
        ),
      );
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(
          ProbePalette.dark.contains(text.style?.color),
          isFalse,
          reason:
              '"${text.data}" is painted in a series hue. A series hue is a '
              'mark — a stroke, an arc, a ≤12 dp dot, a left rule — and may '
              'never carry a word (§16.5).',
        );
      }
    });

    testWidgets('reaching a target closes the ring; it does not turn green', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: DashboardSnapshot(
            probes: _reading().probes
                .map(
                  (p) => p.probe == 2
                      ? ProbeView(
                          probe: 2,
                          role: ProbeRole.food,
                          name: 'Brisket',
                          tempF10: 2050,
                          targetF10: 2030,
                        )
                      : p,
                )
                .toList(),
            link: LinkKind.http,
          ),
          plan: _plan(),
          freshness: ProbeFreshness.live,
          nowUnixMs: 1,
          showChrome: false,
        ),
      );
      // The word travels with the shape.
      expect(find.textContaining('Reached'), findsOneWidget);
      final gauge = tester.widgetList<TargetGauge>(find.byType(TargetGauge));
      expect(gauge.where((g) => g.reached), isNotEmpty);
      for (final box in tester.widgetList<Container>(find.byType(Container))) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration) {
          expect(decoration.color, isNot(StatusPalette.positive));
        }
      }
    });
  });

  group('the temperature is never scaled', () {
    testWidgets('the hero renders at a fixed 96 pt, unfitted', (tester) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: _plan(),
          freshness: ProbeFreshness.live,
          nowUnixMs: 1,
          showChrome: false,
        ),
        size: const Size(360, 900),
      );
      expect(tester.takeException(), isNull);
      expect(
        SmokeType.heroTemp.fontSize,
        96,
        reason: 'The hero style itself must not be retuned to make room.',
      );
      // The style reaches AnimatedTemp unmodified — nothing between the token
      // and the glyph is allowed to renegotiate the size.
      for (final temp in tester.widgetList<AnimatedTemp>(
        find.byType(AnimatedTemp),
      )) {
        expect(temp.style.fontSize, anyOf(96.0, 56.0, 34.0));
      }
      // The gauge is the flexible child: on a 360 dp phone it gives way, and
      // it is the ONLY thing that does.
      final gauges = tester.widgetList<TargetGauge>(find.byType(TargetGauge));
      expect(gauges, isNotEmpty);
      for (final g in gauges) {
        expect(g.size, lessThanOrEqualTo(84.0));
        expect(g.size, greaterThanOrEqualTo(56.0));
      }
    });

    testWidgets('200 % text scale grows the words, not the number', (
      tester,
    ) async {
      await _pump(
        tester,
        CookView(
          snapshot: _reading(),
          plan: null,
          freshness: ProbeFreshness.live,
          showChrome: false,
          onAddMark: () {},
          onSetupCook: () {},
          onExport: () {},
          onTestAlarm: () {},
        ),
        size: const Size(360, 1400),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Mark'), findsOneWidget);
    });
  });

  group('every width', () {
    for (final width in [360.0, 600.0, 840.0]) {
      testWidgets('the reader renders clean at ${width.round()} dp', (
        tester,
      ) async {
        await _pump(
          tester,
          CookView(
            snapshot: _reading(),
            plan: _plan(),
            freshness: ProbeFreshness.live,
            nowUnixMs: 1,
            showChrome: false,
            onAddMark: () {},
            onSetupCook: () {},
            onExport: () {},
            onTestAlarm: () {},
          ),
          size: Size(width, 1200),
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('243'), findsOneWidget);
      });
    }
  });

  // ── layering ────────────────────────────────────────────────────────

  test('no widget under lib/ui writes a Duration literal', () {
    // The motion tokens are the single seam where
    // `MediaQuery.disableAnimations` is honoured. One literal anywhere under
    // `lib/ui/` defeats it silently, for exactly the user who asked for it.
    // Word-boundaried, so `formatDuration(` — a pure string helper — is not
    // mistaken for the constructor.
    final literal = RegExp(r'(?<![A-Za-z0-9_$])Duration\(');
    final offenders = <String>[];
    for (final entity in Directory('lib/ui').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      for (final line in const LineSplitter().convert(source)) {
        if (literal.hasMatch(line) && !line.trimLeft().startsWith('///')) {
          offenders.add('${entity.path}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use SmokeMotion.of(context) — see lib/design/motion.dart.\n'
          '${offenders.join('\n')}',
    );
  });
}
