/// N15.1 — the `BridgeTransport` contract.
///
/// One interface, three implementations (HTTP / BLE / mock). Screens never see
/// this type: `BridgeRepository` is their seam. The transport is the *wire*,
/// the repository is the *app model*. This split is what lets N15 swap the mock
/// repository for the real one without touching a screen (D3, research notes
/// §4).
///
/// Every method returns parsed, typed values. Nothing here imports Flutter, so
/// the whole layer is in the `dart test test/data` gate. HTTP is `dart:io`
/// (not Dio — see the N15 hand-off) so the layer needs no plugin to test.
library;

import '../../domain/domain.dart';

/// Which wire the transport speaks. BLE is a distinct implementation with a
/// different capability set (research notes §4).
enum TransportKind { http, ble, mock }

/// The visible capability differences between transports (research notes §4).
///
/// A screen asks the *repository* for capability, and the repository asks the
/// active transport. Absent here means the transport throws a named
/// [TransportUnsupported]; the UI degrades through copy (I5), never a dead
/// control.
class TransportCapabilities {
  const TransportCapabilities({
    required this.live,
    required this.historyPreview,
    required this.fullHistory,
    required this.config,
    required this.probeConfig,
    required this.deviceReadBack,
    required this.alarmRules,
    required this.mqtt,
    required this.ota,
  });

  final bool live;
  final bool historyPreview;
  final bool fullHistory;
  final bool config;

  /// Probe names / roles / targets (BLE `✘`).
  final bool probeConfig;

  /// Device config read-back (BLE returns `unknown`).
  final bool deviceReadBack;

  final bool alarmRules;
  final bool mqtt;
  final bool ota;

  /// Wi-Fi HTTP: everything.
  static const TransportCapabilities http = TransportCapabilities(
    live: true,
    historyPreview: true,
    fullHistory: true,
    config: true,
    probeConfig: true,
    deviceReadBack: true,
    alarmRules: true,
    mqtt: true,
    ota: true,
  );

  /// BLE: full history only when `caps` bit 6 is set; no config surfaces.
  static const TransportCapabilities ble = TransportCapabilities(
    live: true,
    historyPreview: true,
    fullHistory: false,
    config: true,
    probeConfig: false,
    deviceReadBack: false,
    alarmRules: false,
    mqtt: false,
    ota: false,
  );

  /// The UX lab / tests: everything, like HTTP.
  static const TransportCapabilities mock = http;
}

/// A wire-level failure with a protocol error `code`, or one of the
/// app-level pseudo-codes `network` / `timeout` / `malformed` / `unsupported`.
///
/// I15: the UI never renders `toString()` — it renders [code]-driven copy.
class TransportException implements Exception {
  const TransportException(this.code, this.message, {this.detail, this.status});

  final String code;
  final String message;
  final Object? detail;
  final int? status;

  /// No response at all (DNS, refused, dropped).
  bool get isNetwork => code == 'network' || code == 'timeout';

  /// `session_active`, `ota_in_progress`, … — a device refusal, not a bug.
  bool get isDeviceRefusal =>
      code == 'session_active' ||
      code == 'ota_in_progress' ||
      code == 'busy' ||
      code == 'storage_error' ||
      code == 'radio_unavailable';

  @override
  String toString() =>
      'TransportException($code${status == null ? '' : ' · $status'}): $message';
}

/// The capability is not available on this transport (e.g. OTA over BLE).
class TransportUnsupported extends TransportException {
  const TransportUnsupported(String feature)
    : super('unsupported', 'this transport cannot $feature');
}

// ── /status ───────────────────────────────────────────────────────────────

class DeviceStatus {
  const DeviceStatus({
    required this.id,
    required this.model,
    required this.fw,
    required this.uptimeS,
    required this.freeHeap,
    required this.minFreeHeap,
    required this.resetReason,
    required this.coredumpAvailable,
  });

  final String id;
  final String model;
  final String fw;
  final int uptimeS;
  final int freeHeap;
  final int minFreeHeap;
  final String resetReason;
  final bool coredumpAvailable;

  factory DeviceStatus.fromJson(Map<String, Object?> j) => DeviceStatus(
    id: _str(j['id']) ?? 'simbridge',
    model: _str(j['model']) ?? 'X4',
    fw: _str(j['fw']) ?? '0.0.0',
    uptimeS: _int(j['uptime_s']) ?? 0,
    freeHeap: _int(j['free_heap']) ?? 0,
    minFreeHeap: _int(j['min_free_heap']) ?? 0,
    resetReason: _str(j['reset_reason']) ?? 'unknown',
    coredumpAvailable: j['coredump_available'] == true,
  );
}

class TimeStatus {
  const TimeStatus({
    required this.unixMs,
    required this.source,
    required this.tzOffsetMin,
    required this.valid,
  });

  /// Null when the bridge has no wall clock — never fabricated (I11).
  final int? unixMs;
  final String source;
  final int tzOffsetMin;
  final bool valid;

  factory TimeStatus.fromJson(Map<String, Object?> j) => TimeStatus(
    unixMs: _int(j['unix_ms']),
    source: _str(j['source']) ?? 'none',
    tzOffsetMin: _int(j['tz_offset_min']) ?? 0,
    valid: j['valid'] == true,
  );
}

class NetStatus {
  const NetStatus({
    required this.mode,
    required this.state,
    required this.ssid,
    required this.rssi,
    required this.ip,
    required this.host,
    required this.apClients,
  });

  final String mode;
  final String state;
  final String? ssid;
  final int? rssi;
  final String? ip;
  final String? host;
  final int apClients;

  factory NetStatus.fromJson(Map<String, Object?> j) => NetStatus(
    mode: _str(j['mode']) ?? 'off',
    state: _str(j['state']) ?? 'down',
    ssid: _str(j['ssid']),
    rssi: _int(j['rssi']),
    ip: _str(j['ip']),
    host: _str(j['host']),
    apClients: _int(j['ap_clients']) ?? 0,
  );
}

class BleStatus {
  const BleStatus({
    required this.advertising,
    required this.connections,
    required this.bonded,
  });

  final bool advertising;
  final int connections;
  final int bonded;

  factory BleStatus.fromJson(Map<String, Object?> j) => BleStatus(
    advertising: j['advertising'] == true,
    connections: _int(j['connections']) ?? 0,
    bonded: _int(j['bonded']) ?? 0,
  );
}

class PairingStatus {
  const PairingStatus({
    required this.paired,
    required this.deviceId,
    required this.model,
    required this.numProbes,
    required this.frequencyHz,
    required this.lastPacketSAgo,
    required this.baseLost,
  });

  final bool paired;
  final String? deviceId;
  final String? model;
  final int numProbes;
  final int? frequencyHz;
  final int? lastPacketSAgo;
  final bool baseLost;

  factory PairingStatus.fromJson(Map<String, Object?> j) => PairingStatus(
    paired: j['paired'] == true,
    deviceId: _str(j['device_id']),
    model: _str(j['model']),
    numProbes: _int(j['num_probes']) ?? 0,
    frequencyHz: _int(j['frequency_hz']),
    lastPacketSAgo: _int(j['last_packet_s_ago']),
    baseLost: j['base_lost'] == true,
  );
}

class RadioStatus {
  const RadioStatus({
    required this.rssi,
    required this.snr,
    required this.packetsOk,
    required this.packetsBad,
    required this.idMismatch,
  });

  final int rssi;
  final int snr;
  final int packetsOk;
  final int packetsBad;
  final int idMismatch;

  factory RadioStatus.fromJson(Map<String, Object?> j) => RadioStatus(
    rssi: _int(j['rssi']) ?? 0,
    snr: _int(j['snr']) ?? 0,
    packetsOk: _int(j['packets_ok']) ?? 0,
    packetsBad: _int(j['packets_bad']) ?? 0,
    idMismatch: _int(j['id_mismatch']) ?? 0,
  );
}

class StorageStatus {
  const StorageStatus({
    required this.totalB,
    required this.usedB,
    required this.freePct,
    required this.sessions,
    required this.oldestSessionId,
  });

  final int totalB;
  final int usedB;
  final int freePct;
  final int sessions;
  final int? oldestSessionId;

  factory StorageStatus.fromJson(Map<String, Object?> j) => StorageStatus(
    totalB: _int(j['total_b']) ?? 0,
    usedB: _int(j['used_b']) ?? 0,
    freePct: _int(j['free_pct']) ?? 0,
    sessions: _int(j['sessions']) ?? 0,
    oldestSessionId: _int(j['oldest_session_id']),
  );
}

class PowerStatus {
  const PowerStatus({
    required this.mv,
    required this.socPct,
    required this.charging,
    required this.saver,
  });

  final int mv;

  /// Unknown is 255 on the wire; surfaced as null here (I3).
  final int? socPct;
  final bool charging;
  final bool saver;

  factory PowerStatus.fromJson(Map<String, Object?> j) => PowerStatus(
    mv: _int(j['mv']) ?? 0,
    socPct: _soc(j['soc_pct']),
    charging: j['charging'] == true,
    saver: j['saver'] == true,
  );
}

class SessionStatus {
  const SessionStatus({
    required this.active,
    required this.id,
    required this.name,
    required this.startedUnixMs,
    required this.elapsedS,
    required this.samples,
  });

  final bool active;
  final int id;
  final String name;
  final int? startedUnixMs;
  final int elapsedS;
  final int samples;

  factory SessionStatus.fromJson(Map<String, Object?> j) => SessionStatus(
    active: j['active'] == true,
    id: _int(j['id']) ?? 0,
    name: _str(j['name']) ?? '',
    startedUnixMs: _int(j['started_unix_ms']),
    elapsedS: _int(j['elapsed_s']) ?? 0,
    samples: _int(j['samples']) ?? 0,
  );
}

class CookClockStatus {
  const CookClockStatus({required this.set, required this.elapsedS});

  /// Null when unset — never `0` (a cook that started this instant is
  /// distinct from no cook at all).
  final bool set;
  final int? elapsedS;

  factory CookClockStatus.fromJson(Map<String, Object?> j) =>
      CookClockStatus(set: j['set'] == true, elapsedS: _int(j['elapsed_s']));
}

class OtaStatus {
  const OtaStatus({
    required this.slot,
    required this.gate,
    required this.failed,
  });

  final String slot;
  final String gate;
  final String? failed;

  factory OtaStatus.fromJson(Map<String, Object?> j) => OtaStatus(
    slot: _str(j['slot']) ?? 'ota_0',
    gate: _str(j['gate']) ?? 'unknown',
    failed: _str(j['failed']),
  );
}

/// The parsed `GET /api/v1/status` payload.
class BridgeStatus {
  const BridgeStatus({
    required this.device,
    required this.time,
    required this.net,
    required this.ble,
    required this.pairing,
    required this.radio,
    required this.storage,
    required this.power,
    required this.session,
    required this.cookClock,
    required this.ota,
  });

  final DeviceStatus device;
  final TimeStatus time;
  final NetStatus net;
  final BleStatus ble;
  final PairingStatus pairing;
  final RadioStatus radio;
  final StorageStatus storage;
  final PowerStatus power;
  final SessionStatus session;
  final CookClockStatus cookClock;
  final OtaStatus ota;

  factory BridgeStatus.fromJson(Map<String, Object?> j) => BridgeStatus(
    device: DeviceStatus.fromJson(_map(j['device'])),
    time: TimeStatus.fromJson(_map(j['time'])),
    net: NetStatus.fromJson(_map(j['net'])),
    ble: BleStatus.fromJson(_map(j['ble'])),
    pairing: PairingStatus.fromJson(_map(j['pairing'])),
    radio: RadioStatus.fromJson(_map(j['radio'])),
    storage: StorageStatus.fromJson(_map(j['storage'])),
    power: PowerStatus.fromJson(_map(j['power'])),
    session: SessionStatus.fromJson(_map(j['session'])),
    cookClock: CookClockStatus.fromJson(_map(j['cook_clock'])),
    ota: OtaStatus.fromJson(_map(j['ota'])),
  );
}

// ── /live ─────────────────────────────────────────────────────────────────

class LiveProbe {
  const LiveProbe({
    required this.n,
    required this.name,
    required this.role,
    required this.attached,
    required this.tempF10,
    required this.alarmEnabled,
    required this.targetF10,
    required this.rateFPerHr,
  });

  final int n;
  final String name;
  final ProbeRole role;
  final bool attached;
  final int? tempF10;
  final bool alarmEnabled;
  final int? targetF10;
  final double? rateFPerHr;

  factory LiveProbe.fromJson(Map<String, Object?> j) => LiveProbe(
    n: _int(j['n']) ?? 0,
    name: _str(j['name']) ?? '',
    role: _role(_str(j['role'])),
    attached: j['attached'] == true,
    tempF10: _int(j['temp_f10']),
    alarmEnabled: j['alarm_enabled'] == true,
    targetF10: _int(j['target_f10']),
    rateFPerHr: _num(j['rate_f_per_hr']),
  );
}

class LiveStatus {
  const LiveStatus({
    required this.t,
    required this.unixMs,
    required this.unitsSource,
    required this.billowsAttached,
    required this.billowsTargetF10,
    required this.probes,
  });

  final int t;
  final int? unixMs;
  final String unitsSource;
  final bool billowsAttached;
  final int? billowsTargetF10;
  final List<LiveProbe> probes;

  factory LiveStatus.fromJson(Map<String, Object?> j) {
    final billows = _map(j['billows']);
    final rawProbes = j['probes'];
    return LiveStatus(
      t: _int(j['t']) ?? 0,
      unixMs: _int(j['unix_ms']),
      unitsSource: _str(j['units_source']) ?? 'F',
      billowsAttached: billows['attached'] == true,
      billowsTargetF10: _int(billows['target_f10']),
      probes: [
        for (final p in rawProbes is List ? rawProbes : const [])
          LiveProbe.fromJson(_map(p)),
      ],
    );
  }
}

// ── /sessions ─────────────────────────────────────────────────────────────

class SessionProbe {
  const SessionProbe({
    required this.n,
    required this.name,
    required this.role,
    required this.targetF10,
  });

  final int n;
  final String name;
  final ProbeRole role;
  final int? targetF10;

  factory SessionProbe.fromJson(Map<String, Object?> j) => SessionProbe(
    n: _int(j['n']) ?? 0,
    name: _str(j['name']) ?? '',
    role: _role(_str(j['role'])),
    targetF10: _int(j['target_f10']),
  );
}

class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.name,
    required this.startedUnixMs,
    required this.endedUnixMs,
    required this.samplePeriodS,
    required this.sampleCount,
    required this.numProbes,
    required this.probes,
    required this.closed,
    required this.pinned,
    required this.markCount,
  });

  final int id;
  final String name;

  /// Null when the bridge has no clock (I11).
  final int? startedUnixMs;
  final int? endedUnixMs;

  final int samplePeriodS;
  final int sampleCount;
  final int numProbes;
  final List<SessionProbe> probes;
  final bool closed;
  final bool pinned;
  final int markCount;

  factory SessionInfo.fromJson(Map<String, Object?> j) => SessionInfo(
    id: _int(j['id']) ?? 0,
    name: _str(j['name']) ?? '',
    startedUnixMs: _int(j['started_unix_ms']),
    endedUnixMs: _int(j['ended_unix_ms']),
    samplePeriodS: _int(j['sample_period_s']) ?? 30,
    sampleCount: _int(j['sample_count']) ?? 0,
    numProbes: _int(j['num_probes']) ?? 4,
    probes: [
      for (final p in j['probes'] is List ? j['probes']! as List : const [])
        SessionProbe.fromJson(_map(p)),
    ],
    closed: j['closed'] == true,
    pinned: j['pinned'] == true,
    markCount: _int(j['mark_count']) ?? 0,
  );
}

// ── stream events ─────────────────────────────────────────────────────────

/// One server→client frame from `/api/v1/stream` (or the BLE notify path).
///
/// Kept generic on purpose: the frame's `type` selects the topic, and the
/// typed accessors below are the only place that knows a frame's shape. An
/// unknown `type` is ignored rather than fatal (forward compatibility).
class TransportEvent {
  const TransportEvent(this.type, this.data);

  final String type;
  final Map<String, Object?> data;

  String? get action => _str(data['action']);
  int? get sessionId => _int(data['id']);
  int? get unixMs => _int(data['unix_ms']);
  int? get pct => _int(data['pct']);
  bool? get paired => data['paired'] is bool ? data['paired'] as bool : null;

  /// Parses a `sample` frame (also used by the WS push and BLE notify).
  Sample toSample() {
    final raw = data['temps_f10'];
    final temps = <int?>[null, null, null, null];
    if (raw is List) {
      for (var i = 0; i < 4 && i < raw.length; i++) {
        temps[i] = _int(raw[i]);
      }
    }
    // Some frames carry a single-probe `temp_f10`; fold it into the jack.
    final single = _int(data['temp_f10']);
    final singleN = _int(data['probe']);
    if (single != null && singleN != null && singleN >= 1 && singleN <= 4) {
      temps[singleN - 1] = single;
    }
    final flags = _map(data['flags']);
    return Sample(
      t: _int(data['t']) ?? 0,
      tempsF10: temps,
      unixMs: _int(data['unix_ms']),
      billows: flags['billows'] == true || data['billows'] == true,
      newAlarm: flags['new_alarm'] == true,
      rssi: _int(data['rssi']) ?? 0,
    );
  }

  factory TransportEvent.fromJson(Object? frame) {
    final j = _map(frame);
    return TransportEvent(_str(j['type']) ?? 'unknown', j);
  }
}

/// The streams a transport exposes. `GET /sessions/{id}/samples` may be
/// streamed in batches ([samples]) and is idempotent on `(session, t)` (I10).
abstract interface class BridgeTransport {
  TransportKind get kind;
  TransportCapabilities get capabilities;

  /// A stable label for logs/UI (`192.168.4.1`, `BLE`, …).
  String get label;

  /// Release sockets. Idempotent.
  Future<void> close();

  /// `GET /status` — the lane probe and the source of identity/power/session.
  Future<BridgeStatus> status();

  /// `GET /live` — current readings and the recent window.
  Future<LiveStatus> live({int windowS});

  /// `GET /sessions`.
  Future<List<SessionInfo>> sessions();

  /// `GET /sessions/{id}`.
  Future<SessionInfo> session(int sessionId);

  /// `GET /sessions/{id}/samples` streamed in batches.
  ///
  /// [fromT] and [toT] are seconds into the session; [stride] decimates.
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT,
    int? toT,
    int stride,
  });

  /// `GET /sessions/{id}/marks`.
  Future<List<Mark>> marks(int sessionId);

  /// `POST /sessions/{id}/marks`.
  Future<Mark> postMark(
    int sessionId, {
    int? t,
    required MarkKind kind,
    int probe,
    String text,
  });

  /// `GET /config/wifi`.
  Future<Map<String, Object?>> wifiConfig();

  /// `POST /config/wifi` (the deferred reconfigure; answers before applying).
  Future<Map<String, Object?>> applyNetwork({
    required String mode,
    String? ssid,
    String? psk,
    String? user,
  });

  /// `POST /config/wifi/commit` — cancel the pending revert (N10.7).
  Future<Map<String, Object?>> commitNetwork();

  /// `GET/POST /config/device`.
  Future<Map<String, Object?>> deviceConfig();
  Future<void> setDeviceConfig(Map<String, Object?> patch);

  /// `GET/POST /config/alarms`.
  Future<Map<String, Object?>> alarmConfig();
  Future<void> setAlarmConfig(Map<String, Object?> patch);

  /// `POST /time`.
  Future<void> setTime(int unixMs, {int? tzOffsetMin});

  /// `GET /cook-clock`.
  Future<CookClockStatus> cookClock();

  /// `POST /cook-clock` — exactly one of [elapsedS]/[startedUnixMs].
  Future<CookClockStatus> setCookClock({int? elapsedS, int? startedUnixMs});

  /// `DELETE /cook-clock`.
  Future<CookClockStatus> clearCookClock();

  /// `POST /pairing/sync` / `POST /pairing/unpair`.
  Future<void> pairSync();
  Future<void> unpair();

  /// `POST /restart`, `POST /factory-reset`, `POST /power-off`.
  Future<void> restart();
  Future<void> factoryReset();
  Future<void> powerOff();

  /// `POST /sessions/{id}/stop` and `DELETE /sessions/{id}`.
  Future<void> stopSession(int sessionId);
  Future<void> deleteSession(int sessionId);

  /// `POST /ota` (`force=1`).
  Future<Map<String, Object?>> uploadOta(Stream<List<int>> image, {bool force});

  /// Server→client frames. HTTP uses `/api/v1/stream`; BLE maps its notify
  /// characteristics onto the same event vocabulary. A transport that cannot
  /// stream yields an empty stream.
  Stream<TransportEvent> events();
}

// ── parse helpers ─────────────────────────────────────────────────────────

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

String? _str(Object? value) => value is String ? value : null;

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

double? _num(Object? value) => value is num ? value.toDouble() : null;

int? _soc(Object? value) {
  final v = _int(value);
  return v == null || v == 255 ? null : v;
}

ProbeRole _role(String? name) => switch (name) {
  'pit' => ProbeRole.pit,
  'food' => ProbeRole.food,
  'ambient' => ProbeRole.ambient,
  _ => ProbeRole.unused,
};
