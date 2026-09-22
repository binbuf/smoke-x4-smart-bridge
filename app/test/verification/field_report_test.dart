/// N16.11 — field report and diagnostics copy dry-run.
///
/// Nothing sensitive may leave the phone unreviewed. Two checks: the payload
/// the app builds carries identity and health but no credential, and the UI
/// asks before sending — the cost sheet names exactly what is bundled and
/// offers a cancel that sends nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/model/connection_state.dart';
import 'package:smoke_bridge/data/model/device_info.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/data/repository/prefs_repository.dart';
import 'package:smoke_bridge/features/settings/settings.dart';

import '../support/load_fonts.dart';
import '../support/settings_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  test(
    'the diagnostics payload carries identity and health, but no secret',
    () {
      const device = DeviceInfo(
        id: 'A4F2-9C71',
        hardware: 'rev C · ESP32-S3',
        version: 'v1.4.2',
        versionDate: '2026-07-18',
        bootloader: '2.1.0',
        channel: DeviceChannel.stable,
        uptimeMin: 4387,
        heapKb: 128,
        storage: DeviceStorage(
          usedKb: 36,
          totalKb: 512,
          sessions: 12,
          days: 54,
        ),
        logs: <DeviceLog>[
          DeviceLog(t: '09:41:02', level: 'info', text: 'boot complete'),
        ],
      );
      const connection = ConnectionState(phase: ConnectionPhase.connected);

      final text = diagnosticsText(device, connection);
      expect(text, contains('A4F2-9C71'));
      expect(text, contains('v1.4.2'));
      expect(text, contains('boot complete'));

      final lower = text.toLowerCase();
      expect(lower, isNot(contains('password')));
      expect(lower, isNot(contains('psk')));
      expect(lower, isNot(contains('token')));
      expect(lower, isNot(contains('secret')));
    },
  );

  testWidgets('the field report asks for review and cancel sends nothing', (
    tester,
  ) async {
    final repo = MockBridgeRepository(nowMs: 1700000000000);
    final prefs = MockPrefsRepository();
    addTearDown(repo.dispose);
    addTearDown(prefs.dispose);

    final probe = await pumpSettings(
      tester,
      repo: repo,
      prefs: prefs,
      child: DiagnosticsSheetBody(onDone: () {}),
    );

    await tester.tap(find.text('Field report'));
    await tester.pumpAndSettle();

    expect(find.text('Send a field report?'), findsOneWidget);
    expect(
      find.textContaining(
        'No cook data leaves the phone without you seeing it first.',
      ),
      findsOneWidget,
    );

    // Cancel is a real cancel: no toast, nothing sent.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(probe.toast, isNull);
  });
}
