/// Screen-level widget tests: the three tabs render their honest states from a
/// real controller over an in-memory cache, and the connection sheet opens.
///
/// No radio is dialled: the prefs hold no remembered bridge, so bootstrap stays
/// disconnected and every assertion is about presentation, not the link.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/bridge_scope.dart';
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

  testWidgets('Live, no link and no cook, offers exactly the connect action', (
    tester,
  ) async {
    final controller = BridgeController(cache);
    await controller.bootstrap();

    await tester.pumpWidget(host(controller, const LiveScreen()));
    await tester.pump();

    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Find my bridge'), findsOneWidget);
    expect(find.text('Cook clock'), findsNothing);

    controller.dispose();
  });

  testWidgets('a running cook stays visible with no link', (tester) async {
    SharedPreferences.setMockInitialValues({
      'cook_started_unix_ms':
          DateTime.now().millisecondsSinceEpoch - 65000, // 1:05
    });
    final controller = BridgeController(cache);
    await controller.bootstrap();

    await tester.pumpWidget(host(controller, const LiveScreen()));
    // The cook ticker repaints once a second, so never pumpAndSettle here.
    await tester.pump();

    expect(find.text('Cook clock'), findsOneWidget);
    expect(find.text('Not started'), findsNothing);
    // The card reads as running, not merely present.
    expect(find.text('Restart cook'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('History lists a cached session and opens its detail', (
    tester,
  ) async {
    await seedSession();
    final controller = BridgeController(cache);
    await controller.bootstrap();

    await tester.pumpWidget(host(controller, const HistoryScreen()));
    await tester.pump();

    expect(find.text('Brisket'), findsOneWidget);
    expect(find.textContaining('3 readings'), findsOneWidget);

    await tester.tap(find.text('Brisket'));
    await tester.pumpAndSettle();

    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('Still recording'), findsNothing);

    controller.dispose();
  });

  testWidgets('Graph shows the session picker, chart legend and metadata', (
    tester,
  ) async {
    await seedSession();
    final controller = BridgeController(cache);
    await controller.bootstrap();

    await tester.pumpWidget(host(controller, const GraphScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Brisket · closed'), findsOneWidget);
    expect(find.text('Probe 1'), findsOneWidget);
    // Probe 3 is detached throughout, so it never earns a legend entry.
    expect(find.text('Probe 3'), findsNothing);
    expect(find.textContaining('Session #26'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('the status chip opens the connection sheet', (tester) async {
    final controller = BridgeController(cache);
    await controller.bootstrap();

    await tester.pumpWidget(host(controller, const LiveScreen()));
    await tester.pump();

    await tester.tap(find.text('Offline'));
    await tester.pumpAndSettle();

    expect(find.text('Connection'), findsOneWidget);
    // The tab's own empty state and the sheet both say "Not connected".
    expect(find.text('Not connected'), findsWidgets);
    expect(find.text('Find my bridge'), findsWidgets);

    controller.dispose();
  });
}
