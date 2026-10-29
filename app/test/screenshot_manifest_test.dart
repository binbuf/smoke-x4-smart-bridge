import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T54 screenshot review gate.
///
/// The golden generator is `tool/ui_screenshots_test.dart`; this test makes the
/// reviewed set explicit. A changed pixel, a missing shot or a new PNG without
/// a manifest entry fails here until the change is reviewed and the manifest is
/// regenerated with `dart run tool/screenshot_manifest.dart`.
void main() {
  final manifest = jsonDecode(
    File('screenshots/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('the reviewed golden set exists at 390 x 844', () {
    final actual = Directory('screenshots')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.png'))
        .map((file) => file.uri.pathSegments.last)
        .toSet();
    expect(actual, manifest.keys.toSet());

    for (final entry in manifest.entries) {
      final value = entry.value as Map<String, dynamic>;
      expect(value['width'], 390, reason: '${entry.key} width');
      expect(value['height'], 844, reason: '${entry.key} height');
    }
  });

  test('the set covers dark and light and the post-T36 states', () {
    for (final name in const [
      'live_dark.png',
      'live_light.png',
      'live_x4_warning_dark.png',
      'live_stale_dark.png',
      'live_offline_nocache_dark.png',
      'history_dark.png',
      'history_light.png',
      'settings_dark.png',
      'settings_light.png',
      'past_cook_dark.png',
      'past_cook_light.png',
      'setup_dark.png',
      'setup_light.png',
      'bridge_details_light.png',
      'confirm_factory_reset_dark.png',
      'confirm_power_off_light.png',
    ]) {
      expect(manifest.containsKey(name), isTrue, reason: name);
    }
  });

  test('no screenshot changes without the manifest being regenerated', () {
    // Every entry, not just one: the whole point of the gate is that a single
    // accepted-looking pixel change cannot hide behind an untouched test.
    for (final entry in manifest.entries) {
      final bytes = File('screenshots/${entry.key}').readAsBytesSync();
      expect(
        _hash(bytes),
        (entry.value as Map<String, dynamic>)['fnv1a'],
        reason:
            '${entry.key} changed. Review it with `make design-diff`, then '
            'record the approval with `make design-approve`.',
      );
    }
  });

  test('a one-byte change is visible to the gate', () {
    final bytes = File('screenshots/live_dark.png').readAsBytesSync();
    final recorded = (manifest['live_dark.png'] as Map<String, dynamic>)['fnv1a'];
    expect(_hash(bytes), recorded);
    final altered = List<int>.from(bytes)..[bytes.length - 1] ^= 0x01;
    expect(
      _hash(altered),
      isNot(recorded),
      reason: 'a one-byte screenshot change must be visible to the gate',
    );
  });
}

String _hash(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
