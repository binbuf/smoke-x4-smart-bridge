/// N15.4 — the in-memory transport.
///
/// Retained for tests and the UX lab: it speaks the same [BridgeTransport]
/// contract as HTTP and BLE, so the connection/session stack runs unchanged
/// against it. Failure injection is explicit ([failWith]) — tests assert the
/// supervisor's failover without a real radio.
library;

import 'dart:async';

import '../../domain/domain.dart';
import 'bridge_transport.dart';

/// A callable the transport records for assertions (lane order, method use).
class TransportCall {
  const TransportCall(this.method, [this.arg]);

  final String method;
  final Object? arg;

  @override
  String toString() => 'TransportCall($method${arg == null ? '' : ', $arg'})';
}

/// One programmable device the [MockTransport] serves.
class MockBridgeDevice {
  MockBridgeDevice({
    Map<String, Object?>? status,
    LiveStatus? live,
    List<SessionInfo>? sessions,
    Map<int, List<Sample>>? samples,
    Map<int, List<Mark>>? marks,
    List<Map<String, Object?>>? alarmRules,
  }) : statusJson = status ?? defaultStatusJson(),
       liveValue = live ?? defaultLive,
       sessionsValue = sessions ?? [defaultSession],
       samplesValue = samples ?? {defaultSession.id: const <Sample>[]},
       marksValue = marks ?? {defaultSession.id: const <Mark>[]},
       alarmRules = alarmRules ?? const [];

  Map<String, Object?> statusJson;
  LiveStatus liveValue;
  List<SessionInfo> sessionsValue;
  final Map<int, List<Sample>> samplesValue;
  final Map<int, List<Mark>> marksValue;

  /// The wire `AlarmRule` array `GET /config/alarms` reports, so a test can
  /// drive the repository's device-rule read-back (N15.8).
  List<Map<String, Object?>> alarmRules;

  /// Named method-level failures: `status`, `live`, `samples`, …
  final Map<String, TransportException> failWith = {};

  /// Successive `status()` results: each entry is either a value or an error.
  /// When non-empty this queue is consumed before [statusJson] is used, which
  /// lets a test drive a flaky → healthy failover deterministically.
  final List<Object> statusPlan = [];

  static const SessionInfo defaultSession = SessionInfo(
    id: 1,
    name: 'Sim Cook',
    startedUnixMs: 1700000000000,
    endedUnixMs: null,
    samplePeriodS: 30,
    sampleCount: 3,
    numProbes: 4,
    probes: [],
    closed: false,
    pinned: false,
    markCount: 0,
  );

  static const LiveStatus defaultLive = LiveStatus(
    t: 90,
    unixMs: 1700000090000,
    unitsSource: 'F',
    billowsAttached: true,
    billowsTargetF10: null,
    probes: [
      LiveProbe(
        n: 1,
        name: 'Brisket',
        role: ProbeRole.food,
        attached: true,
        tempF10: 1642,
        alarmEnabled: false,
        targetF10: 2010,
        rateFPerHr: 4.2,
      ),
    ],
  );

  static Map<String, Object?> defaultStatusJson() => {
    'device': {
      'id': '480001',
      'model': 'sim',
      'fw': '1.4.2',
      'uptime_s': 3600,
      'free_heap': 168432,
      'min_free_heap': 141008,
      'reset_reason': 'poweron',
      'coredump_available': false,
    },
    'time': {
      'unix_ms': 1700000090000,
      'source': 'phone',
      'tz_offset_min': 0,
      'valid': true,
    },
    'net': {
      'mode': 'ap',
      'state': 'up',
      'ssid': 'SmokeBridge-A4F2',
      'rssi': -54,
      'ip': '192.168.4.1',
      'host': 'smokebridge.local',
      'ap_clients': 0,
    },
    'ble': {'advertising': true, 'connections': 0, 'bonded': 0},
    'pairing': {
      'paired': true,
      'device_id': 'X4-480001',
      'model': 'X4',
      'num_probes': 4,
      'frequency_hz': 910500000,
      'last_packet_s_ago': 8,
      'base_lost': false,
    },
    'radio': {
      'rssi': -71,
      'snr': 9,
      'packets_ok': 120,
      'packets_bad': 0,
      'id_mismatch': 0,
    },
    'storage': {
      'total_b': 2490368,
      'used_b': 214016,
      'free_pct': 91,
      'sessions': 1,
      'oldest_session_id': 1,
    },
    'power': {'mv': 3894, 'soc_pct': 71, 'charging': true, 'saver': false},
    'session': {
      'active': true,
      'id': 1,
      'name': 'Sim Cook',
      'started_unix_ms': 1700000000000,
      'elapsed_s': 90,
      'samples': 3,
    },
    'cook_clock': {'set': true, 'elapsed_s': 90},
    'ota': {'slot': 'ota_0', 'pending_verify': false, 'gate': 'not_applicable'},
    'alarms': <Object?>[],
  };

  static Map<String, Object?> defaultWifiJson() => {
    'mode': 'ap',
    'sta': {'ssid': 'HomeNet-5G', 'auth': 'wpa2_psk'},
    'ap': {
      'ssid': 'SmokeBridge-A4F2',
      'psk': 'smoke-4471',
      'ip': '192.168.4.1',
    },
  };
}

/// The programmable transport. All state lives in [device]; [calls] records
/// every method invocation.
class MockTransport implements BridgeTransport {
  MockTransport({
    MockBridgeDevice? device,
    this.kind = TransportKind.mock,
    this.label = 'mock',
  }) : device = device ?? MockBridgeDevice();

  final MockBridgeDevice device;
  @override
  final String label;
  @override
  final TransportKind kind;

  final List<TransportCall> calls = [];
  final StreamController<TransportEvent> _events =
      StreamController<TransportEvent>.broadcast();
  bool closed = false;
  int connectCount = 0;
  int statusCount = 0;

  void _record(String method, [Object? arg]) =>
      calls.add(TransportCall(method, arg));

  Never _fail(String method) {
    final e = device.failWith[method];
    throw e ?? StateError('no injected failure for $method');
  }

  void emit(TransportEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  /// Push a sample frame the way the stream would.
  void emitSample(Sample sample) => emit(
    TransportEvent('sample', {
      't': sample.t,
      'unix_ms': sample.unixMs,
      'temps_f10': sample.tempsF10,
      'flags': {'billows': sample.billows},
      'rssi': sample.rssi,
    }),
  );

  @override
  TransportCapabilities get capabilities => TransportCapabilities.mock;

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }

  @override
  Future<BridgeStatus> status() async {
    _record('status');
    statusCount++;
    if (device.failWith.containsKey('status')) {
      _fail('status');
    }
    if (device.statusPlan.isNotEmpty) {
      final next = device.statusPlan.removeAt(0);
      if (next is TransportException) {
        throw next;
      }
      if (next is Map<String, Object?>) {
        return BridgeStatus.fromJson(next);
      }
    }
    return BridgeStatus.fromJson(device.statusJson);
  }

  @override
  Future<LiveStatus> live({int windowS = 3600}) async {
    _record('live', windowS);
    if (device.failWith.containsKey('live')) {
      _fail('live');
    }
    return device.liveValue;
  }

  @override
  Future<List<SessionInfo>> sessions() async {
    _record('sessions');
    if (device.failWith.containsKey('sessions')) {
      _fail('sessions');
    }
    return List<SessionInfo>.unmodifiable(device.sessionsValue);
  }

  @override
  Future<SessionInfo> session(int sessionId) async {
    _record('session', sessionId);
    if (device.failWith.containsKey('session')) {
      _fail('session');
    }
    return device.sessionsValue.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => throw TransportException(
        'session_not_found',
        'no session $sessionId',
      ),
    );
  }

  @override
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int? toT,
    int stride = 1,
  }) async* {
    _record('samples', sessionId);
    if (device.failWith.containsKey('samples')) {
      _fail('samples');
    }
    final all = device.samplesValue[sessionId] ?? const <Sample>[];
    final selected = [
      for (final s in all)
        if (s.t >= fromT && (toT == null || s.t <= toT)) s,
    ];
    for (var i = 0; i < selected.length; i += stride < 1 ? 1 : stride) {
      yield [selected[i]];
    }
  }

  @override
  Future<List<Mark>> marks(int sessionId) async {
    _record('marks', sessionId);
    if (device.failWith.containsKey('marks')) {
      _fail('marks');
    }
    return List<Mark>.unmodifiable(
      device.marksValue[sessionId] ?? const <Mark>[],
    );
  }

  @override
  Future<Mark> postMark(
    int sessionId, {
    int? t,
    required MarkKind kind,
    int probe = 0,
    String text = '',
  }) async {
    _record('postMark', sessionId);
    if (device.failWith.containsKey('postMark')) {
      _fail('postMark');
    }
    final mark = Mark(t: t ?? 0, kind: kind, probe: probe, text: text);
    (device.marksValue[sessionId] ??= <Mark>[]).add(mark);
    return mark;
  }

  @override
  Future<Map<String, Object?>> wifiConfig() async {
    _record('wifiConfig');
    return MockBridgeDevice.defaultWifiJson();
  }

  @override
  Future<Map<String, Object?>> applyNetwork({
    required String mode,
    String? ssid,
    String? psk,
    String? user,
  }) async {
    _record('applyNetwork', mode);
    if (device.failWith.containsKey('applyNetwork')) {
      _fail('applyNetwork');
    }
    // The password is a transient argument only (N10.7).
    return {'accepted': true, 'applying_in_ms': 500, 'mode': mode};
  }

  @override
  Future<Map<String, Object?>> commitNetwork() async {
    _record('commitNetwork');
    return {'ok': true};
  }

  @override
  Future<Map<String, Object?>> deviceConfig() async {
    _record('deviceConfig');
    if (device.failWith.containsKey('deviceConfig')) {
      _fail('deviceConfig');
    }
    return {'units': 'F'};
  }

  @override
  Future<void> setDeviceConfig(Map<String, Object?> patch) async {
    _record('setDeviceConfig', patch);
  }

  @override
  Future<Map<String, Object?>> alarmConfig() async {
    _record('alarmConfig');
    return {'rules': device.alarmRules};
  }

  @override
  Future<void> setAlarmConfig(Map<String, Object?> patch) async {
    _record('setAlarmConfig', patch);
  }

  @override
  Future<void> setTime(int unixMs, {int? tzOffsetMin}) async {
    _record('setTime', unixMs);
    if (device.failWith.containsKey('setTime')) {
      _fail('setTime');
    }
  }

  @override
  Future<CookClockStatus> cookClock() async {
    _record('cookClock');
    return const CookClockStatus(set: true, elapsedS: 90);
  }

  @override
  Future<CookClockStatus> setCookClock({
    int? elapsedS,
    int? startedUnixMs,
  }) async {
    _record('setCookClock', elapsedS ?? startedUnixMs);
    return CookClockStatus(set: true, elapsedS: elapsedS ?? 0);
  }

  @override
  Future<CookClockStatus> clearCookClock() async {
    _record('clearCookClock');
    return const CookClockStatus(set: false, elapsedS: null);
  }

  @override
  Future<void> pairSync() async => _record('pairSync');

  @override
  Future<void> unpair() async => _record('unpair');

  @override
  Future<void> restart() async {
    _record('restart');
    if (device.failWith.containsKey('restart')) {
      _fail('restart');
    }
  }

  @override
  Future<void> factoryReset() async {
    _record('factoryReset');
    if (device.failWith.containsKey('factoryReset')) {
      _fail('factoryReset');
    }
  }

  @override
  Future<void> powerOff() async => _record('powerOff');

  @override
  Future<void> stopSession(int sessionId) async =>
      _record('stopSession', sessionId);

  @override
  Future<void> deleteSession(int sessionId) async =>
      _record('deleteSession', sessionId);

  @override
  Future<Map<String, Object?>> uploadOta(
    Stream<List<int>> image, {
    bool force = false,
  }) async {
    _record('uploadOta', force);
    if (device.failWith.containsKey('uploadOta')) {
      _fail('uploadOta');
    }
    var size = 0;
    await for (final chunk in image) {
      size += chunk.length;
    }
    return {'accepted': true, 'image_size_b': size, 'slot': 'ota_1'};
  }

  @override
  Stream<TransportEvent> events() => _events.stream;
}
