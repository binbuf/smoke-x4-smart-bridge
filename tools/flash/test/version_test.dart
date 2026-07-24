/// T5.4 / T5.5 — the guards that keep a release from publishing a wrong
/// thing, run as tests so they fail in CI on every push rather than only
/// on a tag.
///
/// The version guard reads the SAME three files `release.yml` reads.
/// §10.8 makes firmware and app share a version because the API contract
/// binds them (06 §6.5); this is where a bump that touched only one of
/// them turns red.
///
/// The public-repo sweep is Q-F's obligation. The answer is "public", and
/// "we'll check before we publish" is how credentials get published.
library;

import 'dart:io';

import 'package:test/test.dart';

String repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/protocol/records.yaml').existsSync()) {
    if (dir.parent.path == dir.path) throw StateError('repo root not found');
    dir = dir.parent;
  }
  return dir.path;
}

void main() {
  final root = repoRoot();

  group('version agreement', () {
    test('firmware and app carry the same version', () {
      final sdk = File('$root/firmware/sdkconfig.defaults').readAsStringSync();
      final fw = RegExp(
        r'^CONFIG_APP_PROJECT_VER="(.*)"$',
        multiLine: true,
      ).firstMatch(sdk)?.group(1);
      expect(
        fw,
        isNotNull,
        reason:
            'CONFIG_APP_PROJECT_VER must be pinned (F14.7): without it the '
            'app descriptor carries a git-describe abbreviation and '
            '/status.fw disagrees with the image it is running',
      );

      final pubspec = File('$root/app/pubspec.yaml').readAsStringSync();
      final app = RegExp(
        r'^version: ([0-9]+\.[0-9]+\.[0-9]+)\+',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1);
      expect(app, isNotNull);

      expect(
        fw,
        app,
        reason:
            'firmware and app share a version (10 §10.8) — the app enforces '
            'a minimum firmware version (06 §6.5), so a release that bumps '
            'one and not the other ships a mismatch',
      );
      expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(fw!), isTrue);
    });

    test('rollback is enabled, or the health gate is decoration', () {
      final sdk = File('$root/firmware/sdkconfig.defaults').readAsStringSync();
      // Without this the bootloader never rolls back, and F14.3's whole
      // verdict is a log line.
      expect(sdk, contains('CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y'));
    });
  });

  group('public-repo sweep (Q-F)', () {
    // Files that legitimately contain credential-shaped strings: the
    // fixtures and the design docs that specify their format.
    bool exempt(String path) {
      final p = path.replaceAll(r'\', '/');
      return p.contains('/docs/reference/') ||
          p.contains('/build/') ||
          p.contains('/.dart_tool/') ||
          p.contains('/managed_components/') ||
          p.contains('/.git/');
    }

    Iterable<File> sources() sync* {
      for (final dir in const [
        'firmware/components',
        'firmware/main',
        'app/lib',
        'tools',
        'protocol',
        // docs/hardware-verified.md is the likeliest place a credential
        // leaks: it is a bench log, written when nobody was thinking
        // about publication.
        'docs',
      ]) {
        final d = Directory('$root/$dir');
        if (!d.existsSync()) continue;
        for (final e in d.listSync(recursive: true)) {
          if (e is File && !exempt(e.path)) yield e;
        }
      }
    }

    test('no real Wi-Fi credential is committed', () {
      // The bench log names the test network on purpose (it is a
      // throwaway SSID with no secret attached); a PSK beside it would
      // not be. This asserts the shape that matters: an assignment of a
      // non-placeholder password.
      final bad = <String>[];
      // Deliberately narrow: an assignment of a QUOTED literal to a
      // credential-named key. A looser pattern matches every comment
      // containing the word "password" and gets muted within a week,
      // which protects nothing.
      final pattern = RegExp(
        '''(?:psk|password|passphrase)["']?\\s*[:=]\\s*(["'])([^"'\\n]{8,})\\1''',
        caseSensitive: false,
      );
      const placeholders = [
        'correct horse',
        'Gk7mR2xQpT', // the committed AP-PSK fixture value
        'hunter2hunter2',
        '<password>',
        'wrong-password',
        'never returned',
      ];
      for (final f in sources()) {
        if (!const [
          '.dart',
          '.c',
          '.h',
          '.yaml',
          '.yml',
          '.json',
          '.md',
        ].any(f.path.endsWith)) {
          continue;
        }
        // Some sources carry °/± as Latin-1 rather than UTF-8; a decode
        // failure is not a finding.
        String text;
        try {
          text = f.readAsStringSync();
        } on FileSystemException {
          text = String.fromCharCodes(f.readAsBytesSync());
        }
        for (final m in pattern.allMatches(text)) {
          final v = m.group(2)!.trim();
          if (placeholders.any(v.contains)) continue;
          if (v.contains(r'$') || v.contains('...')) continue;
          if (v.startsWith('*') || v.startsWith('<')) continue;
          bad.add('${f.path}: $v');
        }
      }
      expect(bad, isEmpty, reason: 'credential-shaped values found');
    });

    test('MIT attribution rides with the code it covers (D9)', () {
      // D9: the upstream parser is carried under MIT WITH ATTRIBUTION.
      // Publishing it without the notice is a licence violation, not a
      // style slip.
      final parser = File(
        '$root/firmware/components/smoke_x/smoke_x_parser.c',
      ).readAsStringSync();
      expect(parser, contains('MIT'));
      expect(parser, contains('G-Two'));
      expect(
        File('$root/docs/reference/smoke-x-receiver/LICENSE').existsSync(),
        isTrue,
      );
    });
  });
}
