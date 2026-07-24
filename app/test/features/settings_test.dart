/// A12 — settings.
///
/// The rule this epic lives under, checked rather than asserted in prose:
/// **a control that cannot work is worse than no control.** Battery
/// calibration, OTA on a BLE link, probe editing on a BLE link, and alarm
/// delivery are each either absent or disabled *with a reason on screen*.
///
/// And the claim §9.1 makes about the two alarm tiers has to survive the
/// UI: the device tier keeps working with the phone switched off, the app
/// tier is advisory, and the screen says which is which.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/settings/settings.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Settings pages are long lists; on the default 800x600 test surface the
/// controls at the bottom are never built, let alone tappable. A taller
/// surface is the honest fix — the alternative is asserting against
/// widgets that a real phone would also have to scroll to.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('the shell', () {
    testWidgets('offers the seven §8.6 sections', (tester) async {
      _tall(tester);
      final opened = <SettingsSection>[];
      await tester.pumpWidget(_wrap(SettingsHomeView(onOpen: opened.add)));
      for (final s in SettingsSection.values) {
        expect(
          find.byKey(Key('settings-section-${s.name}')),
          findsOneWidget,
          reason: 'missing ${s.name}',
        );
      }
      await tester.tap(find.byKey(const Key('settings-section-probes')));
      expect(opened, [SettingsSection.probes]);
    });
  });

  group('probes', () {
    testWidgets('saving sends the whole draft through configure()', (
      tester,
    ) async {
      _tall(tester);
      List<Probe>? saved;
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(
            probes: const [Probe(n: 1, name: 'Pit', role: ProbeRole.pit)],
            onSave: (p) async => saved = p,
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('probe-name-2')), 'Brisket');
      await tester.tap(find.byKey(const Key('probe-role-2-food')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('probe-target-2')), '203.0');
      await tester.pump();
      await tester.tap(find.byKey(const Key('probes-save')));
      await tester.pump();
      expect(saved, isNotNull);
      final p2 = saved!.firstWhere((p) => p.n == 2);
      expect(p2.name, 'Brisket');
      expect(p2.role, ProbeRole.food);
      expect(p2.targetF10, 2030);
      // Roles drive which tile is large — probe 1 stays the pit.
      expect(saved!.firstWhere((p) => p.n == 1).role, ProbeRole.pit);
    });

    testWidgets('an out-of-range target is refused in the form', (
      tester,
    ) async {
      _tall(tester);
      var saves = 0;
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(probes: const [], onSave: (_) async => saves++),
        ),
      );
      await tester.enterText(find.byKey(const Key('probe-target-1')), '9999');
      await tester.pump();
      expect(find.textContaining('Between'), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.byKey(const Key('probes-save')),
      );
      expect(save.onPressed, isNull);
      expect(saves, 0);
    });

    testWidgets('a transport that cannot do this says so, and disables', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(
            probes: const [],
            onSave: (_) async {},
            unsupportedReason:
                'Probe names and targets need a Wi-Fi connection to the '
                'bridge.',
          ),
        ),
      );
      expect(find.byKey(const Key('probes-unsupported')), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.byKey(const Key('probes-save')),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('a failed save keeps the edits and states the failure', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          ProbeSettingsView(
            probes: const [],
            onSave: (_) async => throw StateError('bridge said no'),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('probe-name-1')), 'Kettle');
      await tester.pump();
      await tester.tap(find.byKey(const Key('probes-save')));
      await tester.pump();
      expect(find.byKey(const Key('probes-save-error')), findsOneWidget);
      // Ten minutes of typing must not vanish on one dropped packet.
      expect(find.text('Kettle'), findsOneWidget);
    });
  });

  group('alarms', () {
    testWidgets('the two tiers are distinct, and say what they promise', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const AlarmSettingsView(
            deviceRules: {'target_reached': true, 'pit_crash': true},
            alarms: [],
          ),
        ),
      );
      expect(find.byKey(const Key('alarms-device-tier')), findsOneWidget);
      expect(find.byKey(const Key('alarms-app-tier')), findsOneWidget);
      expect(find.textContaining('phone switched off'), findsOneWidget);
      expect(find.textContaining('Advisory only'), findsOneWidget);
      expect(find.text('Target reached'), findsOneWidget);
    });

    testWidgets('nothing here claims a capability M5 has not built', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const AlarmSettingsView(deviceRules: {}, alarms: [])),
      );
      expect(find.byKey(const Key('alarms-delivery-caveat')), findsOneWidget);
      expect(find.textContaining('later release'), findsOneWidget);
    });

    testWidgets('an alarm raised before the app connected is still latched', (
      tester,
    ) async {
      _tall(tester);
      final acked = <Alarm>[];
      await tester.pumpWidget(
        _wrap(
          AlarmSettingsView(
            deviceRules: const {},
            alarms: const [
              Alarm(
                id: 3,
                rule: 'target_reached',
                probe: 2,
                severity: AlarmSeverity.critical,
              ),
            ],
            onAck: acked.add,
          ),
        ),
      );
      expect(find.textContaining('not acknowledged'), findsOneWidget);
      await tester.tap(find.byKey(const Key('alarm-ack-3')));
      await tester.pump();
      expect(acked.single.id, 3);
    });

    testWidgets('an acked alarm shows as silenced, not resolved', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const AlarmSettingsView(
            deviceRules: {},
            alarms: [Alarm(id: 4, rule: 'pit_crash', acked: true)],
          ),
        ),
      );
      // Acknowledging silences; the alarm stays in the list (§9.2).
      expect(find.byKey(const Key('alarm-entry-4')), findsOneWidget);
      expect(find.textContaining('acknowledged'), findsOneWidget);
      expect(find.byKey(const Key('alarm-ack-4')), findsNothing);
    });
  });

  group('network', () {
    testWidgets('a manual address is normalised and handed on', (tester) async {
      _tall(tester);
      final entered = <String>[];
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.sta,
            onApply: (_, _, _) async {},
            onManualAddress: entered.add,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('network-manual')),
        '192.168.1.42',
      );
      await tester.tap(find.byKey(const Key('network-manual-connect')));
      await tester.pump();
      expect(entered, ['http://192.168.1.42']);
    });

    testWidgets('a malformed address is refused in the field', (tester) async {
      _tall(tester);
      final entered = <String>[];
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.sta,
            onApply: (_, _, _) async {},
            onManualAddress: entered.add,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('network-manual-connect')));
      await tester.pump();
      expect(find.textContaining('not an address'), findsOneWidget);
      expect(entered, isEmpty);
    });

    testWidgets('AP mode shows the PSK the user needs to join', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.ap,
            ssid: 'SmokeBridge-8274',
            apPsk: 'Gk7mR2xQpT',
            onApply: (_, _, _) async {},
          ),
        ),
      );
      expect(find.textContaining('Gk7mR2xQpT'), findsOneWidget);
    });

    testWidgets('an unreachable bridge lands on copy, not a spinner', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.sta,
            onApply: (_, _, _) async {},
            recoveryMessage:
                'The bridge joined the network but this phone cannot reach '
                'it. Try its address directly, or switch it back to hosting.',
          ),
        ),
      );
      expect(find.byKey(const Key('network-recovery')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('joining sends one config with both fields', (tester) async {
      _tall(tester);
      final applied = <(NetMode, String, String)>[];
      await tester.pumpWidget(
        _wrap(
          NetworkSettingsView(
            mode: NetMode.ap,
            onApply: (m, s, p) async => applied.add((m, s, p)),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('network-ssid')), 'Backyard');
      await tester.enterText(find.byKey(const Key('network-psk')), 'hunter2');
      await tester.tap(find.byKey(const Key('network-join')));
      await tester.pump();
      expect(applied.single, (NetMode.sta, 'Backyard', 'hunter2'));
    });
  });

  group('device, advanced, about', () {
    testWidgets('units default to °F and travel when changed', (tester) async {
      _tall(tester);
      final chosen = <String>[];
      await tester.pumpWidget(
        _wrap(DeviceSettingsView(units: 'F', onUnits: chosen.add)),
      );
      await tester.tap(find.text('°C'));
      await tester.pump();
      expect(chosen, ['C']);
    });

    testWidgets('battery calibration is present, disabled, and explains', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(DeviceSettingsView(units: 'F', onUnits: (_) {})),
      );
      final tile = tester.widget<ListTile>(
        find.byKey(const Key('settings-battery-calibration')),
      );
      expect(tile.enabled, isFalse);
      expect(find.textContaining('does not report a battery'), findsOneWidget);
    });

    testWidgets('an empty packet ring and novelty log render honestly', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const AdvancedSettingsView()));
      expect(find.byKey(const Key('settings-packets-empty')), findsOneWidget);
      expect(find.text('Nothing new observed.'), findsOneWidget);
    });

    testWidgets('the novelty log renders verbatim', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const AdvancedSettingsView(
            noveltyLog: 'field 21 changed: 0 -> 1 @ uptime 4211',
            packets: ['LMXC[\\,30,1,0,...'],
          ),
        ),
      );
      expect(find.textContaining('field 21 changed'), findsOneWidget);
      expect(find.byKey(const Key('settings-packets-empty')), findsNothing);
    });

    testWidgets('about carries the D9 MIT attribution', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(const AboutView(appVersion: '1.0.0', firmwareVersion: '1.0.0')),
      );
      expect(find.byKey(const Key('settings-attribution')), findsOneWidget);
      expect(find.textContaining('MIT'), findsOneWidget);
    });

    testWidgets('about renders an unknown firmware as absence', (tester) async {
      _tall(tester);
      await tester.pumpWidget(_wrap(const AboutView(appVersion: '1.0.0')));
      expect(find.text('—'), findsNWidgets(2));
    });
  });

  group('firmware', () {
    testWidgets('a transport that cannot OTA shows no upload button', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const FirmwareSettingsView(
            currentVersion: '1.0.0',
            otaSupported: false,
          ),
        ),
      );
      expect(find.byKey(const Key('firmware-upload')), findsNothing);
      expect(find.byKey(const Key('firmware-unsupported')), findsOneWidget);
    });

    testWidgets('progress renders from real ota frames', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          const FirmwareSettingsView(
            currentVersion: '1.0.0',
            otaSupported: true,
            progressPct: 42,
            phase: 'writing',
          ),
        ),
      );
      expect(find.byKey(const Key('firmware-progress')), findsOneWidget);
      expect(find.text('writing — 42%'), findsOneWidget);
    });

    testWidgets('the 409 is explained, and force is a separate action', (
      tester,
    ) async {
      _tall(tester);
      final forced = <bool>[];
      await tester.pumpWidget(
        _wrap(
          FirmwareSettingsView(
            currentVersion: '1.0.0',
            otaSupported: true,
            sessionActive: true,
            refusal: 'session_active',
            onUpload: ({required bool force}) async => forced.add(force),
          ),
        ),
      );
      expect(find.byKey(const Key('firmware-refusal')), findsOneWidget);
      expect(
        find.textContaining('fourteen hours into a brisket'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('firmware-upload-force')));
      await tester.pump();
      expect(forced, [true]);
    });

    testWidgets('with no cook running there is no force button at all', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        _wrap(
          FirmwareSettingsView(
            currentVersion: '1.0.0',
            otaSupported: true,
            onUpload: ({required bool force}) async {},
          ),
        ),
      );
      expect(find.byKey(const Key('firmware-upload')), findsOneWidget);
      expect(find.byKey(const Key('firmware-upload-force')), findsNothing);
    });
  });
}
