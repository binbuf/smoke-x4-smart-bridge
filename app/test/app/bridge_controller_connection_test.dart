/// The connection lifecycle driven end-to-end by a fake peripheral: the cook
/// clock is declared to the bridge (there is no read-back) and re-declared on
/// reconnect, and the link signal is read. No radio.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/ble/ble_transport.dart';
import 'package:smoke_bridge/data/ble/bridge_transport.dart';
import 'package:smoke_bridge/data/local/app_database.dart';
import 'package:smoke_bridge/data/local/drift_sample_cache.dart';

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
}
