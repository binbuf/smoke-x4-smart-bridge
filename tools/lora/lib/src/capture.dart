/// Parsing an ESP-IDF monitor log from the reference firmware
/// (docs/reference/smoke-x-receiver) into captured LoRa packets.
///
/// The reference's log grammar (main/app_lora.c, main/smoke_x.c):
///
///   I (12345) app_lora: Packet received - Size: 87 RSSI: -71, SNR: 9
///   I (12346) app_lora: |abCDe,30,1,1,0,848,1,125,32,...
///   I (12350) smoke_x: Received sync message: 020001,|abCDe,160,32,69,54,
///   I (12360) smoke_x: X4 DATA: |abCDe,30,1,0,...
///   I (12355) smoke_x: Sending sync acknowledgement to transmitter: |abCDe,SUCCESS,
///
/// Every received packet appears via app_lora (with RSSI/SNR) even before
/// pairing; the smoke_x lines are secondary and deduplicated against it.
library;

/// Where a payload line came from.
enum CaptureSource { appLora, smokeX, txAck }

class CapturedPacket {
  CapturedPacket({
    required this.tMs,
    required this.payload,
    required this.source,
    required this.bootIndex,
    this.rssi,
    this.snr,
  });

  /// Milliseconds since boot (the ESP-IDF log timestamp).
  final int tMs;
  final String payload;
  final CaptureSource source;

  /// Increments every time the log's timestamps go backwards (a reset).
  final int bootIndex;
  final int? rssi;
  final int? snr;

  /// Number of ',' characters — the protocol's message discriminator.
  int get commaCount => ','.allMatches(payload).length;

  /// `sync6`, `ack2`, `state16`, `state26`, or `unknown<N>`.
  String get messageClass => switch (commaCount) {
    6 => 'sync6',
    2 => 'ack2',
    16 => 'state16',
    26 => 'state26',
    final n => 'unknown$n',
  };

  /// CSV fields with the trailing-comma empty token dropped.
  List<String> get fields {
    final parts = payload.split(',');
    if (parts.isNotEmpty && parts.last.isEmpty) {
      parts.removeLast();
    }
    return parts;
  }
}

final _ansi = RegExp('\x1b\\[[0-9;]*[A-Za-z]');
final _logLine = RegExp(r'^([IWEDV]) \((\d+)\) ([A-Za-z0-9_]+): (.*)$');
final _packetHeader = RegExp(
  r'^Packet received - Size: (\d+) RSSI: (-?\d+), SNR: (-?\d+(?:\.\d+)?)$',
);

/// A payload must look like Smoke X CSV: printable, comma-bearing, ends
/// with a comma (the protocol's trailing comma, no terminator).
bool _plausiblePayload(String s) =>
    s.length >= 3 &&
    s.endsWith(',') &&
    s.contains(',') &&
    !s.contains(' ') &&
    s.codeUnits.every((c) => c >= 0x20 && c < 0x7F);

/// Parses monitor-log text. Handles ANSI colour codes, CRLF, boot resets
/// (timestamp regressions), interleaved noise, and the duplicate payload
/// lines smoke_x emits for packets app_lora already logged.
List<CapturedPacket> parseMonitorLog(String text) {
  final packets = <CapturedPacket>[];
  var bootIndex = 0;
  var lastT = -1;
  ({int rssi, int snr, int tMs})? pendingMeta;

  void add(CapturedPacket p) {
    // Dedupe: smoke_x re-logs payloads app_lora captured moments earlier.
    if (p.source == CaptureSource.smokeX) {
      final dup = packets.any(
        (q) =>
            q.payload == p.payload &&
            q.bootIndex == p.bootIndex &&
            (p.tMs - q.tMs).abs() < 2000,
      );
      if (dup) {
        return;
      }
    }
    packets.add(p);
  }

  for (final rawLine in text.split('\n')) {
    final line = rawLine.replaceAll(_ansi, '').trimRight();
    final m = _logLine.firstMatch(line);
    if (m == null) {
      pendingMeta = null;
      continue;
    }
    final tMs = int.parse(m.group(2)!);
    final tag = m.group(3)!;
    final body = m.group(4)!;

    if (lastT >= 0 && tMs + 5000 < lastT) {
      bootIndex++; // timestamps went backwards: the board reset
    }
    lastT = tMs;

    if (tag == 'app_lora') {
      final header = _packetHeader.firstMatch(body);
      if (header != null) {
        pendingMeta = (
          rssi: int.parse(header.group(2)!),
          snr: double.parse(header.group(3)!).round(),
          tMs: tMs,
        );
        continue;
      }
      if (pendingMeta != null && _plausiblePayload(body)) {
        add(
          CapturedPacket(
            tMs: tMs,
            payload: body,
            source: CaptureSource.appLora,
            bootIndex: bootIndex,
            rssi: pendingMeta.rssi,
            snr: pendingMeta.snr,
          ),
        );
      }
      pendingMeta = null;
      continue;
    }
    pendingMeta = null;

    if (tag == 'smoke_x') {
      const rxPrefixes = [
        'Received sync message: ',
        'Received unexpected sync message that will be ignored: ',
        'X2 DATA: ',
        'X4 DATA: ',
        'Received unrecognized message type: ',
      ];
      const txPrefix = 'Sending sync acknowledgement to transmitter: ';
      for (final prefix in rxPrefixes) {
        if (body.startsWith(prefix)) {
          final payload = body.substring(prefix.length);
          if (_plausiblePayload(payload)) {
            add(
              CapturedPacket(
                tMs: tMs,
                payload: payload,
                source: CaptureSource.smokeX,
                bootIndex: bootIndex,
              ),
            );
          }
          break;
        }
      }
      if (body.startsWith(txPrefix)) {
        final payload = body.substring(txPrefix.length);
        if (_plausiblePayload(payload)) {
          add(
            CapturedPacket(
              tMs: tMs,
              payload: payload,
              source: CaptureSource.txAck,
              bootIndex: bootIndex,
            ),
          );
        }
      }
    }
  }
  return packets;
}
