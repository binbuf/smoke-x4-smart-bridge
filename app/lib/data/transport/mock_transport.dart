/// A3.3 — the deterministic fixture-backed transport.
///
/// Backed by a `.smk` fixture (cookgen output or a real capture). Replays
/// the cook through the same [BridgeTransport] surface the HTTP and BLE
/// transports implement, so repository and widget tests run full 18-hour
/// cooks in milliseconds with no network anywhere.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../domain/entities/entities.dart';
import 'bridge_transport.dart';
import 'wire_reader.dart';

class MockTransport implements BridgeTransport {
  MockTransport.fromSmkBytes(
    Uint8List smkBytes, {
    Uint8List? mrkBytes,
    this.replayPeriod = Duration.zero,
  }) : _archive = SmkArchive.parse(smkBytes),
       _marks = mrkBytes != null ? marksFromBytes(mrkBytes) : const <Mark>[];

  final SmkArchive _archive;
  final List<Mark> _marks;

  /// Delay between replayed samples on [events]. Zero = as fast as the
  /// event loop drains (deterministic, instant in tests).
  final Duration replayPeriod;

  final List<ControlCommand> controlLog = [];
  final List<BridgeConfig> configureLog = [];
  bool _closed = false;

  /// The device's probe configuration, as `/live` would report it (06
  /// §6.2). Defaults to the convention every X4 owner already uses and
  /// the OLED already assumes — **jack 1 is the pit** — so a dashboard
  /// test does not have to configure one to have a headline tile.
  List<Probe> probeConfig = [
    const Probe(n: 1, name: 'Pit', role: ProbeRole.pit),
    const Probe(n: 2, name: 'Food 1', role: ProbeRole.food),
    const Probe(n: 3, name: 'Food 2', role: ProbeRole.food),
    const Probe(n: 4, name: 'Food 3', role: ProbeRole.food),
  ];

  List<Mark> get marks => List.unmodifiable(_marks);

  @override
  BridgeCapabilities get capabilities => const BridgeCapabilities(
    liveState: true,
    fullHistory: true,
    historyPreview: true,
    config: true,
    ota: false,
    mqtt: true,
  );

  @override
  Stream<BridgeEvent> get events async* {
    for (final rec in _archive.toSamples()) {
      if (_closed) {
        return;
      }
      if (replayPeriod != Duration.zero) {
        await Future<void>.delayed(replayPeriod);
      }
      yield BridgeEvent.sample(rec);
    }
    yield BridgeEvent.session(
      action: SessionAction.ended,
      sessionId: _archive.header.sessionId,
    );
  }

  @override
  Future<BridgeStatus> status() async {
    final h = _archive.header;
    return BridgeStatus(
      deviceId: h.deviceId,
      model: 'mock',
      fw: '0.0.0-mock',
      uptimeS: _archive.records.isEmpty ? 0 : _archive.records.last.t,
      paired: true,
      numProbes: h.numProbes,
      lastPacketSAgo: 0,
      sessionActive: !h.closed,
      activeSessionId: h.closed ? null : h.sessionId,
      storageFreePct: 91,
      socPct: 71,
      charging: false,
    );
  }

  @override
  Future<LiveState> live({Duration window = const Duration(hours: 1)}) async {
    final samples = _archive.toSamples();
    if (samples.isEmpty) {
      return LiveState(
        t: 0,
        tempsF10: const [null, null, null, null],
        probes: probeConfig,
      );
    }
    final last = samples.last;
    final fromT = last.t - window.inSeconds;
    return LiveState(
      t: last.t,
      unixMs: _archive.header.clockValid
          ? _archive.header.startedUnixMs + last.t * 1000
          : null,
      tempsF10: last.tempsF10,
      billows: last.billows,
      recent: [
        for (final s in samples)
          if (s.t > fromT) s,
      ],
      probes: probeConfig,
    );
  }

  @override
  Future<List<CookSession>> sessions() async => [_archive.toSession()];

  @override
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int? toT,
    int? bucketS,
  }) async* {
    if (sessionId != _archive.header.sessionId) {
      throw StateError('session_not_found: $sessionId');
    }
    const batch = 500;
    var pending = <Sample>[];
    for (final s in _archive.toSamples()) {
      if (s.t < fromT || (toT != null && s.t > toT)) {
        continue;
      }
      pending.add(s);
      if (pending.length == batch) {
        yield pending;
        pending = <Sample>[];
      }
    }
    if (pending.isNotEmpty) {
      yield pending;
    }
  }

  @override
  Future<void> control(ControlCommand cmd) async {
    controlLog.add(cmd);
  }

  @override
  Future<void> configure(BridgeConfig cfg) async {
    configureLog.add(cfg);
    if (cfg.probes != null) {
      probeConfig = List.of(cfg.probes!)..sort((a, b) => a.n.compareTo(b.n));
    }
  }

  /// Recorded like every other write. A switch to AP answers with a fixed
  /// PSK so a test can assert the screen shows the key back to the user.
  final List<({NetworkMode mode, String ssid, String psk})> networkLog = [];

  @override
  Future<String> applyNetwork({
    required NetworkMode mode,
    String ssid = '',
    String psk = '',
  }) async {
    networkLog.add((mode: mode, ssid: ssid, psk: psk));
    return mode == NetworkMode.ap ? 'MockApPsk1' : '';
  }

  @override
  Future<void> uploadFirmware(
    Stream<List<int>> image, {
    required int lengthBytes,
    bool force = false,
  }) async {
    // The mock has no OTA (capabilities.ota is false); a call here is a
    // wiring bug the analyzer cannot see, so surface it loudly.
    throw UnsupportedError('MockTransport does not do OTA');
  }

  /// In-memory MQTT config, recorded like every other write so the settings
  /// page and the contract suite can drive it with no broker.
  MqttConfig mqtt = const MqttConfig();

  @override
  Future<MqttConfig> mqttConfig() async => mqtt;

  @override
  Future<void> setMqttConfig({
    bool? enabled,
    String? host,
    int? port,
    String? user,
    String? password,
    String? prefix,
    bool? haDiscovery,
  }) async {
    mqtt = MqttConfig(
      enabled: enabled ?? mqtt.enabled,
      host: host ?? mqtt.host,
      port: port ?? mqtt.port,
      user: user ?? mqtt.user,
      prefix: prefix ?? mqtt.prefix,
      haDiscovery: haDiscovery ?? mqtt.haDiscovery,
      // The password is write-only; the mock just accepts and forgets it, and
      // "connected" reflects whether it is enabled with a host.
      connected: (enabled ?? mqtt.enabled) && (host ?? mqtt.host).isNotEmpty,
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
