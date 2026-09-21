/// N13.9–N13.17 — the firmware / OTA / diagnostics sheets and the verb sheet.
///
/// The OTA rules are pinned here: Wi-Fi only, the 409 session guard behind an
/// explicit force toggle, and the auto-rollback promise verbatim.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dev_panel.dart';
import 'package:smoke_bridge/data/model/app_settings.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/data/repository/prefs_repository.dart';
import 'package:smoke_bridge/features/settings/settings.dart';

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

  Future<SettingsProbe> pumpBody(WidgetTester tester, Widget body) =>
      pumpSettings(tester, repo: repo, prefs: prefs, child: body);

  Future<void> toggleForce(WidgetTester tester) async {
    final finder = find.descendant(
      of: find.byKey(const ValueKey<String>('firmware-force')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('firmware sheet (N13.9)', () {
    testWidgets('states installed, hardware, bootloader and rollback', (
      tester,
    ) async {
      await pumpBody(tester, FirmwareSheetBody(onDone: () {}));

      expect(find.text('v1.4.2'), findsOneWidget);
      expect(
        find.text('Installed 2026-07-18 · stable channel'),
        findsOneWidget,
      );
      expect(find.text('rev C · ESP32-S3'), findsOneWidget);
      expect(find.text('2.1.0'), findsOneWidget);
      expect(find.text('Auto-rollback'), findsOneWidget);
      // N13.14 — the promise is stated verbatim.
      expect(
        find.textContaining(
          'A failed health check within 120 s of boot auto-rolls back to the '
          'previous slot. Nothing is lost.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the channel control persists through prefs', (tester) async {
      await pumpBody(tester, FirmwareSheetBody(onDone: () {}));

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(prefs.current.otaChannel, OtaChannel.beta);
    });

    testWidgets('Check for updates reads the update back and offers Install', (
      tester,
    ) async {
      final probe = await pumpBody(tester, FirmwareSheetBody(onDone: () {}));

      await tester.tap(find.byKey(const ValueKey<String>('firmware-check')));
      await tester.pumpAndSettle();

      expect(repo.device.available, 'v1.5.0');
      expect(probe.toast, 'Update available: v1.5.0');
      expect(find.text('Available now'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('firmware-install')));
      await tester.pumpAndSettle();
      expect(probe.request?.name, DevOverlay.firmwareUpdate);
    });
  });

  group('update sheet (N13.10–N13.12)', () {
    testWidgets('an up-to-date device offers Check again, not Install', (
      tester,
    ) async {
      await pumpBody(tester, FirmwareUpdateSheetBody(onDone: () {}));

      expect(find.textContaining('You are on the latest'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('firmware-check')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('firmware-install')),
        findsNothing,
      );
    });

    testWidgets('recording on Wi-Fi: Install is gated on the force toggle', (
      tester,
    ) async {
      await repo.checkForUpdates();
      final probe = await pumpBody(
        tester,
        FirmwareUpdateSheetBody(onDone: () {}),
      );

      expect(find.text('v1.4.2'), findsOneWidget);
      expect(find.text('v1.5.0'), findsOneWidget);
      expect(find.textContaining('409 session_active'), findsOneWidget);
      expect(
        find.text('Force the update above, or wait until the cook is done'),
        findsOneWidget,
      );

      await toggleForce(tester);
      expect(prefs.current.forceOta, isTrue);
      expect(
        find.text('Force the update above, or wait until the cook is done'),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey<String>('firmware-install')));
      await tester.pumpAndSettle();
      expect(probe.request?.name, DevOverlay.verb);
      expect(probe.request?.props['kind'], 'ota');
    });

    testWidgets('not on Wi-Fi: the primary action is Join Wi-Fi', (
      tester,
    ) async {
      await repo.selectScenario('offline');
      await repo.checkForUpdates();
      final probe = await pumpBody(
        tester,
        FirmwareUpdateSheetBody(onDone: () {}),
      );

      expect(find.text('Wi-Fi required to install'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('firmware-install')),
        findsOneWidget,
      );

      await tester.tap(find.text('Join Wi-Fi'));
      await tester.pumpAndSettle();
      expect(probe.request?.name, DevOverlay.provisionSta);
    });
  });

  group('diagnostics sheet (N13.15–N13.17)', () {
    testWidgets('renders every fact, both hops, storage and the logs', (
      tester,
    ) async {
      await pumpBody(tester, DiagnosticsSheetBody(onDone: () {}));

      expect(find.text('A4F2-9C71'), findsOneWidget);
      expect(find.text('v1.4.2 · stable'), findsOneWidget);
      expect(find.text('rev C · ESP32-S3'), findsOneWidget);
      expect(find.text('2.1.0'), findsOneWidget);
      expect(find.text('73h 7m'), findsOneWidget);
      expect(find.text('128 KB'), findsOneWidget);
      expect(find.text('71%'), findsOneWidget);
      expect(find.text('Yes — on the bridge'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);

      // Two hops, never conflated.
      expect(find.text('Bluetooth'), findsOneWidget);
      expect(find.text('Wi-Fi'), findsOneWidget);
      expect(find.textContaining('good · -62 dBm'), findsOneWidget);
      expect(find.textContaining('192.168.1.42'), findsWidgets);

      expect(find.text('12 of 64'), findsOneWidget);
      expect(find.text('36 of 512 KB'), findsOneWidget);
      expect(find.text('~54 days of recording'), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        expect(
          find.byKey(ValueKey<String>('diagnostics-log-$i')),
          findsOneWidget,
          reason: 'log $i',
        );
      }
    });

    testWidgets('Copy diagnostics and Field report both do something', (
      tester,
    ) async {
      final probe = await pumpBody(tester, DiagnosticsSheetBody(onDone: () {}));

      await tester.tap(find.text('Copy diagnostics'));
      await tester.pumpAndSettle();
      expect(probe.toast, 'Diagnostics copied to clipboard');

      await tester.tap(find.text('Field report'));
      await tester.pumpAndSettle();
      expect(find.text('Send a field report?'), findsOneWidget);
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect(probe.toast, 'Field report sent');
    });
  });

  group('verb sheet (N13.13/N13.20)', () {
    testWidgets('a verb with no kind is passive (no run, no mutation)', (
      tester,
    ) async {
      await pumpBody(tester, VerbSheetBody(onDone: () {}));

      expect(
        find.byKey(const ValueKey<String>('verb-passive')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey<String>('verb-sheet')), findsNothing);
    });

    testWidgets('OTA completes its steps and reads the new version back', (
      tester,
    ) async {
      await repo.checkForUpdates();
      var closed = 0;
      await pumpBody(
        tester,
        VerbSheetBody(kind: 'ota', onDone: () => closed++),
      );

      expect(find.text('Verifying the image'), findsOneWidget);
      // Advance the named steps: each is one SmokeMotion.value.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 700));
      }
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
      expect(repo.device.version, 'v1.5.0');
      expect(find.text('Firmware updated to v1.5.0.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('verb-close')));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });
  });
}
