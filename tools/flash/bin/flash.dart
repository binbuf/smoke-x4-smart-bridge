/// T5.1 / T5.2 — build the merged image, the esp-web-tools manifest, and
/// print the manual esptool command.
///
///     dart run flash --build firmware/build/heltec-v3 \
///                    --version 1.0.0 --out dist
///
/// This tool does NOT flash anything. Writing to a board is a deliberate
/// act with a cable in it, and §12.6 rule 8 is why nothing in this repo
/// automates it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:bridge_protocol/bridge_protocol.dart';
import 'package:flash/flash.dart';

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption(
      'build',
      help: 'ESP-IDF build directory (contains flasher_args.json)',
      defaultsTo: 'firmware/build/heltec-v3',
    )
    ..addOption('version', help: 'Release version, e.g. 1.0.0')
    ..addOption('out', help: 'Output directory', defaultsTo: 'dist')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(argv);
  if (args.flag('help') || args.option('version') == null) {
    stdout
      ..writeln('Usage: dart run flash --version <x.y.z> [options]')
      ..writeln(parser.usage);
    exit(args.flag('help') ? 0 : 2);
  }

  final version = args.option('version')!;
  final buildDir = args.option('build')!;
  final outDir = Directory(args.option('out')!)..createSync(recursive: true);

  final flasher = readFlasherArgs(buildDir);
  final merged = mergeImage(flasher);

  // Name what was just packed, using the same inspector the device and
  // the sim use. A merged image whose app descriptor disagrees with the
  // release version is a mislabelled release.
  final app = inspectOtaImage(flasher.appPart.bytes);
  if (!app.ok) {
    stderr.writeln('the app image did not inspect clean: ${app.reason}');
    exit(1);
  }
  if (app.version != version) {
    stderr.writeln(
      'version mismatch: --version $version but the image says '
      '${app.version} (CONFIG_APP_PROJECT_VER)',
    );
    exit(1);
  }

  final mergedPath = '${outDir.path}/${mergedImageName(version)}';
  File(mergedPath).writeAsBytesSync(merged);
  final otaPath = '${outDir.path}/${otaImageName(version)}';
  File(otaPath).writeAsBytesSync(flasher.appPart.bytes);

  final manifest = webToolsManifest(version: version, args: flasher);
  File('${outDir.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );

  stdout
    ..writeln('project ${app.project} v${app.version} (${app.idfVer})')
    ..writeln(
      'merged  $mergedPath  ${merged.length} B '
      '(${flasher.parts.length} parts, ${flasher.flashMode}/'
      '${flasher.flashFreq}/${flasher.flashSize})',
    )
    ..writeln('ota     $otaPath  ${flasher.appPart.bytes.length} B')
    ..writeln('manifest ${outDir.path}/manifest.json')
    ..writeln('')
    ..writeln('Flash by hand with:')
    ..writeln('  ${esptoolCommand(version: version, args: flasher)}');

  if (!headerPatchIsNoop(flasher)) {
    stdout.writeln(
      'note: the flash header at offset 0 was PATCHED — the bootloader '
      'was built with different flash settings than flasher_args.json '
      'declares.',
    );
  }
}
