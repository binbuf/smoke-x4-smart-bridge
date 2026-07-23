import 'dart:io';

import 'package:args/args.dart';
import 'package:lora/lora.dart';

/// T4.1b: `dart run lora:pull --host <addr>` — fetch the packet ring and
/// novelty log over HTTP, archive the raw pulls date-stamped, and stage a
/// normalised `.loralog` + report under protocol/fixtures/lora/staging/.
Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('host', help: 'bridge address (required)')
    ..addOption('port', defaultsTo: '80')
    ..addOption('name', help: 'fixture basename (default: pull-<date>)')
    ..addOption(
      'out-dir',
      help: 'output directory (default: <repo>/protocol/fixtures/lora/staging)',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(argv);

  final host = args['host'] as String?;
  if (args['help'] as bool || host == null) {
    stdout.writeln(
      'pull — fetch /debug/packets + /debug/novelty into fixture staging\n\n'
      'usage: dart run lora:pull --host 192.168.4.1 [--name x] '
      '[--out-dir d]\n\n${parser.usage}',
    );
    if (host == null && !(args['help'] as bool)) {
      exitCode = 64;
    }
    return;
  }

  var dir = Directory.current;
  while (!File('${dir.path}/protocol/records.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      stderr.writeln('not inside the repo (protocol/records.yaml not found)');
      exitCode = 66;
      return;
    }
    dir = parent;
  }

  final now = DateTime.now().toUtc();
  final stamp =
      '${now.year}${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  final outDir =
      (args['out-dir'] as String?) ??
      '${dir.path}/protocol/fixtures/lora/staging';
  final name = (args['name'] as String?) ?? 'pull-$stamp';

  final result = await pull(
    host: host,
    port: int.parse(args['port'] as String),
    outDir: outDir,
    name: name,
    stamp: stamp,
  );
  stdout.writeln(
    'pulled ${result.packetCount} packets -> ${result.loralogPath}',
  );
  stdout.writeln('report -> ${result.reportPath}');
  if (result.noveltyPath != null) {
    stdout.writeln('novelty -> ${result.noveltyPath}');
  }
  exit(0);
}
