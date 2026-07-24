/// V3.3's instrument.
///
///     dart run soak --host 192.168.8.197 --hours 24 --trace soak.ndjson
///     dart run soak --report soak.ndjson        # evaluate an existing trace
///
/// It holds a WebSocket for liveness, polls /status and /debug/tasks on a
/// cadence, appends one NDJSON line per sample to a file that survives the
/// tool being killed, and prints the four-criteria verdict. The criteria
/// are fixed in advance (src/report.dart) — a 24-hour trace can be made to
/// support almost any conclusion if you pick the threshold afterwards.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:soak/soak.dart';

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('host', help: 'Bridge IP or hostname')
    ..addOption('port', defaultsTo: '80')
    ..addOption('token', help: 'Bearer token, if the bridge sets one')
    ..addOption('hours', defaultsTo: '24')
    ..addOption('interval', help: 'Poll cadence, seconds', defaultsTo: '30')
    ..addOption('trace', defaultsTo: 'soak.ndjson')
    ..addOption('report', help: 'Evaluate an existing trace and exit')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(argv);
  if (args.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  // Report-only: no bridge needed, so a soak can be re-scored offline.
  final reportPath = args.option('report');
  if (reportPath != null) {
    final report = evaluate(Recorder.readTrace(reportPath));
    stdout.write(renderMarkdown(report));
    exit(report.pass ? 0 : 1);
  }

  final host = args.option('host');
  if (host == null) {
    stderr.writeln('--host is required (or use --report <trace>)');
    exit(2);
  }
  final port = int.parse(args.option('port')!);
  final token = args.option('token');
  final hours = double.parse(args.option('hours')!);
  final interval = Duration(seconds: int.parse(args.option('interval')!));
  final tracePath = args.option('trace')!;

  final client = HttpClient();
  Future<Map<String, Object?>> fetch(String path) async {
    final req = await client.get(host, port, path);
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await utf8.decoder.bind(res).join();
    if (res.statusCode != 200) {
      throw HttpException('$path -> ${res.statusCode}');
    }
    return jsonDecode(body) as Map<String, Object?>;
  }

  final recorder = Recorder(fetch: fetch, tracePath: tracePath);
  var seq = recorder.lastSeqOnDisk() + 1;
  if (seq > 0) {
    stdout.writeln('resuming trace at seq $seq');
  }

  final deadline = DateTime.now().add(
    Duration(milliseconds: (hours * 3600000).round()),
  );
  stdout.writeln(
    'soaking $host:$port until $deadline, every ${interval.inSeconds}s',
  );

  while (DateTime.now().isBefore(deadline)) {
    try {
      final s = await recorder.pollOnce(seq++);
      stdout.writeln(
        'seq ${s.seq}  free ${(s.freeHeap / 1024).toStringAsFixed(1)}K  '
        'min ${(s.minFreeHeap / 1024).toStringAsFixed(1)}K  '
        'block ${(s.largestFreeBlock / 1024).toStringAsFixed(1)}K  '
        'gate ${s.gate}',
      );
    } on Object catch (e) {
      // A poll that fails is a reconnect, not a crash: the bridge may be
      // mid-reboot, and the whole point is to survive 24 h unattended.
      recorder.reconnects++;
      stderr.writeln('poll failed (${recorder.reconnects}): $e');
    }
    await Future<void>.delayed(interval);
  }

  final report = evaluate(Recorder.readTrace(tracePath));
  stdout.write(renderMarkdown(report));
  exit(report.pass ? 0 : 1);
}
