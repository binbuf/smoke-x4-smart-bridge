/// The states the three tabs and the connection sheet can be in, asserted
/// directly by setting the controller's fields — no radio is dialled.
///
/// These are the screens and branches a field user meets when the happy path
/// fails: the sheet's scanning/error/connected bodies, the reconnect-exhausted
/// affordance, the live-only bridge, and the empty cache.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/bridge_scope.dart';
import 'package:smoke_bridge/data/ble/bridge_transport.dart';
import 'package:smoke_bridge/data/local/app_database.dart';
import 'package:smoke_bridge/data/local/drift_sample_cache.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/graph/graph_screen.dart';
import 'package:smoke_bridge/features/history/history_screen.dart';
import 'package:smoke_bridge/features/live/live_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftSampleCache cache;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftSampleCache(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget host(BridgeController controller, Widget child) => BridgeScope(
    controller: controller,
    child: MaterialApp(theme: buildSmokeTheme(), home: child),
  );

  Future<BridgeController> controller() async {
    final c = BridgeController(cache);
    await c.bootstrap();
    addTearDown(c.dispose);
    return c;
  }

  Future<void> seedSession() async {
    await cache.upsertSessions('A4F2', const [
      SessionInfo(
        id: 0x1A,
        name: 'Brisket',
        startedUnixMs: 1774051200000,
        endedUnixMs: 1774054800000,
        samplePeriodS: 30,
        sampleCount: 3,
        numProbes: 4,
        closed: true,
        pinned: false,
      ),
    ]);
    await cache.upsertSamples('A4F2', 0x1A, const [
      Sample(t: 0, tempsF10: [2000, 1600, null, 900]),
      Sample(t: 30, tempsF10: [2010, 1601, null, 901]),
      Sample(t: 60, tempsF10: [2020, 1602, null, 902]),
    ]);
  }

  group('connection sheet', () {
    testWidgets('a scanning link is named, not left blank', (tester) async {
      final c = await controller();
      c.link = BridgeLink.scanning;

      await tester.pumpWidget(host(c, const LiveScreen()));
      await tester.pump();

      expect(find.text('Searching'), findsOneWidget);

      await tester.tap(find.text('Searching'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Searching for your bridge…'), findsOneWidget);
    });

    testWidgets('an error names the failure and the fix', (tester) async {
      final c = await controller();
      c.link = BridgeLink.error;
      c.problem = ConnectionProblem.permissions;
      c.errorMessage = 'Bluetooth permission was denied.';

      await tester.pumpWidget(host(c, const LiveScreen()));
      await tester.pump();

      expect(find.text('No link'), findsOneWidget);

      await tester.tap(find.text('No link'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't connect"), findsOneWidget);
      expect(find.text('Bluetooth permission was denied.'), findsOneWidget);
      expect(find.text('App settings'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('reconnect exhaustion offers a retry, not dead text', (
      tester,
    ) async {
      final c = await controller();
      c.reconnectExhausted = true;
      c.link = BridgeLink.disconnected;

      await tester.pumpWidget(host(c, const LiveScreen()));
      await tester.pump();

      expect(find.text('Lost bridge'), findsOneWidget);

      await tester.tap(find.text('Lost bridge'));
      await tester.pumpAndSettle();

      expect(find.text('Lost the bridge'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets(
      'a connected sheet identifies the bridge and offers disconnect',
      (tester) async {
        final c = await controller();
        c.link = BridgeLink.connected;
        c.identity = const DeviceIdentity(
          id: 'A4F2',
          model: 'heltec-v3',
          fw: '1.0.0',
          probes: 4,
          historyFull: true,
          admin: false,
        );

        await tester.pumpWidget(host(c, const LiveScreen()));
        await tester.pump();

        expect(find.text('Connected'), findsOneWidget);

        await tester.tap(find.text('Connected'));
        await tester.pumpAndSettle();

        expect(find.text('heltec-v3 · A4F2 · fw 1.0.0'), findsOneWidget);
        expect(find.text('Disconnect'), findsOneWidget);
      },
    );
  });

  group('empty and degraded states', () {
    testWidgets('a live-only bridge says so rather than showing nothing', (
      tester,
    ) async {
      final c = await controller();
      c.link = BridgeLink.connected;
      c.identity = const DeviceIdentity(
        id: 'A4F2',
        model: 'heltec-v3',
        fw: '1.0.0',
        probes: 4,
        historyFull: false,
        admin: false,
      );

      await tester.pumpWidget(host(c, const HistoryScreen()));
      await tester.pump();

      expect(find.text('This bridge serves live only'), findsOneWidget);
    });

    testWidgets('a disconnected graph points at the connect action', (
      tester,
    ) async {
      final c = await controller();

      await tester.pumpWidget(host(c, const GraphScreen()));
      await tester.pump();

      expect(find.text('No sessions cached'), findsOneWidget);
      expect(find.text('Connection settings'), findsOneWidget);
    });

    testWidgets('a connected live tab shows the probe cards', (tester) async {
      final c = await controller();
      c.link = BridgeLink.connected;

      await tester.pumpWidget(host(c, const LiveScreen()));
      await tester.pump();

      expect(find.text('Probe 1'), findsOneWidget);
      expect(find.text('Probe 4'), findsOneWidget);
      expect(find.text('No reading yet'), findsOneWidget);
    });
  });

  testWidgets('session detail names permanent recording holes by cause', (
    tester,
  ) async {
    await seedSession();
    await cache.recordGap(
      'A4F2',
      0x1A,
      const RecordedGap(fromT: 30, toT: 600, reason: GapReason.baseLost),
    );
    final c = await controller();
    expect(await c.gapsFor(0x1A), hasLength(1));

    await tester.pumpWidget(host(c, const HistoryScreen()));
    await tester.pump();
    await tester.tap(find.text('Brisket'));
    await tester.pumpAndSettle();

    expect(find.text('Statistics'), findsOneWidget);

    // The gaps card sits below the fold; scroll it into view.
    await tester.drag(find.text('Statistics'), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Gaps in recording'), findsOneWidget);
    expect(find.textContaining('Smoke X4 lost'), findsOneWidget);
    expect(find.textContaining('gone for good'), findsOneWidget);
  });
}
