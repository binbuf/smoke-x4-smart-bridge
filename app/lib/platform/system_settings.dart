/// The OS-settings deep links the connection sheet offers when the fix is not
/// something the app can do itself: turn Bluetooth on, or grant a permission
/// the user has permanently refused.
///
/// The Android half lives in `MainActivity`; this is the thin Dart wrapper.
library;

import 'package:flutter/services.dart';

const _channel = MethodChannel('smokebridge/platform');

/// Opens the phone's Bluetooth settings screen.
///
/// The recovery path for "Bluetooth is off" and for the rare stale bond the OS
/// refused to forget: the user can turn the radio on, or forget the bridge, and
/// come back.
Future<void> openBluetoothSettings() =>
    _channel.invokeMethod<void>('openBluetoothSettings');

/// Opens this app's details page, where a permanently-denied permission can be
/// re-enabled.
Future<void> openAppSettings() =>
    _channel.invokeMethod<void>('openAppSettings');
