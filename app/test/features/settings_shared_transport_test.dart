/// The settings tree writes through the **shared** connection, and verifies by
/// read-back (newapp §F, §I.1 Phase 0).
///
/// Two defects are pinned here, and the first one is the reason this file
/// exists at all:
///
///  1. **On a Bluetooth-only setup, saving probe settings appeared to succeed
///     while writing nothing.** `SettingsRoute` built its own `HttpTransport`
///     from `prefs.lastBaseUrl`; a BLE-only phone has no base URL, so the
///     transport stayed null, and every write went through a null-aware
///     `_transport?.configure(...)` that silently did nothing. The form said
///     saved. The bridge never heard.
///  2. **Device rows rendered constructor defaults as facts** — display
///     timeout 60 s, status LED on, 64 cooks kept — on rows whose write
///     callback was null.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/app_env.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/settings/settings_probes.dart';
import 'package:smoke_bridge/features/settings/settings_route.dart';
import 'package:smoke_bridge/features/settings/settings_screen.dart';

import '../support/fake_env.dart';

void main() {
  group('§F — no shared link means no live-looking controls', () {
    testWidgets('the probe page states why it cannot write, rather than '
        'offering a form that silently drops the save', (tester) async {
      // The BLE-only shape: a bridge id remembered, no base URL. Under the old
      // code this produced `_transport == null` and a silent no-op behind a
      // form that reported success.
      AppEnv.instance = fakeEnv(prefs: InMemoryBridgePrefs(lastBridgeId: 'b'));
      addTearDown(() => AppEnv.instance = null);

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsRoute(
            initialSection: SettingsSection.probes,
            embedded: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProbeSettingsView), findsOneWidget);
      expect(
        find.textContaining('Not connected'),
        findsWidgets,
        reason:
            'disabled-with-a-reason, never a live-looking form over a dead '
            'write',
      );
    });
  });

  group('§G.3 — the read-back comparison', () {
    test('an exact echo matches', () {
      const sent = [Probe(n: 1, name: 'Pit', role: ProbeRole.pit)];
      expect(probeWriteWasHonoured(sent, sent), isTrue);
    });

    test('a device that kept its own name does NOT match', () {
      const sent = [Probe(n: 1, name: 'Firebox', role: ProbeRole.pit)];
      const echoed = [Probe(n: 1, name: 'Pit', role: ProbeRole.pit)];
      expect(
        probeWriteWasHonoured(sent, echoed),
        isFalse,
        reason:
            'this is the whole point — a 200 that changed nothing must not '
            'read as saved',
      );
    });

    test('a device that clamped a target does NOT match', () {
      const sent = [Probe(n: 2, role: ProbeRole.food, targetF10: 6000)];
      const echoed = [Probe(n: 2, role: ProbeRole.food, targetF10: 5720)];
      expect(probeWriteWasHonoured(sent, echoed), isFalse);
    });

    test('a probe missing from the echo does NOT match', () {
      const sent = [Probe(n: 3, name: 'Flat', role: ProbeRole.food)];
      expect(probeWriteWasHonoured(sent, const []), isFalse);
    });

    test('extra state the device manages itself is not a mismatch', () {
      const sent = [Probe(n: 1, name: 'Pit', role: ProbeRole.pit)];
      const echoed = [
        Probe(n: 1, name: 'Pit', role: ProbeRole.pit, alarmMinF10: 2250),
        Probe(n: 2, role: ProbeRole.food),
      ];
      expect(probeWriteWasHonoured(sent, echoed), isTrue);
    });
  });

  group('§I.0 — absent is absent, not a constructor default', () {
    testWidgets('device rows render a dash until the bridge reports', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DeviceSettingsView(units: 'F', onUnits: _noop)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('1m'),
        findsNothing,
        reason: 'a 60 s display timeout nobody read is not a fact',
      );
      expect(
        find.textContaining('64 —'),
        findsNothing,
        reason: 'the bridge never said it keeps 64 cooks',
      );
      expect(find.text('—'), findsWidgets);
      expect(find.textContaining('hasn’t reported this yet'), findsWidgets);
    });

    testWidgets('the LED switch is disabled while unknown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceSettingsView(
              units: 'F',
              onUnits: _noop,
              onDeviceConfig: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final led = tester.widget<SwitchListTile>(
        find.byKey(const Key('settings-led')),
      );
      expect(
        led.onChanged,
        isNull,
        reason:
            'a switch that cannot know its own state must not offer to '
            'change it',
      );
    });

    testWidgets('once reported, the rows are live', (tester) async {
      var wrote = <String, Object?>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceSettingsView(
              units: 'F',
              onUnits: _noop,
              displayTimeoutS: 60,
              ledEnabled: true,
              maxSessions: 64,
              batterySaver: 'auto',
              onDeviceConfig: (m) => wrote = m,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-led')));
      await tester.pumpAndSettle();
      expect(wrote['led_enabled'], false);
      expect(find.textContaining('64 —'), findsOneWidget);
    });
  });
}

void _noop(String _) {}
