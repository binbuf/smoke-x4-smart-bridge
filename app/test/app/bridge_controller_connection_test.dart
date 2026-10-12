/// The connection lifecycle driven end-to-end by a fake peripheral: the cook
/// clock is declared to the bridge (there is no read-back) and re-declared on
/// reconnect, and the link signal is read. No radio.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/ble/ble_gatt.dart';
import 'package:smoke_bridge/data/ble/ble_transport.dart';
import 'package:smoke_bridge/data/ble/bridge_transport.dart';
import 'package:smoke_bridge/data/dto/records.g.dart' hide ProbeRole;
import 'package:smoke_bridge/data/local/app_database.dart';
import 'package:smoke_bridge/data/local/drift_sample_cache.dart';
import 'package:smoke_bridge/domain/domain.dart';

import '../support/fake_peripheral.dart';

Future<void> _waitFor(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// How many `set_time` writes the fake saw on `device_control`.
int _setTimeWrites(FakePeripheral fake) => fake.writes
    .where((w) => w.$1 == BridgeChar.deviceControl)
    .map((w) => DeviceControl.unpack(w.$2).opEnum)
    .where((op) => op == ControlOp.setTime)
    .length;

/// How many `pair`/`unpair` writes the fake saw.
int _opWrites(FakePeripheral fake, ControlOp op) => fake.writes
    .where((w) => w.$1 == BridgeChar.deviceControl)
    .map((w) => DeviceControl.unpack(w.$2).opEnum)
    .where((o) => o == op)
    .length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DriftSampleCache cache;
  late FakePeripheral fake;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cache = DriftSampleCache(db);
    fake = FakePeripheral();
  });

  tearDown(() async {
    await db.close();
  });

  Future<BleTransport> openTransport() async {
    await fake.connect('AA:BB:CC:DD:AA:BB');
    await fake.bond();
    await fake.requestMtu(247);
    final transport = BleTransport(fake);
    await transport.start();
    return transport;
  }

  void seedPrefs({int? cookStartedMs}) {
    SharedPreferences.setMockInitialValues({
      'last_bridge_device_id': 'AA:BB:CC:DD:AA:BB',
      'cook_started_unix_ms': ?cookStartedMs,
    });
  }

  test('connect reads identity and the link signal', () async {
    seedPrefs();
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);

    expect(controller.identity?.id, 'A4F2');
    expect(controller.linkRssiDbm, -58);

    await controller.disconnect();
    controller.dispose();
  });

  test('a persisted cook is re-declared to the bridge on reconnect', () async {
    seedPrefs(cookStartedMs: DateTime.now().millisecondsSinceEpoch - 5000);
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);

    expect(controller.cookRunning, isTrue);
    expect(fake.cookClockElapsedS, inInclusiveRange(4, 8));

    await controller.disconnect();
    controller.dispose();
  });

  test('the declared age is clamped to the OLED width', () async {
    seedPrefs(
      cookStartedMs:
          DateTime.now().millisecondsSinceEpoch - (cookClockMaxS + 600) * 1000,
    );
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);

    expect(controller.cookElapsedS, cookClockMaxS);
    expect(fake.cookClockElapsedS, cookClockMaxS);

    await controller.disconnect();
    controller.dispose();
  });

  test('start/clear cook update the bridge and report an outcome', () async {
    seedPrefs();
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);

    await controller.startCook();
    expect(controller.cookRunning, isTrue);
    expect(fake.cookClockElapsedS, 0);
    expect(controller.actionMessage, 'Cook clock started');

    await controller.clearCook();
    expect(controller.cookRunning, isFalse);
    expect(fake.cookClockElapsedS, isNull);
    expect(controller.actionMessage, 'Cook clock cleared');

    await controller.disconnect();
    controller.dispose();
  });

  test('connect() while already connected opens no second link', () async {
    seedPrefs();
    var opens = 0;
    Future<BleTransport> counting() async {
      opens++;
      await fake.connect('AA:BB:CC:DD:AA:BB');
      await fake.bond();
      await fake.requestMtu(247);
      final transport = BleTransport(fake);
      await transport.start();
      return transport;
    }

    final controller = BridgeController(cache, openTransport: counting);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);
    expect(opens, 1);

    await controller.connect();
    expect(opens, 1, reason: 'already connected: no new transport');
    expect(controller.link, BridgeLink.connected);

    await controller.disconnect();
    controller.dispose();
  });

  test('a dropped link silently reconnects on its own', () async {
    seedPrefs();
    final state = FakeBridgeState();
    final fakes = <FakePeripheral>[];
    var opens = 0;
    Future<BleTransport> freshClient() async {
      opens++;
      final f = FakePeripheral(state: state);
      fakes.add(f);
      await f.connect('AA:BB:CC:DD:AA:BB');
      await f.bond();
      await f.requestMtu(247);
      final transport = BleTransport(f);
      await transport.start();
      return transport;
    }

    final controller = BridgeController(cache, openTransport: freshClient);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);
    expect(opens, 1);

    // The peer drops the link; the controller reconnects without a tap.
    fakes.last.dropLink();
    await _waitFor(
      () => controller.link == BridgeLink.connected && opens >= 2,
      timeout: const Duration(seconds: 8),
    );
    expect(opens, greaterThanOrEqualTo(2));

    await controller.disconnect();
    controller.dispose();
  });

  test('forget drops the OS pairing and the remembered address', () async {
    seedPrefs();
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);
    expect(controller.canForget, isTrue);

    await controller.forgetBridge();

    expect(fake.removeBondCalls, 1);
    expect(controller.link, BridgeLink.disconnected);
    expect(controller.canForget, isFalse);

    controller.dispose();
  });

  test('connect sets the bridge clock exactly once', () async {
    seedPrefs();
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);

    expect(_setTimeWrites(fake), 1);

    await controller.disconnect();
    controller.dispose();
  });

  test('pairSmokeX writes op pair and flips the live pairing state', () async {
    seedPrefs();
    final fake = FakePeripheral(state: FakeBridgeState(paired: false));
    Future<BleTransport> open() async {
      await fake.connect('AA:BB:CC:DD:AA:BB');
      await fake.bond();
      await fake.requestMtu(247);
      final transport = BleTransport(fake);
      await transport.start();
      return transport;
    }

    final controller = BridgeController(cache, openTransport: open);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);
    expect(controller.latestLive?.paired, isFalse);

    await controller.pairSmokeX();

    expect(_opWrites(fake, ControlOp.pair), 1);
    expect(controller.latestLive?.paired, isTrue);

    await controller.disconnect();
    controller.dispose();
  });

  test('auto-reconnect gives up after a bounded number of tries', () async {
    seedPrefs();
    var opens = 0;
    var failing = false;
    Future<BleTransport> flaky() async {
      opens++;
      if (failing) {
        throw const BridgeConnectionException(
          ConnectionProblem.notFound,
          'gone',
        );
      }
      await fake.connect('AA:BB:CC:DD:AA:BB');
      await fake.bond();
      await fake.requestMtu(247);
      final transport = BleTransport(fake);
      await transport.start();
      return transport;
    }

    final controller = BridgeController(cache, openTransport: flaky);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);
    expect(opens, 1);

    failing = true;
    fake.dropLink();
    await _waitFor(
      () => controller.reconnectExhausted,
      timeout: const Duration(seconds: 15),
    );

    expect(controller.reconnectExhausted, isTrue);
    expect(controller.link, BridgeLink.disconnected);
    expect(opens, 4, reason: 'one initial connect + three failed retries');

    controller.dispose();
  });

  test('the periodic sweep reads no data from a finished history', () async {
    seedPrefs();
    fake.state.recordCook(hours: 1, closed: true);
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);
    // The connect sweep (session list + samples) must have settled first.
    await _waitFor(() => fake.historyRequests >= 2 && !controller.syncing);

    final settled = fake.historyRequests;
    await controller.syncIncomplete();

    expect(
      fake.historyRequests,
      settled,
      reason: 'a closed, drained session is skipped without a BLE read',
    );

    await controller.disconnect();
    controller.dispose();
  });

  test('factoryResetBridge wipes the device and the phone copy', () async {
    seedPrefs();
    fake.state.recordCook(hours: 1, closed: true);
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);
    await _waitFor(() => fake.historyRequests >= 2 && !controller.syncing);
    expect(await cache.readSessions('A4F2'), isNotEmpty);

    await controller.factoryResetBridge();

    expect(_opWrites(fake, ControlOp.factoryReset), 1);
    expect(controller.link, BridgeLink.disconnected);
    expect(controller.canForget, isFalse);
    expect(await cache.readSessions('A4F2'), isEmpty);

    controller.dispose();
  });

  test('rebootBridge writes op reboot and drops the link', () async {
    seedPrefs();
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);

    await controller.rebootBridge();

    expect(_opWrites(fake, ControlOp.reboot), 1);
    expect(controller.link, BridgeLink.disconnected);

    controller.dispose();
  });

  test('powerOffBridge writes op power_off and drops the link', () async {
    seedPrefs();
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);

    await controller.powerOffBridge();

    expect(_opWrites(fake, ControlOp.powerOff), 1);
    expect(controller.link, BridgeLink.disconnected);

    controller.dispose();
  });

  test('setBatterySaver records the mode and writes the op', () async {
    seedPrefs();
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);

    await controller.setBatterySaver(BatterySaverMode.auto);

    expect(_opWrites(fake, ControlOp.setBatterySaver), 1);
    expect(controller.batterySaver, BatterySaverMode.auto);

    await controller.disconnect();
    controller.dispose();
  });

  test('setUnit mirrors the choice to the bridge OLED', () async {
    seedPrefs();
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);

    controller.setUnit(TempUnit.celsius);

    await _waitFor(() => _opWrites(fake, ControlOp.setUnits) == 1);
    expect(_opWrites(fake, ControlOp.setUnits), 1);

    await controller.disconnect();
    controller.dispose();
  });

  test('identifyBridge writes op identify', () async {
    seedPrefs();
    final controller = BridgeController(cache, openTransport: openTransport);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);

    await controller.identifyBridge();

    expect(_opWrites(fake, ControlOp.identify), 1);

    await controller.disconnect();
    controller.dispose();
  });

  test('the admin surface loads stats and config, and saves edits', () async {
    seedPrefs();
    final fake = FakePeripheral(state: FakeBridgeState(admin: true));
    Future<BleTransport> open() async {
      await fake.connect('AA:BB:CC:DD:AA:BB');
      await fake.bond();
      await fake.requestMtu(247);
      final transport = BleTransport(fake);
      await transport.start();
      return transport;
    }

    final controller = BridgeController(cache, openTransport: open);
    await controller.bootstrap();
    await _waitFor(() => controller.link == BridgeLink.connected);

    expect(controller.identity?.admin, isTrue);
    expect(controller.deviceStats?.storedSessions, 3);
    expect(controller.deviceConfig?.probes, hasLength(4));

    await controller.setProbeConfig(
      index: 0,
      name: 'Pit',
      role: ProbeRole.pit,
      targetF10: 2250,
    );
    expect(_opWrites(fake, ControlOp.setProbe), 1);
    expect(controller.deviceConfig?.probes[0].name, 'Pit');
    expect(controller.deviceConfig?.probes[0].targetF10, 2250);

    await controller.saveDevicePrefs(
      const DevicePrefs(
        displayTimeoutS: 120,
        ledEnabled: false,
        buzzerEnabled: true,
        retentionMaxSessions: 32,
        retentionMinFreePct: 5,
      ),
    );
    expect(_opWrites(fake, ControlOp.setDevicePrefs), 1);
    expect(controller.deviceConfig?.prefs.displayTimeoutS, 120);

    await controller.disconnect();
    controller.dispose();
  });
}
