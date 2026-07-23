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

  test('the exact §5.8.3 network permission set, nothing extra', () {
    const expected = [
      'android.permission.INTERNET',
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.ACCESS_WIFI_STATE',
      'android.permission.CHANGE_WIFI_STATE',
      'android.permission.CHANGE_WIFI_MULTICAST_STATE',
      'android.permission.NEARBY_WIFI_DEVICES',
      'android.permission.ACCESS_FINE_LOCATION',
    ];
    final found = RegExp(
      'android:name="(android\\.permission\\.[^"]+)"',
    ).allMatches(manifest).map((m) => m.group(1)).toList();
    expect(found, expected);
  });

  test('NEARBY_WIFI_DEVICES declares neverForLocation', () {
    expect(
      manifest,
      contains('android:usesPermissionFlags="neverForLocation"'),
    );
  });

  test('ACCESS_FINE_LOCATION is gated to API <= 32', () {
    final m = RegExp('ACCESS_FINE_LOCATION"\\s+android:maxSdkVersion="32"');
    expect(m.hasMatch(manifest), isTrue);
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
