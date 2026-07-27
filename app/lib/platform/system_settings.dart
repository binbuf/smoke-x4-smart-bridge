/// A24.2 — the OS-settings deep-links the setup preflight needs (design 13
/// §13.2.0, 14 §14.7.1).
///
/// WHY a channel of our own: the preflight screens offer honest next steps —
/// "Open Bluetooth settings", "Open app settings", "Open location settings",
/// "Open notification settings" (§13.2.0 truth table) — and each is a
/// system-`Intent` with no Flutter-plugin equivalent we already depend on. The
/// screens take these as [SetupExternals] callbacks; this wrapper is what a
/// composition root hands them on a real device.
///
/// Mirrors `network_binder.dart`'s shape (a thin [MethodChannel] over Kotlin in
/// `MainActivity.kt`), and lives on a SEPARATE channel name so it never
/// disturbs `smokebridge/network_binder`. Every deep-link is best-effort: a
/// device with no matching settings screen (or a non-Android host in a test)
/// must not crash setup, so every call swallows the platform miss.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opens OS settings screens and reports the Android API level, over the
/// `smokebridge/system_settings` [MethodChannel]. Deep-links never throw; the
/// worst case is that nothing opens.
class SystemSettings {
  SystemSettings({@visibleForTesting MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('smokebridge/system_settings');

  final MethodChannel _channel;

  /// The system Bluetooth settings (`ACTION_BLUETOOTH_SETTINGS`).
  Future<void> openBluetoothSettings() => _open('openBluetoothSettings');

  /// This app's details page (`ACTION_APPLICATION_DETAILS_SETTINGS`) — the only
  /// route back from a permanently-denied permission (§13.2.0).
  Future<void> openAppSettings() => _open('openAppSettings');

  /// The system Wi-Fi settings (`ACTION_WIFI_SETTINGS`).
  Future<void> openWifiSettings() => _open('openWifiSettings');

  /// The location-services toggle (`ACTION_LOCATION_SOURCE_SETTINGS`) — the fix
  /// for §13.2.0 check 1 on Android ≤ 32.
  Future<void> openLocationSettings() => _open('openLocationSettings');

  /// This app's notification settings (`ACTION_APP_NOTIFICATION_SETTINGS`).
  Future<void> openNotificationSettings() => _open('openNotificationSettings');

  /// The device's `Build.VERSION.SDK_INT`, or null off Android (iOS / desktop /
  /// test). The permission and location-services gates read this to decide
  /// which legacy legs apply (05 §5.8.3).
  Future<int?> androidSdkInt() async {
    try {
      return await _channel.invokeMethod<int>('androidSdkInt');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _open(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException {
      // A device with no such settings screen: the button did its best. The
      // machine-backed secondary ("I turned it on") keeps a live next step.
    } on MissingPluginException {
      // Not Android, or under `flutter test` with no channel — a no-op.
    }
  }
}
