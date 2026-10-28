import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/data/ble/bridge_codecs.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';

import 'support/codecs.dart' as proto;

void main() {
  test('setup info decoder matches the generated contract', () {
    final encoded = proto.Info(
      protoMajor: proto.protocolMajor,
      protoMinor: proto.protocolMinor,
      deviceId: 'A4F2',
      fw: '0.1.0',
      model: 'heltec3',
      bondsFree: 2,
    ).encode();

    final info = BridgeInfo.decode(encoded);

    expect(info.protoMajor, proto.protocolMajor);
    expect(info.protoMinor, proto.protocolMinor);
    expect(info.deviceId, 'A4F2');
    expect(info.firmware, '0.1.0');
    expect(info.model, 'heltec3');
    expect(info.bondsFree, 2);
    expect(info.isCompatible, isTrue);
  });

  test('info uuid matches the generated characteristic', () {
    expect(
      bleInfoCharacteristicUuid,
      proto.bleCharacteristicByName('info').uuid,
    );
    expect(bridgeProtocolMajor, proto.protocolMajor);
  });

  test('advertisement decoder shows the approved scan preview', () {
    final encoded = proto.AdvStatus(
      flags: proto.liveFlagClockValid,
      pitTempF10: 2250,
      batteryPct: 87,
    ).encode();
    final bytes = Uint8List(2 + encoded.length);
    ByteData.sublistView(bytes).setUint16(0, proto.bleCompanyId, Endian.little);
    bytes.setRange(2, bytes.length, encoded);
    const device = BleDevice(id: 'fake-A4F2', name: 'SmokeX4-A4F2', rssi: -60);
    final withData = BleDevice(
      id: device.id,
      name: device.name,
      rssi: device.rssi,
      manufacturerData: bytes,
    );

    final advertisement = BridgeAdvertisement.decode(withData);
    expect(advertisement, isNotNull);
    expect(advertisement!.preview, 'P4 225°F · 87%');
    expect(scanResultDetail(withData), 'P4 225°F · 87% · Strong · -60 dBm');
    expect(scanSignalWord(-70), 'Good');
    expect(scanSignalWord(-82), 'Weak');
    expect(BridgeAdvertisement.decode(device), isNull);
  });

  test('a sentinel advertisement shows no invented probe or battery value', () {
    Uint8List withStatus(int tempF10, int battery) {
      final encoded = proto.AdvStatus(
        flags: 0,
        pitTempF10: tempF10,
        batteryPct: battery,
      ).encode();
      final bytes = Uint8List(2 + encoded.length);
      ByteData.sublistView(
        bytes,
      ).setUint16(0, proto.bleCompanyId, Endian.little);
      bytes.setRange(2, bytes.length, encoded);
      return bytes;
    }

    BleDevice row(int tempF10, int battery) => BleDevice(
      id: 'fake-A4F2',
      name: 'SmokeX4-A4F2',
      rssi: -60,
      manufacturerData: withStatus(tempF10, battery),
    );

    // A fresh/blank Bridge advertises the invalid sentinel and unknown battery.
    final blank = BridgeAdvertisement.decode(row(-32767, 255))!;
    expect(blank.hasReading, isFalse);
    expect(blank.preview, isNull);
    expect(scanResultDetail(row(-32767, 255)), 'Strong · -60 dBm');

    // A detached probe is never printed as a temperature; the battery remains
    // honest if the Bridge knows it.
    final detached = BridgeAdvertisement.decode(row(-32768, 87))!;
    expect(detached.hasReading, isFalse);
    expect(detached.preview, 'Battery 87%');
  });

  test(
    'a SmokeX4 advertisement without the contract service needs a new app',
    () {
      const legacy = BleDevice(
        id: 'fake-legacy',
        name: 'SmokeX4-LEGACY',
        serviceUuids: <String>['7f9a0000-4c5b-4b0f-9a3d-1c2e3f405162'],
      );
      const other = BleDevice(id: 'x', name: 'OtherDevice');

      expect(scannedBridgeFor(legacy)?.requiresNewerApp, isTrue);
      expect(scannedBridgeFor(other), isNull);
      expect(
        scannedBridgeFor(
          const BleDevice(
            id: 'fake-A4F2',
            name: 'SmokeX4-A4F2',
            serviceUuids: <String>[bleContractServiceUuid],
          ),
        )?.requiresNewerApp,
        isFalse,
      );
    },
  );
}
