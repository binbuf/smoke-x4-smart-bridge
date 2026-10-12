/// The app model over one connected bridge.
///
/// This is the composition the screens actually talk to: a [BridgeTransport]
/// (the wire), a [DriftSampleCache] (the phone's full copy) and a [SyncEngine]
/// (the delta sync between them). It exists so no screen has to know which
/// cache or which transport is underneath — the same reason the seam types do.
///
/// Everything here reads the *device-authoritative* ids: the bridge id comes
/// from `device_info`, the session ids from the device. The phone never mints
/// either.
library;

import '../../domain/domain.dart';
import '../ble/bridge_transport.dart';
import '../local/drift_sample_cache.dart';
import 'sync_engine.dart';

class BridgeRepository {
  BridgeRepository({
    required this.cache,
    required this.transport,
    SyncEngine? sync,
  }) : _sync = sync ?? SyncEngine();

  final DriftSampleCache cache;
  final BridgeTransport transport;
  final SyncEngine _sync;

  String? _bridgeId;

  /// The device id (`device_info.id`, e.g. `A4F2`). Set by [loadIdentity].
  String get bridgeId {
    final id = _bridgeId;
    if (id == null) {
      throw StateError('bridgeId read before loadIdentity()');
    }
    return id;
  }

  bool get identified => _bridgeId != null;

  /// Reads the unencrypted identity card and latches the bridge id.
  Future<DeviceIdentity> loadIdentity() async {
    final info = await transport.deviceInfo();
    _bridgeId = info.id;
    return info;
  }

  Stream<LiveSnapshot> get live => transport.liveUpdates;

  Future<LiveSnapshot> readLive() => transport.readLive();

  /// Pulls the session list and upserts it (upsert-only: a session the device
  /// has since purged stays in the phone's copy). Returns the phone's view.
  Future<List<SessionInfo>> refreshSessions() async {
    final remote = await transport.sessions();
    await cache.upsertSessions(bridgeId, remote);
    return cache.readSessions(bridgeId);
  }

  /// Delta-syncs one session from its high-water mark.
  Future<SyncResult> syncSession(SessionInfo session) async {
    return _sync.syncSession(
      transport,
      bridgeId: bridgeId,
      session: session,
      cache: cache,
    );
  }

  /// Whether a closed session has already been fully pulled. Lets the periodic
  /// tick skip a long, finished history without even a cache round trip.
  Future<bool> sessionComplete(SessionInfo session) =>
      _sync.isComplete(cache, bridgeId: bridgeId, session: session);

  Future<List<Sample>> samples(int sessionId, {int? fromT, int? toT}) =>
      cache.samples(bridgeId, sessionId, fromT: fromT, toT: toT);

  Future<List<RecordedGap>> gaps(int sessionId) =>
      cache.gaps(bridgeId, sessionId);

  // ── clock / cook clock ──────────────────────────────────────────────

  /// Writes the bridge's wall clock so its sessions carry real timestamps.
  Future<void> setTime(int unixMs, {int? tzOffsetMin}) =>
      transport.setTime(unixMs, tzOffsetMin: tzOffsetMin);

  /// Enters sync/scan mode toward the Smoke X4 (`pair`, op 1).
  Future<void> pair() => transport.pair();

  /// Forgets the paired Smoke X4 (`unpair`, op 2).
  Future<void> unpair() => transport.unpair();

  /// Wakes/flashes the bridge's display (`identify`, op 10).
  Future<void> identify() => transport.identify();

  /// Restarts the bridge (`reboot`, op 7). The link drops and returns.
  Future<void> reboot() => transport.reboot();

  /// Wipes the bridge's bonds, config and cooks, then reboots (op 8).
  Future<void> factoryReset() => transport.factoryReset();

  /// Puts the bridge into deep sleep (`power_off`, op 13).
  Future<void> powerOff() => transport.powerOff();

  /// Sets the bridge's OLED unit preference (`set_units`, op 9).
  Future<void> setUnits(TempUnit unit) => transport.setUnits(unit);

  /// Sets the bridge's battery-saver profile (`set_battery_saver`, op 12).
  Future<void> setBatterySaver(BatterySaverMode mode) =>
      transport.setBatterySaver(mode);

  /// The read-only telemetry snapshot (`device_stats`).
  Future<DeviceStats> stats() => transport.stats();

  /// The current writable settings (`device_config`).
  Future<DeviceConfig> deviceConfig() => transport.deviceConfig();

  /// One probe's label, role and target (`set_probe`, op 16).
  Future<void> setProbe(ProbeConfig probe) => transport.setProbe(probe);

  /// The device preferences (`set_device_prefs`, op 17).
  Future<void> setDevicePrefs(DevicePrefs prefs) =>
      transport.setDevicePrefs(prefs);

  /// Declares the elapsed time the device's OLED shows (the cook clock).
  Future<void> setCookClock(int elapsedS) => transport.setCookClock(elapsedS);

  Future<void> clearCookClock() => transport.clearCookClock();

  /// The phone ↔ bridge link RSSI in dBm.
  Future<int> readRssi() => transport.readRssi();
}
