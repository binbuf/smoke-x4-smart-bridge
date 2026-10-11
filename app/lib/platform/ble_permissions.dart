/// The Android runtime-permission seam.
///
/// BLE scanning and connecting are runtime-gated from Android 6 (location) and
/// Android 12 (the Nearby Devices pair). `flutter_blue_plus` deliberately does
/// not request them, so the app must. This wraps the one platform channel that
/// does, and the SDK-dependent list of names lives in
/// [androidBlePermissions] (pure Dart, host-tested) rather than in Kotlin.
///
/// On any non-Android host the request is a no-op: the app is Android-first and
/// desktop/test runs have no radio to gate.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../data/ble/bridge_transport.dart';

const _channel = MethodChannel('smokebridge/platform');

/// The outcome of a runtime-permission request.
class BlePermissionResult {
  const BlePermissionResult({
    required this.granted,
    required this.permanentlyDenied,
  });

  const BlePermissionResult.granted()
    : granted = true,
      permanentlyDenied = false;

  final bool granted;

  /// A denial the OS will not re-prompt for — only the app's settings page can
  /// change it, so the UI must send the user there instead of asking again.
  final bool permanentlyDenied;
}

/// Requests the BLE permissions this Android version needs, returning whether
/// the app may now scan. Never throws for a denial; a platform failure that
/// cannot even answer is treated as "not granted", never as success.
Future<BlePermissionResult> ensureBlePermissions() async {
  if (!Platform.isAndroid) {
    return const BlePermissionResult.granted();
  }
  try {
    final sdk = await _channel.invokeMethod<int>('androidSdkInt') ?? 31;
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'requestPermissions',
      {'permissions': androidBlePermissions(sdk)},
    );
    if (result == null) {
      return const BlePermissionResult(
        granted: false,
        permanentlyDenied: false,
      );
    }
    return BlePermissionResult(
      granted: result['granted'] == true,
      permanentlyDenied: result['permanentlyDenied'] == true,
    );
  } on PlatformException {
    return const BlePermissionResult(granted: false, permanentlyDenied: false);
  } on MissingPluginException {
    // A build with no Android half (or a test host) has nothing to gate; the
    // scan itself will be the honest failure if there is one.
    return const BlePermissionResult.granted();
  }
}
