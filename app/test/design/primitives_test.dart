/// N3.12–N3.30 — the invariants each primitive encodes.
///
/// These are behaviour tests, not snapshots: each one would fail if a later
/// change broke the rule the primitive exists to enforce (I5, I6, I14, the
/// colour channels, absent≠zero, no double-dimming).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: SmokeThemeData.dark(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

void main() {
  group('colour channels', () {
    testWidgets('an insight banner always carries an icon and a word', (
      tester,
    ) async {
      await _pump(
        tester,
        const InsightBanner(
          message: 'Full history needs Wi-Fi.',
          severity: BannerSeverity.warn,
        ),
      );
      expect(find.text('Warning'), findsOneWidget);
      expect(find.text('Full history needs Wi-Fi.'), findsOneWidget);
      expect(find.byType(SmokeIcon), findsOneWidget);
    });

    testWidgets('banner copy is always textHi', (tester) async {
      await _pump(tester, const InsightBanner(message: 'Hello'));
      final tokens = SmokeTokens.dark();
      final copy = tester.widget<Text>(find.text('Hello'));
      expect(copy.style?.color, tokens.textHi);
    });

    testWidgets('a capability notice says Note', (tester) async {
      await _pump(
        tester,
        const CapabilityNotice(message: 'Jack 4 is the grate by default.'),
      );
      expect(find.text('Note'), findsOneWidget);
    });

    test('target reached closes the ring and is never green', () {
      expect(TargetGauge.isReached(205, 203), isTrue);
      expect(TargetGauge.isReached(150, 203), isFalse);
      expect(TargetGauge.isReached(150, null), isFalse);

      final tokens = SmokeTokens.dark();
      const gauge = TargetGauge(
        value: 205,
        min: 70,
        max: 210,
        target: 203,
        color: Color(0xFF9085E9),
        center: 'DONE',
        caption: 'target',
      );
      // The gauge's colour is the series mark, unchanged by reaching target.
      expect(gauge.color, isNot(tokens.positive));
      expect(gauge.color, isNot(tokens.pit));
    });

    testWidgets('a done gauge renders DONE, not a green word', (tester) async {
      await _pump(
        tester,
        const Center(
          child: TargetGauge(
            value: 205,
            min: 70,
            max: 210,
            target: 203,
            color: Color(0xFF9085E9),
            center: 'DONE',
          ),
        ),
      );
      expect(find.text('DONE'), findsOneWidget);
      final tokens = SmokeTokens.dark();
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.style?.color, isNot(tokens.positive));
      }
    });

    test('food identity stops never reuse a status hue', () {
      final t = SmokeTokens.dark();
      final status = <Color>[t.positive, t.warning, t.critical, t.info, t.pit];
      for (final glyph in FoodGlyph.values) {
        for (final register in FoodAvatarRegister.values) {
          final (a, b) = FoodAvatar.stopsFor(glyph, register);
          expect(status, isNot(contains(a)), reason: '$glyph/$register start');
          expect(status, isNot(contains(b)), reason: '$glyph/$register end');
        }
      }
    });
  });

  group('absent is not zero (I3)', () {
    testWidgets('a detached jack shows a dash, never 0', (tester) async {
      await _pump(tester, const JackBadge(jack: 4, detached: true));
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('an attached jack shows its number', (tester) async {
      await _pump(tester, const JackBadge(jack: 3));
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('no dead controls (I5)', () {
    testWidgets('a disabled settings row states its reason', (tester) async {
      await _pump(
        tester,
        const SettingsRow(
          icon: SmokeGlyph.upload,
          name: 'Update firmware',
          sub: 'Over Wi-Fi only',
          disabledReason: 'Bridge is not on Wi-Fi',
        ),
      );
      expect(find.text('Bridge is not on Wi-Fi'), findsOneWidget);
      final tappable = tester
          .widgetList<InkWell>(find.byType(InkWell))
          .where((w) => w.onTap != null);
      expect(tappable, isEmpty);
    });

    testWidgets('a disabled primary action states its reason', (tester) async {
      await _pump(
        tester,
        const PrimaryAction(
          label: 'Join Wi-Fi first',
          onPressed: null,
          enabledReason: 'An image is Wi-Fi only',
        ),
      );
      expect(find.text('An image is Wi-Fi only'), findsOneWidget);
    });

    testWidgets('a disabled button in an action row states its reason', (
      tester,
    ) async {
      await _pump(
        tester,
        const ActionRow(
          actions: <SmokeActionSpec>[
            SmokeActionSpec(
              label: 'Pull',
              onPressed: null,
              reason: 'No target set',
            ),
          ],
        ),
      );
      expect(find.text('No target set'), findsOneWidget);
    });
  });

  group('no state without a next step (I6)', () {
    testWidgets('each state surface has exactly one action', (tester) async {
      final states = <Widget>[
        EmptyState(
          title: 'No probes',
          copy: 'Plug one in.',
          actionLabel: 'View graph',
          onAction: () {},
        ),
        ProblemState(
          title: 'Unreachable',
          copy: 'Retrying.',
          actionLabel: 'Reconnect',
          onAction: () {},
        ),
        LoadingState(
          title: 'Finding',
          copy: 'Checking.',
          actionLabel: 'Cancel',
          onAction: () {},
        ),
      ];
      for (final state in states) {
        await _pump(tester, state);
        expect(
          find.byType(PrimaryAction),
          findsOneWidget,
          reason: 'a state surface must have exactly one action',
        );
      }
    });
  });

  group('one ember primary action (I14)', () {
    testWidgets('a representative screen has exactly one', (tester) async {
      await _pump(
        tester,
        Column(
          children: <Widget>[
            PrimaryAction(label: 'Start cook', onPressed: () {}),
            SmokeButton(label: 'Cancel', onPressed: () {}),
            SmokeButton(
              label: 'Delete',
              onPressed: () {},
              variant: SmokeButtonVariant.danger,
            ),
          ],
        ),
      );
      expect(find.byType(PrimaryAction), findsOneWidget);
    });
  });

  group('stale veil', () {
    testWidgets('does not double-dim', (tester) async {
      await _pump(
        tester,
        const StaleVeil(ageLabel: '12 min ago', child: Text('158°F')),
      );
      expect(find.byType(ColorFiltered), findsOneWidget);

      await _pump(
        tester,
        const StaleVeil(
          ageLabel: '12 min ago',
          alreadyDimmed: true,
          child: Text('158°F'),
        ),
      );
      expect(find.byType(ColorFiltered), findsNothing);
      expect(find.text('12 min ago'), findsOneWidget);
    });
  });

  group('liveness pulse', () {
    testWidgets('is static without a scope and pulses with one', (
      tester,
    ) async {
      await _pump(tester, const PulseDot());
      expect(
        find.descendant(
          of: find.byType(PulseDot),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );

      await tester.pumpWidget(
        const SmokePulseScope(
          pulse: AlwaysStoppedAnimation<double>(0.5),
          child: MaterialApp(
            home: Scaffold(body: Center(child: PulseDot())),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(PulseDot),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an idle dot is hollow', (tester) async {
      await _pump(tester, const PulseDot(state: PulseState.idle));
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(PulseDot),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, Colors.transparent);
      expect(decoration.border, isNotNull);
    });
  });

  group('haptics (N3.29)', () {
    test('critical is the only two-event pattern', () {
      expect(SmokeHaptics.events(SmokeHaptic.critical), hasLength(2));
      for (final kind in <SmokeHaptic>[
        SmokeHaptic.selection,
        SmokeHaptic.advisory,
        SmokeHaptic.confirm,
        SmokeHaptic.warning,
      ]) {
        expect(SmokeHaptics.events(kind), hasLength(1));
        expect(SmokeHaptics.isTwoEvent(kind), isFalse);
      }
      expect(SmokeHaptics.isTwoEvent(SmokeHaptic.critical), isTrue);
    });
  });

  group('legend (N3.28)', () {
    testWidgets('a glyph is a second identity channel', (tester) async {
      final tokens = SmokeTokens.dark();
      await _pump(
        tester,
        SeriesLegend(
          entries: <SeriesLegendEntry>[
            SeriesLegendEntry(
              label: 'Pit',
              color: tokens.pit,
              value: '230°',
              glyph: SmokeGlyph.flame,
            ),
          ],
        ),
      );
      expect(find.text('Pit'), findsOneWidget);
      expect(find.text('230°'), findsOneWidget);
      expect(find.byType(SmokeIcon), findsOneWidget);
    });
  });

  group('cards (N3.13)', () {
    testWidgets('an accent is a series mark, not a fill', (tester) async {
      final tokens = SmokeTokens.dark();
      await _pump(
        tester,
        SmokeCard(accent: tokens.p2, child: const Text('Pork')),
      );
      final spine = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((c) => c.color == tokens.p2);
      expect(spine, hasLength(1));
    });
  });

  group('mono well (N3.24)', () {
    testWidgets('renders the value in mono', (tester) async {
      await _pump(tester, const MonoWell(value: '481 902'));
      final text = tester.widget<Text>(find.text('481 902'));
      expect(text.style?.fontFamily, SmokeText.monoFont);
    });
  });
}
