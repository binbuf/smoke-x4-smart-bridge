/// The app-model state object: one connection, one repository, one live stream.
///
/// Plain [ChangeNotifier] — no state-management package. The shell publishes it
/// through `BridgeScope`; screens read it and call its async verbs. It owns the
/// connection lifecycle so no screen ever dials the bridge itself.
///
/// **The cache outlives the link.** History and the graph read straight from
/// the on-device cache keyed by the last bridge this phone saw, so a cold,
/// unconnected launch shows every cook already pulled — the bridge being out of
/// range is not an empty app. The live repository is only for what needs a
/// radio: identity, live reads, sync and the cook clock.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/ble/ble_gatt_fbp.dart';
import '../data/ble/bridge_transport.dart';
import '../data/local/app_prefs.dart';
import '../data/local/drift_sample_cache.dart';
import '../data/repo/bridge_repository.dart';
import '../domain/domain.dart';

enum BridgeLink { disconnected, scanning, connecting, connected, error }

class BridgeController extends ChangeNotifier {
  BridgeController(
    this.cache, {
    Future<BridgeTransport> Function()? openTransport,
  }) : _openTransport = openTransport ?? openBleTransport;

  final DriftSampleCache cache;

  /// Opens a live transport. Injectable so the connection lifecycle can be
  /// driven end-to-end by a fake peripheral with no radio.
  final Future<BridgeTransport> Function() _openTransport;

  final AppPrefs _prefs = AppPrefs();

  BridgeRepository? _repo;
  BridgeTransport? _transport;
  StreamSubscription<LiveSnapshot>? _liveSub;
  StreamSubscription<void>? _dropSub;
  Timer? _syncTimer;
  Timer? _freshnessTimer;

  /// The bridge whose cache this phone reads while (or without) being
  /// connected. Restored from the cache itself on a cold launch, so an offline
  /// history tab has a key to read by.
  String? _bridgeId;

  /// The OS address (Android MAC) of the bridge this phone last paired with, so
  /// [forgetBridge] knows whether there is anything to forget.
  String? _rememberedDeviceId;

  /// Set while a deliberate [disconnect] is in flight, so the transport's own
  /// disconnect event is not mistaken for a dropped link.
  bool _tearingDown = false;

  /// Consecutive auto-reconnects since the last successful reading. Bounded, so
  /// a bridge that drops the instant it connects cannot spin forever.
  int _reconnectAttempts = 0;

  /// The bound on silent auto-reconnects before the app stops spinning and
  /// tells the user, rather than reading "Offline" with no explanation.
  static const _maxReconnects = 3;

  /// When the phone last wrote the bridge's clock, so a still-live link can
  /// re-assert it without re-writing on every 30 s tick.
  DateTime? _clockSetAt;

  /// How long a written clock is trusted before the phone re-asserts it while
  /// the link stays up. A reconnect always re-writes regardless — the bridge
  /// forgets its clock across a reboot.
  static const _clockRefreshAfter = Duration(hours: 6);

  BridgeLink link = BridgeLink.disconnected;

  /// True when auto-reconnect gave up after [_maxReconnects] silent tries. The
  /// UI turns this into a tap-to-retry rather than an unexplained "Offline".
  bool reconnectExhausted = false;

  /// Why the last connect attempt failed, when it did — the UI turns this into
  /// the one action that can actually change the outcome.
  ConnectionProblem? problem;
  String? errorMessage;

  DeviceIdentity? identity;
  List<SessionInfo> sessions = const [];

  /// The most recent live snapshot and when the phone received it. The receipt
  /// time is the phone's clock, which is the only clock available for freshness
  /// while live (the bridge's own clock may be unset).
  LiveSnapshot? latestLive;
  DateTime? liveAt;

  /// The phone ↔ bridge link RSSI in dBm, refreshed on connect and on a manual
  /// refresh. Null when it could not be read or there is no link.
  int? linkRssiDbm;

  /// The local start of the app-declared cook, or null when none is running.
  ///
  /// The cook clock is the *glass*, not recording: the bridge has no concept of
  /// a cook, so the phone owns this and re-sends it to the bridge's OLED on
  /// every reconnect (the bridge forgets it across a reboot).
  int? _cookStartedMs;

  bool syncing = false;

  /// The last background-sync failure, if any. A failed sync is not a failed
  /// connection — the cache still holds what it held — but silently swallowing
  /// it is how "Sync now does nothing" becomes a bug report.
  String? syncError;

  /// The last user-triggered action's outcome, success or failure, and a
  /// counter that lets the shell distinguish a fresh note from a repaint of the
  /// same one. Both are how "nothing happened" stops being silent.
  String? actionMessage;
  int actionSeq = 0;

  /// Bumped whenever cached data changes (a session list refresh or a completed
  /// sync), so data-reading tabs know to reload without polling.
  int dataVersion = 0;

  TempUnit unit = TempUnit.fahrenheit;

  /// The bridge's battery-saver profile as last set from here. There is no BLE
  /// read-back, so this reflects the app's intent, not a device report.
  BatterySaverMode batterySaver = BatterySaverMode.off;

  /// The last `device_stats` snapshot, or null when unconnected or the bridge
  /// predates the v1.2 admin surface.
  DeviceStats? deviceStats;

  /// The last `device_config` read (probe names/roles/targets + preferences).
  DeviceConfig? deviceConfig;

  bool get connected => link == BridgeLink.connected;
  BridgeRepository? get repository => _repo;

  /// Whether this phone remembers a bridge pairing to forget.
  bool get canForget => _rememberedDeviceId != null;

  /// True until this phone has ever spoken to a bridge — a factory-fresh
  /// install. Drives the guided first-run surface so a new user is walked
  /// through find → pair rather than shown a bare "Not connected".
  bool get firstRun => _rememberedDeviceId == null && _bridgeId == null;

  /// The freshness of the latest reading: [Freshness.unknown] before any
  /// reading, [Freshness.frozen] when the Smoke X4 is lost, else bucketed
  /// by the age of the last snapshot on the phone's clock.
  Freshness get freshness {
    final at = liveAt;
    if (latestLive == null || at == null) {
      return Freshness.unknown;
    }
    final ageS = DateTime.now().difference(at).inSeconds;
    return Freshness.fromAge(ageS, baseLost: latestLive!.paired == false);
  }

  /// The newest session, which is the one an open cook is being appended to.
  SessionInfo? get newestSession => sessions.isEmpty ? null : sessions.first;

  /// How many probe jacks this bridge actually has (2 or 4), from the identity
  /// card. Defaults to 4 while unconnected or unidentified, so the live list is
  /// never short a jack on first paint.
  int get probeCount {
    final n = identity?.probes ?? 4;
    return n < 1 ? 1 : (n > 4 ? 4 : n);
  }

  /// Whether the app has declared a cook (the device screen's clock is set).
  bool get cookRunning => _cookStartedMs != null;

  /// The elapsed seconds of the declared cook, clamped to the OLED's 99:59
  /// width (the same bound the device enforces), or null when none is running.
  int? get cookElapsedS {
    final start = _cookStartedMs;
    if (start == null) {
      return null;
    }
    final s = (DateTime.now().millisecondsSinceEpoch - start) ~/ 1000;
    if (s < 0) {
      return 0;
    }
    return s > cookClockMaxS ? cookClockMaxS : s;
  }

  /// Restores the saved unit so a °C user is not flipped back to °F on every
  /// launch. Safe to call before any connection.
  Future<void> loadPrefs() async {
    final saved = await _prefs.readUnit();
    if (saved != unit) {
      unit = saved;
      notifyListeners();
    }
  }

  /// What the root widget calls at startup: restore preferences, paint the
  /// cached history immediately, and reconnect to a bridge this phone has
  /// paired with before. First-run (never paired) stays disconnected and lets
  /// the user start the pairing themselves.
  Future<void> bootstrap() async {
    await loadPrefs();
    _cookStartedMs = await _prefs.readCookStartedMs();
    _rememberedDeviceId = await _prefs.readLastBridgeId();
    await _loadCachedData();
    if (_rememberedDeviceId != null) {
      unawaited(connect());
    }
  }

  void setUnit(TempUnit value) {
    if (value == unit) {
      return;
    }
    unit = value;
    unawaited(_prefs.writeUnit(value));
    // Mirror the choice onto the bridge's own OLED, best-effort: the OLED is a
    // convenience, not the record, so a failed write never blocks the toggle.
    unawaited(_writeUnits(value));
    notifyListeners();
  }

  Future<void> _writeUnits(TempUnit value) async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      await repo.setUnits(value);
    } on Object {
      // Best-effort; the phone's preference is already saved.
    }
  }

  // ── connection lifecycle ────────────────────────────────────────────

  /// Scans, connects, bonds, negotiates the MTU and starts the transport. On
  /// failure it lands in [BridgeLink.error] with a reason — never a spinner
  /// that never resolves.
  Future<void> connect() async {
    if (link == BridgeLink.connected ||
        link == BridgeLink.scanning ||
        link == BridgeLink.connecting) {
      return;
    }
    problem = null;
    errorMessage = null;
    reconnectExhausted = false;
    link = BridgeLink.scanning;
    notifyListeners();

    BridgeTransport transport;
    try {
      transport = await _openTransport();
    } on BridgeConnectionException catch (e) {
      problem = e.problem;
      errorMessage = e.message;
      link = BridgeLink.error;
      notifyListeners();
      return;
    } on Object catch (e) {
      problem = ConnectionProblem.failed;
      errorMessage = '$e';
      link = BridgeLink.error;
      notifyListeners();
      return;
    }

    link = BridgeLink.connecting;
    notifyListeners();

    _transport = transport;
    final repo = BridgeRepository(cache: cache, transport: transport);
    _repo = repo;
    try {
      identity = await repo.loadIdentity();
      _bridgeId = identity!.id;
      _liveSub = repo.live.listen(_onLive);
      _dropSub = transport.disconnects.listen((_) => unawaited(_onDrop()));
      latestLive = await repo.readLive();
      liveAt = DateTime.now();
      // The bridge stores sessions with no wall clock until the phone writes
      // one, so a fresh connect always sets it *before* pulling the session
      // list — the device then back-patches its open session with a real date.
      await _writeClock();
      await _refreshSessions();
      await _refreshLinkRssi();
      await _resumeCookClock();
      await _refreshAdmin();
      link = BridgeLink.connected;
      _reconnectAttempts = 0;
      notifyListeners();
      unawaited(_syncSessions());
      _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(_ensureClock());
        // The periodic tick is bounded: only what is still growing or was
        // never finished. The full sweep happens on connect and on a
        // user-triggered sync, so a long finished history costs nothing here.
        unawaited(_syncSessions(full: false));
      });
      // Rebuild every 10 s so the freshness ladder ages on screen even while
      // no new snapshot arrives. Without this a probe that stops updating
      // stays "Live" indefinitely (the ladder is computed from DateTime.now()).
      _freshnessTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => notifyListeners(),
      );
    } on Object catch (e) {
      problem = ConnectionProblem.failed;
      errorMessage = '$e';
      await _teardown();
      link = BridgeLink.error;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _tearingDown = true;
    await _teardown();
    link = BridgeLink.disconnected;
    _tearingDown = false;
    await _loadCachedData();
    notifyListeners();
  }

  /// Forget the remembered bridge so the next connect scans fresh instead of
  /// preferring a stale address. The OS pairing is dropped best-effort (it can
  /// be refused, and a failed bootstrap into a bad bridge is worse than a
  /// leftover bond); the on-device history is deliberately kept, because the
  /// phone's copy is not the bond.
  Future<void> forgetBridge() async {
    final transport = _transport;
    var pairingError = false;
    if (transport != null) {
      try {
        await transport.forget();
      } on Object catch (e) {
        pairingError = true;
        _report('Could not remove the pairing: ${_reason(e)}');
      }
    }
    await _prefs.clearLastBridgeId();
    _rememberedDeviceId = null;
    await disconnect();
    if (!pairingError) {
      _report('Bridge forgotten');
    }
    notifyListeners();
  }

  /// The link dropped from underneath us. Tear down honestly (the chip must not
  /// keep saying "Connected"), repaint from cache, then try a bounded number of
  /// silent reconnects — the whole point of "pair once".
  Future<void> _onDrop() async {
    if (_tearingDown || link != BridgeLink.connected) {
      return;
    }
    await _teardown();
    link = BridgeLink.disconnected;
    notifyListeners();
    await _loadCachedData();
    await _autoReconnect();
  }

  /// Silent reconnect, bounded by [_maxReconnects]. A failed attempt falls back
  /// to [BridgeLink.disconnected] so the next one is allowed to run; when the
  /// bound is reached the app stops spinning and raises [reconnectExhausted] so
  /// the UI can offer a tap-to-retry instead of failing silently.
  Future<void> _autoReconnect() async {
    while (_reconnectAttempts < _maxReconnects) {
      _reconnectAttempts++;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_tearingDown || link != BridgeLink.disconnected) {
        return;
      }
      await connect();
      if (_tearingDown || link == BridgeLink.connected) {
        return;
      }
      // connect() left us in error (or scanning); fall back to disconnected so
      // the loop's guard lets the next attempt run rather than stopping here.
      if (link != BridgeLink.disconnected) {
        link = BridgeLink.disconnected;
        notifyListeners();
      }
    }
    if (!_tearingDown && link != BridgeLink.connected) {
      reconnectExhausted = true;
      notifyListeners();
    }
  }

  Future<void> _teardown() async {
    await _dropSub?.cancel();
    _dropSub = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _freshnessTimer?.cancel();
    _freshnessTimer = null;
    await _liveSub?.cancel();
    _liveSub = null;
    await _transport?.close();
    _transport = null;
    _repo = null;
    latestLive = null;
    liveAt = null;
    linkRssiDbm = null;
    identity = null;
    deviceStats = null;
    deviceConfig = null;
    // sessions and _bridgeId are deliberately kept: the cache still holds the
    // history, and a disconnected app must be able to read it.
  }

  void _onLive(LiveSnapshot snapshot) {
    latestLive = snapshot;
    liveAt = DateTime.now();
    // A stable reading means the link is healthy; forget the reconnect count.
    _reconnectAttempts = 0;
    notifyListeners();
  }

  // ── sessions / history ──────────────────────────────────────────────

  /// Repaints the session list for the active (or last-known) bridge from the
  /// cache alone. No radio, no repository.
  Future<void> _loadCachedData() async {
    final id = _bridgeId ?? await cache.latestBridgeId();
    _bridgeId = id;
    sessions = id == null ? const [] : await cache.readSessions(id);
    dataVersion++;
    notifyListeners();
  }

  Future<void> _refreshSessions() async {
    final repo = _repo;
    if (repo == null) {
      await _loadCachedData();
      return;
    }
    sessions = await repo.refreshSessions();
    _bridgeId = repo.bridgeId;
    dataVersion++;
  }

  /// A user-triggered refresh: re-read live, re-pull the session list and sync.
  Future<void> refresh() async {
    final repo = _repo;
    if (repo == null) {
      // Offline pull-to-refresh still means something: re-read the cache.
      await _loadCachedData();
      return;
    }
    try {
      latestLive = await repo.readLive();
      liveAt = DateTime.now();
      await _refreshSessions();
      await _refreshLinkRssi();
    } on Object catch (e) {
      _report('Refresh failed: ${_reason(e)}');
    }
    notifyListeners();
    await _syncSessions();
  }

  /// Delta-syncs not-yet-cached sessions. Safe to call repeatedly; the
  /// [SyncEngine] skips a closed, fully-cached session without a round trip.
  ///
  /// [full] sweeps every session (connect, pull-to-refresh, "Sync now"). When
  /// false — the periodic tick — a closed session already drained is skipped
  /// entirely, so a long finished history is never a burst of BLE reads.
  Future<void> _syncSessions({bool full = true}) async {
    final repo = _repo;
    if (repo == null || syncing) {
      return;
    }
    syncing = true;
    notifyListeners();
    try {
      for (final s in sessions) {
        if (!full && s.closed && await repo.sessionComplete(s)) {
          continue;
        }
        await repo.syncSession(s);
      }
      syncError = null;
    } on Object catch (e) {
      // A sync failure is not a connection failure: the cache still has what it
      // had, and the next tick retries. It is recorded, not raised, so the sync
      // control can say *why* rather than spinning forever.
      syncError = '$e';
    } finally {
      syncing = false;
      dataVersion++;
      notifyListeners();
    }
  }

  /// A user-triggered sync of every not-yet-cached session.
  Future<void> syncNow() async {
    await _syncSessions();
    _report(syncError == null ? 'History synced' : 'Sync failed: $syncError');
    notifyListeners();
  }

  /// The bounded sweep the periodic tick runs: open or unfinished sessions
  /// only. Exposed so the bound can be asserted without waiting on the timer.
  @visibleForTesting
  Future<void> syncIncomplete() => _syncSessions(full: false);

  /// One session's cached samples (for the graph and history detail). Reads the
  /// cache directly — the link is irrelevant to data already on the phone.
  Future<List<Sample>> samplesFor(int sessionId, {int? fromT, int? toT}) async {
    final id = _bridgeId;
    if (id == null) {
      return const [];
    }
    return cache.samples(id, sessionId, fromT: fromT, toT: toT);
  }

  Future<List<RecordedGap>> gapsFor(int sessionId) async {
    final id = _bridgeId;
    if (id == null) {
      return const [];
    }
    return cache.gaps(id, sessionId);
  }

  // ── clock / cook clock ──────────────────────────────────────────────

  /// Re-declares a running cook to the bridge. The bridge forgets the clock
  /// across a reboot, so every connect re-sends the current age; there is no
  /// read-back to restore from.
  Future<void> _resumeCookClock() async {
    final repo = _repo;
    final elapsed = cookElapsedS;
    if (repo == null || elapsed == null) {
      return;
    }
    try {
      await repo.setCookClock(elapsed);
    } on Object catch (e) {
      _report('Could not restore the cook clock: ${_reason(e)}');
    }
  }

  /// Best-effort read of the phone ↔ bridge link RSSI; a failure just leaves it
  /// unknown rather than failing the connection.
  Future<void> _refreshLinkRssi() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      linkRssiDbm = await repo.readRssi();
    } on Object {
      linkRssiDbm = null;
    }
  }

  /// Starts (or restarts) a cook now, persisting the start so the clock is
  /// still running on the next launch and can be re-sent on reconnect.
  Future<void> startCook() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    final restart = cookRunning;
    try {
      await repo.setCookClock(0);
      _cookStartedMs = DateTime.now().millisecondsSinceEpoch;
      await _prefs.writeCookStartedMs(_cookStartedMs!);
      _report(restart ? 'Cook clock restarted' : 'Cook clock started');
    } on Object catch (e) {
      _report('Could not start the cook clock: ${_reason(e)}');
    }
    notifyListeners();
  }

  Future<void> clearCook() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      await repo.clearCookClock();
      _cookStartedMs = null;
      await _prefs.clearCookStartedMs();
      _report('Cook clock cleared');
    } on Object catch (e) {
      _report('Could not clear the cook clock: ${_reason(e)}');
    }
    notifyListeners();
  }

  /// Writes the bridge's wall clock from the phone, so future sessions carry
  /// real timestamps.
  Future<void> syncClock() async {
    if (await _writeClock()) {
      _report('Bridge clock set');
    }
  }

  /// The one clock write. Sets [unixMs]/timezone from the phone's clock and
  /// stamps when it happened. Best-effort: a failed clock write reports but
  /// never fails the connect it rode in on.
  Future<bool> _writeClock() async {
    final repo = _repo;
    if (repo == null) {
      return false;
    }
    final now = DateTime.now();
    try {
      await repo.setTime(
        now.millisecondsSinceEpoch,
        tzOffsetMin: now.timeZoneOffset.inMinutes,
      );
      _clockSetAt = now;
      return true;
    } on Object catch (e) {
      _report('Could not set the bridge clock: ${_reason(e)}');
      return false;
    }
  }

  /// Re-asserts the clock on a still-live link once it is older than
  /// [_clockRefreshAfter]. A no-op for a recently-set clock, so the periodic
  /// tick does not write on every pass.
  Future<void> _ensureClock() async {
    final last = _clockSetAt;
    if (last != null && DateTime.now().difference(last) < _clockRefreshAfter) {
      return;
    }
    await _writeClock();
  }

  // ── Smoke X4 pairing ────────────────────────────────────────────────

  /// Puts the bridge into sync/scan mode toward the Smoke X4 (`pair`, op 1).
  /// The Smoke X4 must be in SYNC too; the bridge's OLED is the confirmation,
  /// so this reports the step rather than a success it cannot observe.
  Future<void> pairSmokeX() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      await repo.pair();
      latestLive = await repo.readLive();
      liveAt = DateTime.now();
      _report('Listening for the Smoke X4…');
    } on Object catch (e) {
      _report('Could not pair with the Smoke X4: ${_reason(e)}');
    }
    notifyListeners();
  }

  /// Forgets the paired Smoke X4 (`unpair`, op 2).
  Future<void> unpairSmokeX() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      await repo.unpair();
      latestLive = await repo.readLive();
      liveAt = DateTime.now();
      _report('Smoke X4 unpaired');
    } on Object catch (e) {
      _report('Could not unpair the Smoke X4: ${_reason(e)}');
    }
    notifyListeners();
  }

  // ── bridge lifecycle (Settings) ─────────────────────────────────────

  /// Wakes the bridge's OLED and flashes what it has (`identify`, op 10).
  Future<void> identifyBridge() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      await repo.identify();
      _report('Bridge display flashed');
    } on Object catch (e) {
      _report('Could not identify the bridge: ${_reason(e)}');
    }
    notifyListeners();
  }

  /// Sets the bridge's battery-saver profile (`set_battery_saver`, op 12).
  Future<void> setBatterySaver(BatterySaverMode mode) async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      await repo.setBatterySaver(mode);
      batterySaver = mode;
      _report('Battery saver: ${mode.name}');
    } on Object catch (e) {
      _report('Could not set battery saver: ${_reason(e)}');
    }
    notifyListeners();
  }

  /// Restarts the bridge (`reboot`, op 7). The link drops and returns; the app
  /// tears its half down honestly and lets the user (or a later connect)
  /// re-establish it rather than trusting a link the peer has already dropped.
  Future<void> rebootBridge() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      await repo.reboot();
      await disconnect();
      _report('Bridge is rebooting…');
    } on Object catch (e) {
      _report('Could not reboot the bridge: ${_reason(e)}');
    }
    notifyListeners();
  }

  /// Puts the bridge into deep sleep (`power_off`, op 13). Waking needs the
  /// physical button.
  Future<void> powerOffBridge() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      await repo.powerOff();
      await disconnect();
      _report('Bridge powered off');
    } on Object catch (e) {
      _report('Could not power off the bridge: ${_reason(e)}');
    }
    notifyListeners();
  }

  /// Wipes the bridge (`factory_reset`, op 8): its bonds, config and recorded
  /// cooks. The device's bond is gone with it, so this phone forgets its own
  /// pairing and drops the cached history — a reset bridge showing old cooks
  /// would be a lie.
  Future<void> factoryResetBridge() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      await repo.factoryReset();
    } on Object catch (e) {
      _report('Could not reset the bridge: ${_reason(e)}');
      notifyListeners();
      return;
    }
    // Drop the OS bond best-effort (the bridge no longer holds our key), then
    // forget the address so the next connect scans fresh and re-pairs.
    try {
      await _transport?.forget();
    } on Object {
      // A refused removeBond is recoverable via Bluetooth settings.
    }
    await _prefs.clearLastBridgeId();
    _rememberedDeviceId = null;
    _bridgeId = null;
    await cache.clear();
    await cache.clearSessions();
    await disconnect();
    _report('Bridge reset to factory defaults');
    notifyListeners();
  }

  // ── bridge administration (v1.2) ────────────────────────────────────

  /// Re-reads the `device_stats` snapshot on demand (the Settings pane's
  /// refresh). Best-effort: a bridge without the admin surface leaves it null.
  Future<void> refreshStats() async {
    await _refreshAdmin();
    notifyListeners();
  }

  /// Reads the admin characteristics once after connect. A failure is not a
  /// connection failure — an older bridge simply has no admin surface.
  Future<void> _refreshAdmin() async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      deviceStats = await repo.stats();
    } on Object {
      deviceStats = null;
    }
    try {
      deviceConfig = await repo.deviceConfig();
    } on Object {
      deviceConfig = null;
    }
  }

  /// Saves one probe's label, role and target (`set_probe`, op 16), then
  /// re-reads `device_config` so the editor shows what the device accepted.
  Future<void> setProbeConfig({
    required int index,
    required String name,
    required ProbeRole role,
    required int targetF10,
  }) async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      await repo.setProbe(
        ProbeConfig(index: index, name: name, role: role, targetF10: targetF10),
      );
      deviceConfig = await repo.deviceConfig();
      _report('Probe ${index + 1} saved');
    } on Object catch (e) {
      _report('Could not save probe ${index + 1}: ${_reason(e)}');
    }
    notifyListeners();
  }

  /// Saves the bridge preferences (`set_device_prefs`, op 17), then re-reads.
  Future<void> saveDevicePrefs(DevicePrefs prefs) async {
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      await repo.setDevicePrefs(prefs);
      deviceConfig = await repo.deviceConfig();
      _report('Bridge settings saved');
    } on Object catch (e) {
      _report('Could not save bridge settings: ${_reason(e)}');
    }
    notifyListeners();
  }

  // ── user feedback ───────────────────────────────────────────────────

  void _report(String message) {
    actionMessage = message;
    actionSeq++;
  }

  String _reason(Object e) => e is TransportException ? e.message : '$e';

  @override
  void dispose() {
    _syncTimer?.cancel();
    _freshnessTimer?.cancel();
    unawaited(_dropSub?.cancel());
    unawaited(_liveSub?.cancel());
    unawaited(_transport?.close());
    super.dispose();
  }
}
