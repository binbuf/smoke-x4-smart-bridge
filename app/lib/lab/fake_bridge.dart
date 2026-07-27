/// A23.5 — the hardware-free fakes that drive [SetupMachine] (design 13 §13.2,
/// §13.5.1; the seam discipline of `features/onboarding/wizard.dart`).
///
/// WHY this file exists: the whole guided-setup flow is a pure state machine
/// over five injected seams (`BleGattClient`, `BleTransport`, `PreflightProbe`,
/// `BaseListenSeam`, plus the `HandoffVerifier`/`ApJoiner`/`SetupDelay`
/// closures). That is exactly what lets the ~34 states be reviewed in Chrome
/// and asserted in a unit test with **no radio, no bridge, no Smoke X, no
/// board**. This file supplies scriptable fakes for every one of those seams,
/// so a scenario — "one bridge, correct passkey, base pairs, Wi-Fi joins" or a
/// named failure — becomes plain data, not a mock ceremony.
///
/// Two timing concerns are kept apart, and both flow through this file rather
/// than any real wall clock (the test's rule: "no real timers beyond the
/// injected delay"):
///
///  * **budgets/timeouts** — the machine's `SetupDelay` seam. A budget firing
///    is what turns a silent listen window into `timeout_no_beacon`. Injected
///    as [LabClock.budget]. In [LabClock.manual] a budget is a bare completer
///    the test fires with [LabClock.fireBudgets]; in [LabClock.real] it fires
///    on a capped real delay so a timeout stays reviewable, never 120 s away.
///  * **scripted event pacing** — how fast advertisements, base snapshots,
///    scan results and `net_status` frames arrive. Injected as [LabClock.tick]:
///    a microtask in manual mode (timer-free and deterministic), a short real
///    delay in the lab so a reviewer watches the flow move.
///
/// The fake [BleTransport] is a real subclass with its methods overridden — the
/// machine's field is the concrete `BleTransport`, so a scriptable one *is* a
/// `BleTransport`, and every wire type it returns is the genuine `records.g`
/// record the app decodes on device.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../data/dto/records.g.dart' as dto;
import '../data/transport/ble_gatt.dart';
import '../data/transport/ble_transport.dart';
import '../data/transport/bridge_transport.dart' show ControlCommand;
import '../features/setup/preflight.dart';
import '../features/setup/setup_machine.dart';

// ════════════════════════════════════════════════════════════════════════
//  The clock: budgets vs. event pacing, both timer-free in manual mode.
// ════════════════════════════════════════════════════════════════════════

/// The single injected clock. [budget] backs the machine's `SetupDelay`
/// (timeouts); [tick] paces the fakes' scripted events. Kept in one object so
/// a scenario runs the same code path in the lab (real, capped delays) and in
/// a test (manual, microtask-only — no real timers).
class LabClock {
  LabClock._(this._manual, this._budgetCapMs, this._paceMs);

  /// Deterministic, timer-free. Budgets never fire on their own; a test calls
  /// [fireBudgets] to force a timeout. Events pace on microtasks.
  factory LabClock.manual() => LabClock._(true, 0, 0);

  /// Real delays for the interactive lab. Budgets fire on a *capped* delay so a
  /// 120 s listen budget still surfaces its timeout within `budgetCapMs`.
  factory LabClock.real({int budgetCapMs = 3500, int paceMs = 420}) =>
      LabClock._(false, budgetCapMs, paceMs);

  final bool _manual;
  final int _budgetCapMs;
  final int _paceMs;
  final _pending = <Completer<void>>[];

  bool get isManual => _manual;

  /// The machine's `SetupDelay`. A budget represents "give up after d".
  Future<void> budget(Duration d) {
    if (_manual) {
      final c = Completer<void>();
      _pending.add(c);
      return c.future;
    }
    final ms = d.inMilliseconds.clamp(0, _budgetCapMs);
    return Future<void>.delayed(Duration(milliseconds: ms));
  }

  /// The fakes' event pacing. Timer-free in manual mode.
  Future<void> tick() {
    if (_manual) {
      return Future<void>.microtask(() {});
    }
    return Future<void>.delayed(Duration(milliseconds: _paceMs));
  }

  /// Test control: fire every pending budget, forcing all in-flight timeouts.
  void fireBudgets() {
    final due = List.of(_pending);
    _pending.clear();
    for (final c in due) {
      if (!c.isCompleted) {
        c.complete();
      }
    }
  }
}

// ════════════════════════════════════════════════════════════════════════
//  The script — a scenario as plain data.
// ════════════════════════════════════════════════════════════════════════

/// One advertisement the scan should surface (before any connection exists).
class FakeAdv {
  const FakeAdv({required this.deviceId, required this.name, this.rssi = -52});
  final String deviceId;
  final String name;
  final int rssi;
}

/// One Wi-Fi network the AP scan should report.
class FakeNetwork {
  const FakeNetwork({
    required this.ssid,
    this.auth = 3,
    this.rssi = -55,
    this.channel = 6,
  });
  final String ssid;
  final int auth;
  final int rssi;
  final int channel;
}

/// What one `applyWifiConfig` call does, consumed in order across retries so a
/// "wrong password, then correct" recovery is expressible as two outcomes.
enum ApplyResult {
  /// `net_status: up` with an address — the join succeeded.
  up,

  /// `net_status: failed` — classified (default `wrongPassword`).
  failed,

  /// The write itself was refused (`BridgeControlException`) → `assocRefused`.
  refused,

  /// The write ACKed but no result frame ever came (`TimeoutException`).
  timeout,
}

/// A scripted `applyWifiConfig` outcome plus the address it reports on success.
class ApplyOutcome {
  const ApplyOutcome(this.result, {this.ip = const [192, 168, 1, 50]});
  final ApplyResult result;
  final List<int> ip;
}

/// A whole scenario. Every field has a happy-path default, so a failure script
/// overrides only the one seam that misbehaves.
class SetupScript {
  const SetupScript({
    required this.id,
    required this.title,
    required this.blurb,
    this.adapter = SetupAdapterState.on,
    this.permission = PreflightPermission.granted,
    this.permissionAfterPrompt = PreflightPermission.granted,
    this.needsLocation = false,
    this.locationOn = true,
    this.bridges = const [
      FakeAdv(deviceId: 'AA:BB:CC:DD:EE:01', name: 'SmokeBridge-A4F2'),
    ],
    this.connectError,
    this.bondError,
    this.numProbes = 2,
    this.bridgeId = 'A4F2',
    this.baseSnapshots = _happyBaseSnapshots,
    this.networks = const [
      FakeNetwork(ssid: 'Homestead', auth: 3, rssi: -47),
      FakeNetwork(ssid: 'Homestead 5G', auth: 3, rssi: -61),
      FakeNetwork(ssid: 'Backyard Guest', auth: 0, rssi: -70),
    ],
    this.applyOutcomes = const [ApplyOutcome(ApplyResult.up)],
    this.verifyReachable = true,
    this.hostedJoinOk = true,
    this.hostedPsk = 'ember-4821',
  });

  /// Stable key for the picker and [scriptById].
  final String id;

  /// Human label for the lab's script chips.
  final String title;

  /// One line describing what the scenario exercises.
  final String blurb;

  // preflight (hop 0)
  final SetupAdapterState adapter;
  final PreflightPermission permission;
  final PreflightPermission permissionAfterPrompt;
  final bool needsLocation;
  final bool locationOn;

  // hop 1 — find + pair
  final List<FakeAdv> bridges;
  final BleException? connectError;
  final BleException? bondError;
  final int numProbes;
  final String bridgeId;

  // hop 2 — base listen. An empty list = a silent window (drive a timeout by
  // firing the listen budget).
  final List<BasePairSnapshot> baseSnapshots;

  // hop 3 — network
  final List<FakeNetwork> networks;
  final List<ApplyOutcome> applyOutcomes;
  final bool verifyReachable;
  final bool hostedJoinOk;
  final String hostedPsk;

  String get hostedSsid => 'SmokeBridge-$bridgeId';
}

/// The happy hop-2 arc: heard, then a real reading on two probes.
const List<BasePairSnapshot> _happyBaseSnapshots = [
  BasePairSnapshot(state: BasePairState.listening),
  BasePairSnapshot(state: BasePairState.heard, deviceId: 'A4F2'),
  BasePairSnapshot(
    state: BasePairState.confirmed,
    deviceId: 'A4F2',
    numProbes: 2,
    temps: [1650, 1720, null, null],
  ),
];

/// The scenarios the lab offers and the test drives. Happy path first.
const List<SetupScript> labSetupScripts = [
  SetupScript(
    id: 'happy',
    title: 'Happy path',
    blurb:
        'One bridge, correct passkey, base pairs in a beat, Wi-Fi joins — all '
        'three hops to the finish line.',
  ),
  SetupScript(
    id: 'permission-primer',
    title: 'Permission primer',
    blurb:
        'A first-run phone: the rationale primer precedes the OS prompt, then '
        'permission is granted and the flow proceeds.',
    permission: PreflightPermission.denied,
  ),
  SetupScript(
    id: 'no-bridges',
    title: 'No bridges',
    blurb: 'The scan hears nothing for its whole window — the checklist state.',
    bridges: [],
  ),
  SetupScript(
    id: 'wrong-passkey',
    title: 'Wrong passkey',
    blurb: 'The bond is rejected — the retry-choreography state, not a crash.',
    bondError: BleBondRejectedException(),
  ),
  SetupScript(
    id: 'base-timeout',
    title: 'Base never heard',
    blurb:
        'The listen window stays silent; firing the budget surfaces '
        'timeout_no_beacon rather than an endless spinner.',
    baseSnapshots: [],
  ),
  SetupScript(
    id: 'wifi-wrong-password',
    title: 'Wi-Fi wrong password → recover',
    blurb:
        'The first join fails with a stated reason; a corrected password on '
        'the prefilled field then joins.',
    applyOutcomes: [
      ApplyOutcome(ApplyResult.failed),
      ApplyOutcome(ApplyResult.up),
    ],
  ),
  SetupScript(
    id: 'hosted-fallback',
    title: 'No networks → hosted',
    blurb:
        'The AP scan is empty, so hosted mode becomes the primary and the '
        'bridge hosts its own network.',
    networks: [],
  ),
];

/// The script with [id], or the first (happy) script when unknown.
SetupScript scriptById(String id) => labSetupScripts.firstWhere(
  (s) => s.id == id,
  orElse: () => labSetupScripts.first,
);

// ════════════════════════════════════════════════════════════════════════
//  The facade — builds every seam and the wired machine for one script.
// ════════════════════════════════════════════════════════════════════════

/// Wires a [SetupScript] into a live [SetupMachine] over fakes. The lab holds
/// one per selected script; a test builds one per case and disposes it.
class FakeBridge {
  FakeBridge(this.script, {LabClock? clock})
    : clock = clock ?? LabClock.real() {
    _client = _FakeGattClient(script, this.clock);
    _transport = _FakeBleTransport(_client, script, this.clock);
    _probe = _FakeProbe(script);
    _listen = _FakeListen(script, this.clock);
    machine = SetupMachine(
      transport: _transport,
      client: _client,
      probe: _probe,
      listen: _listen,
      verify: (ip) async {
        await this.clock.tick();
        return script.verifyReachable ? 'http://${ip ?? '192.168.4.1'}' : null;
      },
      joinAp: (ssid, psk) async {
        await this.clock.tick();
        return script.hostedJoinOk;
      },
      delay: this.clock.budget,
    );
  }

  final SetupScript script;
  final LabClock clock;

  late final _FakeGattClient _client;
  late final _FakeBleTransport _transport;
  late final _FakeProbe _probe;
  late final _FakeListen _listen;
  late final SetupMachine machine;

  Future<void> dispose() async {
    await machine.dispose();
    await _transport.shutdown();
    await _client.dispose();
    await _probe.dispose();
    await _listen.dispose();
  }
}

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

// ── the fake GATT client (hop 1's radio) ────────────────────────────────

class _FakeGattClient implements BleGattClient {
  _FakeGattClient(this._script, this._clock);

  final SetupScript _script;
  final LabClock _clock;

  final _conn = StreamController<BleConnectionState>.broadcast();
  final _bond = StreamController<BleBondState>.broadcast();
  BleConnectionState _connState = BleConnectionState.disconnected;
  BleBondState _bondState = BleBondState.none;
  bool _scanStopped = false;
  int _mtu = 23;

  @override
  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    _scanStopped = false;
    for (final a in _script.bridges) {
      await _clock.tick();
      if (_scanStopped) {
        return;
      }
      yield BleAdvertisement(deviceId: a.deviceId, name: a.name, rssi: a.rssi);
    }
  }

  @override
  Future<void> stopScan() async {
    _scanStopped = true;
  }

  @override
  BleConnectionState get connectionState => _connState;

  @override
  Stream<BleConnectionState> get connectionStates => _conn.stream;

  @override
  Future<void> connect(String deviceId) async {
    await _clock.tick();
    final err = _script.connectError;
    if (err != null) {
      throw err;
    }
    _connState = BleConnectionState.connected;
    if (!_conn.isClosed) {
      _conn.add(_connState);
    }
  }

  @override
  Future<void> disconnect() async {
    // Deliberately silent: a scripted rebond disconnects on purpose, and
    // emitting `disconnected` here would trip the machine's link-lost watcher.
    _connState = BleConnectionState.disconnected;
  }

  @override
  BleBondState get bondState => _bondState;

  @override
  Stream<BleBondState> get bondStates => _bond.stream;

  @override
  Future<void> bond() async {
    await _clock.tick();
    final err = _script.bondError;
    if (err != null) {
      throw err;
    }
    _bondState = BleBondState.bonded;
    if (!_bond.isClosed) {
      _bond.add(_bondState);
    }
  }

  @override
  Future<void> removeBond() async {
    await _clock.tick();
    _bondState = BleBondState.none;
    if (!_bond.isClosed) {
      _bond.add(_bondState);
    }
  }

  @override
  Future<int> requestMtu(int mtu) async {
    _mtu = mtu;
    return mtu;
  }

  @override
  int get mtu => _mtu;

  @override
  Future<Uint8List> read(int slot) async => Uint8List(0);

  @override
  Future<void> write(int slot, Uint8List value) async {}

  @override
  Stream<Uint8List> subscribe(int slot) => const Stream.empty();

  @override
  Future<void> dispose() async {
    await _conn.close();
    await _bond.close();
  }
}

// ── the fake transport (hops 2/3 answers, as genuine wire records) ──────

class _FakeBleTransport extends BleTransport {
  _FakeBleTransport(super.client, this._script, this._clock);

  final SetupScript _script;
  final LabClock _clock;

  final _net = StreamController<dto.NetStatus>.broadcast();
  final _scan = StreamController<dto.WifiScanResult>.broadcast();
  int _applyIdx = 0;
  dto.NetStatus? _lastNet;

  @override
  Future<void> start() async {}

  @override
  Stream<dto.NetStatus> get netStatus => _net.stream;

  @override
  Stream<dto.WifiScanResult> get scanResults => _scan.stream;

  @override
  Future<dto.DeviceInfo> deviceInfo() async {
    await _clock.tick();
    return dto.DeviceInfo(
      probes: _script.numProbes,
      idRaw: _bytes(_script.bridgeId),
      modelRaw: _bytes('Smoke Bridge'),
      fwRaw: _bytes('1.0.0'),
    );
  }

  @override
  Future<dto.NetStatus> readNetStatus() async {
    await _clock.tick();
    return _lastNet ?? dto.NetStatus();
  }

  @override
  Future<void> control(ControlCommand cmd) async {
    await _clock.tick();
  }

  @override
  Future<void> startWifiScan() async {
    await _clock.tick();
    final nets = _script.networks;
    for (var i = 0; i < nets.length; i++) {
      if (_scan.isClosed) {
        return;
      }
      final n = nets[i];
      _scan.add(
        dto.WifiScanResult(
          index: i,
          total: nets.length,
          rssi: n.rssi,
          auth: n.auth,
          channel: n.channel,
          ssidRaw: _bytes(n.ssid),
        ),
      );
    }
  }

  @override
  Future<dto.ResultFrame> applyWifiConfig({
    required dto.NetMode mode,
    String ssid = '',
    String psk = '',
    String user = '',
    int auth = 3,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await _clock.tick();
    if (mode == dto.NetMode.ap) {
      _scheduleNet(
        dto.NetStatus(
          mode: dto.NetMode.ap.wire,
          state: dto.NetState.up.wire,
          ssidRaw: _bytes(_script.hostedSsid),
        ),
      );
      return dto.ResultFrame(
        status: dto.ResultStatus.ok.wire,
        detailRaw: _bytes(_script.hostedPsk),
      );
    }
    final outcome = _nextApply();
    switch (outcome.result) {
      case ApplyResult.refused:
        throw const BridgeControlException(dto.ResultStatus.failed);
      case ApplyResult.timeout:
        throw TimeoutException('no result frame');
      case ApplyResult.failed:
        _scheduleNet(
          dto.NetStatus(
            mode: dto.NetMode.sta.wire,
            state: dto.NetState.failed.wire,
            ssidRaw: _bytes(ssid),
          ),
        );
      case ApplyResult.up:
        _scheduleNet(
          dto.NetStatus(
            mode: dto.NetMode.sta.wire,
            state: dto.NetState.up.wire,
            ip: outcome.ip,
            ssidRaw: _bytes(ssid),
          ),
        );
    }
    return dto.ResultFrame(status: dto.ResultStatus.ok.wire);
  }

  ApplyOutcome _nextApply() {
    final outcomes = _script.applyOutcomes;
    if (outcomes.isEmpty) {
      return const ApplyOutcome(ApplyResult.up);
    }
    final o = _applyIdx < outcomes.length ? outcomes[_applyIdx] : outcomes.last;
    _applyIdx++;
    return o;
  }

  /// Emit the `net_status` notify one tick *after* the write returns, so it
  /// lands on the machine's already-attached watcher rather than being missed.
  void _scheduleNet(dto.NetStatus ns) {
    _lastNet = ns;
    unawaited(
      _clock.tick().then((_) {
        if (!_net.isClosed) {
          _net.add(ns);
        }
      }),
    );
  }

  Future<void> shutdown() async {
    await _net.close();
    await _scan.close();
  }
}

// ── the fake preflight probe (hop 0) ────────────────────────────────────

class _FakeProbe implements PreflightProbe {
  _FakeProbe(this._script);

  final SetupScript _script;
  final _adapter = StreamController<SetupAdapterState>.broadcast();

  @override
  SetupAdapterState get adapterStateNow => _script.adapter;

  @override
  Stream<SetupAdapterState> get adapterStates => _adapter.stream;

  @override
  Future<void> requestEnable() async {}

  @override
  bool get needsLocationServices => _script.needsLocation;

  @override
  Future<bool> isLocationServicesOn() async => _script.locationOn;

  @override
  Future<PreflightPermission> permissionStatus() async => _script.permission;

  @override
  Future<PreflightPermission> requestPermissions() async =>
      _script.permissionAfterPrompt;

  Future<void> dispose() async {
    await _adapter.close();
  }
}

// ── the fake base-listen seam (hop 2) ───────────────────────────────────

class _FakeListen implements BaseListenSeam {
  _FakeListen(this._script, this._clock);

  final SetupScript _script;
  final LabClock _clock;
  final _updates = StreamController<BasePairSnapshot>.broadcast();
  bool _cancelled = false;

  @override
  Stream<BasePairSnapshot> get updates => _updates.stream;

  @override
  Future<void> startListen({required Duration window}) async {
    _cancelled = false;
    await _clock.tick();
    unawaited(_emit());
  }

  Future<void> _emit() async {
    for (final snap in _script.baseSnapshots) {
      await _clock.tick();
      if (_cancelled || _updates.isClosed) {
        return;
      }
      _updates.add(snap);
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  Future<void> dispose() async {
    await _updates.close();
  }
}
