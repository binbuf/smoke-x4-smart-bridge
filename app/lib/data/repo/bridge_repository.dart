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

  Future<List<Sample>> samples(int sessionId, {int? fromT, int? toT}) =>
      cache.samples(bridgeId, sessionId, fromT: fromT, toT: toT);

  Future<List<RecordedGap>> gaps(int sessionId) =>
      cache.gaps(bridgeId, sessionId);

  // ── clock / cook clock ──────────────────────────────────────────────

  /// Writes the bridge's wall clock so its sessions carry real timestamps.
  Future<void> setTime(int unixMs, {int? tzOffsetMin}) =>
      transport.setTime(unixMs, tzOffsetMin: tzOffsetMin);

  /// Declares the elapsed time the device's OLED shows (the cook clock).
  Future<void> setCookClock(int elapsedS) => transport.setCookClock(elapsedS);

  Future<void> clearCookClock() => transport.clearCookClock();

  /// The phone ↔ bridge link RSSI in dBm.
  Future<int> readRssi() => transport.readRssi();
}
