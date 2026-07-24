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

  /// Recorded on every successful HTTP win. **The BLE lane must not call
  /// this** — there is no address to remember, and blanking the cached
  /// URL would break the next launch's fastest lane (A6.5).
  Future<void> recordConnection(String baseUrl, {String? bridgeId, int? atMs});

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
  Future<void> forgetBridge() async {
    lastBaseUrl = null;
    lastBridgeId = null;
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
  Future<void> forgetBridge() async {
    await _prefs.remove(_kBaseUrl);
    await _prefs.remove(_kBridgeId);
    await _prefs.remove(_kLastSeen);
  }
}
