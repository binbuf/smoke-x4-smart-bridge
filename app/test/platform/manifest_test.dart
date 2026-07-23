/// A14.3: the manifest and cleartext config as assertions — the exact
/// permission set (a future dependency must not quietly add a location
/// prompt) and the scoped-cleartext rule (never a global flag).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../data/records_parity_test.dart' show repoRoot;

void main() {
  final manifest = File(
    '${repoRoot()}/app/android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final nsc = File(
    '${repoRoot()}/app/android/app/src/main/res/xml/network_security_config.xml',
  ).readAsStringSync();

  test('the exact §5.8.3 network + BLE permission set, nothing extra', () {
    // A14.3 pinned the network rows; A6.6 adds the BLE ones in the same
    // task that lands them, which is deliberate: this list is also what
    // stops a dependency from quietly adding a location prompt.
    const expected = [
      'android.permission.INTERNET',
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.ACCESS_WIFI_STATE',
      'android.permission.CHANGE_WIFI_STATE',
      'android.permission.CHANGE_WIFI_MULTICAST_STATE',
      'android.permission.NEARBY_WIFI_DEVICES',
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.BLUETOOTH_SCAN',
      'android.permission.BLUETOOTH_CONNECT',
      'android.permission.BLUETOOTH',
      'android.permission.BLUETOOTH_ADMIN',
    ];
    final found = RegExp(
      'android:name="(android\\.permission\\.[^"]+)"',
    ).allMatches(manifest).map((m) => m.group(1)).toList();
    expect(found, expected);
  });

  test('both scan permissions declare neverForLocation', () {
    // Load-bearing on BOTH: either one missing it re-introduces the
    // location prompt this whole matrix exists to avoid (§5.8.3).
    for (final p in ['NEARBY_WIFI_DEVICES', 'BLUETOOTH_SCAN']) {
      expect(
        RegExp(
          '$p"\\s+android:usesPermissionFlags="neverForLocation"',
        ).hasMatch(manifest),
        isTrue,
        reason: '$p must declare neverForLocation',
      );
    }
    expect(
      'android:usesPermissionFlags="neverForLocation"'.allMatches(manifest),
      hasLength(2),
    );
  });

  test('ACCESS_FINE_LOCATION is gated to API <= 32', () {
    final m = RegExp('ACCESS_FINE_LOCATION"\\s+android:maxSdkVersion="32"');
    expect(m.hasMatch(manifest), isTrue);
  });

  test('the legacy BLE pair is gated to API <= 30', () {
    for (final p in ['BLUETOOTH', 'BLUETOOTH_ADMIN']) {
      expect(
        RegExp(
          'android\\.permission\\.$p"\\s+android:maxSdkVersion="30"',
        ).hasMatch(manifest),
        isTrue,
        reason: '$p must not be requested on modern Android',
      );
    }
  });

  test('the foreground-service rows are still absent (they are A13, M5)', () {
    expect(manifest, isNot(contains('FOREGROUND_SERVICE')));
    expect(manifest, isNot(contains('POST_NOTIFICATIONS')));
  });

  test('cleartext is an NSC decision, never the global manifest flag', () {
    expect(manifest, isNot(contains('usesCleartextTraffic')));
    expect(
      manifest,
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
    expect(nsc, contains('smokebridge.local'));
    expect(nsc, contains('192.168.4.1'));
  });
}
