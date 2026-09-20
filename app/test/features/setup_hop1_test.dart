/// A23.3 — the preflight + hop-1 setup screens (design 13 §13.2.0–§13.2.1).
///
/// One projection per `SetupState` in the hop-0/hop-1 contract, checked for the
/// three things the design makes load-bearing: the *right words* (a wrong
/// passkey does not read as "declined", a reset bridge does not read as "retry")
/// (§13.2.1); *exactly one ember action* and an honest exit, so no screen shows
/// two primaries or strands the user (rail R1/R2, §13.2); and *no overflow* at
/// the three phone widths the design tests against, measured against the fonts
/// that ship (§14.5). The out-of-machine deep-links are injected and their
/// wiring is asserted here — a `null` link disables its button rather than
/// lying.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/setup/copy/setup_copy.dart';
import 'package:smoke_bridge/features/setup/preflight.dart';
import 'package:smoke_bridge/features/setup/screens/hop1_screens.dart';
import 'package:smoke_bridge/features/setup/screens/preflight_screens.dart';
import 'package:smoke_bridge/features/setup/setup_machine.dart';
import 'package:smoke_bridge/ui/setup/device_art.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../data/fake_peripheral.dart';
import '../support/load_fonts.dart';

/// The three phone widths the design tests against (§14.7 golden matrix).
const _widths = <double>[360, 393, 430];

final _digit = RegExp(r'\d');

BridgeDiscovery _bridge({
  String id = 'AA:BB:CC:DD:A4:F2',
  String name = 'SmokeBridge-A4F2',
  int? pit = 2431,
  bool paired = true,
  int rssi = -42,
}) => BridgeDiscovery(
  deviceId: id,
  name: name,
  pitTempF10: pit,
  sessionActive: pit != null,
  sessionMinutes: 252,
  paired: paired,
  rssi: rssi,
);

// ── inert fakes: the machine is a required argument, never driven here ────────

class _FakeProbe implements PreflightProbe {
  final _adapter = StreamController<SetupAdapterState>.broadcast();
  @override
  SetupAdapterState get adapterStateNow => SetupAdapterState.on;
  @override
  Stream<SetupAdapterState> get adapterStates => _adapter.stream;
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
  Future<void> dispose() => _adapter.close();
}

class _FakeListen implements BaseListenSeam {
  final _ctl = StreamController<BasePairSnapshot>.broadcast();
  @override
  Future<void> startListen({required Duration window}) async {}
  @override
  Stream<BasePairSnapshot> get updates => _ctl.stream;
  @override
  Future<void> cancel() async {}
  Future<void> dispose() => _ctl.close();
}

class _Env {
  _Env({FakePeripheralConfig? config}) {
    fake = FakePeripheral(config: config);
    transport = BleTransport(fake);
    probe = _FakeProbe();
    listen = _FakeListen();
    machine = SetupMachine(
      transport: transport,
      client: fake,
      probe: probe,
      listen: listen,
      verify: (_) async => null,
    );
    externals = SetupExternals(
      onLeaveSetup: () => _tally('leave'),
      openBluetoothSettings: () => _tally('bt'),
      openAppSettings: () => _tally('app'),
      openLocationSettings: () => _tally('loc'),
      openNotificationSettings: () => _tally('notif'),
      enterAddressManually: () => _tally('addr'),
      removeAPairedPhone: () => _tally('remove'),
    );
  }

  late final FakePeripheral fake;
  late final BleTransport transport;
  late final _FakeProbe probe;
  late final _FakeListen listen;
  late final SetupMachine machine;
  late final SetupExternals externals;
  final _fired = <String, int>{};

  void _tally(String k) => _fired[k] = (_fired[k] ?? 0) + 1;
  int fired(String k) => _fired[k] ?? 0;

  /// The screen under test — the dispatcher's own output, with the deep-links
  /// wired unless [bare] asks for the default (unwired) seam.
  Widget screen(SetupState state, {bool bare = false}) => setupScreenFor(
    state,
    machine,
    externals: bare ? const SetupExternals() : externals,
  )!;

  Future<void> dispose() async {
    await machine.dispose();
    await transport.close();
    await probe.dispose();
    await listen.dispose();
  }
}

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  double width = 393,
  double height = 1600,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// Every place the rendered tree paints the transport green, at any alpha.
///
/// Walks elements rather than a widget list, so it sees what a `switch` inside
/// a build method actually produced — the same technique `colour_rule_test`
/// uses, kept local so this file needs nothing from it.
List<Color> _greens(WidgetTester tester) {
  final found = <Color>[];
  bool isPositive(Color c) =>
      c.r == StatusPalette.positive.r &&
      c.g == StatusPalette.positive.g &&
      c.b == StatusPalette.positive.b;

  void add(Color? c) {
    if (c != null && isPositive(c)) {
      found.add(c);
    }
  }

  void walk(Element e) {
    switch (e.widget) {
      case Text(:final style):
        add(style?.color);
      case Icon(:final color):
        add(color);
      case Container(:final decoration):
        if (decoration case final BoxDecoration d) {
          add(d.color);
          if (d.border case final Border b) {
            add(b.top.color);
          }
        }
      case ColoredBox(:final color):
        add(color);
      case _:
    }
    e.visitChildElements(walk);
  }

  walk(tester.element(find.byType(SetupScaffold)));
  return found;
}

_Env _fresh({FakePeripheralConfig? config}) {
  final env = _Env(config: config);
  addTearDown(env.dispose);
  return env;
}

void main() {
  setUpAll(loadAppFonts);

  // ── hop 0 — preflight (§13.2.0) ────────────────────────────────────────────
  group('preflight screens', () {
    testWidgets('the primer states plainly what Bluetooth is and is not for', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(const SetupPermissionPrimer()));
      expect(find.text(SetupCopy.primerTitle), findsOneWidget);
      expect(find.text(SetupCopy.primerReassure3), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryAction, SetupCopy.primerPrimary),
        findsOneWidget,
      );
      expect(find.text(SetupCopy.primerNotNow), findsOneWidget);
    });

    testWidgets('Bluetooth-off offers turn-on, then the settings deep-link', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(const SetupBluetoothOff()));
      expect(
        find.widgetWithText(PrimaryAction, SetupCopy.btOffPrimary),
        findsOneWidget,
      );
      expect(find.text(SetupCopy.btOffOpenSettings), findsOneWidget);
    });

    testWidgets('no BLE radio is a terminal instruction — no button, no exit', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(const SetupBluetoothUnsupported()));
      expect(find.text(SetupCopy.unsupportedTitle), findsOneWidget);
      expect(find.textContaining("bridge's screen"), findsOneWidget);
      // The one true dead end: the instruction is the screen (§14.7.1).
      expect(find.byType(PrimaryAction), findsNothing);
      expect(find.byKey(const Key('setup-exit')), findsNothing);
    });

    testWidgets(
      'a soft denial can re-prompt; a permanent one routes to Settings',
      (tester) async {
        final env = _fresh();
        await _pumpAt(
          tester,
          env.screen(const SetupPermissionDenied(permanent: false)),
        );
        expect(
          find.widgetWithText(PrimaryAction, SetupCopy.deniedAllow),
          findsOneWidget,
        );

        await _pumpAt(
          tester,
          env.screen(const SetupPermissionDenied(permanent: true)),
        );
        expect(find.text(SetupCopy.deniedPermanentTitle), findsOneWidget);
        expect(
          find.widgetWithText(PrimaryAction, SetupCopy.deniedOpenAppSettings),
          findsOneWidget,
        );
        expect(find.text(SetupCopy.deniedAllowed), findsOneWidget);
      },
    );

    testWidgets('location-off explains it is Android, not us, that asks', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(const SetupLocationServicesOff()));
      expect(find.text(SetupCopy.locationTitle), findsOneWidget);
      expect(find.textContaining('never uses where you are'), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryAction, SetupCopy.locationOpenSettings),
        findsOneWidget,
      );
    });
  });

  // ── hop 1 — find + pair (§13.2.1) ──────────────────────────────────────────
  group('hop 1 — find', () {
    testWidgets('the scan list sorts by signal and shows the blob line', (
      tester,
    ) async {
      final env = _fresh();
      final weak = _bridge(
        id: '11:22:33',
        name: 'SmokeBridge-Far',
        pit: null,
        rssi: -80,
      );
      final strong = _bridge(rssi: -35);
      await _pumpAt(
        tester,
        env.screen(SetupScanning(found: [weak, strong], scanning: true)),
      );

      // Both rows render...
      expect(
        find.byKey(const Key('setup-bridge-AA:BB:CC:DD:A4:F2')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('setup-bridge-11:22:33')), findsOneWidget);
      // ...the strongest first (§13.2.1).
      final strongY = tester
          .getTopLeft(find.byKey(const Key('setup-bridge-AA:BB:CC:DD:A4:F2')))
          .dy;
      final weakY = tester
          .getTopLeft(find.byKey(const Key('setup-bridge-11:22:33')))
          .dy;
      expect(strongY, lessThan(weakY));
      // The blob line survives unchanged: "pit 243.1 °F · 4 h 12 m".
      expect(find.textContaining('pit 243.1 °F'), findsOneWidget);
      // Rows are the action — no bottom ember button, just Cancel and the exit.
      expect(find.byType(PrimaryAction), findsNothing);
      expect(find.text(SetupCopy.scanningCancel), findsOneWidget);
    });

    // ── 17 §17.3 C — the row is the moment of contact ──────────────────────
    testWidgets('a found row carries signal as bars and a WORD, never dBm', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(
        tester,
        env.screen(
          SetupScanning(
            found: [_bridge(rssi: -35, pit: null, paired: false)],
            scanning: false,
          ),
        ),
      );

      // The bar glyph, and the word beside it — the two together answer
      // "should I move something", which a number does not.
      expect(find.byType(SignalBars), findsOneWidget);
      expect(find.textContaining('Excellent signal'), findsOneWidget);
      // 16 §16.4 rule 3: RSSI and dBm never leave Diagnostics.
      expect(find.textContaining('dBm'), findsNothing);
      expect(find.textContaining('-35'), findsNothing);
      expect(find.textContaining('−35'), findsNothing);
      // The pairing state stays, verbatim — it is honest and useful.
      expect(find.textContaining(SetupCopy.rowNotPaired), findsOneWidget);
    });

    testWidgets('a weak bridge says so in the same words', (tester) async {
      final env = _fresh();
      await _pumpAt(
        tester,
        env.screen(
          SetupScanning(found: [_bridge(rssi: -92)], scanning: false),
        ),
      );
      expect(find.textContaining('Weak signal'), findsOneWidget);
    });

    testWidgets('hop 1 has a subject while it is still searching', (
      tester,
    ) async {
      // 17 §17.1 #4: the bench screen was a rail, a title, a sentence and
      // nothing to look at. The bridge is drawn now, and it is a drawing.
      final env = _fresh();
      await _pumpAt(tester, env.screen(const SetupScanning()));
      expect(find.byKey(const Key('setup-scan-art')), findsOneWidget);
      final art = tester.widget<BridgeIllustration>(
        find.byKey(const Key('setup-scan-art')),
      );
      expect(art.mood, BridgeMood.scanning);
      expect(find.byType(Image), findsNothing);
    });
  });

  // ── 17 §17.3 C — coach the passkey BEFORE the platform's dialog ───────────
  group('hop 1 — what happens next', () {
    testWidgets('tapping a row opens the coach and does NOT start bonding', (
      tester,
    ) async {
      final env = _fresh();
      final before = env.machine.state;
      await _pumpAt(
        tester,
        env.screen(SetupScanning(found: [_bridge()], scanning: false)),
      );
      await tester.tap(find.byKey(const Key('setup-bridge-AA:BB:CC:DD:A4:F2')));
      await tester.pump();

      expect(find.text(SetupCopy.coachTitle), findsOneWidget);
      expect(find.text(SetupCopy.coachBody('SmokeBridge-A4F2')), findsOneWidget);
      // Nothing has been handed to the platform yet — which is the entire
      // point: after this the OS dialog owns the screen.
      expect(env.machine.state, same(before));
    });

    testWidgets('the coach corrects the platform hint before it appears', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(
        tester,
        env.screen(SetupScanning(found: [_bridge()], scanning: false)),
      );
      await tester.tap(find.byKey(const Key('setup-bridge-AA:BB:CC:DD:A4:F2')));
      await tester.pump();

      expect(find.text(SetupCopy.coachStep1), findsOneWidget);
      expect(find.text(SetupCopy.coachStep2), findsOneWidget);
      // The sentence this screen exists for. The platform's own dialog says
      // "Usually 0000 or 1234", cannot be reworded, and is the last thing read
      // before six digits are asked for.
      expect(find.text(SetupCopy.coachStep3), findsOneWidget);
      expect(SetupCopy.coachStep3, contains('0000'));
      expect(SetupCopy.coachStep3, contains('1234'));
      // …and it is chrome, not a sentence in a paragraph (16 §16.5).
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      // Still one ember action and one named way back (rail R1/R2).
      expect(find.byType(PrimaryAction), findsOneWidget);
      expect(find.text(SetupCopy.coachBack), findsOneWidget);
    });

    testWidgets('the coach primary is what actually starts the bond', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(
        tester,
        env.screen(SetupScanning(found: [_bridge()], scanning: false)),
      );
      await tester.tap(find.byKey(const Key('setup-bridge-AA:BB:CC:DD:A4:F2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('setup-coach-pair')));
      // The fake peripheral bonds without a timer, so a couple of frames is
      // enough to drain the machine's microtasks.
      await tester.pump();
      await tester.pump();
      expect(env.machine.state, isA<SetupBonded>());
    });

    testWidgets('the named secondary goes back to the list, not out of setup', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(
        tester,
        env.screen(SetupScanning(found: [_bridge()], scanning: false)),
      );
      await tester.tap(find.byKey(const Key('setup-bridge-AA:BB:CC:DD:A4:F2')));
      await tester.pump();
      await tester.tap(find.text(SetupCopy.coachBack));
      await tester.pump();

      expect(find.text(SetupCopy.scanningTitle), findsOneWidget);
      expect(
        find.byKey(const Key('setup-bridge-AA:BB:CC:DD:A4:F2')),
        findsOneWidget,
      );
      expect(env.fired('leave'), 0);
    });

    testWidgets('nothing-found is a checklist of the bridge\'s own tells', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(const SetupNoBridges()));
      expect(find.text(SetupCopy.noBridgesTitle), findsOneWidget);
      expect(find.text(SetupCopy.noBridgesCheck1), findsOneWidget);
      expect(find.text(SetupCopy.noBridgesCheck2), findsOneWidget);
      expect(find.text(SetupCopy.noBridgesCheck3), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryAction, SetupCopy.noBridgesLookAgain),
        findsOneWidget,
      );
      expect(find.text(SetupCopy.noBridgesManual), findsOneWidget);
    });

    testWidgets('the already-provisioned fork adds this phone in seconds', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(SetupAddThisPhone(_bridge())));
      expect(find.text(SetupCopy.addPhoneTitle), findsOneWidget);
      expect(find.text('SmokeBridge-A4F2'), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryAction, SetupCopy.addPhonePrimary),
        findsOneWidget,
      );
      expect(find.text(SetupCopy.addPhoneOther), findsOneWidget);
    });
  });

  group('hop 1 — the passkey screen', () {
    testWidgets('points at the bridge and renders no code of its own', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(
        tester,
        env.screen(SetupPairing(bridge: _bridge(), passkeyShown: true)),
      );
      expect(find.text(SetupCopy.pairTitle), findsOneWidget);
      expect(find.byType(PasskeyDisplay), findsOneWidget);
      // The illustration is incapable of a real digit (§13.2.1).
      final glyphs = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(PasskeyDisplay),
              matching: find.byType(Text),
            ),
          )
          .map((w) => w.data ?? '');
      for (final s in glyphs) {
        expect(_digit.hasMatch(s), isFalse, reason: 'passkey drew "$s"');
      }
      // Waiting narration, not a bare spinner.
      expect(find.text(SetupCopy.pairWaiting), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryAction, SetupCopy.pairNoPrompt),
        findsOneWidget,
      );

      // 17 §17.3 C: the bridge is drawn, the frame is captioned as *its*
      // screen, and the platform's wrong hint is still contradicted here —
      // because the OS dialog is drawn over this, can be dismissed, and on
      // some phones lands in the notification shade instead.
      expect(find.byKey(const Key('setup-pair-art')), findsOneWidget);
      expect(find.text(SetupCopy.pairCallout), findsOneWidget);
      expect(find.text(SetupCopy.pairIgnoreHint), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      // One wording across the two screens, not two (16 §16.4's single voice).
      expect(SetupCopy.pairIgnoreHint, SetupCopy.coachStep3);
    });

    testWidgets('before the prompt it names what it is connecting to', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(SetupPairing(bridge: _bridge())));
      expect(
        find.text(SetupCopy.connectingTo('SmokeBridge-A4F2')),
        findsOneWidget,
      );
    });

    testWidgets('no OS prompt after 30 s points at the notification shade', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(SetupPasskeyNotSeen(_bridge())));
      expect(find.text(SetupCopy.notSeenTitle), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryAction, SetupCopy.notSeenCheckNotifications),
        findsOneWidget,
      );
      expect(find.text(SetupCopy.notSeenRetry), findsOneWidget);
    });

    testWidgets('bonded is a payoff with a forward step, not a modal', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(SetupBonded(_bridge())));
      expect(find.text(SetupCopy.bondedTitle), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryAction, SetupCopy.bondedContinue),
        findsOneWidget,
      );
      // The payoff shows the device with the tick on its own glass — the same
      // thing the bridge's OLED is showing at this moment — not a checkmark
      // floating on black (17 §17.3 C).
      final art = tester.widget<BridgeIllustration>(
        find.byKey(const Key('setup-bonded-art')),
      );
      expect(art.mood, BridgeMood.linked);
    });
  });

  group('hop 1 — the four bond outcomes are four screens (§13.2.1)', () {
    testWidgets('a wrong code says so, and offers a real retry', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(SetupPasskeyWrong(_bridge())));
      expect(find.text(SetupCopy.wrongTitle), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryAction, SetupCopy.wrongRetry),
        findsOneWidget,
      );
      expect(find.text(SetupCopy.wrongStartOver), findsOneWidget);
    });

    testWidgets('a reset bridge asks to forget-and-repair, not retry', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(SetupRebondNeeded(_bridge())));
      expect(find.text(SetupCopy.rebondTitle), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryAction, SetupCopy.rebondOpenSettings),
        findsOneWidget,
      );
    });

    testWidgets(
      'full slots offers another bridge; remove-a-phone needs op 15',
      (tester) async {
        final env = _fresh();
        await _pumpAt(tester, env.screen(SetupBondSlotsFull(_bridge())));
        expect(find.text(SetupCopy.fullTitle), findsOneWidget);
        expect(
          find.widgetWithText(PrimaryAction, SetupCopy.fullChooseOther),
          findsOneWidget,
        );
        expect(find.text(SetupCopy.fullRemovePhone), findsOneWidget);
      },
    );

    testWidgets('not-a-bridge has NO retry, only "pick another"', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(SetupNotABridge(_bridge())));
      expect(find.text(SetupCopy.notBridgeTitle), findsOneWidget);
      expect(
        find.widgetWithText(PrimaryAction, SetupCopy.notBridgeChoose),
        findsOneWidget,
      );
      // Exactly one action, and it is not a retry.
      expect(find.byType(PrimaryAction), findsOneWidget);
    });
  });

  // ── the shape every state honours: ≤1 primary, an honest exit ──────────────
  group('one primary and an honest exit (rail R1/R2)', () {
    final cases = <(String, SetupState, bool, bool)>[
      ('primer', const SetupPermissionPrimer(), true, true),
      ('btOff', const SetupBluetoothOff(), true, true),
      ('unsupported', const SetupBluetoothUnsupported(), false, false),
      ('deniedSoft', const SetupPermissionDenied(permanent: false), true, true),
      ('deniedPerm', const SetupPermissionDenied(permanent: true), true, true),
      ('locationOff', const SetupLocationServicesOff(), true, true),
      (
        'scanning',
        SetupScanning(found: [_bridge()], scanning: true),
        false,
        true,
      ),
      ('noBridges', const SetupNoBridges(), true, true),
      ('addPhone', SetupAddThisPhone(_bridge()), true, true),
      ('pairing', SetupPairing(bridge: _bridge()), true, true),
      ('notSeen', SetupPasskeyNotSeen(_bridge()), true, true),
      ('bonded', SetupBonded(_bridge()), true, true),
      ('wrong', SetupPasskeyWrong(_bridge()), true, true),
      ('rebond', SetupRebondNeeded(_bridge()), true, true),
      ('full', SetupBondSlotsFull(_bridge()), true, true),
      ('notABridge', SetupNotABridge(_bridge()), true, true),
    ];

    for (final (name, state, hasPrimary, hasExit) in cases) {
      testWidgets('$name has ${hasPrimary ? "one" : "no"} primary and '
          '${hasExit ? "an" : "no"} exit', (tester) async {
        final env = _fresh();
        await _pumpAt(tester, env.screen(state));
        expect(
          find.byType(PrimaryAction),
          hasPrimary ? findsOneWidget : findsNothing,
          reason: '$name primary count',
        );
        expect(
          find.byKey(const Key('setup-exit')),
          hasExit ? findsOneWidget : findsNothing,
          reason: '$name exit',
        );
      });
    }
  });

  // ── the injected deep-links: wired when present, disabled when not ─────────
  group('the platform deep-links', () {
    testWidgets('the exit leaves the /setup route', (tester) async {
      final env = _fresh();
      await _pumpAt(tester, env.screen(const SetupPermissionPrimer()));
      await tester.tap(find.byKey(const Key('setup-exit')));
      expect(env.fired('leave'), 1);
    });

    testWidgets('each secondary/primary link fires its callback', (
      tester,
    ) async {
      final env = _fresh();

      await _pumpAt(tester, env.screen(const SetupBluetoothOff()));
      await tester.tap(find.text(SetupCopy.btOffOpenSettings));
      expect(env.fired('bt'), 1);

      await _pumpAt(
        tester,
        env.screen(const SetupPermissionDenied(permanent: true)),
      );
      await tester.tap(find.text(SetupCopy.deniedOpenAppSettings));
      expect(env.fired('app'), 1);

      await _pumpAt(tester, env.screen(const SetupLocationServicesOff()));
      await tester.tap(find.text(SetupCopy.locationOpenSettings));
      expect(env.fired('loc'), 1);

      await _pumpAt(tester, env.screen(SetupPasskeyNotSeen(_bridge())));
      await tester.tap(find.text(SetupCopy.notSeenCheckNotifications));
      expect(env.fired('notif'), 1);

      await _pumpAt(tester, env.screen(const SetupNoBridges()));
      await tester.tap(find.text(SetupCopy.noBridgesManual));
      expect(env.fired('addr'), 1);

      await _pumpAt(tester, env.screen(SetupBondSlotsFull(_bridge())));
      await tester.tap(find.text(SetupCopy.fullRemovePhone));
      expect(env.fired('remove'), 1);
    });

    testWidgets('an un-wired link disables its button rather than lying', (
      tester,
    ) async {
      final env = _fresh();
      await _pumpAt(
        tester,
        env.screen(const SetupPermissionDenied(permanent: true), bare: true),
      );
      // Primary present but dead (§14.7.1: never a live-looking dead button)...
      final action = tester.widget<PrimaryAction>(find.byType(PrimaryAction));
      expect(action.onPressed, isNull);
      // ...and with no route callback, no exit is drawn.
      expect(find.byKey(const Key('setup-exit')), findsNothing);
    });

    // 16 §16.5 and the hard rule beneath it: a control that cannot work is
    // absent, or disabled **with its reason**. A dimmed button on its own is
    // still a dead control — it just looks deliberate.
    testWidgets('a dead control states what to do instead', (tester) async {
      final env = _fresh();
      final cases = <(SetupState, String)>[
        (SetupPasskeyNotSeen(_bridge()), SetupCopy.noDeepLinkNotifications),
        (const SetupLocationServicesOff(), SetupCopy.noDeepLinkLocation),
        (SetupRebondNeeded(_bridge()), SetupCopy.noDeepLinkBluetoothSettings),
        (SetupBondSlotsFull(_bridge()), SetupCopy.noRemovePhone),
        (const SetupNoBridges(), SetupCopy.noManualAddress),
      ];
      for (final (state, reason) in cases) {
        await _pumpAt(tester, env.screen(state, bare: true));
        expect(
          find.text(reason),
          findsOneWidget,
          reason: '${state.runtimeType} dims a control without saying why',
        );
        // And the reason disappears the moment the control can work.
        await _pumpAt(tester, env.screen(state));
        expect(find.text(reason), findsNothing);
      }
    });
  });

  // ── no overflow, at every state, at the three phone widths (§14.5) ─────────
  group('no overflow across phone widths', () {
    final states = <(String, SetupState)>[
      ('primer', const SetupPermissionPrimer()),
      ('btOff', const SetupBluetoothOff()),
      ('unsupported', const SetupBluetoothUnsupported()),
      ('deniedPerm', const SetupPermissionDenied(permanent: true)),
      ('locationOff', const SetupLocationServicesOff()),
      (
        'scanning',
        SetupScanning(
          found: [
            _bridge(),
            _bridge(id: '11:22:33', name: 'SmokeBridge-Far'),
          ],
          scanning: true,
        ),
      ),
      ('noBridges', const SetupNoBridges()),
      ('addPhone', SetupAddThisPhone(_bridge())),
      ('pairing', SetupPairing(bridge: _bridge(), passkeyShown: true)),
      ('full', SetupBondSlotsFull(_bridge())),
    ];

    for (final (name, state) in states) {
      for (final w in _widths) {
        testWidgets('$name fits at ${w.toInt()} dp', (tester) async {
          final env = _fresh();
          await _pumpAt(tester, env.screen(state), width: w);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  // ── 17 §17.5 — warm, but green never celebrates ───────────────────────────
  group('the palette hop 1 is allowed, and the one it is not', () {
    testWidgets('a found bridge is an ember-accented card, not a plain row', (
      tester,
    ) async {
      // There is no session and no reading anywhere on this hop, so §16.5 has
      // nothing to guard and §17.5 lets the moment of contact look like one.
      final env = _fresh();
      await _pumpAt(
        tester,
        env.screen(SetupScanning(found: [_bridge()], scanning: false)),
      );
      final card = tester.widget<SmokeCard>(
        find.byKey(const Key('setup-bridge-AA:BB:CC:DD:A4:F2')),
      );
      expect(card.accent, StatusPalette.pit);
    });

    testWidgets('no hop-1 screen spends the transport green', (tester) async {
      // The one clause §17.5 does not relax: green means transport health, and
      // a bond landing is not a transport report — it is a step finishing. The
      // ember does the celebrating.
      final env = _fresh();
      final states = <SetupState>[
        const SetupScanning(),
        SetupScanning(found: [_bridge()], scanning: false),
        const SetupNoBridges(),
        SetupAddThisPhone(_bridge()),
        SetupPairing(bridge: _bridge(), passkeyShown: true),
        SetupPasskeyNotSeen(_bridge()),
        SetupBonded(_bridge()),
        SetupPasskeyWrong(_bridge()),
      ];
      for (final state in states) {
        await _pumpAt(tester, env.screen(state));
        expect(
          _greens(tester),
          isEmpty,
          reason: '${state.runtimeType} painted the transport green',
        );
      }
    });
  });

  // ── the illustrated screens, on a short phone at 200 % text (§16.7) ────────
  //
  // The case the drawings could plausibly break, and the reason `SetupScaffold`
  // gained `SetupBodyCenter`: at 200 % the title and subtitle eat most of the
  // body slot, and a fixed-height picture centred in what is left overflows —
  // as a yellow-and-black stripe, on the first screen of the product.
  group('illustrated screens at 200% text on a short phone', () {
    for (final w in <double>[360, 600, 840]) {
      testWidgets('the find list fits at ${w.toInt()} dp', (tester) async {
        final env = _fresh();
        await _pumpAt(
          tester,
          env.screen(SetupScanning(found: [_bridge()], scanning: true)),
          width: w,
          height: 640,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the coach fits at ${w.toInt()} dp', (tester) async {
        final env = _fresh();
        await _pumpAt(
          tester,
          env.screen(SetupScanning(found: [_bridge()], scanning: false)),
          width: w,
          height: 640,
          textScale: 2,
        );
        // At 200 % the row can sit below the fold; scrolling to it is the
        // user's own first move, so the test makes it too.
        final row = find.byKey(const Key('setup-bridge-AA:BB:CC:DD:A4:F2'));
        await tester.ensureVisible(row);
        await tester.pump();
        await tester.tap(row);
        await tester.pump();
        expect(find.text(SetupCopy.coachTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the passkey screen fits at ${w.toInt()} dp', (tester) async {
        final env = _fresh();
        await _pumpAt(
          tester,
          env.screen(SetupPairing(bridge: _bridge(), passkeyShown: true)),
          width: w,
          height: 640,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the payoff fits at ${w.toInt()} dp', (tester) async {
        final env = _fresh();
        await _pumpAt(
          tester,
          env.screen(SetupBonded(_bridge())),
          width: w,
          height: 640,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── the stale-bond heal (A24.11) ─────────────────────────────────────────
  group('stale bond against a factory-reset bridge', () {
    test('heals itself: drop the dead bond, pair fresh, land bonded', () async {
      final env = _fresh(config: const FakePeripheralConfig(staleBond: true));
      await env.machine.select(_bridge());
      // The machine dropped the stale OS bond ONCE and re-paired — the user
      // never saw a failure screen, let alone a raw timeout.
      expect(env.fake.removeBondCalls, 1);
      expect(env.machine.state, isA<SetupBonded>());
    });

    test('falls back to the manual screen when the platform refuses', () async {
      final env = _fresh(
        config: const FakePeripheralConfig(
          staleBond: true,
          refuseRemoveBond: true,
        ),
      );
      await env.machine.select(_bridge());
      // removeBond was attempted, refused — the honest fallback is the
      // "forget it in Bluetooth settings" screen, not a crash.
      expect(env.fake.removeBondCalls, 1);
      expect(env.machine.state, isA<SetupRebondNeeded>());
    });
  });
}
