/// Simulator state: the recorded cook ("flash"), the replay clock, and the
/// mutable device state (pairing, network, config, OTA).
///
/// Model: history endpoints always serve the FULL fixture — it is what's on
/// flash. The live surface (GET /live, the WebSocket sample stream, status's
/// session block) follows the replay cursor, which advances at `speed`×
/// real time from server start. `--speed 60` replays 18 hours in 18 minutes.
library;

import 'dart:math';

import 'package:bridge_protocol/bridge_protocol.dart';
import 'package:cookgen/cookgen.dart';

/// Injectable clock so replay math is unit-testable without wall waiting.
typedef NowMs = int Function();

class SimState {
  SimState({
    required this.cook,
    this.scenario = 'cook',
    this.speed = 1,
    this.paired = true,
    this.netMode = 'sta',
    this.storageFull = false,
    this.baseLostAfterS,
    NowMs? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _startedMs = _nowMs();
  }

  final GeneratedCook cook;
  final String scenario;
  final double speed;
  final NowMs _nowMs;
  late final int _startedMs;

  // Device identity / config.
  final String deviceIdShort = 'A4F2';
  String fw = '0.0.1-sim';
  bool paired;
  bool syncActive = false;
  String netMode; // 'ap' | 'sta'
  String staSsid = 'Backyard';
  String staPsk = 'correct horse'; // never returned by GET
  final String apSsid = 'SmokeBridge-A4F2';
  final String apPsk = 'Gk7mR2xQpT';
  bool clockValid = true;
  int tzOffsetMin = -300;
  String timeSource = 'phone';
  bool storageFull;
  final int? baseLostAfterS;

  // OTA.
  bool otaInProgress = false;
  int otaPct = 0;

  // Alarm ack state, keyed by alarm id.
  final Set<int> ackedAlarms = {};

  // Config store (echoed back by /config/device).
  Map<String, Object?> deviceConfig = {
    'display_units': 'F',
    'display_timeout_s': 60,
    'led_enabled': true,
    'battery_saver': 'auto',
    'retention': {'max_sessions': 64, 'min_free_pct': 10},
  };
  Map<String, Object?> alarmConfig = {'rules': []};

  List<SampleRec> get samples => cook.samples;
  SessionHeader get header => cook.header;
  List<MarkRec> get marks => _marks;
  late final List<MarkRec> _marks = List.of(cook.marks);

  bool sessionStopped = false;

  /// Seconds of cook time the replay cursor has reached.
  int virtualT() {
    final t = ((_nowMs() - _startedMs) * speed / 1000).floor();
    final last = samples.isEmpty ? 0 : samples.last.t;
    return min(t, last + 1);
  }

  /// Whether the base station has gone quiet (base-lost scenario).
  bool baseLostAt(int vT) => baseLostAfterS != null && vT >= baseLostAfterS!;

  /// Samples the live surface may see at the cursor: paired, not stopped,
  /// and not after the base was lost.
  List<SampleRec> liveVisible(int vT) {
    if (!paired) {
      return const [];
    }
    final cutoff = baseLostAfterS ?? 0x7fffffff;
    return [
      for (final s in samples)
        if (s.t <= vT && s.t < cutoff) s,
    ];
  }

  /// The whole cook has been replayed (or explicitly stopped).
  bool sessionEnded(int vT) =>
      sessionStopped || samples.isEmpty || vT > samples.last.t;

  int packetsOk(int vT) => liveVisible(vT).length;

  /// Seconds since the last live-visible sample.
  int? lastPacketAgo(int vT) {
    final visible = liveVisible(vT);
    if (visible.isEmpty) {
      return null;
    }
    return max(0, vT - visible.last.t);
  }
}
