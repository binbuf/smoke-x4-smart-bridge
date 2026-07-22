/// The .loralog v1 fixture format — the normalized form every capture lands
/// in under protocol/fixtures/lora/ (design 10 §10.4).
///
///   # loralog v1
///   # source: <file> · normalized: <label>
///   # fields: boot t_ms rssi snr dir class payload
///   0 43230 -71 9 rx state26 |abCDe,30,1,0,...
///   0 51002 ? ? tx ack2 |abCDe,SUCCESS,
///
/// Plain text so it can be read directly; `?` where RSSI/SNR are unknown
/// (smoke_x-sourced lines); payload is the last field verbatim.
library;

import 'capture.dart';

String writeLoralog(
  List<CapturedPacket> packets, {
  required String sourceLabel,
}) {
  final b = StringBuffer()
    ..writeln('# loralog v1')
    ..writeln('# source: $sourceLabel')
    ..writeln('# fields: boot t_ms rssi snr dir class payload');
  for (final p in packets) {
    final dir = p.source == CaptureSource.txAck ? 'tx' : 'rx';
    b.writeln(
      '${p.bootIndex} ${p.tMs} ${p.rssi ?? '?'} ${p.snr ?? '?'} '
      '$dir ${p.messageClass} ${p.payload}',
    );
  }
  return b.toString();
}

List<CapturedPacket> readLoralog(String text) {
  final out = <CapturedPacket>[];
  for (final line in text.split('\n')) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) {
      continue;
    }
    final parts = t.split(' ');
    if (parts.length < 7) {
      throw FormatException('loralog: bad line "$t"');
    }
    out.add(
      CapturedPacket(
        bootIndex: int.parse(parts[0]),
        tMs: int.parse(parts[1]),
        rssi: parts[2] == '?' ? null : int.parse(parts[2]),
        snr: parts[3] == '?' ? null : int.parse(parts[3]),
        source: parts[4] == 'tx' ? CaptureSource.txAck : CaptureSource.appLora,
        // parts[5] is the class — derived again from the payload on read.
        payload: parts.sublist(6).join(' '),
      ),
    );
  }
  return out;
}
