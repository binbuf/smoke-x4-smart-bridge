/// N13.1–N13.8 and N13.18–N13.22 — the Settings tree, persistence, the
/// five-tap gate and the cost → verb flow.
///
/// Every preference is asserted through [PrefsRepository]; every row that opens
/// a surface is asserted through the captured overlay request; the destructive
/// verbs route through the shared cost sheet and then the real verb sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dev_panel.dart';
import 'package:smoke_bridge/data/model/app_settings.dart';
import 'package:smoke_bridge/data/model/connection_state.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/data/repository/prefs_repository.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/shell/shell_screen.dart';

import '../support/load_fonts.dart';
import '../support/settings_harness.dart';

const int _now = 1700000000000;

void main() {
  setUpAll(loadAppFonts);

  late MockBridgeRepository repo;
  late MockPrefsRepository prefs;

  setUp(() {
    repo = MockBridgeRepository(nowMs: _now);
    prefs = MockPrefsRepository();
  });

  tearDown(() async {
    await repo.dispose();
    await prefs.dispose();
  });

  Future<SettingsProbe> pump(
    WidgetTester tester, {
    String scenario = 'running',
  }) async {
    if (scenario != 'running') {
      await repo.selectScenario(scenario);
    }
    return pumpSettings(tester, repo: repo, prefs: prefs);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester, String key) async {
    final finder = find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Advances the verb sheet's named steps (each is a [SmokeMotion.value]).
  Future<void> runVerb(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 700));
    }
    await tester.pumpAndSettle();
  }

  group('the settings tree (N13.1–N13.8)', () {
    testWidgets('renders every card and row', (tester) async {
      final probe = await pump(tester);

      for (final key in <String>[
        'settings-page',
        'bridge-card',
        'settings-join-wifi',
        'settings-use-hotspot',
        'settings-forget-network',
        'settings-history',
        'settings-units',
        'settings-appearance',
        'settings-profile',
        'settings-density',
        'settings-motion',
        'settings-monitoring',
        'settings-prefer-manual',
        'settings-quiet-hours',
        'settings-hold-ble',
        'settings-wrap-reminders',
        'settings-firmware',
        'settings-update-firmware',
        'settings-about',
        'settings-verb-restart',
        'settings-verb-forget',
        'settings-verb-factory',
        'settings-honesty',
      ]) {
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
      expect(probe.overlayOpens, 0);
    });

    testWidgets('the honesty footer states the no-clock / detached rules', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.textContaining('A bridge with no clock stores no timestamp'),
        findsOneWidget,
      );
      expect(find.textContaining('never 0'), findsOneWidget);
    });

    testWidgets('lays out at the phone width without overflow', (tester) async {
      await pumpSettings(
        tester,
        repo: repo,
        prefs: prefs,
        size: const Size(390, 844),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('settings-page')),
        findsOneWidget,
      );
    });

    testWidgets('the Wi-Fi rows open the provisioning flows', (tester) async {
      final probe = await pump(tester);

      await tapKey(tester, 'settings-join-wifi');
      expect(probe.request?.name, DevOverlay.provisionSta);

      // Dismiss, then the hotspot row.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await tapKey(tester, 'settings-use-hotspot');
      expect(probe.request?.name, DevOverlay.provisionAp);
    });

    testWidgets('Forget network drops the saved home network', (tester) async {
      final probe = await pump(tester);
      await tapKey(tester, 'settings-forget-network');

      expect(repo.current.connection.wifi.mode, WifiMode.off);
      expect(probe.toast, 'Network forgotten');
    });

    testWidgets('History navigates to the History surface', (tester) async {
      final probe = await pump(tester);
      await tapKey(tester, 'settings-history');
      expect(probe.screen, ShellScreen.history);
    });

    testWidgets('Alarms & monitoring opens the alarms sheet', (tester) async {
      final probe = await pump(tester);
      await tapKey(tester, 'settings-monitoring');
      expect(probe.request?.name, DevOverlay.alarms);
    });
  });

  group('preferences persist immediately (N13.3–N13.5)', () {
    testWidgets('Units writes °C and the sub line follows', (tester) async {
      await pump(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('settings-units')),
          matching: find.text('°C'),
        ),
      );
      await tester.pumpAndSettle();

      expect(prefs.current.units, TempUnit.celsius);
      expect(find.text('Temperatures in Celsius'), findsOneWidget);
    });

    testWidgets('Appearance writes the theme mode', (tester) async {
      await pump(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey<String>('settings-appearance')),
          matching: find.text('Dark'),
        ),
      );
      await tester.pumpAndSettle();

      expect(prefs.current.themeMode, AppThemeMode.dark);
      expect(find.text('Dark'), findsWidgets);
    });

    testWidgets('the display toggles write profile / density / motion', (
      tester,
    ) async {
      await pump(tester);

      await toggle(tester, 'settings-profile');
      expect(prefs.current.displayProfile, DisplayProfile.daylight);

      await toggle(tester, 'settings-density');
      expect(prefs.current.density, Density.comfortable);

      await toggle(tester, 'settings-motion');
      expect(prefs.current.reducedMotion, isTrue);
    });

    testWidgets('the behaviour toggles write the alarm preferences', (
      tester,
    ) async {
      await pump(tester);

      await toggle(tester, 'settings-prefer-manual');
      expect(prefs.current.preferManualAlarm, isTrue);

      await toggle(tester, 'settings-quiet-hours');
      expect(prefs.current.quietHours, isFalse);

      await toggle(tester, 'settings-hold-ble');
      expect(prefs.current.holdBle, isFalse);

      await toggle(tester, 'settings-wrap-reminders');
      expect(prefs.current.autoWrapReminder, isFalse);
    });
  });

  group('Bridge card rows (N13.6/N13.18)', () {
    testWidgets('Firmware and Update firmware open their sheets', (
      tester,
    ) async {
      final probe = await pump(tester);

      await tapKey(tester, 'settings-firmware');
      expect(probe.request?.name, DevOverlay.firmware);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      await tapKey(tester, 'settings-update-firmware');
      expect(probe.request?.name, DevOverlay.firmwareUpdate);
    });

    testWidgets('About & diagnostics is gated behind five taps', (
      tester,
    ) async {
      final probe = await pump(tester);
      final row = find.byKey(const ValueKey<String>('settings-about-row'));

      for (var i = 1; i <= 4; i++) {
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(probe.request?.name, isNot(DevOverlay.diagnostics));
        expect(find.text('$i/5'), findsOneWidget);
      }
      expect(probe.toast, contains('1 more tap'));

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(probe.request?.name, DevOverlay.diagnostics);
    });
  });

  group('device actions: cost, then progress, then state (N13.19–N13.21)', () {
    testWidgets('Restart states its cost and completes its steps', (
      tester,
    ) async {
      final probe = await pump(tester);

      await tapKey(tester, 'settings-verb-restart');
      // The shared cost sheet states keeps/loses and names the action.
      expect(find.text('Restart the bridge?'), findsOneWidget);
      expect(find.textContaining('pauses for about'), findsOneWidget);
      expect(find.text('KEEPS'), findsOneWidget);
      expect(probe.request, isNull);

      await tester.tap(find.widgetWithText(PrimaryAction, 'Restart'));
      await tester.pumpAndSettle();
      await runVerb(tester);

      // The verb sheet ran to completion and read the result back (I7).
      expect(probe.request?.name, DevOverlay.verb);
      expect(probe.request?.props['kind'], 'restart');
      expect(
        find.byKey(const ValueKey<String>('verb-readback')),
        findsOneWidget,
      );
      expect(
        find.text('Bridge restarted — recording resumed.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey<String>('verb-close')));
      await tester.pumpAndSettle();
      expect(probe.request, isNull);
    });

    testWidgets('Factory reset erases the cook and shows the loss list', (
      tester,
    ) async {
      final probe = await pump(tester);

      await tapKey(tester, 'settings-verb-factory');
      expect(find.text('Factory reset the bridge?'), findsOneWidget);
      expect(find.textContaining('All recorded sessions'), findsOneWidget);
      expect(find.text('LOSES'), findsOneWidget);

      await tester.tap(find.widgetWithText(PrimaryAction, 'Factory reset'));
      await tester.pumpAndSettle();
      await runVerb(tester);

      expect(probe.request?.props['kind'], 'factory');
      expect(repo.current.cook.active, isFalse);
      expect(
        find.textContaining('Bridge erased and back in setup mode'),
        findsOneWidget,
      );
    });

    testWidgets('Forget says it only affects this app', (tester) async {
      final probe = await pump(tester);

      await tapKey(tester, 'settings-verb-forget');
      expect(find.text('Forget this bridge?'), findsOneWidget);
      expect(find.textContaining('from this app'), findsWidgets);

      await tester.tap(find.widgetWithText(PrimaryAction, 'Forget'));
      await tester.pumpAndSettle();
      await runVerb(tester);

      expect(probe.request?.props['kind'], 'forget');
      expect(repo.current.connection.phase, ConnectionPhase.offline);
    });
  });
}
