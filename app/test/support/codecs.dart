/// Test-support view of the generated protocol codec.
///
/// `app/lib/` cannot import files outside the package root, and T02 owns the
/// generated output at `protocol/gen/`. Tests are allowed to reach it, so this
/// is the one test-side bridge to the single generated source. Do not copy
/// bytes or offsets anywhere else in the app: the fake bridge and tests decode
/// with these classes, so a protocol change breaks the app tests too.
library;

import '../../../protocol/gen/records.dart';

export '../../../protocol/gen/records.dart';

/// Contract metadata for [name] (`info`, `live`, `control`, etc.).
BleCharacteristic bleCharacteristicByName(String name) {
  for (final characteristic in bleCharacteristics) {
    if (characteristic.name == name) return characteristic;
  }
  throw ArgumentError.value(name, 'name', 'unknown BLE characteristic');
}

/// Contract metadata for [uuid], or `null` when it is not in the contract.
BleCharacteristic? bleCharacteristicByUuid(String uuid) {
  final lower = uuid.toLowerCase();
  for (final characteristic in bleCharacteristics) {
    if (characteristic.uuid.toLowerCase() == lower) return characteristic;
  }
  return null;
}

/// Shortcut for the characteristic UUID used by a named slot.
String bleUuid(String name) => bleCharacteristicByName(name).uuid;
