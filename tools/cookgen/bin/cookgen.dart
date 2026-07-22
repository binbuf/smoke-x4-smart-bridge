import 'dart:io';

import 'package:args/args.dart';
import 'package:cookgen/cookgen.dart';

/// CLI: dart run cookgen --scenario brisket-18h --seed 42 \
///        --out protocol/fixtures/brisket-18h.smk
void main(List<String> argv) {
  final parser = ArgParser()
    ..addOption('scenario',
        defaultsTo: 'brisket-18h', allowed: scenarioNames)
    ..addOption('seed', defaultsTo: '42')
    ..addOption('out', help: 'output .smk path (sibling .mrk written too)')
    ..addOption('hours', help: 'override the scenario duration')
    ..addOption('probes', defaultsTo: '4')
    ..addOption('dropout-pct', help: 'percent of samples dropped')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(argv);
  if (args['help'] as bool) {
    stdout.writeln('cookgen — synthesize .smk/.mrk cook fixtures\n');
    stdout.writeln(parser.usage);
    return;
  }

  final scenario = args['scenario'] as String;
  final out = args['out'] as String? ?? '$scenario.smk';

  final cook = generateScenario(
    scenario,
    seed: int.parse(args['seed'] as String),
    hours: args['hours'] != null
        ? double.parse(args['hours'] as String)
        : null,
    probes: int.parse(args['probes'] as String),
    dropoutPct: args['dropout-pct'] != null
        ? double.parse(args['dropout-pct'] as String)
        : null,
  );
  cook.writeTo(out);
  stdout.writeln(
    'wrote $out: ${cook.samples.length} samples, ${cook.marks.length} marks '
    '(${cook.header.name})',
  );
}
