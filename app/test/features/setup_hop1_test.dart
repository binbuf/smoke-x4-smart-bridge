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
import 'package:smoke_bridge/features/setup/copy/setup_copy.dart';
import 'package:smoke_bridge/features/setup/preflight.dart';
import 'package:smoke_bridge/features/setup/screens/hop1_screens.dart';
import 'package:smoke_bridge/features/setup/screens/preflight_screens.dart';
import 'package:smoke_bridge/features/setup/setup_machine.dart';
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
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
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

  // ── the stale-bond heal (A24.11) ─────────────────────────────────────────
  group('stale bond against a factory-reset bridge', () {
    test('heals itself: drop the dead bond, pair fresh, land bonded', () async {
      final env = _fresh(
        config: const FakePeripheralConfig(staleBond: true),
      );
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
