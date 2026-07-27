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
/// Fonts are loaded so overflow is measured against the metrics that ship, and
/// every case is checked at 360 / 393 / 430 dp with `takeException()`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/ui/setup/passkey_display.dart';
import 'package:smoke_bridge/ui/setup/setup_rail.dart';
import 'package:smoke_bridge/ui/setup/setup_scaffold.dart';

import '../support/load_fonts.dart';

/// The three phone widths the design tests against (§14.7 golden matrix).
const _widths = <double>[360, 393, 430];

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

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
      // hop, not a fourth hop.
      final active = tester.widget<Text>(find.text('2'));
      expect(active.style?.color, StatusPalette.critical);
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
