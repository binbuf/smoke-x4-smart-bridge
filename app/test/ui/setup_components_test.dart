/// A23.2 — the ui/setup component tests (design 14 §14.7.4, 13 §13.2).
///
/// These pin the three facts the design makes load-bearing:
///
/// * the rail renders **hop 0 as preflight** — a dimmed three-circle rail with a
///   *Before we start* eyebrow and no lit ring — and [errorTint] recolours the
///   *active* circle (or, at hop 0, the eyebrow) rather than inventing a fourth
///   hop;
/// * the scaffold offers **exactly one** primary slot and an exit;
/// * `PasskeyDisplay` is **incapable of rendering a real passkey** — it takes no
///   code and draws no digit.
///
/// 17 §17.3 C added three more, and they pin the onboarding-presence work:
///
/// * `BridgeIllustration` is a **drawing, not an asset**, it shrinks into
///   whatever slot it is given rather than overflowing, and it **stops moving
///   under reduced motion** — the one accessibility promise an animated
///   illustration can break silently;
/// * `SetupSteps` draws its caution step as *chrome* — fill, border and glyph
///   in `warning`, words at `textHi` — which is 16 §16.5's shape, and it does
///   not renumber the plain steps around it;
/// * `SetupBodyCenter` scrolls instead of overflowing when the body slot is
///   shorter than its child, which is the 200 %-text-scale case.
///
/// Fonts are loaded so overflow is measured against the metrics that ship, and
/// every case is checked at 360 / 393 / 430 dp with `takeException()`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/ui/setup/device_art.dart';
import 'package:smoke_bridge/ui/setup/passkey_display.dart';
import 'package:smoke_bridge/ui/setup/setup_rail.dart';
import 'package:smoke_bridge/ui/setup/setup_scaffold.dart';
import 'package:smoke_bridge/ui/setup/setup_steps.dart';

import '../support/load_fonts.dart';

/// The three phone widths the design tests against (§14.7 golden matrix).
const _widths = <double>[360, 393, 430];

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The same host with `disableAnimations` on. The `MediaQuery` sits *inside*
/// `MaterialApp`, because `WidgetsApp` installs its own from the view and an
/// override above it would simply be replaced.
Widget _wrapReducedMotion(Widget child) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child,
      ),
    ),
  ),
);

/// Pump [child] at [width] dp on a tall surface and fail on any overflow.
Future<void> _pumpAt(WidgetTester tester, Widget child, double width) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(child));
}

final _digit = RegExp(r'\d');

Iterable<String> _texts(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '');

void main() {
  setUpAll(loadAppFonts);

  group('SetupRail', () {
    testWidgets('hop 0 is preflight: dimmed, no lit ring, an eyebrow', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const SetupRail(hop: 0, of: 3, errorTint: false, skipped: {}),
        393,
      );

      // The eyebrow is present and carries the preflight framing.
      expect(find.byKey(const Key('setup-rail-eyebrow')), findsOneWidget);
      expect(find.text('BEFORE WE START'), findsOneWidget);

      // No circle is "done" (a tick) and none is skipped (a dash): every hop
      // is still ahead of the user.
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.byIcon(Icons.remove_rounded), findsNothing);

      // All three circles render, and the rail itself is dimmed to 45 %.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(const Key('setup-rail-circle-1')),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.45);
    });

    testWidgets('errorTint at hop 0 recolours the eyebrow, not a circle', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const SetupRail(hop: 0, of: 3, errorTint: true, skipped: {}),
        393,
      );
      final eyebrow = tester.widget<Text>(
        find.byKey(const Key('setup-rail-eyebrow')),
      );
      expect(eyebrow.style?.color, StatusPalette.critical);
    });

    testWidgets('a mid-flow hop: done tick behind, error tint on the active', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const SetupRail(hop: 2, of: 3, errorTint: true, skipped: {}),
        393,
      );

      // Hop 1 is behind → a tick. No eyebrow off preflight.
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byKey(const Key('setup-rail-eyebrow')), findsNothing);

      // The active circle (2) is recoloured critical — the failure is a bad
      // hop, not a fourth hop. The hue is on the **ring**…
      final circle = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const Key('setup-rail-circle-2')),
          matching: find.byType(Container),
        ),
      );
      final border = (circle.decoration! as BoxDecoration).border! as Border;
      expect(border.top.color, StatusPalette.critical);

      // …and never on the word. §14.6.5: the status hue rides the icon and the
      // border, the words are carried at 13:1 — which is the rule the sibling
      // `SetupScaffold` states about its own title and this half of the
      // component used to contradict.
      final active = tester.widget<Text>(find.text('2'));
      expect(active.style?.color, SmokeTokens.dark.textHi);
      expect(active.style?.color, isNot(StatusPalette.critical));
    });

    testWidgets('the active digit is ink too — only the ring is lit', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const SetupRail(hop: 2, of: 3, errorTint: false, skipped: {}),
        393,
      );
      final active = tester.widget<Text>(find.text('2'));
      expect(active.style?.color, SmokeTokens.dark.textHi);
      expect(active.style?.color, isNot(StatusPalette.pit));
    });

    // 17 §17.5 — the connector is the progress bar.
    testWidgets('the connector fills with ember up to the hop reached', (
      tester,
    ) async {
      double factorAt(int hop) {
        return tester
                .widget<FractionallySizedBox>(
                  find.byKey(const Key('setup-rail-progress')),
                )
                .widthFactor ??
            0;
      }

      // Preflight is *before* step one, so nothing is behind the user.
      await _pumpAt(
        tester,
        const SetupRail(hop: 0, of: 3, errorTint: false, skipped: {}),
        393,
      );
      expect(factorAt(0), 0);

      await _pumpAt(
        tester,
        const SetupRail(hop: 2, of: 3, errorTint: false, skipped: {}),
        393,
      );
      expect(factorAt(2), closeTo(0.5, 0.001));

      await _pumpAt(
        tester,
        const SetupRail(hop: 3, of: 3, errorTint: false, skipped: {}),
        393,
      );
      expect(factorAt(3), 1);
    });

    testWidgets('a skipped hop renders a dash, not a tick', (tester) async {
      await _pumpAt(
        tester,
        const SetupRail(hop: 3, of: 3, errorTint: false, skipped: {2}),
        393,
      );
      // Hop 1 done (tick), hop 2 skipped (dash).
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    });
  });

  group('SetupScaffold', () {
    testWidgets('shows exactly one primary and an exit', (tester) async {
      var exited = false;
      await _pumpAt(
        tester,
        SetupScaffold(
          hop: 1,
          title: 'Pair with your bridge',
          subtitle: 'Look at the screen on the bridge.',
          onExit: () => exited = true,
          body: const SizedBox.shrink(),
          primary: const _Primary(),
          secondary: TextButton(onPressed: () {}, child: const Text('Cancel')),
        ),
        393,
      );

      // One primary slot, one primary widget.
      expect(find.byType(_Primary), findsOneWidget);

      // The exit is present and wired.
      expect(find.byKey(const Key('setup-exit')), findsOneWidget);
      await tester.tap(find.byKey(const Key('setup-exit')));
      expect(exited, isTrue);
    });

    testWidgets('a terminal state (no onExit) renders no exit', (tester) async {
      await _pumpAt(
        tester,
        const SetupScaffold(
          hop: 1,
          title: 'Read the code from the bridge',
          body: SizedBox.shrink(),
        ),
        393,
      );
      expect(find.byKey(const Key('setup-exit')), findsNothing);
    });
  });

  group('PasskeyDisplay', () {
    testWidgets('takes no code and renders no digit', (tester) async {
      // The constructor is parameterless — this line is the proof that no real
      // passkey can be passed in.
      await _pumpAt(tester, const PasskeyDisplay(), 393);

      expect(find.byType(PasskeyDisplay), findsOneWidget);
      for (final s in _texts(tester)) {
        expect(
          _digit.hasMatch(s),
          isFalse,
          reason: 'the passkey illustration rendered a digit: "$s"',
        );
      }
    });
  });

  // ── 17 §17.3 C — onboarding presence ─────────────────────────────────────
  group('BridgeIllustration', () {
    testWidgets('is a drawing — no asset, and never a digit', (tester) async {
      await _pumpAt(
        tester,
        const BridgeIllustration(mood: BridgeMood.passkey),
        393,
      );
      expect(find.byType(CustomPaint), findsWidgets);
      // Vector, not photographic (17 §17.3 A's reasoning, plus the daylight
      // profile: a PNG cannot follow the ink ramp).
      expect(find.byType(Image), findsNothing);
      // The passkey mood draws six cells. It must be as incapable of a real
      // code as `PasskeyDisplay` is — this is the paint half of that promise.
      for (final s in _texts(tester)) {
        expect(_digit.hasMatch(s), isFalse, reason: 'the bridge drew "$s"');
      }
    });

    testWidgets('a scanning ripple runs, and stops under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const BridgeIllustration(mood: BridgeMood.scanning)),
      );
      await tester.pump();
      expect(
        tester.binding.transientCallbackCount,
        greaterThan(0),
        reason: 'the scan should look like it is looking at something',
      );

      // The whole point of routing the period through `SmokeMotion`: the user
      // who asked for less movement gets three static rings, not a loop.
      await tester.pumpWidget(
        _wrapReducedMotion(const BridgeIllustration(mood: BridgeMood.scanning)),
      );
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a still mood holds no ticker open', (tester) async {
      await tester.pumpWidget(
        _wrap(const BridgeIllustration(mood: BridgeMood.linked)),
      );
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('shrinks into a slot smaller than its preferred size', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const Center(
          child: SizedBox(
            width: 64,
            height: 64,
            child: BridgeIllustration(mood: BridgeMood.ready, size: 200),
          ),
        ),
        393,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(CustomPaint).last).width,
        lessThanOrEqualTo(64),
      );
    });

    testWidgets('is decorative unless it is given a label', (tester) async {
      await _pumpAt(
        tester,
        const BridgeIllustration(mood: BridgeMood.ready),
        393,
      );
      expect(
        find.descendant(
          of: find.byType(BridgeIllustration),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
    });
  });

  group('SetupSteps', () {
    const steps = [
      SetupStep('One.'),
      SetupStep('Two.'),
      SetupStep('The phone will guess wrong.', caution: true),
    ];

    testWidgets('a caution is chrome: fill, border, glyph — words at textHi', (
      tester,
    ) async {
      await _pumpAt(tester, const SetupSteps(steps: steps), 393);

      // The glyph carries the hue…
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      final chrome = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(Icons.warning_amber_rounded),
          matching: find.byType(Container),
        ),
      );
      final box = chrome.decoration! as BoxDecoration;
      expect(box.color, StatusPalette.fill(StatusRole.warning));
      expect(
        (box.border! as Border).top.color,
        StatusPalette.border(StatusRole.warning),
      );

      // …and never the words (§14.6.5: text at 13:1, the hue on the icon).
      final words = tester.widget<Text>(
        find.text('The phone will guess wrong.'),
      );
      expect(words.style?.color, SmokeTokens.dark.textHi);
      expect(words.style?.color, isNot(StatusPalette.warning));
    });

    testWidgets('the ordinals count steps, and a caution takes none', (
      tester,
    ) async {
      await _pumpAt(tester, const SetupSteps(steps: steps), 393);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      // Three entries, two numbers — the caution is not "step 3".
      expect(find.text('3'), findsNothing);
    });

    // 17 §17.5 — warm where there is nothing live to misstate.
    testWidgets('a plain step wears a filled ember marker, not a grey disc', (
      tester,
    ) async {
      await _pumpAt(tester, const SetupSteps(steps: steps), 393);
      final disc = tester.widget<Container>(
        find.ancestor(of: find.text('1'), matching: find.byType(Container)),
      );
      expect((disc.decoration! as BoxDecoration).color, StatusPalette.pit);
      // …and the numeral still says which step it is with the colour removed.
      final numeral = tester.widget<Text>(find.text('1'));
      expect(numeral.style?.color, StatusPalette.onPit);
    });
  });

  group('SetupBodyCenter', () {
    testWidgets('scrolls rather than overflowing a short slot', (tester) async {
      await _pumpAt(
        tester,
        const SizedBox(
          height: 80,
          child: SetupBodyCenter(child: SizedBox(height: 400, width: 100)),
        ),
        393,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('no overflow across phone widths', () {
    for (final w in _widths) {
      testWidgets('full setup screen fits at ${w.toInt()} dp', (tester) async {
        await _pumpAt(
          tester,
          SetupScaffold(
            hop: 2,
            title: 'Getting a new code…',
            subtitle:
                'Some phones put the pairing prompt in the notification '
                'shade instead of on screen.',
            onExit: () {},
            errorTint: true,
            body: const Center(child: PasskeyDisplay()),
            primary: const _Primary(),
            secondary: TextButton(
              onPressed: () {},
              child: const Text('Try pairing again'),
            ),
          ),
          w,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('both device drawings fit at ${w.toInt()} dp', (
        tester,
      ) async {
        for (final mood in BridgeMood.values) {
          await _pumpAt(tester, BridgeIllustration(mood: mood), w);
          expect(tester.takeException(), isNull, reason: '$mood at $w dp');
        }
        await _pumpAt(tester, const BaseStationIllustration(), w);
        expect(tester.takeException(), isNull);
      });

      testWidgets('bare rail fits at ${w.toInt()} dp', (tester) async {
        await _pumpAt(
          tester,
          const Padding(
            padding: EdgeInsets.all(SmokeTokens.s4),
            child: SetupRail(hop: 0, of: 3, errorTint: false, skipped: {}),
          ),
          w,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// A stand-in for the app's `PrimaryAction`. The scaffold test only needs to
/// prove there is one slot and it renders what it is handed, so the test stays
/// free of the controls library.
class _Primary extends StatelessWidget {
  const _Primary();

  @override
  Widget build(BuildContext context) =>
      FilledButton(onPressed: () {}, child: const Text('Continue'));
}
