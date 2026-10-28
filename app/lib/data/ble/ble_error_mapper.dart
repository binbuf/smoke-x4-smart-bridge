import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_client.dart';

/// Which client operation produced a platform failure. The operation matters
/// because the same Android code means different things while bonding.
enum BleOperation {
  permission,
  scan,
  connect,
  disconnect,
  bond,
  removeBond,
  mtu,
  read,
  write,
  subscribe,
}

/// Maps every platform failure to a typed [BleException] carrying a [BleFailure].
///
/// The raw plugin description is deliberately not copied into [BleException]:
/// screens render the named [BleAppState] and approved copy. Callers may record
/// the raw error in [BleDiagnostics] at debug level.
BleException mapBlePlatformError(
  Object error, {
  required BleOperation operation,
}) {
  if (error is BleException) return error;

  final fallback = _fallbackFailure(operation);

  if (error is FlutterBluePlusException) {
    final function = error.function.toLowerCase();
    final code = error.code;

    if (function.contains('createbond') || function.contains('pair')) {
      if (code == FbpErrorCode.timeout.index) {
        return const BleException(BleFailure.promptTimeout, 'bond timed out');
      }
      return const BleException(BleFailure.wrongPasskey, 'bond was rejected');
    }
    if (function.contains('removebond')) {
      if (code == FbpErrorCode.timeout.index) {
        return const BleException(BleFailure.timeout, 'remove bond timed out');
      }
      return const BleException(BleFailure.staleBond, 'remove bond failed');
    }

    if (code == FbpErrorCode.adapterIsOff.index ||
        (error.platform == ErrorPlatform.fbp &&
            error.function.toLowerCase().contains('adapter'))) {
      return const BleException(BleFailure.bluetoothOff, 'adapter is off');
    }
    if (code == FbpErrorCode.androidOnly.index) {
      return const BleException(
        BleFailure.unsupportedPhone,
        'operation unsupported on this platform',
      );
    }
    if (code == FbpErrorCode.userRejected.index) {
      return const BleException(
        BleFailure.permissionDenied,
        'permission rejected',
      );
    }
    if (code == FbpErrorCode.timeout.index) {
      if (operation == BleOperation.bond) {
        return const BleException(BleFailure.promptTimeout, 'bond timed out');
      }
      return const BleException(BleFailure.timeout, 'operation timed out');
    }

    // Native Android/iOS GATT statuses share the integer space with FBP's own
    // small error codes (8 is both characteristicNotFound and a link timeout).
    // The platform marker disambiguates them.
    if (error.platform != ErrorPlatform.fbp) {
      final gatt = _fromGattStatus(code, operation);
      if (gatt != null) return gatt;
    }

    if (code == FbpErrorCode.deviceIsDisconnected.index) {
      return const BleException(BleFailure.notConnected, 'device disconnected');
    }
    if (code == FbpErrorCode.serviceNotFound.index ||
        code == FbpErrorCode.characteristicNotFound.index) {
      return const BleException(
        BleFailure.unknownCharacteristic,
        'GATT object is missing',
      );
    }
    if (code == FbpErrorCode.connectionCanceled.index) {
      return const BleException(
        BleFailure.connectionFailed,
        'connection was cancelled',
      );
    }

    final gatt = _fromGattStatus(code, operation);
    if (gatt != null) return gatt;

    return BleException(fallback, 'platform operation failed');
  }

  if (error is TimeoutException) {
    if (operation == BleOperation.bond) {
      return const BleException(BleFailure.promptTimeout, 'bond timed out');
    }
    return const BleException(BleFailure.timeout, 'operation timed out');
  }

  if (error is PlatformException) {
    switch (error.code.toLowerCase()) {
      case 'bluetooth_off':
      case 'bluetooth_disabled':
      case 'adapterisoff':
        return const BleException(BleFailure.bluetoothOff, 'adapter is off');
      case 'permission_denied':
      case 'permissiondenied':
      case 'missing_permission':
        return const BleException(
          BleFailure.permissionDenied,
          'permission missing',
        );
      case 'not_supported':
      case 'unsupported':
      case 'androidonly':
        return const BleException(
          BleFailure.unsupportedPhone,
          'operation unsupported on this phone',
        );
      case 'timeout':
        return const BleException(BleFailure.timeout, 'operation timed out');
    }
    return BleException(fallback, 'platform channel failed');
  }

  if (error is ArgumentError ||
      error is RangeError ||
      error is FormatException) {
    return const BleException(BleFailure.invalidValue, 'invalid value');
  }

  return BleException(fallback, 'unexpected platform failure');
}

BleException? _fromGattStatus(int? code, BleOperation operation) {
  if (code == null) return null;
  // ATT application errors used by `config` (05 §5.9): invalid `0x81`,
  // unsupported `0x82`, storage `0x87`. 133 is deliberately left as the common
  // Android GATT error; the config contract does not use `failed` on the wire.
  if (code == 0x81 || code == 0x82 || code == 0x87) {
    return BleException(
      BleFailure.configRefused,
      'attribute refused with status 0x${code.toRadixString(16)}',
      code,
    );
  }
  switch (code) {
    // ATT insufficient authentication / encryption: bond or re-pair, not a
    // generic GATT error.
    case 5:
    case 15:
      return const BleException(BleFailure.notBonded, 'link needs bonding');
    // ATT read/write not permitted usually means the same security gate.
    case 2:
    case 3:
      return const BleException(
        BleFailure.notBonded,
        'attribute needs bonding',
      );
    case 8:
      return const BleException(BleFailure.timeout, 'link supervision timeout');
    case 133:
      if (operation == BleOperation.connect) {
        return const BleException(
          BleFailure.connectionFailed,
          'GATT connection failed',
        );
      }
      return const BleException(BleFailure.gattError, 'GATT error');
    case 19: // remote device terminated the connection.
    case 22: // local host terminated the connection.
      return const BleException(BleFailure.notConnected, 'link terminated');
  }
  return null;
}

BleFailure _fallbackFailure(BleOperation operation) {
  switch (operation) {
    case BleOperation.permission:
      return BleFailure.permissionDenied;
    case BleOperation.scan:
      return BleFailure.scanFailed;
    case BleOperation.connect:
    case BleOperation.disconnect:
      return BleFailure.connectionFailed;
    case BleOperation.bond:
      return BleFailure.wrongPasskey;
    case BleOperation.removeBond:
      return BleFailure.staleBond;
    case BleOperation.mtu:
    case BleOperation.read:
    case BleOperation.write:
    case BleOperation.subscribe:
      return BleFailure.gattError;
  }
}
