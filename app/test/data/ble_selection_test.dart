/// The scan-selection rule: with several bridges advertising, the remembered
/// one must win over "whichever answered first".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/ble/ble_gatt.dart';
import 'package:smoke_bridge/data/ble/ble_gatt_fbp.dart';

void main() {
  BleAdvertisement adv(String id, {String? name, int rssi = -60}) =>
      BleAdvertisement(deviceId: id, name: name, rssi: rssi);

  test('the remembered bridge wins even when it is not first', () {
    final chosen = selectBridge([
      adv('AA:01', name: 'SmokeBridge-A4F2', rssi: -40),
      adv('AA:02', name: 'SmokeBridge-B7C1', rssi: -55),
    ], preferId: 'AA:02');
    expect(chosen?.deviceId, 'AA:02');
  });

  test('with no remembered bridge the strongest is chosen, not the first', () {
    final chosen = selectBridge([
      adv('AA:01', rssi: -80),
      adv('AA:02', rssi: -45),
    ]);
    expect(chosen?.deviceId, 'AA:02');
  });

  test('a remembered name is used when the address differs', () {
    final chosen = selectBridge([
      adv('AA:01', rssi: -40),
      adv('AA:09', name: 'SmokeBridge-A4F2', rssi: -70),
    ], preferName: 'SmokeBridge-A4F2');
    expect(chosen?.deviceId, 'AA:09');
  });

  test('a preference that is absent falls back to the strongest seen', () {
    final chosen = selectBridge([
      adv('AA:01', rssi: -70),
      adv('AA:02', rssi: -50),
    ], preferId: 'AA:99');
    expect(chosen?.deviceId, 'AA:02');
  });

  test('no advertisements selects nothing', () {
    expect(selectBridge(const []), isNull);
  });
}
