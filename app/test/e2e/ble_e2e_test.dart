/// The end-to-end harness: one test drives the whole kept-feature path over a
/// [FakePeripheral] — connect, set the clock, pull the session list, delta-sync
/// the samples, render the graph — and survives a dropped link by reconnecting.
///
/// No radio, no board: every byte on the wire comes from the fake, which speaks
/// the same generated contract the firmware does. This is the level the old
/// piecemeal unit tests never reached: one flow, one fake, the real screens.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/bridge_scope.dart';
import 'package:smoke_bridge/data/ble/ble_gatt.dart';
import 'package:smoke_bridge/data/ble/ble_transport.dart';
import 'package:smoke_bridge/data/dto/records.g.dart';
import 'package:smoke_bridge/data/local/app_database.dart';
import 'package:smoke_bridge/data/local/drift_sample_cache.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/features/graph/graph_screen.dart';

import '../support/fake_peripheral.dart';

Future<void> _waitFor(
  FutureOr<bool> Function() done, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final end = DateTime.now().add(timeout);
  while (!await done()) {
    if (DateTime.now().isAfter(end)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

int _setTimeWrites(FakePeripheral fake) => fake.writes
    .where((w) => w.$1 == BridgeChar.deviceControl)
    .map((w) => DeviceControl.unpack(w.$2).opEnum)
    .where((op) => op == ControlOp.setTime)
    .length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftSampleCache cache;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'last_bridge_device_id': 'AA:BB:CC:DD:AA:BB',
    });
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftSampleCache(db);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('connect → clock → sessions → sync → graph, across a drop', (
    tester,
  ) async {
    // The bridge is already holding an hour of a finished cook when we arrive.
    final state = FakeBridgeState();
    state.recordCook(hours: 1, closed: true);

    final fakes = <FakePeripheral>[];
    Future<BleTransport> open() async {
      final fake = FakePeripheral(state: state);
      fakes.add(fake);
      await fake.connect('AA:BB:CC:DD:AA:BB');
      await fake.bond();
      await fake.requestMtu(247);
      final transport = BleTransport(fake);
      await transport.start();
      return transport;
    }

    final controller = BridgeController(cache, openTransport: open);
    addTearDown(controller.dispose);

    await tester.runAsync(() async {
      await controller.bootstrap();
      await _waitFor(() => controller.link == BridgeLink.connected);

      // 1. The clock is set once, as part of connect — before the session list,
      //    so the bridge back-patches its open session with a real date.
      expect(_setTimeWrites(fakes.first), 1);

      // 2. The session list arrives and is cached.
      await _waitFor(() => controller.sessions.isNotEmpty);
      expect(controller.sessions.single.id, 0x1A);
      expect(controller.sessions.single.closed, isTrue);

      // 3. The delta sync drains every sample into the phone's cache.
      await _waitFor(() async {
        final samples = await controller.samplesFor(0x1A);
        return samples.length == 120;
      });
      final samples = await controller.samplesFor(0x1A);
      expect(samples.first.t, 0);
      expect(samples.last.t, 119 * 30);
      expect(
        samples.first.tempsF10[2],
        isNull,
        reason: 'the detached probe stays null all the way through',
      );
      expect(
        fakes.first.historyRequests,
        greaterThanOrEqualTo(2),
        reason: 'one request for sessions, one for samples',
      );
    });

    // 4. The graph renders that cached session: picker, legend and metadata.
    await tester.pumpWidget(
      BridgeScope(
        controller: controller,
        child: MaterialApp(
          theme: buildSmokeTheme(),
          home: const GraphScreen(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('· closed'), findsOneWidget);
    expect(find.text('Probe 1'), findsOneWidget);
    expect(find.text('Probe 3'), findsNothing, reason: 'detached probe');
    expect(find.text('All'), findsOneWidget, reason: 'the viewport control');

    // 5. The peer drops the link; the controller reconnects without a tap and
    //    the history it already pulled survives on the phone.
    final firstFake = fakes.first;
    await tester.runAsync(() async {
      firstFake.dropLink();
      await _waitFor(
        () async => fakes.length >= 2 && controller.link == BridgeLink.connected,
        timeout: const Duration(seconds: 15),
      );
    });

    expect(controller.connected, isTrue);
    expect(fakes.length, greaterThanOrEqualTo(2));
    expect(controller.sessions, isNotEmpty);
    expect(await controller.samplesFor(0x1A), hasLength(120));
  });
}
