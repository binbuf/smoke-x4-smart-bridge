/// N10 — the connection surfaces, provisioning flows and the exit gate.
///
/// Every connection-matrix scenario is rendered through the real bodies: the
/// app-bar chip's projection, the connect sheet's dual rows and recovery path,
/// the mode cards and reference, the STA/AP provisioning sheets, and the
/// Settings bridge card.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dev_panel.dart';
import 'package:smoke_bridge/data/model/connection_state.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/data/repository/prefs_repository.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/connection/connection.dart';
import 'package:smoke_bridge/features/shell/shell.dart';
import 'package:smoke_bridge/features/shell/transport_status.dart';

import '../support/load_fonts.dart';

const int _now = 1700000000000;

/// Captures the shell callbacks a body fires.
class _Harness {
  DevOverlay? overlay;
  Map<String, String> props = const <String, String>{};
  String? toast;
  int closed = 0;
  int closeCalls = 0;
}

MockBridgeRepository _repo(String scenario) =>
    MockBridgeRepository(nowMs: _now, initialScenario: scenario);

Future<_Harness> _pump(
  WidgetTester tester,
  Widget child, {
  required MockBridgeRepository repo,
  _Harness? harness,
}) async {
  tester.view
    ..physicalSize = const Size(500, 3000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = MockPrefsRepository();
  addTearDown(prefs.dispose);
  final h = harness ?? _Harness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bridgeRepositoryProvider.overrideWithValue(repo),
        prefsProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        theme: SmokeThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShellScope(
              openOverlay: (overlay, [props = const <String, String>{}]) {
                h.overlay = overlay;
                h.props = props;
              },
              closeOverlay: () => h.closeCalls++,
              showToast: (message) => h.toast = message,
              toggleFullGraph: () {},
              openScreen: (_) {},
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

void main() {
  setUpAll(loadAppFonts);

  group('exit gate — the transport chip (N10.1)', () {
    test('every connection-matrix scenario projects the right chip', () {
      final expected = <String, (String, TransportPhase)>{
        'bt_only': ('Bluetooth', TransportPhase.connected),
        'sta_connecting': ('Connecting…', TransportPhase.connecting),
        'sta_wrong_password': ('Error', TransportPhase.connecting),
        'sta_router_unreachable': ('Error', TransportPhase.connecting),
        'ap_broadcasting': ('Hotspot', TransportPhase.provisioning),
        'ap_joined': ('Bridge Wi-Fi', TransportPhase.connected),
        'switch_rollback': ('Bluetooth', TransportPhase.rollback),
      };
      for (final entry in expected.entries) {
        final scenario = _repo(
          entry.key,
        ).scenarios.firstWhere((s) => s.key == entry.key);
        final status = TransportStatus.from(scenario.snapshot.connection);
        expect(status.label, entry.value.$1, reason: entry.key);
        expect(status.phase, entry.value.$2, reason: entry.key);
      }
    });

    testWidgets('the chip renders the label and both radios', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeThemeData.dark(),
          home: const Scaffold(
            body: TransportChip(
              label: 'Bridge Wi-Fi',
              phase: TransportPhase.connected,
              primary: TransportPrimary.wifi,
              btConnected: true,
              wifiConnected: true,
              wifiAp: true,
            ),
          ),
        ),
      );
      expect(find.text('Bridge Wi-Fi'), findsOneWidget);
    });
  });

  group('connect sheet (N10.2–N10.6)', () {
    testWidgets('every matrix scenario renders a working connect sheet', (
      tester,
    ) async {
      const problemScenarios = <String>{
        'sta_wrong_password',
        'sta_router_unreachable',
        'switch_rollback',
      };
      for (final key in <String>[
        'bt_only',
        'sta_connecting',
        'sta_wrong_password',
        'sta_router_unreachable',
        'ap_broadcasting',
        'ap_joined',
        'switch_rollback',
      ]) {
        final repo = _repo(key);
        addTearDown(repo.dispose);
        await _pump(tester, const ConnectSheetBody(onDone: _noop), repo: repo);

        expect(
          find.byKey(const ValueKey<String>('connection-sheet')),
          findsOneWidget,
          reason: key,
        );
        // Both links stay visible in every state (never unreachable).
        expect(
          find.byKey(const ValueKey<String>('connection-link-bt')),
          findsOneWidget,
          reason: key,
        );
        expect(
          find.byKey(const ValueKey<String>('connection-link-wifi')),
          findsOneWidget,
          reason: key,
        );

        final problem = problemScenarios.contains(key);
        expect(
          find.byKey(const ValueKey<String>('connection-error')),
          problem ? findsOneWidget : findsNothing,
          reason: key,
        );
        if (problem) {
          expect(
            find.byKey(const ValueKey<String>('connection-try-again')),
            findsOneWidget,
            reason: key,
          );
          expect(
            find.byKey(const ValueKey<String>('connection-use-hotspot')),
            findsOneWidget,
            reason: key,
          );
        }
      }
    });

    testWidgets('dual rows, data badge, battery and recording', (tester) async {
      final repo = _repo('running');
      addTearDown(repo.dispose);
      await _pump(tester, const ConnectSheetBody(onDone: _noop), repo: repo);

      expect(
        find.byKey(const ValueKey<String>('connection-device')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('connection-link-bt')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('connection-link-wifi')),
        findsOneWidget,
      );
      // Wi-Fi carries data in `running`; Bluetooth is warm but not primary.
      expect(
        find.byKey(const ValueKey<String>('connection-link-wifi-data')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('connection-link-bt-data')),
        findsNothing,
      );
      expect(find.text('71%'), findsOneWidget);
      expect(find.text('Yes — on the bridge'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('connection-resync')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('connection-disconnect')),
        findsOneWidget,
      );
    });

    testWidgets('mode cards show the active one and open the reference', (
      tester,
    ) async {
      final repo = _repo('running');
      addTearDown(repo.dispose);
      final harness = await _pump(
        tester,
        const ConnectSheetBody(onDone: _noop),
        repo: repo,
      );

      for (final id in ['ble', 'ap', 'sta']) {
        expect(
          find.byKey(ValueKey<String>('connection-mode-$id')),
          findsOneWidget,
        );
      }
      // `running` leads on home Wi-Fi, so STA is the active card.
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('connection-mode-state-sta')),
            )
            .data,
        'The bridge joins your network · Active',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('connection-mode-state-ble')),
            )
            .data,
        'Direct to the bridge · Available',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('connection-mode-info-ble')),
      );
      await tester.pumpAndSettle();
      expect(harness.overlay, DevOverlay.modesRef);
      expect(harness.props['mode'], 'ble');
    });

    testWidgets('switching to Bluetooth applies the mode and closes', (
      tester,
    ) async {
      final repo = _repo('running');
      addTearDown(repo.dispose);
      final harness = await _pump(
        tester,
        const ConnectSheetBody(onDone: _noop),
        repo: repo,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('connection-mode-ble')),
      );
      await tester.pumpAndSettle();
      expect(repo.current.connection.primary, LinkPrimary.bt);
      expect(harness.toast, 'Switched to Bluetooth');
    });

    testWidgets('AP and STA cards open their provisioning sheets', (
      tester,
    ) async {
      final repo = _repo('bt_only');
      addTearDown(repo.dispose);
      final harness = await _pump(
        tester,
        const ConnectSheetBody(onDone: _noop),
        repo: repo,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('connection-mode-ap')),
      );
      await tester.pumpAndSettle();
      expect(harness.overlay, DevOverlay.provisionAp);

      await tester.tap(
        find.byKey(const ValueKey<String>('connection-mode-sta')),
      );
      await tester.pumpAndSettle();
      expect(harness.overlay, DevOverlay.provisionSta);
    });

    testWidgets('wrong password shows its copy and both recoveries', (
      tester,
    ) async {
      final repo = _repo('sta_wrong_password');
      addTearDown(repo.dispose);
      final harness = await _pump(
        tester,
        const ConnectSheetBody(onDone: _noop),
        repo: repo,
      );

      expect(
        find.byKey(const ValueKey<String>('connection-error')),
        findsOneWidget,
      );
      expect(find.textContaining('password was rejected'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('connection-try-again')),
      );
      await tester.pumpAndSettle();
      expect(harness.overlay, DevOverlay.provisionSta);

      await tester.tap(
        find.byKey(const ValueKey<String>('connection-use-hotspot')),
      );
      await tester.pumpAndSettle();
      expect(harness.overlay, DevOverlay.provisionAp);
    });

    testWidgets('rollback keeps the previous link and says so', (tester) async {
      final repo = _repo('switch_rollback');
      addTearDown(repo.dispose);
      await _pump(tester, const ConnectSheetBody(onDone: _noop), repo: repo);

      expect(find.textContaining('kept Bluetooth'), findsOneWidget);
      // The rollback leaves BLE carrying data, so the chip/row still works.
      expect(
        find.byKey(const ValueKey<String>('connection-link-bt-data')),
        findsOneWidget,
      );
    });

    testWidgets('Re-sync calls the repository and toasts', (tester) async {
      final repo = _repo('offline');
      addTearDown(repo.dispose);
      final harness = await _pump(
        tester,
        const ConnectSheetBody(onDone: _noop),
        repo: repo,
      );

      await tester.tap(find.byKey(const ValueKey<String>('connection-resync')));
      await tester.pumpAndSettle();
      expect(repo.current.connection.phase, ConnectionPhase.connected);
      expect(harness.toast, 'Re-synced · up to date');
    });

    testWidgets('Disconnect drops the link and closes', (tester) async {
      final repo = _repo('running');
      addTearDown(repo.dispose);
      final harness = _Harness();
      await _pump(
        tester,
        ConnectSheetBody(onDone: () => harness.closed++),
        repo: repo,
        harness: harness,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('connection-disconnect')),
      );
      await tester.pumpAndSettle();
      expect(repo.current.connection.phase, ConnectionPhase.offline);
      expect(harness.closed, 1);
    });
  });

  group('modes sheet and reference (N10.4/N10.5)', () {
    testWidgets('the modes sheet lists all three cards', (tester) async {
      final repo = _repo('bt_only');
      addTearDown(repo.dispose);
      await _pump(tester, const ConnectionModesBody(onDone: _noop), repo: repo);

      expect(
        find.byKey(const ValueKey<String>('connection-modes')),
        findsOneWidget,
      );
      for (final id in ['ble', 'ap', 'sta']) {
        expect(
          find.byKey(ValueKey<String>('connection-mode-$id')),
          findsOneWidget,
        );
      }
    });

    testWidgets('the reference expands the focused mode and gates I13', (
      tester,
    ) async {
      final repo = _repo('bt_only');
      addTearDown(repo.dispose);
      await _pump(
        tester,
        const ModesReferenceBody(onDone: _noop, focusMode: 'ble'),
        repo: repo,
      );

      expect(
        find.byKey(const ValueKey<String>('connection-modes-ref')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('connection-ref-card-ble')),
        findsOneWidget,
      );
      // BLE cannot download history, and the row says why (I13).
      expect(
        find.byKey(
          const ValueKey<String>('connection-ref-cap-fullHistory-ble'),
        ),
        findsOneWidget,
      );
      expect(find.text('Full history needs Wi-Fi.'), findsOneWidget);
      // Unfocused modes stay collapsed.
      expect(
        find.byKey(const ValueKey<String>('connection-ref-cap-live-ap')),
        findsNothing,
      );
    });
  });

  group('STA provisioning (N10.7/N10.9/N10.11)', () {
    testWidgets('pick a network, type a password, connect', (tester) async {
      final repo = _repo('bt_only');
      addTearDown(repo.dispose);
      final harness = _Harness();
      await _pump(
        tester,
        ProvisionStaBody(onDone: () => harness.closed++),
        repo: repo,
        harness: harness,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('provision-sta-net-HomeNet-2.4G')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('provision-sta-password')),
        'hunter2',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('provision-sta-connect')),
      );
      await tester.pumpAndSettle();

      expect(repo.current.connection.phase, ConnectionPhase.connecting);
      expect(repo.current.connection.wifi.mode, WifiMode.sta);
      expect(repo.current.connection.wifi.ssid, 'HomeNet-2.4G');
      expect(harness.closed, 1);
    });

    testWidgets('an empty password is refused before the bridge is asked', (
      tester,
    ) async {
      final repo = _repo('bt_only');
      addTearDown(repo.dispose);
      await _pump(tester, const ProvisionStaBody(onDone: _noop), repo: repo);

      await tester.tap(
        find.byKey(const ValueKey<String>('provision-sta-connect')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter the Wi-Fi password.'), findsOneWidget);
      expect(repo.current.connection.phase, ConnectionPhase.connected);
      expect(repo.current.connection.wifi.mode, WifiMode.off);
    });

    testWidgets('a named error offers the hotspot escape hatch', (
      tester,
    ) async {
      final repo = _repo('sta_router_unreachable');
      addTearDown(repo.dispose);
      final harness = await _pump(
        tester,
        const ProvisionStaBody(onDone: _noop),
        repo: repo,
      );

      expect(
        find.byKey(const ValueKey<String>('provision-sta-error')),
        findsOneWidget,
      );
      expect(find.textContaining('could not reach the router'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('provision-sta-use-hotspot')),
      );
      await tester.pumpAndSettle();
      expect(harness.overlay, DevOverlay.provisionAp);
    });
  });

  group('AP provisioning (N10.8)', () {
    testWidgets('shows the SSID, passkey, steps and confirms the join', (
      tester,
    ) async {
      final repo = _repo('ap_broadcasting');
      addTearDown(repo.dispose);
      final harness = _Harness();
      await _pump(
        tester,
        ProvisionApBody(onDone: () => harness.closed++),
        repo: repo,
        harness: harness,
      );

      expect(find.text('SmokeBridge-A4F2'), findsWidgets);
      expect(find.text('smoke-4471'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('provision-ap-steps')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('provision-ap-open')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('provision-ap-joined')),
      );
      await tester.pumpAndSettle();
      expect(repo.current.connection.phase, ConnectionPhase.connected);
      expect(repo.current.connection.primary, LinkPrimary.wifi);
      expect(repo.current.connection.wifi.mode, WifiMode.ap);
      expect(harness.closed, 1);
    });
  });

  group('Settings bridge card (N10.12–N10.15)', () {
    testWidgets('dual rows, two-hop copy and the verbs', (tester) async {
      final repo = _repo('running');
      addTearDown(repo.dispose);
      final harness = await _pump(tester, const BridgeCard(), repo: repo);

      expect(find.byKey(const ValueKey<String>('bridge-card')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bridge-bt')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('bridge-wifi')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('bridge-wifi-data')),
        findsOneWidget,
      );
      // Two hops are named, never conflated (N10.13).
      expect(find.textContaining('Phone → bridge'), findsOneWidget);
      expect(find.textContaining('Bridge → router'), findsOneWidget);
      expect(find.text('71%'), findsOneWidget);
      // STA carries full history, so the gate is absent.
      expect(
        find.byKey(const ValueKey<String>('bridge-capability')),
        findsNothing,
      );
      // A joined home network offers Forget network (N10.9).
      expect(
        find.byKey(const ValueKey<String>('bridge-forget-network')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('bridge-change-mode')),
      );
      await tester.pumpAndSettle();
      expect(harness.overlay, DevOverlay.modes);
    });

    testWidgets('BLE-only gates full history and hides Forget network', (
      tester,
    ) async {
      final repo = _repo('bt_only');
      addTearDown(repo.dispose);
      await _pump(tester, const BridgeCard(), repo: repo);

      expect(
        find.byKey(const ValueKey<String>('bridge-capability')),
        findsOneWidget,
      );
      expect(find.textContaining('Full history needs Wi-Fi.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('bridge-forget-network')),
        findsNothing,
      );
    });

    testWidgets('Forget network clears the SSID and falls back to BLE', (
      tester,
    ) async {
      final repo = _repo('running');
      addTearDown(repo.dispose);
      final harness = await _pump(tester, const BridgeCard(), repo: repo);

      await tester.tap(
        find.byKey(const ValueKey<String>('bridge-forget-network')),
      );
      await tester.pumpAndSettle();
      expect(repo.current.connection.wifi.mode, WifiMode.off);
      expect(repo.current.connection.wifi.ssid, isNull);
      expect(repo.current.connection.primary, LinkPrimary.bt);
      expect(harness.toast, 'Network forgotten');
    });

    testWidgets('Re-sync from offline reconnects and toasts', (tester) async {
      final repo = _repo('offline');
      addTearDown(repo.dispose);
      final harness = await _pump(tester, const BridgeCard(), repo: repo);

      await tester.tap(find.byKey(const ValueKey<String>('bridge-resync')));
      await tester.pumpAndSettle();
      expect(repo.current.connection.phase, ConnectionPhase.connected);
      expect(harness.toast, 'Re-synced · up to date');
    });
  });
}

void _noop() {}
