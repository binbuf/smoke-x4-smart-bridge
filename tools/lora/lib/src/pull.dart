/// T4.1b — fetch the packet ring and novelty log over HTTP and stage them
/// as fixtures. No serial cable, no reflash, no interrupting a cook: the
/// tool that turns standing-work's after-every-cook obligation into one
/// command.
///
/// (The design named this `pull.py`; T4.1's normaliser landed as Dart and
/// one language owns the fixture tooling — see the M2 plan's T4.1b note.)
library;

import 'dart:convert';
import 'dart:io';

import 'capture.dart';
import 'loralog.dart';
import 'report.dart';

class PullResult {
  PullResult({
    required this.packetCount,
    required this.loralogPath,
    required this.reportPath,
    required this.noveltyPath,
    required this.rawPath,
  });

  final int packetCount;
  final String loralogPath;
  final String reportPath;
  final String? noveltyPath;
  final String rawPath;
}

/// Fetches `/debug/packets` + `/debug/novelty` from `host:port`, archives
/// the raw pulls under `outDir/raw/`, and writes `<name>.loralog` +
/// `<name>.report.md` into `outDir`. Idempotent: same device state, same
/// outputs (the raw archive is keyed by `stamp`, so re-running with the
/// same stamp overwrites rather than accumulates).
Future<PullResult> pull({
  required String host,
  int port = 80,
  required String outDir,
  required String name,
  required String stamp,
  HttpClient? client,
}) async {
  final http = client ?? HttpClient();
  http.connectionTimeout = const Duration(seconds: 10);

  Future<String> get(String path) async {
    final req = await http.get(host, port, path);
    final res = await req.close();
    final body = await utf8.decoder.bind(res).join();
    if (res.statusCode != 200) {
      throw HttpException('$path -> ${res.statusCode}: $body');
    }
    return body;
  }

  final packetsRaw = await get('/api/v1/debug/packets');
  String? noveltyRaw;
  try {
    noveltyRaw = await get('/api/v1/debug/novelty');
  } on HttpException {
    noveltyRaw = null; // older firmware: the ring alone is still worth it
  }

  final rawDir = Directory('$outDir/raw')..createSync(recursive: true);
  final rawPath = '${rawDir.path}/$name-$stamp.packets.json';
  File(rawPath).writeAsStringSync(packetsRaw);
  String? noveltyPath;
  if (noveltyRaw != null) {
    noveltyPath = '${rawDir.path}/$name-$stamp.novelty.log';
    File(noveltyPath).writeAsStringSync(noveltyRaw);
  }

  final decoded = jsonDecode(packetsRaw);
  if (decoded is! Map || decoded['packets'] is! List) {
    throw const FormatException('unexpected /debug/packets shape');
  }
  final packets = <CapturedPacket>[
    for (final p in decoded['packets'] as List)
      if (p is Map)
        CapturedPacket(
          tMs: (p['uptime_s'] as num? ?? 0).toInt() * 1000,
          payload: '${p['payload'] ?? ''}',
          source: CaptureSource.appLora,
          bootIndex: 0,
          rssi: (p['rssi'] as num?)?.toInt(),
          snr: (p['snr'] as num?)?.toInt(),
        ),
  ];

  final loralogPath = '$outDir/$name.loralog';
  File(loralogPath).writeAsStringSync(
    writeLoralog(packets, sourceLabel: 'pull $host:$port ($stamp)'),
  );
  final reportPath = '$outDir/$name.report.md';
  File(reportPath).writeAsStringSync(
    CaptureReport(packets).markdown(sourceLabel: 'pull $host:$port -> $name'),
  );

  return PullResult(
    packetCount: packets.length,
    loralogPath: loralogPath,
    reportPath: reportPath,
    noveltyPath: noveltyPath,
    rawPath: rawPath,
  );
}
