import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/bootstrap.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';
import 'package:smoke_bridge/data/repository.dart';

import 'support/codecs.dart';
import 'support/fake_ble_client.dart';
import 'support/fake_bridge.dart';

String _uuid(String name) => bleCharacteristicByName(name).uuid;

void main() {
  late FakeBridge bridge;
  late FakeBleClient client;

  setUp(() {
    bridge = FakeBridge();
    client = FakeBleClient(
      server: bridge,
      advertisements: <BleDevice>[bridge.advertisement()],
      expectedPasskey: '418302',
    );
  });

  tearDown(() async {
    await client.dispose();
    await bridge.dispose();
  });

  test(
    'scan emits scripted advertisements with a generated status blob',
    () async {
      final devices = await client.scan().toList();

      expect(devices, hasLength(1));
      final device = devices.single;
      expect(device.name, 'SmokeX4-A4F2');
      expect(device.isSmokeBridge, isTrue);
      expect(device.serviceUuids, contains(bleServiceUuid));

      final data = device.manufacturerData!;
      expect(data.length, 2 + AdvStatus.size);
      final companyId = ByteData.sublistView(data).getUint16(0, Endian.little);
      expect(companyId, bleCompanyId);
      final status = AdvStatus.decode(data.sublist(2));
      expect(status.batteryPct, 87);
      expect(status.pitTempF10, 800);
      expect(status.ageS, 12);
    },
  );

  test('connect, bond, MTU and reads all use generated codecs', () async {
    final device = (await client.scan().toList()).single;

    await expectLater(
      client.read(_uuid('live')),
      throwsA(
        isA<BleException>().having(
          (error) => error.failure,
          'failure',
          BleFailure.notConnected,
        ),
      ),
    );

    await client.connect(device);
    expect(client.connectionState, BleConnectionState.connected);
    expect(client.negotiatedMtu, bleMtuDefault);

    // info is open, so it is readable before bonding.
    final info = Info.decode(await client.read(_uuid('info')));
    expect(info.protoMajor, protocolMajor);
    expect(info.deviceId, 'A4F2');
    expect(info.model, 'heltec3');
    expect(info.billowsControl, isFalse);
    expect(info.config, isTrue);

    await expectLater(
      client.read(_uuid('live')),
      throwsA(
        isA<BleException>().having(
          (error) => error.failure,
          'failure',
          BleFailure.notBonded,
        ),
      ),
    );

    expect(await client.bond(passkey: '000000'), BleBondState.wrongPasskey);
    expect(await client.bond(passkey: '418 302'), BleBondState.bonded);
    expect(client.bondState, BleBondState.bonded);

    expect(await client.requestMtu(bleMtuRequest), bleMtuRequest);
    expect(client.negotiatedMtu, bleMtuRequest);

    final live = Live.decode(await client.read(_uuid('live')));
    expect(live.tempOrNull(0), 2250);
    expect(live.tempOrNull(2), isNull);
    expect(live.batteryPct, 87);
    expect(live.billowsTargetF10, 2250);

    final config = Config.decode(await client.read(_uuid('config')));
    expect(config.deviceName, 'Backyard Bridge');
    expect(config.units, 1);
    expect(config.billowsMode, 0);

    final stats = Stats.decode(await client.read(_uuid('stats')));
    expect(stats.recordsStored, 3);
    expect(stats.recordsCapacity, recordCapacity);
    expect(stats.minSeq, 100);
    expect(stats.maxSeq, 102);
    expect(stats.generation, 0xA1B2C3D4);
  });

  test(
    'live notifications are decoded and config writes are read back',
    () async {
      await client.connect((await client.scan().toList()).single);
      await client.bond(passkey: '418302');

      await client.setNotify(_uuid('live'), enabled: true);
      final received = <Uint8List>[];
      final subscription = client
          .notifications(_uuid('live'))
          .listen(received.add);

      bridge.publishLive(
        seq: 2000,
        tempsF10: const <int>[1800, 1600, tempDetached, 900],
        batteryPct: 64,
        rssiLora: -82,
        ageS: 4,
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      final live = Live.decode(received.single);
      expect(live.seq, 2000);
      expect(live.tempOrNull(0), 1800);
      expect(live.tempOrNull(2), isNull);
      expect(live.batteryPct, 64);
      expect(live.rssiLora, -82);
      expect(live.ageS, 4);

      await client.write(
        _uuid('config'),
        Config(
          units: 0,
          displayTimeoutS: 30,
          deviceName: 'Patio Bridge',
        ).encode(),
      );
      final config = Config.decode(await client.read(_uuid('config')));
      expect(config.deviceName, 'Patio Bridge');
      expect(config.units, 0);
      expect(config.displayTimeoutS, 30);
      expect(config.billowsMode, 0);

      await expectLater(
        client.write(_uuid('config'), Config(billowsMode: 1).encode()),
        throwsA(
          isA<BleException>()
              .having(
                (error) => error.failure,
                'failure',
                BleFailure.configRefused,
              )
              .having((error) => error.attCode, 'attCode', 0x82),
        ),
      );

      await subscription.cancel();
    },
  );

  test('sync_ctrl streams contiguous framed START/RECORDS/END', () async {
    await client.connect((await client.scan().toList()).single);
    await client.bond(passkey: '418302');
    await client.setNotify(_uuid('sync_data'), enabled: true);

    final chunks = <Uint8List>[];
    final finished = Completer<void>();
    final subscription = client.notifications(_uuid('sync_data')).listen((
      chunk,
    ) {
      chunks.add(chunk);
      if (SyncFrame.decode(chunk).end && !finished.isCompleted) {
        finished.complete();
      }
    });

    await client.write(
      _uuid('sync_ctrl'),
      SyncCtrl(
        cmd: SyncCmd.read.wire,
        direction: SyncDirection.forward.wire,
        cursorSeq: 0,
        maxRecords: 64,
      ).encode(),
    );
    await finished.future.timeout(const Duration(seconds: 2));

    expect(chunks.length, greaterThan(1), reason: 'default MTU splits frames');
    final stream = BytesBuilder();
    var nextFrameSeq = 0;
    for (final chunk in chunks) {
      final header = SyncFrame.decode(chunk);
      expect(header.frameSeq, nextFrameSeq);
      expect(header.len, chunk.length - SyncFrame.size);
      nextFrameSeq = (nextFrameSeq + 1) & 0xFF;
      stream.add(Uint8List.sublistView(chunk, SyncFrame.size));
    }
    expect(SyncFrame.decode(chunks.first).start, isTrue);
    expect(SyncFrame.decode(chunks.last).end, isTrue);

    final bytes = stream.toBytes();
    final start = SyncStart.decode(bytes);
    expect(start.generation, 0xA1B2C3D4);
    expect(start.count, 3);
    expect(start.startSeq, 100);
    expect(start.recordSize, recordSize);
    expect(start.status, SyncStatus.ok.wire);

    final records = <SampleRec>[
      for (var index = 0; index < start.count; index++)
        SampleRec.decode(bytes, SyncStart.size + index * recordSize),
    ];
    expect(records.map((record) => record.seq), <int>[100, 101, 102]);
    expect(records.every((record) => record.crcOk), isTrue);

    final end = SyncEnd.decode(
      bytes,
      SyncStart.size + start.count * recordSize,
    );
    expect(end.status, SyncStatus.ok.wire);
    expect(end.nextSeq, 103);
    expect(end.maxSeq, 102);

    await subscription.cancel();
  });

  test('disconnect drops the link and reports offline states', () async {
    final states = <BleConnectionState>[];
    final subscription = client.connectionStates.listen(states.add);

    await client.connect((await client.scan().toList()).single);
    await client.bond(passkey: '418302');
    await client.requestMtu(bleMtuRequest);
    await client.disconnect();

    expect(states, contains(BleConnectionState.connected));
    expect(states, contains(BleConnectionState.disconnecting));
    expect(client.connectedDevice, isNull);
    expect(client.negotiatedMtu, isNull);
    expect(client.bondState, BleBondState.bonded);
    await Future<void>.delayed(Duration.zero);
    expect(states.last, BleConnectionState.disconnected);
    await expectLater(
      client.read(_uuid('info')),
      throwsA(
        isA<BleException>().having(
          (error) => error.failure,
          'failure',
          BleFailure.notConnected,
        ),
      ),
    );

    await subscription.cancel();
  });

  test('scan-name filtering matches the generated local name prefix', () {
    expect(bleLocalNamePrefix, 'SmokeX4-');
    expect(
      const BleDevice(id: 'x', name: 'SmokeX4-A4F2').isSmokeBridge,
      isTrue,
    );
    expect(
      const BleDevice(id: 'x', name: 'OtherDevice').isSmokeBridge,
      isFalse,
    );
  });

  test('bootstrap accepts the injected BLE client seam', () async {
    final controller = await createBridgeController(
      repository: EmptyBridgeRepository(),
      bleClient: client,
    );

    expect(controller.bleClient, same(client));
    expect(controller.phoneRecords, 0);
    controller.dispose();
  });

  test('release lib never imports the fake BLE implementation', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final fakeImport = RegExp(
      r'''import\s+['"][^'"]*(fake_ble_client|fake_bridge|fake_gatt_server)''',
    );
    for (final file in sources) {
      expect(
        fakeImport.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} must stay out of the release graph',
      );
    }
  });
}
