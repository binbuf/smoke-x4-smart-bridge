/// N2.16–N2.20 — the scenario fixtures.
///
/// Every UI situation the app must handle, ported from `MOCK.SCENARIOS`. Each
/// is a complete [BridgeSnapshot] with the prototype's exact numbers, so UI
/// comparisons stay valid. Times are relative to "now" at build time.
library;

import '../../domain/domain.dart';
import '../model/alarm.dart';
import '../model/bridge_snapshot.dart';
import '../model/connection_state.dart';
import '../model/cook_state.dart';

const int _h = 60 * 60 * 1000;
const int _m = 60 * 1000;

int _f10(num f) => (f * 10).round();

List<int> _spark(List<num> xs) => [for (final x in xs) _f10(x)];

LinkState _link({
  bool available = true,
  bool connected = false,
  WifiMode? mode,
  int? bars,
  int? rssi,
  int? lastSyncS,
  bool warm = false,
  String? ssid,
  String? ip,
  String? passkey,
}) => LinkState(
  available: available,
  connected: connected,
  mode: mode,
  bars: bars,
  rssi: rssi,
  lastSyncS: lastSyncS,
  warm: warm,
  ssid: ssid,
  ip: ip,
  passkey: passkey,
);

ProbeState _probe({
  required ProbeJack jack,
  ProbeRole role = ProbeRole.unused,
  bool attached = false,
  Freshness freshness = Freshness.unknown,
  num? tempF,
  num? targetF,
  num? pullF,
  double? trendFPerHr,
  bool stalled = false,
  num? peakF,
  num? lowF,
  num? avgF,
  int? etaMin,
  String etaNote = '',
  List<num> spark = const [],
}) => ProbeState(
  jack: jack,
  role: role,
  attached: attached,
  freshness: freshness,
  tempF10: tempF == null ? null : _f10(tempF),
  targetF10: targetF == null ? null : _f10(targetF),
  pullF10: pullF == null ? null : _f10(pullF),
  trendFPerHr: trendFPerHr,
  stalled: stalled,
  peakF10: peakF == null ? null : _f10(peakF),
  lowF10: lowF == null ? null : _f10(lowF),
  avgF10: avgF == null ? null : _f10(avgF),
  etaMin: etaMin,
  etaNote: etaNote,
  spark: _spark(spark),
);

/// A detached jack.
ProbeState _detached(ProbeJack jack) => ProbeState(jack: jack);

/// The neutral 4-probe set for the connection-matrix scenarios.
List<ProbeState> freshProbes() => [
  _probe(
    jack: ProbeJack.one,
    role: ProbeRole.food,
    attached: true,
    freshness: Freshness.live,
    tempF: 68.0,
    trendFPerHr: 0,
    peakF: 68,
    lowF: 67.8,
    avgF: 67.9,
    spark: [68, 68, 68.1, 68, 68, 68, 68, 68, 68, 68, 68, 68],
  ),
  _detached(ProbeJack.two),
  _detached(ProbeJack.three),
  _probe(
    jack: ProbeJack.four,
    role: ProbeRole.pit,
    attached: true,
    freshness: Freshness.live,
    tempF: 92.0,
    trendFPerHr: 24,
    peakF: 92,
    lowF: 74,
    avgF: 83,
    spark: [74, 76, 79, 82, 85, 88, 90, 91, 92, 92, 92, 92],
  ),
];

/// Builds every scenario keyed by its id, at [nowMs] (defaults to now).
Map<String, Scenario> allScenarios({int? nowMs}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  return {
    for (final s in [
      _running(now),
      _idle(now),
      _existing(now),
      _offline(now),
      _btOnly(),
      _staConnecting(),
      _staWrongPassword(),
      _staRouterUnreachable(),
      _apBroadcasting(),
      _apJoined(),
      _switchRollback(),
    ])
      s.key: s,
  };
}

Scenario _scenario(String key, String label, BridgeSnapshot snapshot) =>
    Scenario(key: key, label: label, snapshot: snapshot);

Scenario _running(int now) => _scenario(
  'running',
  'Running — Wi-Fi + BLE warm',
  BridgeSnapshot(
    connection: ConnectionState(
      phase: ConnectionPhase.connected,
      batteryPct: 71,
      primary: LinkPrimary.wifi,
      bt: _link(connected: true, bars: 3, rssi: -62, lastSyncS: 4, warm: true),
      wifi: _link(
        connected: true,
        mode: WifiMode.sta,
        ssid: 'HomeNet-5G',
        ip: '192.168.1.42',
        bars: 4,
        rssi: -48,
        lastSyncS: 4,
      ),
    ),
    cook: CookState(
      active: true,
      name: 'Sunday Brisket & Ribs',
      startedAtMs: now - (4 * _h + 12 * _m),
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      grateTargetF10: 2500,
      styleId: 'central_texas',
      items: [
        CookItem(
          presetId: 'beef_brisket',
          jack: ProbeJack.one,
          addedAtMs: now - (4 * _h + 12 * _m),
        ),
        CookItem(
          presetId: 'pork_ribs',
          jack: ProbeJack.two,
          addedAtMs: now - (3 * _h + 20 * _m),
        ),
        CookItem(
          presetId: 'pork_sausage',
          jack: ProbeJack.three,
          addedAtMs: now - 55 * _m,
        ),
      ],
    ),
    probes: [
      _probe(
        jack: ProbeJack.one,
        role: ProbeRole.food,
        attached: true,
        freshness: Freshness.live,
        tempF: 164.2,
        targetF: 201,
        pullF: 193,
        trendFPerHr: 0.4,
        stalled: true,
        peakF: 164.2,
        lowF: 58.0,
        avgF: 128.4,
        etaNote: 'No estimate while it is in a stall.',
        spark: [70, 96, 118, 134, 146, 152, 157, 160, 162, 163, 164, 164.2],
      ),
      _probe(
        jack: ProbeJack.two,
        role: ProbeRole.food,
        attached: true,
        freshness: Freshness.live,
        tempF: 172.4,
        targetF: 195,
        pullF: 195,
        trendFPerHr: 6.2,
        peakF: 172.4,
        lowF: 62.0,
        avgF: 118.7,
        etaMin: 38,
        spark: [60, 88, 110, 126, 138, 148, 155, 161, 166, 169, 171, 172.4],
      ),
      _probe(
        jack: ProbeJack.three,
        role: ProbeRole.food,
        attached: true,
        freshness: Freshness.live,
        tempF: 141.8,
        targetF: 160,
        pullF: 160,
        trendFPerHr: 18.0,
        peakF: 141.8,
        lowF: 71.0,
        avgF: 96.2,
        etaMin: 11,
        spark: [72, 80, 92, 104, 116, 126, 133, 137, 139, 140, 141, 141.8],
      ),
      _probe(
        jack: ProbeJack.four,
        role: ProbeRole.pit,
        attached: true,
        freshness: Freshness.live,
        tempF: 248.6,
        targetF: 250,
        trendFPerHr: -4.1,
        peakF: 261.0,
        lowF: 238.0,
        avgF: 249.3,
        spark: [252, 255, 258, 261, 259, 256, 253, 251, 250, 249, 249, 248.6],
      ),
    ],
    alarms: [
      Alarm(
        id: 'pit_crash',
        tier: AlarmTier.device,
        severity: AlarmSeverity.critical,
        rule: 'Pit temperature falling fast',
        detail: 'Down 18°F in 12 min. Check fuel and vents.',
        valueF10: _f10(248.6),
        atMs: now - 3 * _m,
        ruleId: 'pit_crash',
        trigger: 'Fell 18°F in 12 min',
        suggestion: 'Open a vent or add a lit chimney.',
      ),
      Alarm(
        id: 'eta_soon',
        tier: AlarmTier.app,
        severity: AlarmSeverity.info,
        rule: 'Sausages almost ready',
        detail: 'ETA about 11 minutes to 160°F.',
        valueF10: _f10(141.8),
        atMs: now - 1 * _m,
        ruleId: 'eta_soon',
        trigger: 'Within 15 min of target',
        suggestion: 'Get the buns and mustard ready.',
      ),
    ],
    marks: [
      Mark(t: 0, kind: MarkKind.phaseChange, text: 'Cook started'),
      Mark(
        t: 3 * 3600 + 20 * 60,
        kind: MarkKind.note,
        probe: 2,
        text: 'Added ribs',
      ),
      Mark(
        t: 2 * 3600 + 55 * 60,
        kind: MarkKind.wrapped,
        probe: 1,
        text: 'Wrapped brisket in butcher paper',
      ),
      Mark(t: 2 * 3600, kind: MarkKind.note, probe: 2, text: 'Spritzed ribs'),
      Mark(t: 55 * 60, kind: MarkKind.note, probe: 3, text: 'Added sausages'),
    ],
  ),
);

Scenario _idle(int now) => _scenario(
  'idle',
  'Idle — Wi-Fi only, instrument mode',
  BridgeSnapshot(
    connection: ConnectionState(
      phase: ConnectionPhase.connected,
      batteryPct: 88,
      primary: LinkPrimary.wifi,
      bt: _link(),
      wifi: _link(
        connected: true,
        mode: WifiMode.sta,
        ssid: 'HomeNet-5G',
        ip: '192.168.1.42',
        bars: 4,
        rssi: -48,
        lastSyncS: 2,
      ),
    ),
    cook: const CookState(pitBandMinF10: 2250, pitBandMaxF10: 2750),
    probes: [
      _probe(
        jack: ProbeJack.one,
        role: ProbeRole.food,
        attached: true,
        freshness: Freshness.live,
        tempF: 68.1,
        trendFPerHr: -0.2,
        peakF: 68.1,
        lowF: 67.9,
        avgF: 68.0,
        spark: [
          68,
          68.1,
          68.2,
          68.1,
          68.0,
          68.1,
          68.1,
          68.1,
          68.2,
          68.1,
          68.1,
          68.1,
        ],
      ),
      _detached(ProbeJack.two),
      _detached(ProbeJack.three),
      _probe(
        jack: ProbeJack.four,
        role: ProbeRole.pit,
        attached: true,
        freshness: Freshness.live,
        tempF: 92.4,
        trendFPerHr: 24.0,
        peakF: 92.4,
        lowF: 74.0,
        avgF: 83.0,
        spark: [74, 76, 79, 82, 85, 88, 90, 91, 92, 92.2, 92.3, 92.4],
      ),
    ],
  ),
);

Scenario _existing(int now) => _scenario(
  'existing',
  'Bridge has a session already running (BLE)',
  BridgeSnapshot(
    connection: ConnectionState(
      phase: ConnectionPhase.connected,
      batteryPct: 64,
      primary: LinkPrimary.bt,
      bt: _link(connected: true, bars: 2, rssi: -74, lastSyncS: 7),
      wifi: _link(mode: WifiMode.off),
    ),
    cook: const CookState(pitBandMinF10: 2250, pitBandMaxF10: 2750),
    probes: [
      _probe(
        jack: ProbeJack.one,
        role: ProbeRole.food,
        attached: true,
        freshness: Freshness.live,
        tempF: 158.0,
        trendFPerHr: 1.1,
        stalled: true,
        peakF: 158.0,
        lowF: 61.0,
        avgF: 121.0,
        spark: [
          61,
          92,
          118,
          138,
          149,
          154,
          156,
          157,
          157.5,
          157.8,
          157.9,
          158.0,
        ],
      ),
      _detached(ProbeJack.two),
      _detached(ProbeJack.three),
      _probe(
        jack: ProbeJack.four,
        role: ProbeRole.pit,
        attached: true,
        freshness: Freshness.live,
        tempF: 243.0,
        trendFPerHr: -2.0,
        peakF: 258.0,
        lowF: 231.0,
        avgF: 246.0,
        spark: [231, 240, 248, 255, 258, 256, 252, 249, 246, 244, 243.5, 243.0],
      ),
    ],
    pendingSession: PendingSession(
      sessionId: 'SMK-4471',
      startedAtMs: now - (2 * _h + 5 * _m),
      samples: 253,
      probeCount: 2,
      attachedJacks: const [1, 4],
    ),
  ),
);

Scenario _offline(int now) => _scenario(
  'offline',
  'Unreachable — stale data',
  BridgeSnapshot(
    connection: ConnectionState(
      phase: ConnectionPhase.offline,

      bt: _link(bars: 0, lastSyncS: 742),
      wifi: _link(
        mode: WifiMode.sta,
        ssid: 'HomeNet-5G',
        bars: 0,
        lastSyncS: 742,
      ),
    ),
    cook: CookState(
      active: true,
      name: 'Sunday Brisket & Ribs',
      startedAtMs: now - (4 * _h + 30 * _m),
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      grateTargetF10: 2500,
      items: [
        CookItem(
          presetId: 'beef_brisket',
          jack: ProbeJack.one,
          addedAtMs: now - (4 * _h + 30 * _m),
        ),
        CookItem(
          presetId: 'pork_ribs',
          jack: ProbeJack.two,
          addedAtMs: now - (3 * _h + 40 * _m),
        ),
      ],
    ),
    probes: [
      _probe(
        jack: ProbeJack.one,
        role: ProbeRole.food,
        attached: true,
        freshness: Freshness.frozen,
        tempF: 176.3,
        targetF: 201,
        pullF: 193,
        peakF: 176.3,
        lowF: 58.0,
        avgF: 130.0,
        spark: [70, 100, 124, 142, 155, 164, 170, 174, 175, 176, 176.2, 176.3],
      ),
      _probe(
        jack: ProbeJack.two,
        role: ProbeRole.food,
        attached: true,
        freshness: Freshness.frozen,
        tempF: 181.0,
        targetF: 195,
        pullF: 195,
        peakF: 181.0,
        lowF: 62.0,
        avgF: 120.0,
        spark: [62, 90, 112, 130, 145, 158, 168, 175, 178, 180, 180.5, 181.0],
      ),
      _detached(ProbeJack.three),
      _probe(
        jack: ProbeJack.four,
        role: ProbeRole.pit,
        attached: true,
        freshness: Freshness.frozen,
        tempF: 251.0,
        targetF: 250,
        peakF: 261.0,
        lowF: 238.0,
        avgF: 249.0,
        spark: [252, 255, 258, 261, 259, 256, 253, 251, 250, 249, 249, 251],
      ),
    ],
    alarms: [
      Alarm(
        id: 'bridge_unreachable',
        tier: AlarmTier.app,
        severity: AlarmSeverity.warning,
        rule: 'Bridge unreachable',
        detail:
            'No data for 12 minutes. The bridge is still recording — the gap '
            'will fill when it reconnects.',
        atMs: now - 12 * _m,
        sessionScoped: false,
        ruleId: 'bridge_unreachable',
        trigger: 'No packet for 12 min',
        suggestion: 'Move closer, or re-sync when you can.',
      ),
    ],
    marks: [
      Mark(t: 0, kind: MarkKind.phaseChange, text: 'Cook started'),
      Mark(
        t: 3 * 3600 + 40 * 60,
        kind: MarkKind.note,
        probe: 2,
        text: 'Added ribs',
      ),
      Mark(
        t: 3 * 3600,
        kind: MarkKind.wrapped,
        probe: 1,
        text: 'Wrapped brisket in butcher paper',
      ),
    ],
  ),
);

Scenario _btOnly() => _scenario(
  'bt_only',
  'Bluetooth only — no Wi-Fi configured',
  BridgeSnapshot(
    connection: ConnectionState(
      phase: ConnectionPhase.connected,
      batteryPct: 82,
      primary: LinkPrimary.bt,
      bt: _link(connected: true, bars: 3, rssi: -60, lastSyncS: 3, warm: true),
      wifi: _link(mode: WifiMode.off),
    ),
    cook: const CookState(pitBandMinF10: 2250, pitBandMaxF10: 2750),
    probes: [
      _probe(
        jack: ProbeJack.one,
        role: ProbeRole.food,
        attached: true,
        freshness: Freshness.live,
        tempF: 22.4,
        trendFPerHr: 0,
        peakF: 22.4,
        lowF: 22.0,
        avgF: 22.2,
        spark: [
          22,
          22,
          22.1,
          22.2,
          22.3,
          22.4,
          22.4,
          22.4,
          22.4,
          22.4,
          22.4,
          22.4,
        ],
      ),
      _detached(ProbeJack.two),
      _detached(ProbeJack.three),
      _probe(
        jack: ProbeJack.four,
        role: ProbeRole.pit,
        attached: true,
        freshness: Freshness.live,
        tempF: 23.0,
        trendFPerHr: 0,
        peakF: 23.2,
        lowF: 22.8,
        avgF: 23.0,
        spark: [23, 23, 23.1, 23, 22.9, 23, 23, 23.1, 23, 23, 23, 23],
      ),
    ],
  ),
);

ConnectionState _matrixConnection({
  required ConnectionPhase phase,
  String? error,
  LinkPrimary? primary,
  WifiMode wifiMode = WifiMode.sta,
  bool wifiConnected = false,
  int? wifiBars,
  int? wifiRssi,
  String? wifiSsid = 'HomeNet-5G',
  String? wifiIp,
  String? passkey,
  int? wifiLastSyncS,
}) => ConnectionState(
  phase: phase,
  error: error,

  batteryPct: 82,

  primary: primary,
  bt: _link(connected: true, bars: 3, rssi: -60, lastSyncS: 3, warm: true),
  wifi: _link(
    mode: wifiMode,
    connected: wifiConnected,
    bars: wifiBars,
    rssi: wifiRssi,
    ssid: wifiSsid,
    ip: wifiIp,
    passkey: passkey,
    lastSyncS: wifiLastSyncS,
  ),
);

Scenario _staConnecting() => _scenario(
  'sta_connecting',
  'Joining home Wi-Fi (connecting…)',
  BridgeSnapshot(
    connection: _matrixConnection(phase: ConnectionPhase.connecting),
    cook: const CookState(pitBandMinF10: 2250, pitBandMaxF10: 2750),
    probes: freshProbes(),
  ),
);

Scenario _staWrongPassword() => _scenario(
  'sta_wrong_password',
  'Wi-Fi: wrong password',
  BridgeSnapshot(
    connection: _matrixConnection(
      phase: ConnectionPhase.error,
      error: 'wrong_password',
      primary: LinkPrimary.bt,
    ),
    cook: const CookState(pitBandMinF10: 2250, pitBandMaxF10: 2750),
    probes: freshProbes(),
  ),
);

Scenario _staRouterUnreachable() => _scenario(
  'sta_router_unreachable',
  'Wi-Fi: router unreachable',
  BridgeSnapshot(
    connection: _matrixConnection(
      phase: ConnectionPhase.error,
      error: 'router_unreachable',
      primary: LinkPrimary.bt,
      wifiBars: 0,
      wifiRssi: -92,
    ),
    cook: const CookState(pitBandMinF10: 2250, pitBandMaxF10: 2750),
    probes: freshProbes(),
  ),
);

Scenario _apBroadcasting() => _scenario(
  'ap_broadcasting',
  'Bridge hotspot — waiting for phone',
  BridgeSnapshot(
    connection: _matrixConnection(
      phase: ConnectionPhase.provisioning,
      primary: LinkPrimary.bt,
      wifiMode: WifiMode.ap,
      wifiSsid: 'SmokeBridge-A4F2',
      passkey: 'smoke-4471',
    ),
    cook: const CookState(pitBandMinF10: 2250, pitBandMaxF10: 2750),
    probes: freshProbes(),
  ),
);

Scenario _apJoined() => _scenario(
  'ap_joined',
  'Bridge hotspot — phone joined',
  BridgeSnapshot(
    connection: _matrixConnection(
      phase: ConnectionPhase.connected,
      primary: LinkPrimary.wifi,
      wifiMode: WifiMode.ap,
      wifiConnected: true,
      wifiSsid: 'SmokeBridge-A4F2',
      passkey: 'smoke-4471',
      wifiIp: '192.168.4.1',
      wifiBars: 4,
      wifiRssi: -40,
      wifiLastSyncS: 1,
    ),
    cook: const CookState(pitBandMinF10: 2250, pitBandMaxF10: 2750),
    probes: freshProbes(),
  ),
);

Scenario _switchRollback() => _scenario(
  'switch_rollback',
  'Mode switch failed — rolled back to BLE',
  BridgeSnapshot(
    connection: ConnectionState(
      phase: ConnectionPhase.rollback,
      error: 'switch_failed',
      batteryPct: 82,
      primary: LinkPrimary.bt,
      bt: _link(connected: true, bars: 3, rssi: -60, lastSyncS: 0),
      wifi: _link(mode: WifiMode.off),
    ),
    cook: const CookState(pitBandMinF10: 2250, pitBandMaxF10: 2750),
    probes: freshProbes(),
    notice:
        'The bridge could not join that network, so it kept Bluetooth. '
        'Nothing was lost.',
  ),
);
