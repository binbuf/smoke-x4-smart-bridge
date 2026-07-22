import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:lora/lora.dart';

/// Normalizes an ESP-IDF monitor log from the reference firmware into a
/// committed .loralog fixture plus a protocol-question report:
///
///   dart run lora:normalize capture.log --name first-x4-capture
///
/// writes protocol/fixtures/lora/first-x4-capture.loralog and
/// protocol/fixtures/lora/first-x4-capture.report.md, and prints the report.
void main(List<String> argv) {
  final parser = ArgParser()
    ..addOption('name', help: 'fixture basename (default: from the input)')
    ..addOption(
      'out-dir',
      help: 'output directory (default: <repo>/protocol/fixtures/lora)',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(argv);

  if (args['help'] as bool || args.rest.isEmpty) {
    stdout.writeln(
      'normalize — monitor log(s) → .loralog fixture + report\n\n'
      'usage: dart run lora:normalize <monitor.log> [more.log …] '
      '[--name x] [--out-dir d]\n\n${parser.usage}',
    );
    if (args.rest.isEmpty && !(args['help'] as bool)) {
      exitCode = 64;
    }
    return;
  }

  final inputs = args.rest;
  final packets = <CapturedPacket>[];
  for (final path in inputs) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('no such file: $path');
      exitCode = 66;
      return;
    }
    // Raw serial captures carry non-UTF-8 bytes around every reset (boot-ROM
    // banner, half-transmitted lines); decode leniently rather than requiring
    // a hand-sanitized log.
    packets.addAll(
      parseMonitorLog(utf8.decode(file.readAsBytesSync(), allowMalformed: true)),
    );
  }
  if (packets.isEmpty) {
    stderr.writeln(
      'no LoRa payloads found. Expected ESP-IDF monitor output from the '
      'reference firmware (app_lora/smoke_x INFO lines) — check the log '
      'level and that the capture actually contains packets.',
    );
    exitCode = 65;
    return;
  }

  final name =
      (args['name'] as String?) ??
      inputs.first
          .split(Platform.pathSeparator)
          .last
          .replaceAll(RegExp(r'\.(log|txt)$'), '');
  final outDir = Directory(
    (args['out-dir'] as String?) ?? '${_repoRoot()}/protocol/fixtures/lora',
  )..createSync(recursive: true);
  final sourceLabel = '${inputs.join(', ')} → $name';

  final logPath = '${outDir.path}/$name.loralog';
  File(
    logPath,
  ).writeAsStringSync(writeLoralog(packets, sourceLabel: sourceLabel));

  final report = CaptureReport(packets).markdown(sourceLabel: sourceLabel);
  final reportPath = '${outDir.path}/$name.report.md';
  File(reportPath).writeAsStringSync(report);

  stdout
    ..writeln('wrote $logPath (${packets.length} packets)')
    ..writeln('wrote $reportPath')
    ..writeln()
    ..write(report);
}

String _repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/protocol/records.yaml').existsSync()) {
    if (dir.parent.path == dir.path) {
      return '.';
    }
    dir = dir.parent;
  }
  return dir.path;
}
