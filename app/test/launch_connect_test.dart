import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/smoke_bridge_app.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';
import 'package:smoke_bridge/data/db/app_database.dart';
import 'package:smoke_bridge/data/db/sample_dao.dart';
import 'package:smoke_bridge/domain/content.dart';
import 'package:smoke_bridge/features/setup/setup_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_ble_client.dart';
import 'support/fake_bridge.dart';

const int _nowMs = 1700000000000;
const Duration _scanWindow = Duration(milliseconds: 100);

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SampleDao dao;
  late FakeBridge bridge;
  late FakeBleClient client;

  BleDevice device() => bridge.advertisement();

  setUp(() async {
    database = await AppDatabase.openInMemory(factory: databaseFactoryFfi);
    dao = SqfliteSampleDao(database);
    bridge = FakeBridge();
    client = FakeBleClient(
      server: bridge,
      advertisements: <BleDevice>[device()],
      connectDelay: Duration.zero,
      bondDelay: Duration.zero,
      scanInterval: Duration.zero,
    );
  });

  tearDown(() async {
    await client.dispose();
    await bridge.dispose();
    await dao.close();
  });

  Future<void> seedSavedBridge({
    List<BleDevice>? advertisements,
    BleBondState bondState = BleBondState.bonded,
    bool bluetoothOn = true,
  }) async {
    final advert = device();
    await dao.saveBridge(
      SavedBridge(
        id: advert.id,
        name: advert.name,
        lastSeenMs: _nowMs,
        generation: 1,
        cursorAfter: 10,
      ),
    );
    await dao.insertSamples(<StoredSample>[
      StoredSample(
        bridgeId: advert.id,
        generation: 1,
        seq: 10,
        unixS: (_nowMs ~/ 1000) - 120,
        recordedMs: _nowMs - 120000,
        timeEstimated: 0,
        tempsF10: const <int?>[700, 710, 720, 730],
        flags: 0x1F,
      ),
    ]);
    await client.dispose();
    client = FakeBleClient(
      server: bridge,
      advertisements: advertisements ?? <BleDevice>[advert],
      initialBondState: bondState,
      bluetoothOn: bluetoothOn,
      connectDelay: Duration.zero,
      bondDelay: Duration.zero,
      scanInterval: Duration.zero,
    );
  }

  BridgeController controller() =>
      BridgeController(bleClient: client, sampleDao: dao, content: const EmptyBridgeContent());

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition not reached in 5 s');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('a first install with no saved Bridge starts Setup, not Live', () async {
    await client.dispose();
    client = FakeBleClient(
      server: bridge,
      advertisements: <BleDevice>[device()],
      connectDelay: Duration.zero,
      scanInterval: Duration.zero,
    );
    final app = controller();

    await app.prepareLaunch(scanWindow: _scanWindow);

    expect(app.hasSavedBridge, isFalse);
    expect(app.phase, ConnectionPhase.setup);
    expect(app.savedBridge, isNull);
    app.dispose();
  });

  test('a saved Bridge is found by BLE identity and connects without a new '
      'passkey prompt', () async {
    await seedSavedBridge();
    final app = controller();
    await app.prepareLaunch(scanWindow: _scanWindow);

    expect(app.phase, ConnectionPhase.offline);
    expect(app.hasSavedBridge, isTrue);
    expect(app.lookingForBridge, isTrue);

    await app.connectSavedBridge();

    expect(app.phase, ConnectionPhase.live);
    expect(app.lookingForBridge, isFalse);
    expect(
      client.operations.where((entry) => entry == 'bond'),
      isEmpty,
      reason: 'a valid stored bond must not prompt on launch',
    );
    final saved = await dao.savedBridge();
    expect(saved!.id, device().id);
    expect(saved.lastSeenMs, greaterThanOrEqualTo(_nowMs));
    await app.link?.dispose();
    app.dispose();
  });

  test('an unrelated advertisement is never auto-connected', () async {
    await seedSavedBridge(
      advertisements: <BleDevice>[
        bridge.advertisement(id: 'other-id', name: 'SmokeX4-FFFF'),
      ],
    );
    final app = controller();
    await app.prepareLaunch(scanWindow: _scanWindow);

    await app.connectSavedBridge();

    expect(app.phase, ConnectionPhase.offline);
    expect(app.lookingForBridge, isTrue);
    expect(client.operations.where((entry) => entry.startsWith('connect:')), isEmpty);
    app.dispose();
  });

  test('a saved Bridge absent after the bounded scan leaves Live with the '
      'archive and a manual Connect action', () async {
    await seedSavedBridge(
      advertisements: <BleDevice>[
        bridge.advertisement(id: 'other-id', name: 'SmokeX4-FFFF'),
      ],
    );
    final app = controller();
    await app.prepareLaunch(scanWindow: _scanWindow);

    await app.connectSavedBridge();

    expect(app.phase, ConnectionPhase.offline);
    expect(app.lookingForBridge, isTrue);
    expect(app.hasSavedBridge, isTrue);
    expect(app.liveProbeTemps, <double?>[70, 71, 72, 73]);
    expect(app.offlineCache, isTrue);
    expect(app.connectionTitle, 'Looking for the Bridge…');
    expect(app.bridgeConnectedLabel, isNot(startsWith('Bridge connected')));
    app.dispose();
  });

  testWidgets('the absent-Bridge launch renders Live with Connect, not Setup', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedSavedBridge(
        advertisements: <BleDevice>[
          bridge.advertisement(id: 'other-id', name: 'SmokeX4-FFFF'),
        ],
      );
    });
    final app = controller();
    await tester.runAsync(() async {
      await app.prepareLaunch(scanWindow: _scanWindow);
      await app.connectSavedBridge();
    });

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SmokeBridgeApp(controller: app));
    await tester.pump();

    expect(find.byType(SetupScreen), findsNothing);
    expect(find.byKey(const Key('live.lookingForBridge')), findsOneWidget);
    expect(
      find.byKey(const Key('live.lookingForBridge.connect')),
      findsOneWidget,
    );
    expect(find.text('Looking for the Bridge…'), findsWidgets);
    app.dispose();
  });

  test('Bluetooth off at launch is the named BLOCKED state, not Setup', () async {
    await seedSavedBridge(bluetoothOn: false);
    final app = controller();
    await app.prepareLaunch(scanWindow: _scanWindow);

    await app.connectSavedBridge();

    expect(app.phase, ConnectionPhase.blocked);
    expect(app.blockReason, BlockReason.bluetoothOff);
    expect(app.connectionTitle, 'Bluetooth is off');
    expect(app.hasSavedBridge, isTrue);
    app.dispose();
  });

  testWidgets('the blocked launch offers a system action', (tester) async {
    await tester.runAsync(() => seedSavedBridge(bluetoothOn: false));
    final app = controller();
    await tester.runAsync(() async {
      await app.prepareLaunch(scanWindow: _scanWindow);
      await app.connectSavedBridge();
    });

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SmokeBridgeApp(controller: app));
    await tester.pump();

    expect(find.byType(SetupScreen), findsNothing);
    expect(find.byKey(const Key('live.blocked')), findsOneWidget);
    expect(find.byKey(const Key('live.blocked.settings')), findsOneWidget);
    app.dispose();
  });

  test('a process kill and relaunch loads the saved Bridge and last-known '
      'archive from the same file', () async {
    final path = '${Directory.systemTemp.path}/smoke_bridge_launch_test.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    final firstDb = await AppDatabase.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    final firstDao = SqfliteSampleDao(firstDb);
    final advert = device();
    await firstDao.saveBridge(
      SavedBridge(id: advert.id, name: advert.name, lastSeenMs: _nowMs),
    );
    await firstDao.insertSamples(<StoredSample>[
      StoredSample(
        bridgeId: advert.id,
        generation: 1,
        seq: 7,
        unixS: (_nowMs ~/ 1000) - 60,
        recordedMs: _nowMs - 60000,
        timeEstimated: 0,
        tempsF10: const <int?>[810, 820, 830, 840],
        flags: 0x1F,
      ),
    ]);
    await firstDao.close();

    final reopened = await AppDatabase.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    final reopenedDao = SqfliteSampleDao(reopened);
    await client.dispose();
    client = FakeBleClient(
      server: bridge,
      advertisements: <BleDevice>[advert],
      initialBondState: BleBondState.bonded,
      connectDelay: Duration.zero,
      bondDelay: Duration.zero,
      scanInterval: Duration.zero,
    );
    final app = BridgeController(
      bleClient: client,
      sampleDao: reopenedDao,
      content: const EmptyBridgeContent(),
    );

    await app.initialize();
    await app.prepareLaunch(scanWindow: _scanWindow);

    expect(app.hasSavedBridge, isTrue);
    expect(app.phase, isNot(ConnectionPhase.setup));
    expect(app.liveProbeTemps, <double?>[81, 82, 83, 84]);
    expect(app.offlineCache, isTrue);
    expect(app.hasSavedData, isTrue);
    app.dispose();
    await reopenedDao.close();
    if (file.existsSync()) file.deleteSync();
  });

  test('forget and factory reset clear the saved identity but keep orphaned '
      'history', () async {
    await seedSavedBridge();
    var app = controller();
    await app.prepareLaunch(scanWindow: _scanWindow);

    app.forgetPhone();
    await waitFor(() => app.phase == ConnectionPhase.setup);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await dao.savedBridge(), isNull);
    expect(await dao.countSamples(), 1);
    expect(app.hasSavedData, isTrue);

    await dao.saveBridge(
      SavedBridge(id: device().id, name: device().name, lastSeenMs: _nowMs),
    );
    await app.prepareLaunch(scanWindow: _scanWindow);

    app.factoryReset();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await dao.savedBridge(), isNull);
    expect(await dao.countSamples(), 1);
    app.dispose();
  });

  test('turning phone Bluetooth off on Live leaves Connected and shows '
      'BLOCKED; turning it on reconnects', () async {
    await seedSavedBridge();
    final app = controller();
    await app.prepareLaunch(scanWindow: _scanWindow);
    await app.connectSavedBridge();
    expect(app.phase, ConnectionPhase.live);

    await client.setBluetoothOn(false);
    await waitFor(() => app.phase == ConnectionPhase.blocked);

    expect(app.blockReason, BlockReason.bluetoothOff);
    expect(app.bridgeConnectedLabel, isNot(startsWith('Bridge connected')));
    expect(app.effectiveHealth, ProbeHealth.frozen);
    expect(app.connectionTitle, 'Bluetooth is off');

    await client.setBluetoothOn(true);
    await waitFor(() => app.phase == ConnectionPhase.live);

    expect(app.blockReason, BlockReason.none);
    expect(app.bridgeConnectedLabel, startsWith('Bridge connected'));
    await app.link?.dispose();
    app.dispose();
  });
}
