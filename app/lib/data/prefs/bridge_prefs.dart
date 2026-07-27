/// A7.5 — the small store that makes the second launch fast (design 08
/// §8.4, §8.5).
///
/// §8.4 promises _"every successful connection updates the cache, so the
/// common case — same bridge, same network, second launch — is one 50 ms
/// request."_ It has never been true: `ConnectionManager.writeCache` is a
/// typedef, and every production call site passed `(_) async {}`. A bridge
/// provisioned at 19:00 was a stranger at 19:05, and the M3 bench sitting
/// is where that finally showed.
///
/// `shared_preferences` is a plugin, so it hides behind an interface —
/// the same seam discipline `nsd` and `flutter_blue_plus` live under. The
/// in-memory implementation is what the host suite uses; nothing in the
/// app depends on which one it has.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../transport/bridge_transport.dart' show PreferredTransport;

/// What the app remembers between launches. Deliberately tiny: anything
/// with structure belongs in drift, and anything secret belongs nowhere
/// (05 §5.9 — no stored STA password ever leaves the device, and the app
/// has no reason to hold one either).
abstract interface class BridgePrefs {
  String? get lastBaseUrl;
  String? get lastBridgeId;
  int? get lastSeenUnixMs;

  /// `F` or `C`. Null = never chosen; D14 makes °F the default.
  String? get displayUnits;

  /// A13.6 — quiet hours and background monitoring (09 §9.5, §9.6).
  /// Both default ON: the design's defaults, and the ones a user who
  /// never opens settings should get.
  bool get quietHoursEnabled;
  bool get monitoringEnabled;
  Future<void> setQuietHours(bool enabled);
  Future<void> setMonitoringEnabled(bool enabled);

  /// 05 §5.7 — which transport to prefer when more than one is reachable.
  /// A tiebreak for the launch race, never an exclusion. Defaults to
  /// [PreferredTransport.auto]: BLE shows instantly, Wi-Fi upgrades in.
  PreferredTransport get preferredTransport;
  Future<void> setPreferredTransport(PreferredTransport t);

  /// 05 §5.7 — hold the BLE link connected as a warm standby even while
  /// Wi-Fi is the active data path, so failover is instant when the network
  /// drops (it costs the bridge ~1–3 mA). Default ON; the connection sheet
  /// turns it off for the battery-conscious or an MQTT-at-home install.
  bool get holdBleWhenOnWifi;
  Future<void> setHoldBleWhenOnWifi(bool enabled);

  /// Recorded on every successful HTTP win. **The BLE lane must not call
  /// this** — there is no address to remember, and blanking the cached
  /// URL would break the next launch's fastest lane (A6.5).
  Future<void> recordConnection(String baseUrl, {String? bridgeId, int? atMs});

  /// A25 — the OS address of the bonded bridge, so the BLE lane can *connect*
  /// on the next launch instead of having nothing to dial. Recorded by setup
  /// on a successful bond, including the Bluetooth-only path where there is
  /// no base URL at all.
  String? get lastBleDeviceId;
  Future<void> recordBleBridge(String deviceId, {String? bridgeId});

  /// Whether this phone knows a bridge by ANY lane (A25). Keying this on the
  /// base URL alone sent every Bluetooth-only user back through onboarding on
  /// each launch — the board-found setup loop.
  bool get hasBridge;

  Future<void> setDisplayUnits(String units);

  /// Onboarding a second bridge replaces the first (D12).
  Future<void> forgetBridge();
}

class InMemoryBridgePrefs implements BridgePrefs {
  InMemoryBridgePrefs({
    this.lastBaseUrl,
    this.lastBridgeId,
    this.lastSeenUnixMs,
    this.displayUnits,
    this.quietHoursEnabled = true,
    this.monitoringEnabled = true,
    this.preferredTransport = PreferredTransport.auto,
    this.holdBleWhenOnWifi = true,
    this.lastBleDeviceId,
  });

  @override
  String? lastBaseUrl;
  @override
  String? lastBridgeId;
  @override
  int? lastSeenUnixMs;
  @override
  String? displayUnits;
  @override
  bool quietHoursEnabled;
  @override
  bool monitoringEnabled;
  @override
  PreferredTransport preferredTransport;
  @override
  bool holdBleWhenOnWifi;
  @override
  String? lastBleDeviceId;

  @override
  bool get hasBridge =>
      (lastBaseUrl ?? '').isNotEmpty || (lastBleDeviceId ?? '').isNotEmpty;

  @override
  Future<void> recordBleBridge(String deviceId, {String? bridgeId}) async {
    if (deviceId.isEmpty) {
      return;
    }
    lastBleDeviceId = deviceId;
    if (bridgeId != null && bridgeId.isNotEmpty) {
      lastBridgeId = bridgeId;
    }
    lastSeenUnixMs = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Future<void> recordConnection(
    String baseUrl, {
    String? bridgeId,
    int? atMs,
  }) async {
    lastBaseUrl = baseUrl;
    if (bridgeId != null && bridgeId.isNotEmpty) {
      lastBridgeId = bridgeId;
    }
    lastSeenUnixMs = atMs ?? DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Future<void> setDisplayUnits(String units) async {
    displayUnits = units;
  }

  @override
  Future<void> setQuietHours(bool enabled) async {
    quietHoursEnabled = enabled;
  }

  @override
  Future<void> setMonitoringEnabled(bool enabled) async {
    monitoringEnabled = enabled;
  }

  @override
  Future<void> setPreferredTransport(PreferredTransport t) async {
    preferredTransport = t;
  }

  @override
  Future<void> setHoldBleWhenOnWifi(bool enabled) async {
    holdBleWhenOnWifi = enabled;
  }

  @override
  Future<void> forgetBridge() async {
    lastBaseUrl = null;
    lastBridgeId = null;
    lastBleDeviceId = null;
    lastSeenUnixMs = null;
  }
}

/// The production store. Loaded once at bootstrap so reads are
/// synchronous — a launch that has to await the disk before it can decide
/// which lane to race has already lost the 50 ms it was trying to save.
class SharedPrefsBridgePrefs implements BridgePrefs {
  SharedPrefsBridgePrefs(this._prefs);

  static const _kBaseUrl = 'bridge.base_url';
  static const _kBridgeId = 'bridge.id';
  static const _kLastSeen = 'bridge.last_seen_ms';
  static const _kUnits = 'display.units';
  static const _kQuiet = 'alarms.quiet_hours';
  static const _kMonitor = 'alarms.monitoring';
  static const _kPreferredTransport = 'transport.preferred';
  static const _kHoldBle = 'transport.hold_ble';
  static const _kBleDeviceId = 'bridge.ble_device_id';

  final SharedPreferences _prefs;

  static Future<SharedPrefsBridgePrefs> load() async =>
      SharedPrefsBridgePrefs(await SharedPreferences.getInstance());

  /// A stored value of the wrong type (an older build, a corrupt file) is
  /// treated as absent rather than thrown: losing the fast lane is a
  /// slower launch, losing the launch is a bug report.
  T? _read<T>(String key) {
    try {
      final v = _prefs.get(key);
      return v is T ? v : null;
    } on Object {
      return null;
    }
  }

  @override
  String? get lastBaseUrl {
    final v = _read<String>(_kBaseUrl);
    return v == null || v.isEmpty ? null : v;
  }

  @override
  String? get lastBridgeId => _read<String>(_kBridgeId);

  @override
  int? get lastSeenUnixMs => _read<int>(_kLastSeen);

  @override
  String? get displayUnits => _read<String>(_kUnits);

  /// Absent means never chosen, which is ON for both — the §9.5/§9.6
  /// defaults. `?? true` rather than `?? false` is the whole decision.
  @override
  bool get quietHoursEnabled => _read<bool>(_kQuiet) ?? true;

  @override
  bool get monitoringEnabled => _read<bool>(_kMonitor) ?? true;

  /// Stored by [Enum.name]; an unknown or absent value (older build, corrupt
  /// file) reads as [PreferredTransport.auto] — the same absent-means-default
  /// discipline as the flags above.
  @override
  PreferredTransport get preferredTransport {
    final v = _read<String>(_kPreferredTransport);
    for (final t in PreferredTransport.values) {
      if (t.name == v) {
        return t;
      }
    }
    return PreferredTransport.auto;
  }

  @override
  bool get holdBleWhenOnWifi => _read<bool>(_kHoldBle) ?? true;

  @override
  String? get lastBleDeviceId {
    final v = _read<String>(_kBleDeviceId);
    return v == null || v.isEmpty ? null : v;
  }

  @override
  bool get hasBridge =>
      (lastBaseUrl ?? '').isNotEmpty || (lastBleDeviceId ?? '').isNotEmpty;

  @override
  Future<void> recordBleBridge(String deviceId, {String? bridgeId}) async {
    if (deviceId.isEmpty) {
      return;
    }
    await _prefs.setString(_kBleDeviceId, deviceId);
    if (bridgeId != null && bridgeId.isNotEmpty) {
      await _prefs.setString(_kBridgeId, bridgeId);
    }
    await _prefs.setInt(_kLastSeen, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Future<void> recordConnection(
    String baseUrl, {
    String? bridgeId,
    int? atMs,
  }) async {
    if (baseUrl.isEmpty) {
      return; // a BLE win has no address; see the interface comment
    }
    await _prefs.setString(_kBaseUrl, baseUrl);
    if (bridgeId != null && bridgeId.isNotEmpty) {
      await _prefs.setString(_kBridgeId, bridgeId);
    }
    await _prefs.setInt(
      _kLastSeen,
      atMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> setDisplayUnits(String units) =>
      _prefs.setString(_kUnits, units);

  @override
  Future<void> setQuietHours(bool enabled) => _prefs.setBool(_kQuiet, enabled);

  @override
  Future<void> setMonitoringEnabled(bool enabled) =>
      _prefs.setBool(_kMonitor, enabled);

  @override
  Future<void> setPreferredTransport(PreferredTransport t) =>
      _prefs.setString(_kPreferredTransport, t.name);

  @override
  Future<void> setHoldBleWhenOnWifi(bool enabled) =>
      _prefs.setBool(_kHoldBle, enabled);

  /// The transport preference is a device-agnostic user choice, so
  /// forgetting a bridge deliberately leaves it untouched.
  @override
  Future<void> forgetBridge() async {
    await _prefs.remove(_kBaseUrl);
    await _prefs.remove(_kBridgeId);
    await _prefs.remove(_kBleDeviceId);
    await _prefs.remove(_kLastSeen);
  }
}
