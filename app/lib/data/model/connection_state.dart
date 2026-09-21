/// N2.15 — the dual-link connection model.
///
/// `bt` and `wifi` are independent links with their own health; [primary] says
/// which one is carrying data right now. Wi-Fi additionally has a [WifiMode]
/// (`off` / `ap` / `sta`). The appbar chip, the connection sheet, Settings and
/// the provisioning flows all read this one model.
library;

/// The connection phase — `connected | connecting | offline | provisioning |
/// rollback | error`.
enum ConnectionPhase {
  connected,
  connecting,
  offline,
  provisioning,
  rollback,
  error;

  bool get isBusy =>
      this == ConnectionPhase.connecting ||
      this == ConnectionPhase.provisioning;

  bool get hasError => this == ConnectionPhase.error;
}

/// Which link currently carries data.
enum LinkPrimary { bt, wifi }

/// Wi-Fi mode: `off`, the bridge's own AP, or station on a home network.
enum WifiMode { off, ap, sta }

/// One link's health. Every measurement is nullable: unknown is not zero.
class LinkState {
  const LinkState({
    this.available = true,
    this.connected = false,
    this.mode,
    this.bars,
    this.rssi,
    this.lastSyncS,
    this.warm = false,
    this.ssid,
    this.ip,
    this.passkey,
  });

  /// Whether the radio exists on this bridge.
  final bool available;

  final bool connected;
  final WifiMode? mode;

  /// Signal bars 0..4, or null when unknown.
  final int? bars;

  /// RSSI in dBm, or null.
  final int? rssi;

  /// Seconds since the last packet, or null.
  final int? lastSyncS;

  /// BLE kept warm while Wi-Fi carries data, for fast failover.
  final bool warm;

  final String? ssid;
  final String? ip;

  /// The AP passkey shown while the bridge broadcasts its own network.
  final String? passkey;

  LinkState copyWith({
    bool? available,
    bool? connected,
    Object? mode = _sentinel,
    Object? bars = _sentinel,
    Object? rssi = _sentinel,
    Object? lastSyncS = _sentinel,
    bool? warm,
    Object? ssid = _sentinel,
    Object? ip = _sentinel,
    Object? passkey = _sentinel,
  }) => LinkState(
    available: available ?? this.available,
    connected: connected ?? this.connected,
    mode: mode == _sentinel ? this.mode : mode as WifiMode?,
    bars: bars == _sentinel ? this.bars : bars as int?,
    rssi: rssi == _sentinel ? this.rssi : rssi as int?,
    lastSyncS: lastSyncS == _sentinel ? this.lastSyncS : lastSyncS as int?,
    warm: warm ?? this.warm,
    ssid: ssid == _sentinel ? this.ssid : ssid as String?,
    ip: ip == _sentinel ? this.ip : ip as String?,
    passkey: passkey == _sentinel ? this.passkey : passkey as String?,
  );
}

const Object _sentinel = Object();

/// The bridge's whole connection state.
class ConnectionState {
  const ConnectionState({
    required this.phase,
    this.error,
    this.deviceName = 'SmokeBridge-A4F2',
    this.batteryPct,
    this.recording = true,
    this.primary,
    this.bt = const LinkState(),
    this.wifi = const LinkState(mode: WifiMode.sta),
  });

  final ConnectionPhase phase;

  /// The named error (`wrong_password`, `router_unreachable`, `switch_failed`).
  final String? error;

  final String deviceName;

  /// Battery percent, or null when the bridge cannot report it.
  final int? batteryPct;

  /// The bridge records with or without the phone (I2); always true in mocks.
  final bool recording;

  final LinkPrimary? primary;
  final LinkState bt;
  final LinkState wifi;

  ConnectionState copyWith({
    ConnectionPhase? phase,
    Object? error = _sentinel,
    String? deviceName,
    Object? batteryPct = _sentinel,
    bool? recording,
    Object? primary = _sentinel,
    LinkState? bt,
    LinkState? wifi,
  }) => ConnectionState(
    phase: phase ?? this.phase,
    error: error == _sentinel ? this.error : error as String?,
    deviceName: deviceName ?? this.deviceName,
    batteryPct: batteryPct == _sentinel ? this.batteryPct : batteryPct as int?,
    recording: recording ?? this.recording,
    primary: primary == _sentinel ? this.primary : primary as LinkPrimary?,
    bt: bt ?? this.bt,
    wifi: wifi ?? this.wifi,
  );
}

/// A bridge session the app has not adopted yet.
class PendingSession {
  const PendingSession({
    required this.sessionId,
    required this.startedAtMs,
    required this.samples,
    required this.probeCount,
    this.attachedJacks = const [],
  });

  final String sessionId;
  final int startedAtMs;

  /// Samples already recorded — the cost is stated before adopting (I8).
  final int samples;

  final int probeCount;
  final List<int> attachedJacks;
}
