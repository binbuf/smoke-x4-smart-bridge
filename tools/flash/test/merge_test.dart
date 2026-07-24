/// T5.1 / T5.2 — the merged image and the artifacts that describe it.
///
/// Every test runs against a synthesised build directory EXCEPT the two
/// that need the real one; those skip with a stated reason rather than
/// silently passing, because a merged-image test that never sees a real
/// bootloader proves nothing about the offsets.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bridge_protocol/bridge_protocol.dart';
import 'package:flash/flash.dart';
import 'package:test/test.dart';

String repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/protocol/records.yaml').existsSync()) {
    if (dir.parent.path == dir.path) throw StateError('repo root not found');
    dir = dir.parent;
  }
  return dir.path;
}

/// A build directory with our real offsets and plausible contents.
Directory fakeBuild({
  Map<String, int>? sizes,
  String flashMode = 'dio',
  String flashFreq = '80m',
  String flashSize = '8MB',
  Map<String, String>? files,
  int bootByte2 = 2,
  int bootByte3 = 0x3F,
  bool includeOtaData = true,
}) {
  final dir = Directory.systemTemp.createTempSync('flashtest');
  addTearDown(() => dir.deleteSync(recursive: true));

  final s =
      sizes ??
      const {
        'bootloader/bootloader.bin': 21120,
        'partition_table/partition-table.bin': 3072,
        'ota_data_initial.bin': 8192,
        'smoke_bridge.bin': 4096,
      };

  final flashFiles =
      files ??
      {
        '0x0': 'bootloader/bootloader.bin',
        '0x8000': 'partition_table/partition-table.bin',
        if (includeOtaData) '0xf000': 'ota_data_initial.bin',
        '0x20000': 'smoke_bridge.bin',
      };

  for (final rel in flashFiles.values) {
    if (!s.containsKey(rel)) continue;
    final f = File('${dir.path}/$rel')..createSync(recursive: true);
    final bytes = Uint8List(s[rel]!);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (i + rel.length) & 0xFF;
    }
    if (rel.contains('bootloader')) {
      bytes[0] = 0xE9;
      bytes[2] = bootByte2;
      bytes[3] = bootByte3;
    }
    f.writeAsBytesSync(bytes);
  }

  File('${dir.path}/flasher_args.json').writeAsStringSync(
    jsonEncode({
      'flash_settings': {
        'flash_mode': flashMode,
        'flash_size': flashSize,
        'flash_freq': flashFreq,
      },
      'flash_files': flashFiles,
      'app': {'offset': '0x20000', 'file': 'smoke_bridge.bin'},
      'extra_esptool_args': {'chip': 'esp32s3'},
    }),
  );
  return dir;
}

void main() {
  group('merged image (T5.1)', () {
    test('every part lands at its own offset, and nothing is stranded', () {
      final dir = fakeBuild();
      final args = readFlasherArgs(dir.path);
      final merged = mergeImage(args);

      // The offsets ARE the reference's trap: it merges at
      // 0x0/0x8000/0x10000/0x210000 with no otadata at all.
      expect(args.parts.map((p) => p.offset), [0, 0x8000, 0xF000, 0x20000]);

      for (final part in args.parts) {
        expect(
          merged.sublist(part.offset, part.end),
          part.bytes,
          reason: '${part.path} is not byte-identical at its offset',
        );
      }
      // No trailing padding: the image ends where the app ends.
      expect(merged.length, 0x20000 + 4096);
      // The gaps are erased flash, not zeros.
      expect(merged[0x8000 - 1], 0xFF);
      expect(merged[0x20000 - 1], 0xFF);
    });

    test('a merged image without ota_data_initial is refused', () {
      // It boots nowhere: the bootloader reads otadata to choose a slot.
      final dir = fakeBuild(includeOtaData: false);
      expect(
        () => mergeImage(readFlasherArgs(dir.path)),
        throwsA(
          isA<MergeException>().having(
            (e) => e.message,
            'message',
            contains('ota_data_initial'),
          ),
        ),
      );
    });

    test('overlapping parts are an error, not last-writer-wins', () {
      final dir = fakeBuild(
        sizes: const {
          'bootloader/bootloader.bin': 0x9000, // runs past 0x8000
          'partition_table/partition-table.bin': 3072,
          'ota_data_initial.bin': 8192,
          'smoke_bridge.bin': 4096,
        },
      );
      expect(
        () => mergeImage(readFlasherArgs(dir.path)),
        throwsA(
          isA<MergeException>().having(
            (e) => e.message,
            'message',
            contains('overlaps'),
          ),
        ),
      );
    });

    test('a part past the end of flash is an error', () {
      // 0x20000 + 1 MB = 0x120000, past a 1 MB part.
      final dir = fakeBuild(
        flashSize: '1MB',
        sizes: const {
          'bootloader/bootloader.bin': 21120,
          'partition_table/partition-table.bin': 3072,
          'ota_data_initial.bin': 8192,
          'smoke_bridge.bin': 0x100000,
        },
      );
      expect(
        () => mergeImage(readFlasherArgs(dir.path)),
        throwsA(
          isA<MergeException>().having(
            (e) => e.message,
            'message',
            contains('past the 1MB flash'),
          ),
        ),
      );
    });

    test('a build directory with no flasher_args.json says so', () {
      final dir = Directory.systemTemp.createTempSync('empty');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(
        () => readFlasherArgs(dir.path),
        throwsA(
          isA<MergeException>().having(
            (e) => e.message,
            'message',
            contains('build the firmware first'),
          ),
        ),
      );
    });

    test('a flasher_args.json naming a missing file says which', () {
      final dir = fakeBuild();
      File('${dir.path}/smoke_bridge.bin').deleteSync();
      expect(
        () => readFlasherArgs(dir.path),
        throwsA(
          isA<MergeException>().having(
            (e) => e.message,
            'message',
            contains('smoke_bridge.bin'),
          ),
        ),
      );
    });
  });

  group('flash header patch (T5.1)', () {
    test('is a no-op for a dio/80m/8MB build', () {
      // The interesting half of the assertion: the day this stops being a
      // no-op is the day someone changed a flash setting without changing
      // the bootloader.
      final dir = fakeBuild();
      final args = readFlasherArgs(dir.path);
      expect(headerPatchIsNoop(args), isTrue);
      final merged = mergeImage(args);
      expect(merged[2], args.parts.first.bytes[2]);
      expect(merged[3], args.parts.first.bytes[3]);
    });

    test('rewrites bytes 2-3 for a qio/40m/4MB bootloader', () {
      final dir = fakeBuild(
        flashMode: 'qio',
        flashFreq: '40m',
        flashSize: '4MB',
        bootByte2: 2, // still says dio
        bootByte3: 0x3F, // still says 8MB/80m
      );
      final args = readFlasherArgs(dir.path);
      expect(headerPatchIsNoop(args), isFalse);
      final merged = mergeImage(args);
      expect(merged[2], 0); // qio
      expect(merged[3], (2 << 4) | 0x0); // 4MB, 40m
    });
  });

  group('artifacts (T5.2)', () {
    test('the manifest names exactly one part at offset 0', () {
      final dir = fakeBuild();
      final args = readFlasherArgs(dir.path);
      final m = webToolsManifest(version: '1.0.0', args: args);
      expect(m['name'], 'Smoke X4 Smart Bridge');
      expect(m['version'], '1.0.0');
      // A board carrying a previous install has an otadata and a `cooks`
      // filesystem a fresh flash should not inherit silently.
      expect(m['new_install_prompt_erase'], isTrue);
      final builds = m['builds']! as List;
      expect(builds, hasLength(1));
      final build = builds.single as Map;
      expect(build['chipFamily'], 'ESP32-S3');
      final parts = build['parts']! as List;
      expect(parts, hasLength(1));
      expect((parts.single as Map)['offset'], 0);
      expect((parts.single as Map)['path'], 'smoke-bridge-heltec-v3-1.0.0.bin');
    });

    test('chipFamily follows the build, not a constant', () {
      expect(chipFamilyFor('esp32s3'), 'ESP32-S3');
      expect(chipFamilyFor('esp32'), 'ESP32');
      expect(() => chipFamilyFor('esp32h9'), throwsA(isA<MergeException>()));
    });

    test('the two release images cannot be confused for one another', () {
      // F14.1 exists because somebody uploads the wrong one anyway; two
      // names differing by one word in the middle are two names that get
      // confused.
      expect(mergedImageName('1.0.0'), 'smoke-bridge-heltec-v3-1.0.0.bin');
      expect(otaImageName('1.0.0'), 'smoke-bridge-1.0.0-ota.bin');
      expect(mergedImageName('1.0.0'), isNot(otaImageName('1.0.0')));
      expect(otaImageName('1.0.0'), endsWith('-ota.bin'));
    });

    test('the esptool command carries the real chip, offset and name', () {
      final dir = fakeBuild();
      final cmd = esptoolCommand(
        version: '1.0.0',
        args: readFlasherArgs(dir.path),
      );
      expect(cmd, contains('--chip esp32s3'));
      expect(cmd, contains('write_flash 0x0'));
      expect(cmd, contains('smoke-bridge-heltec-v3-1.0.0.bin'));
    });

    test('the installer page references only what the release publishes', () {
      // T5.3: a page that fetches something the workflow does not deploy
      // is a 404 on Pages, and the only place it shows up is a user's
      // browser.
      final page = File(
        '${repoRoot()}/tools/installer/index.html',
      ).readAsStringSync();
      expect(page, contains('manifest.json'));
      // The antenna warning (01 §1.5): powering an SX1262 with no antenna
      // damages it, and this page is aimed at people holding a new board.
      expect(page.toLowerCase(), contains('antenna'));
      // §10.8's first-boot handoff into BLE onboarding (05 §5.7).
      expect(page, contains('SmokeBridge-'));
      // A fresh install erases stored cooks; say so.
      expect(page.toLowerCase(), contains('erase'));
      // No external asset beyond the esp-web-tools module itself.
      final srcs = RegExp(
        r'''(?:src|href)="(https?://[^"]+)"''',
      ).allMatches(page).map((m) => m.group(1)!);
      for (final src in srcs) {
        expect(
          src,
          anyOf(contains('esp-web-tools'), contains('github.com')),
          reason: 'unexpected external asset: $src',
        );
      }
    });
  });

  group('against the real build', () {
    final buildDir = '${repoRoot()}/firmware/build/heltec-v3';
    final present = File('$buildDir/flasher_args.json').existsSync();

    test(
      'the merged image is the real parts at the real offsets',
      () {
        final args = readFlasherArgs(buildDir);
        final merged = mergeImage(args);
        // 03 §3.5's table, read from the build rather than transcribed.
        expect(args.parts.map((p) => p.offset), [0, 0x8000, 0xF000, 0x20000]);
        expect(args.chip, 'esp32s3');
        expect(args.flashSize, '8MB');
        expect(merged.length, 0x20000 + args.appPart.bytes.length);
        expect(
          merged.sublist(0x20000, 0x20000 + args.appPart.bytes.length),
          args.appPart.bytes,
        );
        // The bootloader was already built dio/80m/8MB.
        expect(headerPatchIsNoop(args), isTrue);
      },
      skip: present ? null : 'firmware not built (no $buildDir)',
    );

    test(
      'the app image inspects clean and carries the pinned version',
      () {
        final args = readFlasherArgs(buildDir);
        final info = inspectOtaImage(args.appPart.bytes);
        expect(info.ok, isTrue, reason: info.reason);
        expect(info.project, 'smoke_bridge');
        // F14.7 — CONFIG_APP_PROJECT_VER, not a git-describe abbreviation.
        expect(info.version, '1.0.0');
      },
      skip: present ? null : 'firmware not built (no $buildDir)',
    );

    test(
      'the MERGED image is refused as an OTA upload',
      () {
        // The whole point of F14.1: the merged image starts with the
        // bootloader, has 0xE9 and the right chip id, and no app
        // descriptor. Uploading it to /api/v1/ota produces a board that
        // does not boot, and there is no second board.
        final args = readFlasherArgs(buildDir);
        final merged = mergeImage(args);
        final info = inspectOtaImage(merged);
        expect(info.ok, isFalse);
        expect(info.reason, 'not_an_app_image_use_the_ota_bin');
      },
      skip: present ? null : 'firmware not built (no $buildDir)',
    );
  });
}
