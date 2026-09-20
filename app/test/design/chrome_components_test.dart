/// The chrome and state components (design 14 §14.7, 16 §16.5, newapp §H.2).
///
/// These live under `test/design/` rather than `test/features/` on purpose:
/// everything here is a `ui/` primitive — stateless over plain values, no
/// session, no transport — and the point of the layering rule is that they can
/// be pinned without one.
///
/// What is being defended is the §H.2 verdict: *"the layout is not curated or
/// considered."* So the assertions are about the decisions, not the pixels —
/// that a notice is a bordered slab and not a bare fill, that a wait has
/// words, that a terminal state has no button, that a reveal is a single
/// shared motion, and that every one of them says something to a screen
/// reader.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/ui/ui.dart';

Widget _host(Widget child, {double textScale = 1, bool reducedMotion = false}) =>
    MaterialApp(
      theme: SmokeTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: Scaffold(body: child),
      ),
    );

List<String> _haptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add((call.arguments as String?) ?? 'vibrate');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

/// The border a status-hue slab must carry. §14.6.1: chrome is 12–16 % fill
/// **and** a 22–35 % border **and** an icon **and** a word — a bare fill is
/// three-quarters of the rule.
BoxDecoration _decorationOf(WidgetTester tester, Finder inside) {
  final found = find
      .descendant(
        of: inside,
        matching: find.byWidgetPredicate(
          (w) =>
              (w is Container && w.decoration is BoxDecoration) ||
              (w is DecoratedBox && w.decoration is BoxDecoration),
        ),
      )
      .first;
  final w = tester.widget(found);
  return (w is Container ? w.decoration : (w as DecoratedBox).decoration)!
      as BoxDecoration;
}

void main() {
  group('ChromeSlot — one reveal, shared', () {
    testWidgets('silent takes no height at all', (tester) async {
      await tester.pumpWidget(_host(const Column(children: [ChromeSlot()])));
      expect(tester.getSize(find.byType(ChromeSlot)).height, 0);
    });

    testWidgets('a notice grows downward and then holds', (tester) async {
      Widget at(bool present) => _host(
        Column(
          children: [
            ChromeSlot(child: present ? const SizedBox(height: 40) : null),
          ],
        ),
      );
      await tester.pumpWidget(at(false));
      await tester.pumpWidget(at(true));
      await tester.pump();
      final mid = tester.getSize(find.byType(ChromeSlot)).height;
      await tester.pump(const Duration(milliseconds: 400));
      final settled = tester.getSize(find.byType(ChromeSlot)).height;
      expect(mid, lessThan(settled), reason: 'it should have animated open');
      expect(settled, 40);
    });

    testWidgets('reduced motion swaps instantly rather than not at all', (
      tester,
    ) async {
      // The point of routing every duration through SmokeMotion: reduced
      // motion removes the animation, never the information.
      Widget at(bool present) => _host(
        Column(
          children: [
            ChromeSlot(child: present ? const SizedBox(height: 40) : null),
          ],
        ),
        reducedMotion: true,
      );
      await tester.pumpWidget(at(false));
      await tester.pumpWidget(at(true));
      await tester.pump();
      expect(tester.getSize(find.byType(ChromeSlot)).height, 40);
    });
  });

  group('AlarmBar', () {
    const critical = Alarm(
      id: 9,
      rule: 'pit_crash',
      probe: 0,
      severity: AlarmSeverity.critical,
    );
    const warning = Alarm(id: 7, rule: 'pit_out_of_band', probe: 1);
    const advisory = Alarm(
      id: 5,
      rule: 'target_reached',
      probe: 2,
      severity: AlarmSeverity.info,
    );

    testWidgets('is a bordered slab, not a bare band of fill', (tester) async {
      await tester.pumpWidget(_host(const AlarmBar(alarm: critical)));
      await tester.pump(const Duration(milliseconds: 400));
      final d = _decorationOf(tester, find.byType(AlarmBar));
      expect(d.border, isNotNull, reason: '§14.6.1 wants fill AND border');
      expect(d.borderRadius, BorderRadius.circular(SmokeTokens.radiusChip));
      // Icon and word, both, always.
      expect(find.byType(Icon), findsWidgets);
      expect(find.text('The fire is dying'), findsOneWidget);
    });

    testWidgets('a critical alarm buzzes the two-event pattern', (tester) async {
      final calls = _haptics(tester);
      await tester.pumpWidget(_host(const AlarmBar(alarm: critical)));
      await tester.pump();
      expect(calls, ['HapticFeedbackType.heavyImpact', 'vibrate']);
    });

    testWidgets('an advisory alarm does not feel like a pit crash', (
      tester,
    ) async {
      final calls = _haptics(tester);
      await tester.pumpWidget(_host(const AlarmBar(alarm: advisory)));
      await tester.pump();
      expect(calls, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('a warning sits between the two, and is one event', (
      tester,
    ) async {
      final calls = _haptics(tester);
      await tester.pumpWidget(_host(const AlarmBar(alarm: warning)));
      await tester.pump();
      expect(calls, ['HapticFeedbackType.heavyImpact']);
    });

    testWidgets('it buzzes once per alarm id, not once per rebuild', (
      tester,
    ) async {
      final calls = _haptics(tester);
      await tester.pumpWidget(_host(const AlarmBar(alarm: critical)));
      await tester.pump();
      final afterFirst = calls.length;
      // Same alarm, three more builds: a tab change, a new reading, a rotate.
      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(_host(const AlarmBar(alarm: critical)));
        await tester.pump();
      }
      expect(calls.length, afterFirst);

      // A *different* alarm is a new demand for attention.
      await tester.pumpWidget(_host(const AlarmBar(alarm: advisory)));
      await tester.pump();
      expect(calls.length, greaterThan(afterFirst));
    });

    testWidgets('a device-scope alarm names no probe', (tester) async {
      await tester.pumpWidget(_host(const AlarmBar(alarm: critical)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Probe'), findsNothing);
    });

    testWidgets('the acknowledge target clears 44 dp', (tester) async {
      await tester.pumpWidget(
        _host(AlarmBar(alarm: critical, onAck: () {})),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.getSize(find.text('Acknowledge')).height,
        lessThan(44),
      );
      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(44),
        reason: 'a 3 a.m. tap with a cold finger needs a real target',
      );
    });

    testWidgets('at large text the button moves under the words', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(AlarmBar(alarm: critical, onAck: () {}), textScale: 2),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final title = tester.getRect(find.text('The fire is dying'));
      final button = tester.getRect(find.byType(TextButton));
      expect(
        button.top,
        greaterThanOrEqualTo(title.bottom),
        reason: 'side by side at 200% clips one of them',
      );
    });

    testWidgets('nothing ringing renders nothing', (tester) async {
      await tester.pumpWidget(_host(const AlarmBar(alarm: null)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getSize(find.byType(AlarmBar)).height, 0);
    });
  });

  group('TransportChip', () {
    testWidgets('says what the dot is doing, in words', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const TransportChip(
            state: TransportState.wifiSta,
            label: 'Wi-Fi',
            live: false,
            liveLabel: 'receiving readings',
            idleLabel: 'no readings arriving',
          ),
        ),
      );
      // The dot ceasing to breathe is the staleness signal — invisible to a
      // screen reader, so the label has to carry it.
      expect(
        tester.getSemantics(find.byType(TransportChip)).label,
        'Wi-Fi, no readings arriving',
      );
      handle.dispose();
    });

    testWidgets('a tappable chip clears 48 dp without becoming a lozenge', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Align(
            child: TransportChip(
              state: TransportState.ble,
              label: 'Bluetooth',
              live: true,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(InkWell)).height,
        greaterThanOrEqualTo(48),
      );
      // …but the visible pill stays a status-bar chip.
      expect(tester.getSize(find.byType(Container).last).height, lessThan(40));
    });
  });

  group('PulseDot — the one animation reduced motion may not kill', () {
    testWidgets('it still breathes under disableAnimations', (tester) async {
      await tester.pumpWidget(
        _host(
          const PulseDot(color: Color(0xFFD95926), live: true),
          reducedMotion: true,
        ),
      );
      await tester.pump();
      final a = tester.widget<Container>(find.byType(Container)).decoration;
      await tester.pump(const Duration(milliseconds: 700));
      final b = tester.widget<Container>(find.byType(Container)).decoration;
      expect(
        a,
        isNot(b),
        reason:
            'the dot stopping IS the staleness signal — zeroing the pulse '
            'would delete the information for the users who asked for less '
            'motion (§14.4.1)',
      );
    });

    testWidgets('not live means hollow and still, never simply hidden', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const PulseDot(color: Color(0xFFD95926), live: false)),
      );
      await tester.pump();
      final d =
          tester.widget<Container>(find.byType(Container)).decoration!
              as BoxDecoration;
      expect(d.color, isNull, reason: 'hollow');
      expect(d.border, isNotNull, reason: 'a ring, so "stale" reads at a glance');
    });
  });

  group('SeriesLegend — the third identity channel, spent', () {
    testWidgets('every entry carries a glyph and names it aloud', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          SeriesLegend(
            entries: [
              for (var p = 1; p <= 4; p++)
                SeriesLegendEntry(
                  name: 'Probe $p',
                  style: ProbePalette.styleFor(p, Brightness.dark),
                ),
            ],
          ),
        ),
      );
      for (var p = 1; p <= 4; p++) {
        final entry = find.byKey(Key('legend-$p'));
        expect(entry, findsOneWidget);
        final label = tester.getSemantics(entry).label;
        expect(
          label,
          contains(ProbePalette.glyphFor(p).label),
          reason: 'entry $p must name its shape, not only draw it',
        );
        expect(
          label,
          contains(ProbePalette.styleFor(p, Brightness.dark).strokeName),
        );
      }
      handle.dispose();
    });

    testWidgets('a detached series stays in the legend, dimmed', (tester) async {
      await tester.pumpWidget(
        _host(
          SeriesLegend(
            entries: [
              SeriesLegendEntry(
                name: 'Probe 3',
                style: ProbePalette.styleFor(3, Brightness.dark),
                dimmed: true,
              ),
            ],
          ),
        ),
      );
      // A series that vanishes when unplugged takes its identity with it and
      // the rows below appear to change jack.
      expect(find.text('Probe 3'), findsOneWidget);
    });
  });

  group('the state components', () {
    testWidgets('an empty state is glyph, title, one sentence, one action', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          EmptyState(
            icon: Icons.outdoor_grill_outlined,
            title: 'No cooks yet',
            message: 'Your bridge is still recording.',
            action: FilledButton(onPressed: () {}, child: const Text('Start')),
          ),
        ),
      );
      expect(find.text('No cooks yet'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      // The medallion: a framed glyph, not a bare icon floating on the page.
      expect(
        find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxWidth == 76,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a problem state carries the hue as chrome, not as an icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const ProblemState(
            title: 'Can’t reach your bridge',
            message: 'Last seen 12 minutes ago.',
          ),
        ),
      );
      final medallion = tester.widget<Container>(
        find
            .byWidgetPredicate(
              (w) => w is Container && w.constraints?.maxWidth == 76,
            )
            .first,
      );
      final d = medallion.decoration! as BoxDecoration;
      expect(d.color, StatusPalette.fill(StatusRole.critical));
      expect(d.border, isNotNull);
    });

    testWidgets('a terminal problem state has no button, by construction', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const ProblemState(
            title: 'This phone has no Bluetooth',
            message:
                'Read the network name and password from the bridge’s screen, '
                'then join that network in Android settings.',
            terminal: true,
          ),
        ),
      );
      // A button that leads nowhere is worse than an admitted dead end
      // (§14.7.1).
      expect(find.byType(ButtonStyleButton), findsNothing);
      expect(find.textContaining('Read the network name'), findsOneWidget);
    });

    test('a terminal state with an action is a contradiction, and asserts', () {
      expect(
        () => ProblemState(
          title: 'x',
          message: 'y',
          terminal: true,
          action: const Text('nope'),
        ).build(_FakeContext()),
        throwsAssertionError,
      );
    });

    testWidgets('a wait has words, and says them to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const LoadingState(
            title: 'Looking for your bridge',
            message: 'This takes a few seconds over Bluetooth.',
          ),
        ),
      );
      // §16.2: a spinner with no words is worse than an error with words.
      expect(find.text('Looking for your bridge'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.getSemantics(find.byType(LoadingState)).label,
        contains('Looking for your bridge'),
      );
      handle.dispose();
    });

    testWidgets('a capability notice is an advisory, not a page error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CapabilityNotice(message: 'On Bluetooth — live readings only.'),
        ),
      );
      final d = _decorationOf(tester, find.byType(CapabilityNotice));
      expect(d.color, StatusPalette.fill(StatusRole.info));
      expect(d.border, isNotNull);
      expect(
        find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxWidth == 76,
        ),
        findsNothing,
        reason: 'a section notice must not look like a page-level empty state',
      );
    });
  });

  group('SmokeCard', () {
    testWidgets('a spine is a 3 dp mark, and nothing wider', (tester) async {
      await tester.pumpWidget(
        _host(
          SmokeCard(
            spine: ProbePalette.hue(1),
            child: const SizedBox(height: 60),
          ),
        ),
      );
      final rule = find.byKey(const Key('smoke-card-spine'));
      expect(rule, findsOneWidget);
      expect(tester.getSize(rule).width, SmokeCard.spineWidth);
      expect(tester.widget<ColoredBox>(rule).color, ProbePalette.hue(1));
      // It runs the full height of the card — a rule that stops short is a
      // decoration, and this is an identity mark.
      expect(
        tester.getSize(rule).height,
        tester.getSize(find.byType(SmokeCard)).height,
      );
    });

    testWidgets('no spine, no extra layer', (tester) async {
      await tester.pumpWidget(
        _host(const SmokeCard(child: SizedBox(height: 60))),
      );
      expect(find.byKey(const Key('smoke-card-spine')), findsNothing);
    });
  });
}

/// Just enough of a `BuildContext` to reach the assert in `build`.
class _FakeContext extends StatelessElement {
  _FakeContext() : super(const _Nothing());
}

class _Nothing extends StatelessWidget {
  const _Nothing();
  @override
  Widget build(BuildContext context) => const SizedBox();
}
