/// A23.4 — a widget per hop-2, hop-3 and finish `SetupState` (design 13
/// §13.2.2–§13.2.4), and the [setupNetScreenFor] dispatcher.
///
/// The discipline mirrors the component tests (`ui/setup_components_test.dart`):
/// fonts loaded so overflow is measured against shipping metrics, every screen
/// checked at 360 / 393 / 430 dp with `takeException()`, and the load-bearing
/// facts of each state pinned — the payoff renders real temperatures, the
/// password field validates length before Connect enables and reveals on retry,
/// applying narrates four phases, each Wi-Fi failure states its own reason, and
/// the summary shows a skipped hop as "— not set up" with a dash on the rail.
///
/// Screens are driven by a real [SetupMachine] on fake seams (no widgets in the
/// machine, no radio) so a tapped primary calls a real method and rail R3
/// (no throw escapes) is exercised at the UI boundary.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/features/setup/copy/base_sync_copy.dart';
import 'package:smoke_bridge/features/setup/copy/setup_net_copy.dart';
import 'package:smoke_bridge/features/setup/preflight.dart';
import 'package:smoke_bridge/features/setup/screens/finish_screens.dart';
import 'package:smoke_bridge/features/setup/setup_machine.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../data/fake_peripheral.dart';
import '../support/load_fonts.dart';

const _widths = <double>[360, 393, 430];

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

WifiScanResult _ap(String ssid, {int rssi = -55, int auth = 3}) =>
    WifiScanResult(rssi: rssi, auth: auth, channel: 6, ssidRaw: _b(ssid));

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, [
  double width = 393,
]) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(child));
}

/// A real machine on fake seams; disposed at teardown. `delay` never completes,
/// so no budget ever fires on its own and no wall-clock timer leaks.
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
    joinAp: (s, p) async => true,
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

/// The `onPressed` of the [PrimaryAction] under [key], or null when disabled.
VoidCallback? _primaryOnPressed(WidgetTester tester, Key key) {
  final button = tester.widget<FilledButton>(
    find.descendant(of: find.byKey(key), matching: find.byType(FilledButton)),
  );
  return button.onPressed;
}

void main() {
  setUpAll(loadAppFonts);

  // ══ hop 2 (§13.2.2) ═══════════════════════════════════════════════════
  group('hop 2 screens', () {
    testWidgets('intro shows the SYNC gesture and both actions', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(tester, setupNetScreenFor(const SetupBaseIntro(), m));
      expect(find.text(BaseSyncCopy.introHeadline), findsOneWidget);
      expect(find.text('SYNC'), findsOneWidget);
      expect(find.byKey(const Key('base-intro-primary')), findsOneWidget);
      expect(find.text(BaseSyncCopy.introSkip), findsOneWidget);
      expect(find.byKey(const Key('setup-exit')), findsOneWidget);
    });

    testWidgets('listening shows the count-up and the keep-close hint', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(const SetupBaseListening(elapsed: Duration.zero), m),
      );
      expect(find.text(BaseSyncCopy.listening), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text(BaseSyncCopy.listeningKeepClose), findsOneWidget);
    });

    testWidgets('a faint signal is a listening sub-state, not a failure', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupBaseListening(elapsed: Duration.zero, garbled: 2),
          m,
        ),
      );
      expect(find.text(BaseSyncCopy.garbledFaint), findsOneWidget);
    });

    testWidgets('heard narrates the wait and names the base', (tester) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(const SetupBaseHeard(deviceId: '3F91'), m),
      );
      expect(find.textContaining('3F91'), findsOneWidget);
      expect(find.text(BasePayoffCopy.heardBody), findsOneWidget);
    });

    testWidgets('confirmed renders a real temperature per probe', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupBaseConfirmed(
            deviceId: '3F91',
            numProbes: 4,
            temps: [2431, 680, null, null],
          ),
          m,
        ),
      );
      expect(find.text(BasePayoffCopy.confirmedHeadline), findsOneWidget);
      // Four probe readings, two of them real numbers, never a checkmark count.
      expect(find.byType(AnimatedTemp), findsNWidgets(4));
      expect(find.text('243'), findsOneWidget);
      expect(find.text('68'), findsOneWidget);
      expect(find.byKey(const Key('base-confirmed-primary')), findsOneWidget);
    });

    testWidgets('skip is real: states the consequence and moves to Wi-Fi', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(tester, setupNetScreenFor(const SetupBaseSkipped(), m));
      expect(find.text(BaseSyncCopy.skippedCard), findsOneWidget);
      expect(find.byKey(const Key('base-skipped-primary')), findsOneWidget);
    });

    testWidgets('each failure reason states its own cause', (tester) async {
      for (final reason in BaseSyncFailure.values) {
        final m = _machine();
        await _pumpAt(
          tester,
          setupNetScreenFor(SetupBaseFailed(reason: reason), m),
        );
        expect(
          find.text(BaseSyncCopy.failureHeadline(reason)),
          findsOneWidget,
          reason: 'reason $reason must render its own headline',
        );
        expect(find.byKey(const Key('base-failed-primary')), findsOneWidget);
      }
    });

    testWidgets('the intro skip is wired to the machine', (tester) async {
      final m = _machine();
      await _pumpAt(tester, setupNetScreenFor(const SetupBaseIntro(), m));
      await tester.tap(find.text(BaseSyncCopy.introSkip));
      await tester.pump();
      expect(m.state, isA<SetupBaseSkipped>());
    });
  });

  // ══ hop 3 (§13.2.3) ═══════════════════════════════════════════════════
  group('hop 3 — picker', () {
    testWidgets('lists networks and offers hidden + hosted links', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          SetupNetworkPick(networks: [_ap('Backyard')], scanning: false),
          m,
        ),
      );
      expect(find.text(SetupNetCopy.pickTitle), findsOneWidget);
      expect(find.byKey(const Key('wifi-Backyard')), findsOneWidget);
      expect(find.byKey(const Key('network-hidden-link')), findsOneWidget);
      expect(find.byKey(const Key('network-hosted-link')), findsOneWidget);
      // A25: Bluetooth-only is the default forward action — Wi-Fi opts in
      // by tapping a network row.
      expect(find.byKey(const Key('network-ble-only')), findsOneWidget);
      // Under two failures, hosted is NOT the primary.
      expect(
        find.byKey(const Key('network-pick-hosted-primary')),
        findsNothing,
      );
    });

    testWidgets('Bluetooth-only finishes the network hop (A25)', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          SetupNetworkPick(networks: [_ap('Backyard')], scanning: false),
          m,
        ),
      );
      await tester.tap(find.byKey(const Key('network-ble-only')));
      await tester.pumpAndSettle();
      // Straight to name + units — no Wi-Fi hoop, no warning.
      expect(m.state, isA<SetupNameAndUnits>());
    });

    testWidgets('an enterprise row is disabled with a stated reason', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          SetupNetworkPick(networks: [_ap('Campus', auth: 5)], scanning: false),
          m,
        ),
      );
      expect(find.text(SetupNetCopy.enterpriseDisabled), findsOneWidget);
      final card = tester.widget<SmokeCard>(
        find.byKey(const Key('wifi-Campus')),
      );
      expect(card.onTap, isNull, reason: 'enterprise is not tappable');
    });

    testWidgets('two failures make hosted the primary', (tester) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          SetupNetworkPick(
            networks: [_ap('Backyard')],
            scanning: false,
            failureCount: 2,
          ),
          m,
        ),
      );
      expect(
        find.byKey(const Key('network-pick-hosted-primary')),
        findsOneWidget,
      );
      // The tertiary hosted link is gone once hosted is the primary.
      expect(find.byKey(const Key('network-hosted-link')), findsNothing);
      // Bluetooth-only stays reachable as the secondary (A25).
      expect(find.byKey(const Key('network-ble-only-link')), findsOneWidget);
    });

    testWidgets('empty makes hosted the primary automatically', (tester) async {
      final m = _machine();
      await _pumpAt(tester, setupNetScreenFor(const SetupNetworkEmpty(), m));
      expect(find.text(SetupNetCopy.emptyTitle), findsOneWidget);
      expect(find.byKey(const Key('network-empty-primary')), findsOneWidget);
    });

    testWidgets('manual entry has an SSID field and an auth selector', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(tester, setupNetScreenFor(const SetupNetworkManual(), m));
      expect(find.byKey(const Key('manual-ssid-field')), findsOneWidget);
      expect(find.byType(SegmentedChips<int>), findsOneWidget);
      // Continue is disabled until a name is typed.
      expect(_primaryOnPressed(tester, const Key('manual-primary')), isNull);
      await tester.enterText(find.byKey(const Key('manual-ssid-field')), 'Hi');
      await tester.pump();
      expect(_primaryOnPressed(tester, const Key('manual-primary')), isNotNull);
    });
  });

  group('hop 3 — password', () {
    testWidgets('validates length before Connect enables', (tester) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(const SetupNetworkPassword(ssid: 'Backyard'), m),
      );
      // Too short → disabled.
      await tester.enterText(find.byKey(const Key('password-field')), '123');
      await tester.pump();
      expect(_primaryOnPressed(tester, const Key('password-primary')), isNull);
      // 8+ chars → enabled.
      await tester.enterText(
        find.byKey(const Key('password-field')),
        'hunter2boo',
      );
      await tester.pump();
      expect(
        _primaryOnPressed(tester, const Key('password-primary')),
        isNotNull,
      );
    });

    testWidgets('a fresh field is obscured; the toggle reveals it', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(const SetupNetworkPassword(ssid: 'Backyard'), m),
      );
      TextField field() =>
          tester.widget<TextField>(find.byKey(const Key('password-field')));
      expect(field().obscureText, isTrue);
      await tester.tap(find.byKey(const Key('password-reveal')));
      await tester.pump();
      expect(field().obscureText, isFalse);
    });

    testWidgets('retry prefills, reveals, and states the error', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupNetworkPassword(
            ssid: 'Backyard',
            prefill: 'WRONGpass',
            error: 'Incorrect password for Backyard',
          ),
          m,
        ),
      );
      final field = tester.widget<TextField>(
        find.byKey(const Key('password-field')),
      );
      expect(field.controller?.text, 'WRONGpass');
      expect(field.obscureText, isFalse, reason: 'retry opens revealed');
      expect(find.text('Incorrect password for Backyard'), findsOneWidget);
    });
  });

  group('hop 3 — applying and failures', () {
    testWidgets('applying narrates four phases with a cancel', (tester) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupApplying(phase: ApplyingPhase.joining, ssid: 'MyHouse'),
          m,
        ),
      );
      expect(find.text('Sent your network to the bridge'), findsOneWidget);
      expect(find.text('The bridge is joining MyHouse'), findsOneWidget);
      expect(find.text('Getting an address'), findsOneWidget);
      expect(find.text('Checking this phone can reach it'), findsOneWidget);
      expect(find.byKey(const Key('applying-cancel')), findsOneWidget);
      // The phase before the active one is done; the ones after are pending.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.circle_outlined), findsNWidgets(2));
    });

    testWidgets('each Wi-Fi failure reason has its own headline', (
      tester,
    ) async {
      for (final reason in WifiFailure.values) {
        final m = _machine();
        await _pumpAt(
          tester,
          setupNetScreenFor(
            SetupWifiFailed(reason: reason, ssid: 'Backyard'),
            m,
          ),
        );
        final copy = SetupNetCopy.wifiFailure(reason, 'Backyard');
        expect(
          find.text(copy.headline),
          findsOneWidget,
          reason: 'reason $reason must not collapse into one sentence',
        );
      }
    });

    testWidgets('after two attempts hosted becomes the primary', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupWifiFailed(
            reason: WifiFailure.wrongPassword,
            ssid: 'Backyard',
            attempts: 2,
          ),
          m,
        ),
      );
      expect(find.text(SetupNetCopy.useHosted), findsWidgets);
      expect(find.text(SetupNetCopy.wifiRetryPassword), findsOneWidget);
    });

    testWidgets('a wifi failure retry is wired back to the password', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupWifiFailed(
            reason: WifiFailure.wrongPassword,
            ssid: 'Backyard',
          ),
          m,
        ),
      );
      await tester.tap(find.byKey(const Key('wifi-failed-primary')));
      await tester.pump();
      expect(m.state, isA<SetupNetworkPassword>());
    });

    testWidgets('unreachable shows the IP it is hiding today', (tester) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(const SetupUnreachable(ip: '192.168.1.57'), m),
      );
      expect(find.text('192.168.1.57'), findsOneWidget);
      expect(find.byKey(const Key('unreachable-primary')), findsOneWidget);
    });
  });

  group('hop 3 — hosted', () {
    testWidgets('hosted join shows SSID and PSK on screen', (tester) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupHostedJoin(ssid: 'SmokeBridge-A4F2', psk: 'k7Ru4mXwTz'),
          m,
        ),
      );
      expect(find.text('SmokeBridge-A4F2'), findsOneWidget);
      expect(find.text('k7Ru4mXwTz'), findsOneWidget);
      expect(find.byKey(const Key('hosted-join-primary')), findsOneWidget);
    });

    testWidgets('a refused join still shows the credentials', (tester) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupHostedRefused(ssid: 'SmokeBridge-A4F2', psk: 'k7Ru4mXwTz'),
          m,
        ),
      );
      expect(find.text('k7Ru4mXwTz'), findsOneWidget);
      expect(find.byKey(const Key('hosted-refused-primary')), findsOneWidget);
    });
  });

  // ══ finish (§13.2.4) ══════════════════════════════════════════════════
  group('finish screens', () {
    testWidgets('name + units asks both, once', (tester) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupNameAndUnits(suggestedName: 'Backyard'),
          m,
        ),
      );
      final field = tester.widget<TextField>(
        find.byKey(const Key('name-field')),
      );
      expect(field.controller?.text, 'Backyard');
      expect(find.byType(SegmentedChips<bool>), findsOneWidget);

      await tester.tap(find.byKey(const Key('name-primary')));
      await tester.pump();
      final done = m.state as SetupDone;
      expect(done.summary.bridgeName, 'Backyard');
    });

    testWidgets('done shows the three-row summary, skipped hop as not-set-up', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(
          const SetupDone(
            SetupSummary(
              bridgeName: 'Backyard smoker',
              blePaired: true,
              wifiSsid: 'MyHouse',
              ip: '192.168.1.57',
            ),
          ),
          m,
        ),
      );
      expect(find.text('Backyard smoker is ready'), findsOneWidget);
      expect(find.text(SetupFinishCopy.doneBluetooth), findsOneWidget);
      expect(find.text(SetupFinishCopy.doneSmokeX), findsOneWidget);
      expect(find.text(SetupFinishCopy.doneWifi), findsOneWidget);
      // Base was skipped → "— not set up" and a dash on the rail.
      expect(find.text(SetupFinishCopy.doneNotSetUp), findsOneWidget);
      expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    });

    testWidgets('done "See my probes" is wired to the finish handler', (
      tester,
    ) async {
      var finished = false;
      await _pumpAt(
        tester,
        SetupDoneScreen(
          summary: const SetupSummary(bridgeName: 'Backyard', blePaired: true),
          onSeeProbes: () => finished = true,
        ),
      );
      await tester.tap(find.byKey(const Key('done-primary')));
      expect(finished, isTrue);
    });

    testWidgets('link lost offers reconnect and restart', (tester) async {
      final m = _machine();
      await _pumpAt(tester, setupNetScreenFor(const SetupLinkLost(), m));
      expect(find.text(SetupFinishCopy.linkLostTitle), findsOneWidget);
      expect(find.byKey(const Key('link-lost-primary')), findsOneWidget);
      expect(find.text(SetupFinishCopy.linkLostRestart), findsOneWidget);
    });

    testWidgets('fault shows the detail and a start-over', (tester) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(const SetupFault(detail: 'boom'), m),
      );
      expect(find.text(SetupFinishCopy.faultTitle), findsOneWidget);
      expect(find.text('boom'), findsOneWidget);
      expect(find.byKey(const Key('fault-primary')), findsOneWidget);
    });
  });

  // ══ the dispatcher ════════════════════════════════════════════════════
  group('setupNetScreenFor', () {
    test('returns a shrink for states this agent does not own', () {
      final m = _machine();
      expect(setupNetScreenFor(const SetupScanning(), m), isA<SizedBox>());
      expect(
        setupNetScreenFor(const SetupPermissionPrimer(), m),
        isA<SizedBox>(),
      );
    });
  });

  // ══ no overflow across phone widths ═══════════════════════════════════
  group('no overflow across widths', () {
    final samples = <String, SetupState>{
      'intro': const SetupBaseIntro(),
      'listening': const SetupBaseListening(elapsed: Duration.zero, garbled: 2),
      'confirmed': const SetupBaseConfirmed(
        deviceId: '3F91',
        numProbes: 4,
        temps: [2431, 680, null, null],
      ),
      'failed': const SetupBaseFailed(reason: BaseSyncFailure.garbled),
      'pick': SetupNetworkPick(
        networks: [_ap('Backyard'), _ap('Campus', auth: 5)],
        scanning: false,
      ),
      'password': const SetupNetworkPassword(
        ssid: 'A-very-long-network-name-that-could-wrap',
        error:
            'Incorrect password for A-very-long-network-name-that-could-wrap',
      ),
      'applying': const SetupApplying(
        phase: ApplyingPhase.gettingAddress,
        ssid: 'MyHouse',
      ),
      'wifiFailed': const SetupWifiFailed(
        reason: WifiFailure.notFound,
        ssid: 'MyHouse_5G',
        attempts: 2,
      ),
      'unreachable': const SetupUnreachable(ip: '192.168.1.57'),
      'hosted': const SetupHostedJoin(
        ssid: 'SmokeBridge-A4F2',
        psk: 'k7Ru4mXwTz',
      ),
      'nameUnits': const SetupNameAndUnits(suggestedName: 'Backyard smoker'),
      'done': const SetupDone(
        SetupSummary(bridgeName: 'Backyard smoker', blePaired: true),
      ),
      'fault': const SetupFault(
        detail: 'TimeoutException after 0:00:10.000000',
      ),
    };

    for (final entry in samples.entries) {
      for (final w in _widths) {
        testWidgets('${entry.key} fits at ${w.toInt()} dp', (tester) async {
          final m = _machine();
          await _pumpAt(tester, setupNetScreenFor(entry.value, m), w);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  // ══ factory reset over Bluetooth (A24.2) ══════════════════════════════
  group('reset over Bluetooth', () {
    testWidgets('unreachable offers a BLE reset behind a destructive confirm', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(
        tester,
        setupNetScreenFor(const SetupUnreachable(ip: '192.168.1.42'), m),
      );
      // The recovery for a stale/unreachable bridge with no USB: wipe it over
      // the already-bonded BLE link.
      final resetBtn = find.byKey(const Key('unreachable-reset'));
      expect(resetBtn, findsOneWidget);
      expect(find.text(SetupNetCopy.resetBridge), findsOneWidget);

      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // Destructive → the wipe is spelled out, not a silent button.
      expect(find.text(SetupNetCopy.resetConfirmTitle), findsOneWidget);
      expect(find.textContaining('wipes the bridge'), findsOneWidget);
      expect(
        find.byKey(const Key('unreachable-reset-confirm')),
        findsOneWidget,
      );
    });

    testWidgets('the reset-done screen tells you to forget the stale pairing', (
      tester,
    ) async {
      final m = _machine();
      await _pumpAt(tester, setupNetScreenFor(const SetupResetDone(), m));
      expect(find.text(SetupNetCopy.resetDoneTitle), findsOneWidget);
      expect(find.textContaining('forget'), findsOneWidget);
      expect(find.byKey(const Key('reset-done-primary')), findsOneWidget);
    });
  });
}

// ── minimal fakes for the machine's non-BLE seams ─────────────────────────

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
