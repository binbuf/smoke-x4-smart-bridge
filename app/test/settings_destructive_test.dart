import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';
import 'package:smoke_bridge/data/ble/bridge_link.dart';
import 'package:smoke_bridge/domain/content.dart';
import 'package:smoke_bridge/features/settings/bridge_details.dart';
import 'package:smoke_bridge/features/settings/settings_views.dart';
import 'package:smoke_bridge/features/setup/setup_screen.dart';
import 'package:smoke_bridge/theme/app_theme.dart';

import 'support/codecs.dart' as gen;
import 'support/fake_ble_client.dart';
import 'support/fake_bridge.dart';

final DateTime _now = DateTime.utc(2026, 10, 27, 12);

void main() {
  group('confirmation sheets keep the exact loss copy', () {
    testWidgets('forget', (tester) async {
      final controller = _ScriptedController()..phase = ConnectionPhase.live;
      addTearDown(controller.dispose);
      await _pumpDetails(tester, controller);

      await _tap(tester, 'Forget this phone');
      expect(find.text('Forget this phone?'), findsOneWidget);
      expect(
        find.text(
          'This removes the Bluetooth pairing for this phone. The Bridge keeps recording.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('History on this phone stays until you delete it.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'You can pair again later. Other paired phones are not affected.',
        ),
        findsOneWidget,
      );
      expect(controller.pendingAction, isNull);
    });

    testWidgets('factory reset names every category of loss', (tester) async {
      final controller = _ScriptedController()..phase = ConnectionPhase.live;
      addTearDown(controller.dispose);
      await _pumpDetails(tester, controller);

      await _tap(tester, 'Factory reset Bridge');
      expect(find.text('Factory reset this Bridge?'), findsOneWidget);
      expect(
        find.text(
          'The Bridge erases its pairings, settings, and saved readings, then restarts.',
        ),
        findsOneWidget,
      );
      expect(find.text('All paired phones, including this one'), findsOneWidget);
      expect(
        find.text('Bridge settings and screen preferences'),
        findsOneWidget,
      );
      expect(find.text('Saved readings and the clock'), findsOneWidget);
      expect(
        find.text('The Bridge becomes available to pair as a new device'),
        findsOneWidget,
      );
      expect(find.text('History on this phone is kept.'), findsOneWidget);
      expect(controller.pendingAction, isNull);
    });

    testWidgets('power off', (tester) async {
      final controller = _ScriptedController()..phase = ConnectionPhase.live;
      addTearDown(controller.dispose);
      await _pumpDetails(tester, controller);

      await _tap(tester, 'Power off the Bridge');
      expect(find.text('Power off the Bridge?'), findsOneWidget);
      expect(
        find.text('The Bridge stops recording until you turn it back on.'),
        findsOneWidget,
      );
      expect(
        find.text('Recording stops while the Bridge is off'),
        findsOneWidget,
      );
      expect(find.text('History on this phone is kept'), findsOneWidget);
      expect(
        find.text('Hold PRG for 1.5 seconds to turn the Bridge back on.'),
        findsOneWidget,
      );
      expect(controller.pendingAction, isNull);
    });

    testWidgets('clear history names the count and keeps phone history', (
      tester,
    ) async {
      final controller = _ScriptedController()
        ..phase = ConnectionPhase.live
        ..bridgeRecords = 24810
        ..bridgeCapacity = 338400
        ..bridgeOldestReadingAt = DateTime(2026, 7, 2, 8)
        ..bridgeNewestReadingAt = DateTime(2026, 10, 27, 8);
      addTearDown(controller.dispose);
      await _pumpHistory(tester, controller);

      await tester.ensureVisible(find.text('Clear history on the Bridge…'));
      await tester.tap(find.text('Clear history on the Bridge…'));
      await tester.pumpAndSettle();

      expect(find.text('Clear history on the Bridge?'), findsOneWidget);
      expect(
        find.text('24,810 readings in history on the Bridge'),
        findsOneWidget,
      );
      expect(find.textContaining('Date range:'), findsOneWidget);
      expect(find.text('History on this phone is kept'), findsOneWidget);
      expect(controller.pendingAction, isNull);
    });
  });

  testWidgets('sending state is neutral and success waits for the result', (
    tester,
  ) async {
    final controller = _ScriptedController()
      ..phase = ConnectionPhase.live
      ..bridgeRecords = 120
      ..bridgeCapacity = 338400;
    addTearDown(controller.dispose);
    await _pumpHistory(tester, controller);

    await tester.ensureVisible(find.text('Clear history on the Bridge…'));
    await tester.tap(find.text('Clear history on the Bridge…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pump();

    expect(controller.pendingAction, DestructiveActionKind.clearHistory);
    expect(find.byKey(const Key('destructive.sending')), findsOneWidget);
    expect(find.text('Clearing history on the Bridge…'), findsOneWidget);
    expect(controller.bridgeRecords, 120);
    expect(find.byKey(const Key('destructive.clear.success')), findsNothing);

    controller.complete(DestructiveOutcome.timedOut);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('destructive.failure')), findsOneWidget);
    expect(controller.bridgeRecords, 120);
  });

  testWidgets('clear history succeeds only on an ok result', (tester) async {
    final controller = _ScriptedController()
      ..phase = ConnectionPhase.live
      ..bridgeRecords = 120
      ..phoneRecords = 7;
    addTearDown(controller.dispose);
    await _pumpHistory(tester, controller);

    await tester.ensureVisible(find.text('Clear history on the Bridge…'));
    await tester.tap(find.text('Clear history on the Bridge…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pump();
    controller.complete(DestructiveOutcome.success);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('destructive.clear.success')), findsOneWidget);
    expect(controller.bridgeRecords, 0);
    expect(controller.phoneRecords, 7);
  });

  testWidgets('a refused clear history keeps the Bridge figures', (tester) async {
    final controller = _ScriptedController()
      ..phase = ConnectionPhase.live
      ..bridgeRecords = 120;
    addTearDown(controller.dispose);
    await _pumpHistory(tester, controller);

    await tester.ensureVisible(find.text('Clear history on the Bridge…'));
    await tester.tap(find.text('Clear history on the Bridge…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pump();
    controller.complete(DestructiveOutcome.failed);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('destructive.failure')), findsOneWidget);
    expect(find.byKey(const Key('destructive.clear.success')), findsNothing);
    expect(controller.bridgeRecords, 120);
  });

  testWidgets('factory reset treats the expected disconnect as success and '
      'returns to Setup with orphaned history', (tester) async {
    final controller = _ScriptedController()
      ..phase = ConnectionPhase.live
      ..phoneRecords = 42
      ..hasSavedData = true
      ..savedDataEmpty = false;
    addTearDown(controller.dispose);
    await _pumpDetails(tester, controller);

    await _tap(tester, 'Factory reset Bridge');
    await tester.tap(find.text('Factory reset'));
    await tester.pump();

    expect(controller.pendingAction, DestructiveActionKind.factoryReset);
    expect(find.byKey(const Key('destructive.sending')), findsOneWidget);
    expect(find.text('Resetting the Bridge…'), findsOneWidget);
    expect(controller.hasSavedBridge, isTrue);

    controller.complete(DestructiveOutcome.disconnected);
    await tester.pumpAndSettle();

    expect(controller.hasSavedBridge, isFalse);
    expect(controller.historyOrphaned, isTrue);
    expect(controller.phoneRecords, 42);
    expect(find.byType(SetupScreen), findsOneWidget);
    expect(find.text('History on this phone'), findsOneWidget);
    expect(find.textContaining('from your previous Bridge.'), findsOneWidget);
  });

  testWidgets('factory reset failure stays on the screen and changes nothing', (
    tester,
  ) async {
    final controller = _ScriptedController()
      ..phase = ConnectionPhase.live
      ..phoneRecords = 42
      ..hasSavedData = true;
    addTearDown(controller.dispose);
    await _pumpDetails(tester, controller);

    await _tap(tester, 'Factory reset Bridge');
    await tester.tap(find.text('Factory reset'));
    await tester.pump();
    controller.complete(DestructiveOutcome.timedOut);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('destructive.failure')), findsOneWidget);
    expect(controller.hasSavedBridge, isTrue);
    expect(find.byType(SetupScreen), findsNothing);
  });

  testWidgets('forget clears the local connection, keeps history and explains '
      'when the pairing may remain', (tester) async {
    final controller = _ScriptedController()
      ..phase = ConnectionPhase.live
      ..phoneRecords = 42
      ..hasSavedData = true
      ..savedDataEmpty = false;
    addTearDown(controller.dispose);
    await _pumpDetails(tester, controller);

    await _tap(tester, 'Forget this phone');
    await tester.tap(find.text('Forget phone'));
    await tester.pump();

    expect(controller.pendingAction, DestructiveActionKind.forgetPhone);
    expect(find.text('Forgetting this phone…'), findsOneWidget);

    controller.complete(DestructiveOutcome.disconnected);
    await tester.pumpAndSettle();

    expect(controller.hasSavedBridge, isFalse);
    expect(controller.phoneRecords, 42);
    expect(controller.historyOrphaned, isTrue);
    expect(find.byType(SetupScreen), findsOneWidget);
    expect(find.text('History on this phone'), findsOneWidget);
    expect(find.text('Pairing not confirmed'), findsNothing);
  });

  testWidgets('forget offline returns to Setup and says the Bridge may still '
      'hold the pairing', (tester) async {
    final controller = _ScriptedController()
      ..phase = ConnectionPhase.offline
      ..hasSavedBridge = true
      ..phoneRecords = 42
      ..hasSavedData = true
      ..savedDataEmpty = false;
    addTearDown(controller.dispose);
    await _pumpDetails(tester, controller);

    await _tap(tester, 'Forget this phone');
    await tester.tap(find.text('Forget phone'));
    await tester.pump();
    controller.complete(DestructiveOutcome.unavailable);
    await tester.pumpAndSettle();

    expect(find.byType(SetupScreen), findsOneWidget);
    expect(find.text('Pairing not confirmed'), findsOneWidget);
    expect(
      find.textContaining('may still have this phone paired'),
      findsOneWidget,
    );
  });

  testWidgets('power off shows Bridge is off and never claims it is reachable', (
    tester,
  ) async {
    final controller = _ScriptedController()..phase = ConnectionPhase.live;
    addTearDown(controller.dispose);
    await _pumpDetails(tester, controller);

    await _tap(tester, 'Power off the Bridge');
    await tester.tap(find.text('Power off'));
    await tester.pump();
    controller.complete(DestructiveOutcome.disconnected);
    await tester.pumpAndSettle();

    expect(find.text('Bridge is off'), findsWidgets);
    expect(
      find.text(
        'The Bridge isn’t recording. Hold PRG for 1.5 seconds to turn it back on.',
      ),
      findsOneWidget,
    );
    expect(controller.bridgeOff, isTrue);
    expect(controller.isConnected, isFalse);
  });

  testWidgets('no current cook copy appears in any destructive sheet', (
    tester,
  ) async {
    final controller = _ScriptedController()
      ..phase = ConnectionPhase.live
      ..bridgeRecords = 120;
    addTearDown(controller.dispose);
    await _pumpDetails(tester, controller);

    for (final action in <String>[
      'Forget this phone',
      'Factory reset Bridge',
      'Power off the Bridge',
    ]) {
      await _tap(tester, action);
      expect(
        find.textContaining('current cook', findRichText: true),
        findsNothing,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });

  group('real link outcomes', () {
    test('forget sends forget_phone and clears the saved connection on ok', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.connect();
      harness.controller
        ..phoneRecords = 42
        ..hasSavedData = true;

      final outcome = await harness.controller.forgetPhone();

      expect(outcome, DestructiveOutcome.success);
      expect(
        harness.bridge.controlWrites.map((control) => control.op),
        contains(gen.ControlOp.forgetPhone.wire),
      );
      expect(harness.controller.hasSavedBridge, isFalse);
      expect(harness.controller.phoneRecords, 42);
      expect(harness.controller.historyOrphaned, isTrue);
      expect(harness.client.bondState, BleBondState.none);
    });

    test('factory reset treats the disconnect after the request as success', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.connect();
      harness.controller
        ..phoneRecords = 42
        ..hasSavedData = true;
      harness.bridge.dropControlResults = true;

      final pending = harness.controller.factoryReset();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await harness.client.disconnect();
      final outcome = await pending;

      expect(outcome, DestructiveOutcome.disconnected);
      expect(
        harness.bridge.controlWrites.map((control) => control.op),
        contains(gen.ControlOp.factoryReset.wire),
      );
      expect(harness.controller.hasSavedBridge, isFalse);
      expect(harness.controller.historyOrphaned, isTrue);
    });

    test('power off sends power_off and stops presenting the Bridge as reachable', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.connect();

      final outcome = await harness.controller.powerOff();

      expect(outcome, DestructiveOutcome.success);
      expect(
        harness.bridge.controlWrites.map((control) => control.op),
        contains(gen.ControlOp.powerOff.wire),
      );
      expect(harness.controller.bridgeOff, isTrue);
      expect(harness.controller.isConnected, isFalse);
    });

    test('clear history changes the Bridge figures only on ok', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.connect();
      harness.controller
        ..bridgeRecords = 120
        ..phoneRecords = 7;

      final ok = await harness.controller.clearBridgeHistory();

      expect(ok, DestructiveOutcome.success);
      expect(
        harness.bridge.controlWrites.map((control) => control.op),
        contains(gen.ControlOp.clearHistory.wire),
      );
      expect(harness.controller.bridgeRecords, 0);
      expect(harness.controller.phoneRecords, 7);

      harness.controller.bridgeRecords = 120;
      harness.bridge.forcedControlStatus = gen.ResultStatus.busy;
      final refused = await harness.controller.clearBridgeHistory();

      expect(refused, DestructiveOutcome.failed);
      expect(harness.controller.bridgeRecords, 120);
    });
  });
}

Future<void> _pumpDetails(
  WidgetTester tester,
  BridgeController controller,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: BridgeDetailsScreen(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpHistory(
  WidgetTester tester,
  BridgeController controller,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: HistoryStorageScreen(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

enum DestructiveActionKind { forgetPhone, factoryReset, powerOff, clearHistory }

/// Widget-test double for the four destructive actions.
///
/// Each call parks until the test supplies the device outcome, so the sending
/// state and every success/failure/disconnect branch are deterministic. The
/// real GATT mapping is proved separately with the scripted bridge.
class _ScriptedController extends BridgeController {
  _ScriptedController() : super(content: _EmptyContent());

  DestructiveActionKind? pendingAction;
  Completer<DestructiveOutcome>? _pending;

  @override
  Future<DestructiveOutcome> forgetPhone() =>
      _begin(DestructiveActionKind.forgetPhone);

  @override
  Future<DestructiveOutcome> factoryReset() =>
      _begin(DestructiveActionKind.factoryReset);

  @override
  Future<DestructiveOutcome> powerOff() =>
      _begin(DestructiveActionKind.powerOff);

  @override
  Future<DestructiveOutcome> clearBridgeHistory() =>
      _begin(DestructiveActionKind.clearHistory);

  Future<DestructiveOutcome> _begin(DestructiveActionKind kind) {
    pendingAction = kind;
    final completer = Completer<DestructiveOutcome>();
    _pending = completer;
    return completer.future;
  }

  void complete(DestructiveOutcome outcome) {
    final kind = pendingAction;
    final pending = _pending;
    if (kind == null || pending == null || pending.isCompleted) return;
    pending.complete(outcome);
    pendingAction = null;
    _pending = null;
    switch (kind) {
      case DestructiveActionKind.forgetPhone:
        hasSavedBridge = false;
        final hasOrphanedHistory = phoneRecords > 0 || hasSavedData;
        hasSavedData = hasOrphanedHistory;
        savedDataEmpty = !hasOrphanedHistory;
        historyOrphaned = hasOrphanedHistory;
        phase = ConnectionPhase.setup;
        if (!outcome.landed) {
          destructiveNotice =
              'The Bridge may still have this phone paired. You can pair again later from another phone.';
        }
        break;
      case DestructiveActionKind.factoryReset:
        if (outcome.landed) {
          hasSavedBridge = false;
          final hasOrphanedHistory = phoneRecords > 0 || hasSavedData;
          hasSavedData = hasOrphanedHistory;
          savedDataEmpty = !hasOrphanedHistory;
          historyOrphaned = hasOrphanedHistory;
          phase = ConnectionPhase.setup;
        }
        break;
      case DestructiveActionKind.powerOff:
        if (outcome.landed) {
          bridgeOff = true;
          phase = ConnectionPhase.offline;
        }
        break;
      case DestructiveActionKind.clearHistory:
        if (outcome == DestructiveOutcome.success) {
          bridgeRecords = 0;
          bridgeOldestReadingAt = null;
          bridgeNewestReadingAt = null;
        }
        break;
    }
    notifyListeners();
  }
}

class _Harness {
  _Harness() {
    bridge = FakeBridge();
    client = FakeBleClient(
      server: bridge,
      advertisements: <BleDevice>[bridge.advertisement()],
      connectDelay: Duration.zero,
      bondDelay: Duration.zero,
      scanInterval: Duration.zero,
    );
    controller = BridgeController(bleClient: client, content: _EmptyContent())
      ..hasSavedBridge = true
      ..phase = ConnectionPhase.offline;
    link = controller.ensureLink(
      settings: const BridgeLinkSettings(
        controlTimeout: Duration(seconds: 3),
      ),
      bondPrompt: () async => true,
    );
  }

  late final FakeBridge bridge;
  late final FakeBleClient client;
  late final BridgeController controller;
  late final BridgeLink link;

  Future<void> connect() async {
    await link.connectAndSecure(bridge.advertisement());
    expect(controller.phase, ConnectionPhase.live);
  }

  Future<void> dispose() async {
    await link.dispose();
    controller.dispose();
    await client.dispose();
    await bridge.dispose();
  }
}

class _EmptyContent implements BridgeContent {
  @override
  List<double?> get probeTemps => const <double?>[null, null, null, null];

  @override
  DateTime get now => _now;

  @override
  HistoryWindow get historyWindow =>
      HistoryWindow(start: now.subtract(const Duration(hours: 1)), end: now);

  @override
  int get bridgeRecords => 0;

  @override
  int get bridgeCapacity => 0;

  @override
  int get phoneRecords => 0;

  @override
  String get savedDataRange => '—';

  @override
  String get savedDataSize => '0 B';

  @override
  List<ChartPoint> sparkline(int probe, {required bool hasData}) =>
      const <ChartPoint>[];

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
    return HistoryFixture(
      start: now,
      end: now,
      series: const <ChartSeries>[],
      gapStart: now,
      gapEnd: now,
      gapReason: HistoryGapReason.noSignal,
      estimated: estimated,
      missingFromBridge: missingFromBridge,
    );
  }

  @override
  List<CookSession> cooks() => const <CookSession>[];
}
