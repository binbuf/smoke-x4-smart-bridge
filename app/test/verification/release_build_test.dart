/// N16.10 — release-build checks that are provable at the desk.
///
/// The bench half of the release checklist (a signed APK, an install on the
/// phone) cannot run here; the parts that can be checked are pinned so a
/// regression in the release gate fails in CI. See `docs/RELEASE.md`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the dev panel is compiled out of release', () {
    // The shell owns the gate; the panel and the deep-link boot each check it
    // too, so the tree-shaker can drop the whole mock surface.
    for (final path in <String>[
      'lib/features/dev/dev_panel.dart',
      'lib/features/dev/dev_boot.dart',
      'lib/features/shell/shell.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('kReleaseMode'),
        reason: '$path must gate on kReleaseMode',
      );
    }
  });

  test('the app version is a semver release', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml needs version: x.y.z+build');
  });

  test('a changelog ships with the app', () {
    final changelog = File('CHANGELOG.md');
    expect(changelog.existsSync(), isTrue);
    expect(changelog.readAsStringSync(), contains('## 1.0.0'));
  });
}
