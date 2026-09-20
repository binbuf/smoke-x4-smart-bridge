/// THE COLOUR RULE (design 16 §16.5, 14 §14.6.1) — the one the spine itself
/// calls *"the most-broken rule"*, pinned at the places it broke.
///
/// Three clauses, restated so the assertions below can be read against them:
///
///  * a **series hue** is only ever a *mark* — a chart stroke, a gauge arc, a
///    ≤12 dp dot, a card's left rule. It never fills a large shape and it never
///    carries a word;
///  * a **status hue** is only ever *chrome* — a 12–16 % fill with a 22–35 %
///    border, always with an icon **and** a word, the words at `textHi`;
///  * **green means transport health and nothing else.**
///
/// It is the third clause that rots, and it rots the same way every time:
/// `check_circle` + `positive` is the obvious way to draw any pleasant outcome,
/// so green leaks onto "what you keep", "this check passed", "the reset
/// finished", "we don't track you" — and then the one mark where green has to
/// mean something, the transport chip, is competing with a dozen decorations.
///
/// So these tests are mostly **negative**, deliberately: they do not say what
/// each surface must be, they say what none of them may be. A hue can be
/// retuned, a glyph swapped, a layout rebuilt, and every assertion still holds,
/// because what is defended here is the meaning of green rather than a pixel.
/// The two sanctioned greens are asserted **present** at the end — a rule with
/// no positive case is indistinguishable from having deleted the colour.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/bridge/verb_progress.dart';
import 'package:smoke_bridge/features/fieldreport/field_report.dart';
import 'package:smoke_bridge/features/fieldreport/field_report_route.dart';
import 'package:smoke_bridge/features/setup/copy/setup_copy.dart';
import 'package:smoke_bridge/features/setup/preflight.dart';
import 'package:smoke_bridge/features/setup/screens/finish_screens.dart';
import 'package:smoke_bridge/features/setup/screens/hop2_screens.dart';
import 'package:smoke_bridge/features/setup/screens/preflight_screens.dart';
import 'package:smoke_bridge/features/setup/setup_machine.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../data/fake_peripheral.dart';
import '../support/load_fonts.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: SmokeTheme.dark, home: Scaffold(body: child));

/// Every colour the rendered tree actually paints: text ink, icon ink, and the
/// fills, borders and shadows of anything decorated.
///
/// Walks **elements**, not a widget list, so it sees what a `switch` inside a
/// build method produced rather than what one constructor was handed — the
/// difference between pinning the render and pinning a single call site.
Set<Color> _paints(WidgetTester tester, Finder root) {
  final found = <Color>{};

  void addDecoration(Decoration? d) {
    if (d is! BoxDecoration) {
      return;
    }
    if (d.color != null) {
      found.add(d.color!);
    }
    if (d.border case final Border b) {
      found.addAll([b.top.color, b.bottom.color, b.left.color, b.right.color]);
    }
    for (final s in d.boxShadow ?? const <BoxShadow>[]) {
      found.add(s.color);
    }
  }

  void walk(Element e) {
    switch (e.widget) {
      case Text(:final style):
        if (style?.color case final c?) {
          found.add(c);
        }
      // Every `Text` lowers to one of these, so this is where a *resolved*
      // ink shows up — including the per-span colours of a `RichText` ledger,
      // which is exactly the shape "a status hue carrying a word" takes.
      case RichText(:final text):
        text.visitChildren((span) {
          if (span is TextSpan && span.style?.color != null) {
            found.add(span.style!.color!);
          }
          return true;
        });
      case Icon(:final color?):
        found.add(color);
      case Container(:final decoration):
        addDecoration(decoration);
      case DecoratedBox(:final decoration):
        addDecoration(decoration);
      case ColoredBox(:final color):
        found.add(color);
      case _:
    }
    e.visitChildElements(walk);
  }

  walk(tester.element(root));
  return found;
}

/// True when [c] is the app's green **at any alpha** — `positive` itself, its
/// 12 % chrome fill, its 30 % border.
///
/// The rule is about the hue. An assertion that only looked for the opaque
/// value would sail straight past a green banner, which is the exact shape of
/// the violation being defended against.
bool _isPositive(Color c) =>
    c.r == StatusPalette.positive.r &&
    c.g == StatusPalette.positive.g &&
    c.b == StatusPalette.positive.b;

Matcher get _paintsNoGreen => predicate<Set<Color>>(
  (cs) => !cs.any(_isPositive),
  'paints nothing in the transport-health green',
);

/// Series slots 2–4. Slot 1 is excluded on purpose: §14.6.4 pins it to the same
/// value as `StatusPalette.pit` deliberately, so that an ember chart line
/// beside an ember button does not read as a rendering bug — which means its
/// presence cannot tell a series mark from the brand accent. Slots 2–4 can.
final _seriesOnly = <Color>{
  ProbePalette.hue(2),
  ProbePalette.hue(3),
  ProbePalette.hue(4),
};

/// A real machine on fake seams — no radio, no timer that ever fires. The
/// screens under test only need one because a tapped action calls a real
/// method; none of these tests taps.
SetupMachine _machine() {
  final fake = FakePeripheral();
  final transport = BleTransport(fake);
  final probe = _Probe();
  final listen = _Listen();
  final m = SetupMachine(
    transport: transport,
    client: fake,
    probe: probe,
    listen: listen,
    verify: (ip) async => 'http://192.168.1.42',
    delay: (_) => Completer<void>().future,
  );
  addTearDown(() async {
    await m.dispose();
    await transport.close();
    await probe.dispose();
    await listen.dispose();
  });
  return m;
}

void main() {
  setUpAll(loadAppFonts);

  group('green is transport health and nothing else', () {
    testWidgets('a cost sheet does not paint what you KEEP green', (
      tester,
    ) async {
      // One widget, ten call sites — end a cook, adopt a bridge, merge, split,
      // delete, clear data, restart, power off, factory reset, and the field
      // report's rollback opt-in. Not one of them is a link coming back, so a
      // stray green here did more damage than anywhere else in the app.
      await tester.pumpWidget(
        _host(
          const CostSheet(
            title: 'End this cook?',
            body: 'The bridge keeps recording either way.',
            keeps: 'Every reading already stored.',
            loses: 'The running cook’s name.',
            confirmLabel: 'End it',
            cancelLabel: 'Keep it running',
          ),
        ),
      );
      expect(_paints(tester, find.byType(CostSheet)), _paintsNoGreen);

      // The tick and the word are what carry "Keeps", and they stay. Only the
      // hue was ever wrong. (The ledger is a `RichText`, so `find.text` cannot
      // see it — read the spans.)
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
      final ledger = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((w) => w.text.toPlainText())
          .join('\n');
      expect(ledger, contains('Keeps'));
      expect(ledger, contains('Loses'));
    });

    test('a field-report PASS is not green', () {
      // Dozens of markers land on one screen: notification permission,
      // full-screen intent, storage headroom, alarm rules, clock skew. A wall
      // of green is how a reader learns the app's green is decorative.
      expect(roleForCheck(CheckStatus.pass), isNot(StatusRole.positive));
      expect(roleForCheck(CheckStatus.fail), StatusRole.critical);
      expect(
        roleForCheck(CheckStatus.skipped),
        StatusRole.info,
        reason: '"could not run" is not "broken" — they call for different '
            'next steps (14 §14.6.5)',
      );
    });

    testWidgets('a finished disruptive verb is not green', (tester) async {
      // This sheet reaches "done" by the link *going away*. For a power-off it
      // renders at the exact moment transport health is gone, by design.
      for (final verb in DisruptiveVerb.values) {
        await tester.pumpWidget(
          _host(
            VerbProgressSheet(
              verb: verb,
              send: () async {},
              probe: () async => throw StateError('down'),
              pollEvery: const Duration(milliseconds: 10),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('verb-done')), findsOneWidget);
        expect(
          _paints(tester, find.byType(VerbProgressSheet)),
          _paintsNoGreen,
          reason: '$verb ends with the bridge unreachable, not healthy',
        );
        // The tick still says it worked.
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      }
    });

    testWidgets('the permission primer’s promises are not green', (
      tester,
    ) async {
      // "We don't track you" is a promise about behaviour, not a link state —
      // and this is the first screen a new user reads, so whatever green means
      // here is what it will seem to mean on the chip afterwards.
      final screen = preflightScreenFor(
        const SetupPermissionPrimer(),
        _machine(),
      );
      await tester.pumpWidget(_host(screen!));
      expect(find.text(SetupCopy.primerReassure1), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));
      expect(_paints(tester, find.byType(SetupScaffold)), _paintsNoGreen);
    });

    testWidgets('a factory-fresh bridge is not green', (tester) async {
      await tester.pumpWidget(
        _host(
          ResetDoneScreen(
            state: const SetupResetDone(),
            machine: _machine(),
          ),
        ),
      );
      expect(find.byIcon(Icons.restart_alt_rounded), findsOneWidget);
      expect(
        _paints(tester, find.byType(SetupScaffold)),
        _paintsNoGreen,
        reason: 'a wipe drops the link — it is the opposite of health',
      );
    });
  });

  group('the two sanctioned greens survive', () {
    testWidgets('the transport chip', (tester) async {
      // The one mark the whole rule exists to protect.
      await tester.pumpWidget(
        _host(
          const TransportChip(
            state: TransportState.wifiSta,
            label: 'Wi-Fi',
            live: true,
          ),
        ),
      );
      expect(
        _paints(tester, find.byType(TransportChip)).any(_isPositive),
        isTrue,
      );
    });

    testWidgets('the wizard landing — its whole subject IS the link', (
      tester,
    ) async {
      // The counter-case, and the reason this file is not simply "ban green".
      // Every row under that tick is a transport (BLE, LoRa, Wi-Fi) and the
      // phone is holding a live BLE link at the moment it renders.
      await tester.pumpWidget(
        _host(
          const SetupDoneScreen(
            summary: SetupSummary(
              bridgeName: 'Smoke Bridge',
              blePaired: true,
              baseDeviceId: '3F91',
              baseNumProbes: 4,
              wifiSsid: 'Yard',
              ip: '192.168.1.50',
            ),
          ),
        ),
      );
      expect(
        _paints(tester, find.byType(SetupScaffold)).any(_isPositive),
        isTrue,
      );
    });
  });

  group('a series hue is a mark, never a word', () {
    testWidgets('the hop-2 payoff draws its temperatures in ink', (
      tester,
    ) async {
      // The payoff is the moment the product justifies itself, and the first
      // screen a new user ever sees working — and it used to paint the reading
      // itself in the probe's hue at 34 pt. The dot beside it is the mark.
      await tester.pumpWidget(
        _host(
          BaseConfirmedScreen(
            state: const SetupBaseConfirmed(
              deviceId: '3F91',
              numProbes: 4,
              temps: [2431, 1680, 940, 720],
            ),
            machine: _machine(),
          ),
        ),
      );

      final temps = tester.widgetList<AnimatedTemp>(find.byType(AnimatedTemp));
      expect(temps, hasLength(4));
      for (final temp in temps) {
        expect(
          temp.color,
          SmokeTokens.dark.textHi,
          reason: 'every sibling readout in the app (hero, compact, strip, '
              'detail) keeps the digits at textHi and spends the hue on a '
              '3 dp underline',
        );
        expect(_seriesOnly, isNot(contains(temp.color)));
      }

      // …and the marks are still there: one 12 dp dot per jack, in its hue.
      expect(
        _paints(tester, find.byType(SetupScaffold)),
        containsAll(_seriesOnly),
      );
    });

    testWidgets('a detached probe is muted, still not a series hue', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          BaseConfirmedScreen(
            state: const SetupBaseConfirmed(
              deviceId: '3F91',
              numProbes: 4,
              temps: [2431, null, null, null],
            ),
            machine: _machine(),
          ),
        ),
      );
      final temps = tester
          .widgetList<AnimatedTemp>(find.byType(AnimatedTemp))
          .toList();
      expect(temps.first.color, SmokeTokens.dark.textHi);
      for (final temp in temps.skip(1)) {
        expect(
          temp.color,
          SmokeTokens.dark.textMuted,
          reason: 'dimming a detached reading is freshness, not identity',
        );
      }
    });

    testWidgets('the setup rail never tints a step number', (tester) async {
      // Two halves of one component: `SetupScaffold` states that its title is
      // never tinted, and the rail beside it used to tint its digits. The ring
      // and the glow carry the hue in both lit states.
      for (final error in [false, true]) {
        await tester.pumpWidget(
          _host(SetupRail(hop: 2, of: 3, errorTint: error, skipped: const {})),
        );
        final digit = tester.widget<Text>(find.text('2'));
        expect(digit.style?.color, SmokeTokens.dark.textHi);
        expect(digit.style?.color, isNot(StatusPalette.pit));
        expect(digit.style?.color, isNot(StatusPalette.critical));
      }
    });
  });
}

// ── fake seams, so a screen can be pumped with no radio ──────────────────────

class _Probe implements PreflightProbe {
  final _ctl = StreamController<SetupAdapterState>.broadcast();

  @override
  SetupAdapterState get adapterStateNow => SetupAdapterState.on;
  @override
  Stream<SetupAdapterState> get adapterStates => _ctl.stream;
  @override
  Future<void> requestEnable() async {}
  @override
  bool get needsLocationServices => false;
  @override
  Future<bool> isLocationServicesOn() async => true;
  @override
  Future<PreflightPermission> permissionStatus() async =>
      PreflightPermission.granted;
  @override
  Future<PreflightPermission> requestPermissions() async =>
      PreflightPermission.granted;

  Future<void> dispose() => _ctl.close();
}

class _Listen implements BaseListenSeam {
  final _ctl = StreamController<BasePairSnapshot>.broadcast();

  @override
  Future<void> startListen({required Duration window}) async {}
  @override
  Stream<BasePairSnapshot> get updates => _ctl.stream;
  @override
  Future<void> cancel() async {}

  Future<void> dispose() => _ctl.close();
}
