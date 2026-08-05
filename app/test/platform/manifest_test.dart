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
      // A13.5 (M5). This list is exact on purpose: it is also what stops
      // a dependency from quietly adding a location prompt, and that only
      // works if it is maintained deliberately.
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      // newapp §G.4 — the delivery-hardening rows.
      'android.permission.USE_FULL_SCREEN_INTENT',
      'android.permission.USE_EXACT_ALARM',
      'android.permission.SCHEDULE_EXACT_ALARM',
      'android.permission.WAKE_LOCK',
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

  test('A13.5 — the foreground-service rows, with the TYPE Android 14 '
      'requires', () {
    // M4 pinned their ABSENCE. M5 is where they arrive, and the type is
    // the load-bearing half: omitting FOREGROUND_SERVICE_CONNECTED_DEVICE
    // is a crash on Android 14 rather than a warning (09 §9.6).
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE"'));
    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE'),
    );
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(
      manifest,
      contains('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'),
    );
  });

  group('newapp §G.4 — what actually wakes someone at 3 a.m.', () {
    test('the full-screen intent is declared', () {
      // Without it a critical alarm is a notification found at breakfast,
      // which is the failure the whole product exists to prevent. This app
      // qualifies for it as an ALARM app (Play Console declaration required
      // since 31 May 2024; default grant narrowed on 22 January 2025).
      expect(manifest, contains('android.permission.USE_FULL_SCREEN_INTENT'));
    });

    test('exact alarms are declared so time rules fire in Doze', () {
      expect(manifest, contains('android.permission.USE_EXACT_ALARM'));
      expect(
        RegExp(
          r'SCHEDULE_EXACT_ALARM"\s+android:maxSdkVersion="32"',
        ).hasMatch(manifest),
        isTrue,
        reason: 'the pre-33 fallback only, since USE_EXACT_ALARM covers 33+',
      );
    });

    test('the foreground service is declared, and is connectedDevice', () {
      // `flutter_foreground_task` does not declare this service itself, so
      // without this block the Dart-side service type has nothing to bind to.
      expect(
        manifest,
        contains(
          'com.pravera.flutter_foreground_task.service.ForegroundService',
        ),
        reason: 'the plugin does not declare its own service',
      );
      expect(
        manifest,
        contains('android:foregroundServiceType="connectedDevice"'),
      );
    });

    test('the service is NOT dataSync — that cap kills a 14-hour cook', () {
      // Android 15: dataSync and mediaProcessing foreground services get a
      // total of 6 hours per 24, then the system calls Service.onTimeout().
      // Six hours is a third of a brisket, and the phone would report
      // nothing wrong.
      // The ATTRIBUTE, not the file: the comment above the service block
      // names the capped types precisely so nobody reintroduces them, and a
      // naive substring search would fail on that explanation.
      final types = RegExp('android:foregroundServiceType="([^"]+)"')
          .allMatches(manifest)
          .map((m) => m.group(1))
          .toList();
      expect(types, ['connectedDevice']);
      expect(
        manifest,
        isNot(contains('FOREGROUND_SERVICE_DATA_SYNC')),
        reason:
            'declaring the permission is how the type creeps back in during '
            'a dependency bump',
      );
    });
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
