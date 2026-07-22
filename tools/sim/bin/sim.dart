import 'dart:io';

import 'package:args/args.dart';
import 'package:sim/sim.dart';

/// The fake bridge (design 10 §10.3):
///
///   dart run sim --port 8080 --speed 60 --cook fixtures/brisket-18h.smk
///   dart run sim --scenario stall --probes 4
///   dart run sim --scenario lid-open --drop 5
///   dart run sim --scenario base-lost --after 2h
///   dart run sim --scenario unpaired
///   dart run sim --advertise-mdns
void main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('port', defaultsTo: '8080')
    ..addOption('speed', defaultsTo: '1', help: 'replay multiplier')
    ..addOption('cook', help: '.smk fixture to serve (sibling .mrk loaded)')
    ..addOption('scenario', allowed: simScenarios)
    ..addOption('probes', defaultsTo: '4')
    ..addOption('seed', defaultsTo: '42')
    ..addOption('drop', help: 'packet-loss percent (flaky)')
    ..addOption('after', help: 'base-lost cutoff, e.g. 2h, 45m, 300s')
    ..addFlag('advertise-mdns', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(argv);

  if (args['help'] as bool) {
    stdout.writeln('sim — the fake Smoke Bridge\n\n${parser.usage}');
    return;
  }

  final speed = double.parse(args['speed'] as String);
  final SimState state;
  if (args['scenario'] != null) {
    state = scenarioState(
      args['scenario'] as String,
      speed: speed,
      seed: int.parse(args['seed'] as String),
      probes: int.parse(args['probes'] as String),
      dropPct: args['drop'] != null
          ? double.parse((args['drop'] as String).replaceAll('%', ''))
          : null,
      afterS: args['after'] != null
          ? _parseDuration(args['after'] as String)
          : null,
    );
  } else {
    final cookPath = args['cook'] as String? ?? 'fixtures/brisket-18h.smk';
    state = SimState(cook: loadCook(cookPath), speed: speed);
  }

  final server = SimServer(state);
  await server.start(port: int.parse(args['port'] as String));
  stdout.writeln(
    'sim: serving ${state.header.name} (${state.samples.length} samples, '
    'scenario=${state.scenario}, speed=${state.speed}×) '
    'on http://localhost:${server.port}/api/v1/status',
  );

  MdnsAdvertiser? mdns;
  if (args['advertise-mdns'] as bool) {
    mdns = MdnsAdvertiser(
      instance: 'SmokeBridge-${state.deviceIdShort}',
      port: server.port,
      txt: {
        'id': state.deviceIdShort,
        'model': 'sim',
        'fw': state.fw,
        'api': 'v1',
        'probes': '${state.header.numProbes}',
        'paired': state.paired ? '1' : '0',
        'session': '${state.header.sessionId}',
        'mode': state.netMode,
      },
    );
    await mdns.start();
    stdout.writeln('sim: advertising _smokebridge._tcp via mDNS');
  }

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nsim: shutting down');
    mdns?.stop();
    await server.stop();
    exit(0);
  });
}

int _parseDuration(String s) {
  final m = RegExp(r'^(\d+(?:\.\d+)?)\s*(h|m|s)?$').firstMatch(s.trim());
  if (m == null) {
    throw FormatException('bad duration: $s (use e.g. 2h, 45m, 300s)');
  }
  final value = double.parse(m.group(1)!);
  return switch (m.group(2)) {
    'h' => (value * 3600).round(),
    'm' => (value * 60).round(),
    _ => value.round(),
  };
}
