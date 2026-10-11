import 'package:smoke_bridge/data/ble/bridge_transport.dart';
import 'package:test/test.dart';

void main() {
  group('androidBlePermissions', () {
    test('Android 12+ uses the Nearby Devices pair, never location', () {
      final perms = androidBlePermissions(31);
      expect(perms, ['BLUETOOTH_SCAN', 'BLUETOOTH_CONNECT']);
      expect(perms, isNot(contains('ACCESS_FINE_LOCATION')));
    });

    test('older Android still needs fine location to scan', () {
      expect(androidBlePermissions(30), ['ACCESS_FINE_LOCATION']);
      expect(androidBlePermissions(29), ['ACCESS_FINE_LOCATION']);
    });
  });

  group('BridgeConnectionException', () {
    test('carries the actionable problem, not just a string', () {
      const e = BridgeConnectionException(
        ConnectionProblem.bluetoothOff,
        'Bluetooth is off.',
      );
      expect(e.problem, ConnectionProblem.bluetoothOff);
      expect(e.message, 'Bluetooth is off.');
    });
  });
}
