import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/db/sample_dao.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/domain/content.dart';
import 'package:smoke_bridge/features/live/live_screen.dart';
import 'package:smoke_bridge/features/setup/setup_screen.dart';
import 'package:smoke_bridge/features/settings/bridge_details.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/theme/app_theme.dart';
import 'package:smoke_bridge/widgets/probe_chart.dart';

/// T45: one widget test per History/data empty and error state in 06 §6.8 and
/// 13 §13.4. Copy is asserted literally so a later refactor cannot quietly
/// reintroduce raw exceptions, fake zeros or an actionless dead end.
void main() {
  Future<void> pumpLive(WidgetTester tester, BridgeController controller) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: Scaffold(body: LiveScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpShell(WidgetTester tester, BridgeController controller) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: AppShell(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectNoRawException(WidgetTester tester) {
    for (final marker in [
      'Exception',
      'StateError',
      'DatabaseException',
      'sqlite',
      'stack',
    ]) {
      expect(
        find.textContaining(marker),
        findsNothing,
        reason: 'raw "$marker" text reached the UI',
      );
    }
  }

  group('History empty states', () {
    testWidgets('no history says No readings yet and offers View Live', (
      tester,
    ) async {
      final controller = demoBridgeController()
        ..tab = AppTab.history
        ..historyHasData = false
        ..phoneRecords = 0;
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      expect(find.text('No readings yet'), findsOneWidget);
      expect(
        find.text(
          'The Bridge records whenever it’s on and paired with the Smoke X4.',
        ),
        findsOneWidget,
      );
      expect(find.text('View Live'), findsOneWidget);
      expect(find.byKey(const Key('history.empty')), findsOneWidget);
      expectNoRawException(tester);

      await tester.tap(find.text('View Live'));
      await tester.pumpAndSettle();
      expect(controller.tab, AppTab.live);
    });

    testWidgets('a range with no saved readings offers Show all saved history', (
      tester,
    ) async {
      final controller = BridgeController(content: const _EmptyHistoryContent())
        ..tab = AppTab.history
        ..historyHasData = true
        ..phoneRecords = 12;
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      expect(find.text('No readings in this range'), findsOneWidget);
      expect(
        find.text(
          'This range has no saved readings. Show all saved history to find the readings you expect.',
        ),
        findsOneWidget,
      );
      expect(find.text('Show all saved history'), findsOneWidget);
      expect(find.text('No probes'), findsOneWidget);
      expectNoRawException(tester);
    });

    testWidgets('a filtered probe with no readings has no line and no zero', (
      tester,
    ) async {
      final controller = BridgeController(content: const _ProbeGapContent())
        ..tab = AppTab.history
        ..historyHasData = true
        ..historyProbe = 3;
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      expect(find.text('No readings in this range'), findsOneWidget);
      expect(
        find.text(
          'Probe 3 has no readings in this range. Try another range or show all probes.',
        ),
        findsOneWidget,
      );
      expect(find.text('Show all probes'), findsOneWidget);
      // Summary is honest: P3 is No data with dashes, never a zero line.
      expect(find.text('No data'), findsWidgets);
      expect(find.text('—'), findsWidgets);
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.byType(HistoryChart), findsNothing);
      expectNoRawException(tester);

      await tester.tap(find.text('Show all probes'));
      await tester.pumpAndSettle();
      expect(controller.historyProbe, isNull);
      expect(find.byType(HistoryChart), findsOneWidget);
    });
  });

  group('Bridge offline', () {
    testWidgets('offline with cache labels saved readings and keeps the chart', (
      tester,
    ) async {
      final controller = demoBridgeController()
        ..tab = AppTab.history
        ..phase = ConnectionPhase.offline
        ..offlineCache = true;
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      expect(find.text('Showing saved readings'), findsOneWidget);
      expect(find.text('Last reading 2 hr ago'), findsOneWidget);
      expect(find.text('Can’t reach the Bridge'), findsNothing);
      expect(find.byKey(const Key('history.chart')), findsOneWidget);
      expectNoRawException(tester);
    });

    testWidgets('failed reconnect with cache still says saved readings', (
      tester,
    ) async {
      final controller = demoBridgeController()
        ..tab = AppTab.history
        ..phase = ConnectionPhase.failed
        ..offlineCache = true;
      addTearDown(controller.dispose);
      await pumpShell(tester, controller);

      expect(find.text('Showing saved readings'), findsOneWidget);
      expect(find.text('Can’t reach the Bridge'), findsNothing);
      expect(find.byKey(const Key('history.chart')), findsOneWidget);
    });

    testWidgets('Live offline with cache shows one saved-readings banner', (
      tester,
    ) async {
      final controller = demoBridgeController()
        ..phase = ConnectionPhase.offline
        ..offlineCache = true;
      addTearDown(controller.dispose);
      await pumpLive(tester, controller);

      expect(
        find.textContaining('Showing saved readings · last reading'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('live.savedReadings')), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('165.2'), findsOneWidget);
      expect(find.text('Can’t reach the Bridge'), findsNothing);
    });

    testWidgets('Live failed reconnect with cache hides the unreachable notice', (
      tester,
    ) async {
      final controller = demoBridgeController()
        ..phase = ConnectionPhase.failed
        ..offlineCache = true;
      addTearDown(controller.dispose);
      await pumpLive(tester, controller);

      expect(find.byKey(const Key('live.savedReadings')), findsOneWidget);
      expect(find.byKey(const Key('live.unreachable')), findsNothing);
    });

    testWidgets('offline without cache is named and renders no probe values', (
      tester,
    ) async {
      final controller = demoBridgeController()
        ..phase = ConnectionPhase.offline
        ..offlineCache = false;
      addTearDown(controller.dispose);
      await pumpLive(tester, controller);

      expect(
        find.text('Bridge disconnected · nothing saved yet'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('live.noCache')), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      for (var probe = 1; probe <= 4; probe++) {
        final card = find.byKey(Key('live.probe.$probe'));
        expect(
          find.descendant(of: card, matching: find.text('—')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('165.2')),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('225.0')),
          findsNothing,
        );
      }
      expectNoRawException(tester);
    });
  });

  group('Live data failures', () {
    testWidgets('no probes names the cause and opens Bridge details', (
      tester,
    ) async {
      final controller = demoBridgeController()
        ..probePresence = ProbePresence.none;
      addTearDown(controller.dispose);
      await pumpLive(tester, controller);

      expect(find.text('No probes connected'), findsOneWidget);
      expect(
        find.text('Plug a probe into the Smoke X4 to see a reading.'),
        findsOneWidget,
      );
      expect(find.text('Bridge details'), findsOneWidget);
      expect(find.text('Not connected'), findsNothing);
      expectNoRawException(tester);

      await tester.tap(find.text('Bridge details'));
      await tester.pumpAndSettle();
      expect(find.byType(BridgeDetailsScreen), findsOneWidget);
    });

    testWidgets('no X4 data is one amber warning with the SYNC-mode dialog', (
      tester,
    ) async {
      final controller = demoBridgeController()
        ..phase = ConnectionPhase.live
        ..smokeXStatus = SmokeXStatus.pairedLive
        ..smokeXAgeOverride = const Duration(minutes: 4);
      addTearDown(controller.dispose);
      await pumpLive(tester, controller);

      expect(find.byKey(const Key('live.smokeXWarning')), findsOneWidget);
      expect(find.text('No data from Smoke X4'), findsNothing);
      expect(find.text('Can’t reach the Bridge'), findsNothing);

      await tester.tap(find.byKey(const Key('live.smokeXWarning')));
      await tester.pumpAndSettle();

      expect(find.text('No data from Smoke X4'), findsOneWidget);
      expect(
        find.text(
          'The Bridge is connected but isn’t receiving data from the Smoke X4. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pairing steps'), findsOneWidget);
      expect(
        find.text('Plug a probe into the Smoke X4 to see a reading.'),
        findsNothing,
      );
    });

    testWidgets('an unpaired X4 also uses the approved no-data copy', (
      tester,
    ) async {
      final controller = demoBridgeController()
        ..phase = ConnectionPhase.live
        ..smokeXStatus = SmokeXStatus.unpaired
        ..probePresence = ProbePresence.none;
      addTearDown(controller.dispose);
      await pumpLive(tester, controller);

      expect(find.byKey(const Key('live.smokeXUnpaired')), findsOneWidget);
      expect(find.text('No data from Smoke X4'), findsOneWidget);
      expect(
        find.text(
          'The Bridge is connected but isn’t receiving data from the Smoke X4. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pairing steps'), findsOneWidget);
      expect(find.text('Can’t reach the Bridge'), findsNothing);
      expectNoRawException(tester);
    });

    testWidgets('sync failure keeps live readings and offers Retry sync', (
      tester,
    ) async {
      final controller = demoBridgeController()..syncState = SyncState.error;
      addTearDown(controller.dispose);
      await pumpLive(tester, controller);

      expect(find.byKey(const Key('live.syncFailed')), findsOneWidget);
      expect(find.text('History sync failed'), findsOneWidget);
      expect(
        find.text(
          'Live readings are still updating. Retry when the Bluetooth connection is stable.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry sync'), findsOneWidget);
      expect(find.textContaining('165.2'), findsOneWidget);
      expectNoRawException(tester);
    });

    testWidgets('storage unavailable says Not recording and opens Bridge details', (
      tester,
    ) async {
      final controller = demoBridgeController()..storageOk = false;
      addTearDown(controller.dispose);
      await pumpLive(tester, controller);

      expect(find.byKey(const Key('live.storageUnavailable')), findsOneWidget);
      expect(find.text('Not recording'), findsOneWidget);
      expect(
        find.text(
          'Live readings are available, but the Bridge can’t save them. Check the Bridge’s storage.',
        ),
        findsOneWidget,
      );
      expect(find.text('Bridge details'), findsOneWidget);

      await tester.tap(find.text('Bridge details'));
      await tester.pumpAndSettle();
      expect(find.byType(BridgeDetailsScreen), findsOneWidget);
    });
  });

  group('Protocol mismatch', () {
    testWidgets('names the update, keeps the Bridge unchanged and saves history', (
      tester,
    ) async {
      final controller = demoBridgeController()..hasSavedData = true;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          home: SetupScreen(
            controller: controller,
            initialStep: SetupStep.protocolMismatch,
            autoAdvance: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update the app to use this Bridge'), findsOneWidget);
      expect(find.text('Update app'), findsOneWidget);
      expect(
        find.textContaining('The Bridge hasn’t been changed.'),
        findsOneWidget,
      );
      expect(find.text('View history on this phone'), findsOneWidget);
      expect(find.text('Learn more'), findsOneWidget);
      expectNoRawException(tester);

      await tester.tap(find.text('Learn more'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The Bridge hasn’t been changed and keeps recording.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('a storage read failure never renders raw exception text', (
    tester,
  ) async {
    final controller = BridgeController(
      content: const _EmptyHistoryContent(),
      sampleDao: _ThrowingDao(),
    )..tab = AppTab.history;
    addTearDown(controller.dispose);

    await pumpShell(tester, controller);

    expect(find.text('Couldn’t load saved readings'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expectNoRawException(tester);
  });
}

/// History with a saved extent but no series values in the selected range.
class _EmptyHistoryContent implements BridgeContent {
  const _EmptyHistoryContent();

  static final DateTime _now = DateTime(2026, 10, 27, 12);

  @override
  DateTime get now => _now;

  @override
  List<double?> get probeTemps => const <double?>[null, null, null, null];

  @override
  HistoryWindow get historyWindow =>
      HistoryWindow(start: _now.subtract(const Duration(hours: 24)), end: _now);

  @override
  int get bridgeRecords => 0;

  @override
  int get bridgeCapacity => 0;

  @override
  int get phoneRecords => 12;

  @override
  String get savedDataRange => 'Oct 27, 2026';

  @override
  String get savedDataSize => '864 B';

  @override
  List<ChartPoint> sparkline(int probe, {required bool hasData}) => const [];

  @override
  HistoryFixture history(
    HistoryRange range, {
    required bool empty,
    required bool oneProbe,
    required bool estimated,
    required bool missingFromBridge,
    required bool hasGap,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final start = customStart ?? _now.subtract(const Duration(hours: 1));
    final end = customEnd ?? _now;
    return HistoryFixture(
      start: start,
      end: end,
      series: const <ChartSeries>[
        ChartSeries(0, <ChartPoint>[]),
        ChartSeries(1, <ChartPoint>[]),
        ChartSeries(2, <ChartPoint>[]),
        ChartSeries(3, <ChartPoint>[]),
      ],
      gapStart: start,
      gapEnd: start,
      gapReason: HistoryGapReason.noSignal,
      estimated: estimated,
      missingFromBridge: missingFromBridge,
    );
  }

  @override
  List<CookSession> cooks() => const <CookSession>[];
}

/// P1 has readings, P3 has none in the selected range.
class _ProbeGapContent extends _EmptyHistoryContent {
  const _ProbeGapContent();

  @override
  HistoryFixture history(
    HistoryRange range, {
    required bool empty,
    required bool oneProbe,
    required bool estimated,
    required bool missingFromBridge,
    required bool hasGap,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final start =
        customStart ??
        _EmptyHistoryContent._now.subtract(const Duration(hours: 1));
    final end = customEnd ?? _EmptyHistoryContent._now;
    final points = <ChartPoint>[
      ChartPoint(start, 165.0),
      ChartPoint(start.add(const Duration(minutes: 5)), 166.0),
    ];
    return HistoryFixture(
      start: start,
      end: end,
      series: <ChartSeries>[
        ChartSeries(0, points),
        const ChartSeries(1, <ChartPoint>[]),
        const ChartSeries(2, <ChartPoint>[]),
        const ChartSeries(3, <ChartPoint>[]),
      ],
      gapStart: start,
      gapEnd: start,
      gapReason: HistoryGapReason.noSignal,
      estimated: estimated,
      missingFromBridge: missingFromBridge,
    );
  }
}

/// A platform/database failure: the loader must map it to named copy.
class _ThrowingDao implements SampleDao {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not used here');

  @override
  Future<SampleExtent?> extent({String? bridgeId, int? generation}) {
    throw StateError('DatabaseException(disk I/O error)');
  }
}
