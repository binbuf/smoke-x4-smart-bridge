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

  BridgeLink link = BridgeLink.disconnected;

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

  bool get connected => link == BridgeLink.connected;
  BridgeRepository? get repository => _repo;

  /// Whether this phone remembers a bridge pairing to forget.
  bool get canForget => _rememberedDeviceId != null;

  /// The freshness of the latest reading: [Freshness.unknown] before any
  /// reading, [Freshness.frozen] when the base station is lost, else bucketed
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
    notifyListeners();
  }

  // ── connection lifecycle ────────────────────────────────────────────

  /// Scans, connects, bonds, negotiates the MTU and starts the transport. On
  /// failure it lands in [BridgeLink.error] with a reason — never a spinner
  /// that never resolves.
  Future<void> connect() async {
    if (link == BridgeLink.scanning || link == BridgeLink.connecting) {
      return;
    }
    problem = null;
    errorMessage = null;
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
      await _refreshSessions();
      await _refreshLinkRssi();
      await _resumeCookClock();
      link = BridgeLink.connected;
      _reconnectAttempts = 0;
      notifyListeners();
      unawaited(_syncSessions());
      _syncTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_syncSessions()),
      );
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
    if (_reconnectAttempts < 3) {
      _reconnectAttempts++;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!_tearingDown && link == BridgeLink.disconnected) {
        await connect();
      }
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

  /// Delta-syncs every not-yet-cached session. Safe to call repeatedly; the
  /// [SyncEngine] skips a closed, fully-cached session without a round trip.
  Future<void> _syncSessions() async {
    final repo = _repo;
    if (repo == null || syncing) {
      return;
    }
    syncing = true;
    notifyListeners();
    try {
      for (final s in sessions) {
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
    final repo = _repo;
    if (repo == null) {
      return;
    }
    try {
      final now = DateTime.now();
      await repo.setTime(
        now.millisecondsSinceEpoch,
        tzOffsetMin: now.timeZoneOffset.inMinutes,
      );
      _report('Bridge clock set');
    } on Object catch (e) {
      _report('Could not set the bridge clock: ${_reason(e)}');
    }
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
