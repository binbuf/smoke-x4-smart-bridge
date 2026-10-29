import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/ble/ble_client.dart';
import '../data/ble/bridge_codecs.dart';
import '../data/ble/bridge_link.dart';
import '../data/ble/bridge_protocol.dart';
import '../data/db/sample_dao.dart';
import '../data/history/history_archive.dart';
import '../data/history/history_deletion.dart';
import '../data/recent_history_store.dart';
import '../data/repository.dart';
import '../data/sync/archive_sync.dart';
import '../domain/content.dart';
import '../domain/models.dart';
import 'formatters.dart';
import 'view_state.dart';

export '../domain/models.dart';

/// Outcome of one destructive Bridge action (05 §5.5, 05 §5.12).
///
/// A result is never inferred from the GATT write. [disconnected] is a success
/// only for the ops whose contract makes the link drop the expected answer
/// (forget, factory reset, power off).
enum DestructiveOutcome {
  success,
  disconnected,
  failed,
  timedOut,
  unavailable;

  /// True when the Bridge did what the sheet promised.
  bool get landed => this == success || this == disconnected;
}

/// The app's control seam.
///
/// Owns navigation, theme and the state the approved shell renders. Data access
/// goes through [BridgeRepository] and [BridgeContent]; widgets render immutable
/// view state from [liveView], [historyView], [setupView], [settingsView] and
/// [bridgeDetailsView], never these mutable fields.
class BridgeController extends ChangeNotifier {
  BridgeController({
    BridgeRepository? repository,
    this.content = const EmptyBridgeContent(),
    this.bleClient,
    this.sampleDao,
    this.localeName = 'en_US',
    this.use24Hour = false,
  }) : repository = repository ?? EmptyBridgeRepository(),
       bridgeRecords = content.bridgeRecords,
       bridgeCapacity = content.bridgeCapacity,
       phoneRecords = content.phoneRecords,
       savedDataRange = content.savedDataRange,
       savedDataSize = content.savedDataSize;

  final BridgeRepository repository;
  final BridgeContent content;

  /// The durable archive seam. Null for review builds and tests that have no
  /// database; then the link keeps the V0 in-memory path.
  final SampleDao? sampleDao;
  ArchiveSyncCoordinator? _archive;
  HistoryArchive? _historyArchive;
  HistoryDeletionService? _historyDeletion;

  /// Average SQLite cost of one stored reading. 04 §4.9 puts a 30-day archive at
  /// 5–8 MB for 86,400 readings, so 72 B is the approved mid-point. The screen
  /// labels the result "Storage used"; it is an estimate, not a file-system
  /// measurement, and never drives automatic deletion.
  static const int estimatedStoredBytesPerReading = 72;

  /// Incremented whenever committed archive rows change, so the History screen
  /// reloads its SQL window after a sync batch instead of caching stale data.
  int historyRevision = 0;

  /// V0 History's data: the batches the current link session syncs. The
  /// durable archive replaces this store in T39–T41.
  late final RecentHistoryStore recentHistory = RecentHistoryStore(
    onChanged: notifyListeners,
    now: () => content.now,
  );

  /// The BLE seam. Production bootstrap passes the platform-backed client
  /// (M2); tests pass the scripted fake. `null` means no link is configured.
  final BleClient? bleClient;
  bool _initialized = false;

  /// Reads the cached summary once. Call from bootstrap after opening the DB.
  Future<void> initialize() async {
    if (_initialized) return;
    final snapshot = await repository.loadSnapshot();
    phoneRecords = snapshot.readingCount;
    hasSavedData = snapshot.readingCount > 0;
    savedDataEmpty = snapshot.readingCount == 0;
    _initialized = true;
    // The DAO also knows the exact time range and the per-reading storage
    // estimate; the small repository snapshot only carries the count.
    await refreshLocalHistorySummary();
    notifyListeners();
  }

  /// Re-reads the phone copy's count, real date range and estimated storage.
  ///
  /// Only an explicit read or a completed deletion calls this. It is deliberately
  /// not a cleanup path: nothing is ever deleted on launch, sync, generation
  /// change or low storage.
  Future<void> refreshLocalHistorySummary() async {
    final dao = sampleDao;
    if (dao == null) return;
    final extent = await dao.extent();
    if (extent == null) {
      phoneRecords = 0;
      savedDataRange = '—';
      savedDataSize = '0 B';
      savedDataEmpty = true;
      hasSavedData = false;
    } else {
      phoneRecords = extent.count;
      savedDataRange = dateRangeLabel(
        DateTime.fromMillisecondsSinceEpoch(extent.minRecordedMs),
        DateTime.fromMillisecondsSinceEpoch(extent.maxRecordedMs),
        locale: localeName,
      );
      savedDataSize = storageSizeLabel(
        extent.count * estimatedStoredBytesPerReading,
        locale: localeName,
      );
      savedDataEmpty = false;
      hasSavedData = true;
    }
    notifyListeners();
  }

  /// Loads the saved Bridge and the last-known archive before the first frame.
  ///
  /// A saved Bridge keeps the approved shell (Live), never Setup. With no saved
  /// Bridge, this is a first install and Setup remains the owner of pairing.
  Future<void> prepareLaunch({Duration? scanWindow}) async {
    if (scanWindow != null) launchScanWindow = scanWindow;
    await loadLocalPreferences();
    final dao = sampleDao;
    SavedBridge? saved;
    if (dao != null) {
      saved = await dao.savedBridge();
      await refreshLocalHistorySummary();
      final newest = await dao.newestSamples(limit: 1);
      if (newest.isNotEmpty) {
        final row = newest.single;
        liveProbeTemps = <double?>[
          for (final value in row.tempsF10) value == null ? null : value / 10,
        ];
        lastKnownReadingAt = DateTime.fromMillisecondsSinceEpoch(
          row.recordedMs,
          isUtc: true,
        );
        hasSavedData = true;
        savedDataEmpty = false;
      } else {
        hasSavedData = phoneRecords > 0;
        savedDataEmpty = phoneRecords == 0;
      }
      // Live sparklines are a view of the same archive, not a session-only
      // buffer. Seed the last hour before the first paint so a cold launch with
      // stored readings never claims `No history yet`.
      await _backfillLiveHistory();
    }
    // Offline values come only from the archive; a launch with nothing stored
    // must not present fixture values as last-known (ADR 0041).
    offlineCache = hasSavedData;
    _subscribePlatformStates();
    if (saved == null) {
      beginSetup();
      return;
    }
    savedBridge = saved;
    rememberedBridgeId = saved.id;
    rememberedBridgeName = saved.name;
    // The offline header names the saved Bridge, never the controller's
    // fixture default. The configured name only arrives with `config` after a
    // connect, so use the saved advertised name and the short BLE id here.
    deviceName = saved.name.trim().isEmpty ? '—' : saved.name.trim();
    deviceId = savedBridgeShortId(saved.id);
    localMaxSeq = saved.cursorAfter;
    lastSyncedAt = DateTime.fromMillisecondsSinceEpoch(saved.lastSeenMs);
    hasSavedBridge = true;
    lookingForBridge = true;
    phase = ConnectionPhase.offline;
    tab = AppTab.live;
    _bridgeConnectedSince = null;
    _smokeXConnectedSince = null;
    billowsAttachment = BillowsAttachment.unknown;
    billowsSeenThisSession = false;
    billowsLastDetectedAt = null;
    billowsLostAt = null;
    notifyListeners();
  }

  /// The four-character display id used for a saved Bridge before the protocol
  /// `info` read supplies its identity. A BLE address keeps its last four hex
  /// digits (`AC:A7:…:82:76` → `8276`); an unknown id renders as `—`.
  static String savedBridgeShortId(String id) {
    var value = id.trim();
    final dash = value.lastIndexOf('-');
    if (dash >= 0 && dash < value.length - 1) {
      value = value.substring(dash + 1);
    }
    final hex = value.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (hex.isEmpty) return '—';
    final tail = hex.length <= 4 ? hex : hex.substring(hex.length - 4);
    return tail.toUpperCase();
  }

  /// Seeds Live's one-hour sparkline window from the durable archive.
  ///
  /// The window ends at the newest saved reading when the archive is older than
  /// an hour, so an offline launch shows the last hour the Bridge recorded
  /// rather than `No history yet`. The archive remains the only source.
  Future<void> _backfillLiveHistory() async {
    final dao = sampleDao;
    if (dao == null) return;
    final newest = lastKnownReadingAt;
    final end = newest != null && newest.isBefore(content.now)
        ? newest
        : content.now;
    final start = end.subtract(const Duration(hours: 1));
    final rows = await dao.samplesInRange(
      fromMs: start.millisecondsSinceEpoch,
      toMs: end.millisecondsSinceEpoch + 1,
    );
    if (rows.isEmpty) return;
    recentHistory.seed(<RecentSample>[
      for (final row in rows)
        RecentSample(
          seq: row.seq,
          time: DateTime.fromMillisecondsSinceEpoch(row.recordedMs),
          tempsF: <double?>[
            for (final value in row.tempsF10) value == null ? null : value / 10,
          ],
          clockValid: row.clockValid,
          billowsAttached: false,
        ),
    ]);
  }

  /// Scans for the saved Bridge by BLE identity, then by name, and connects.
  ///
  /// Returns after the bounded foreground scan. A missing Bridge leaves the
  /// shell on Live with `Looking for the Bridge…` and the archive's values.
  Future<void> connectSavedBridge() async {
    final saved = savedBridge;
    if (saved == null) {
      beginSetup();
      return;
    }
    final client = bleClient;
    if (client == null || launchScanning) return;
    launchScanning = true;
    lookingForBridge = true;
    phase = ConnectionPhase.offline;
    notifyListeners();
    _LaunchScanResult result;
    try {
      final status = await client.platformStatus();
      if (status.state != BleAppState.ready) {
        _applyPlatformBlocked(status.state);
        return;
      }
      result = await _scanForSavedBridge(saved);
    } finally {
      // A blocked launch already cleared the flag; a scan result path clears it
      // below. Either way the Connect action becomes available again.
    }
    if (result.blockedBy != null) {
      _applyPlatformBlocked(result.blockedBy!);
      return;
    }
    final device = result.device;
    if (device == null) {
      launchScanning = false;
      lookingForBridge = true;
      phase = ConnectionPhase.offline;
      notifyListeners();
      return;
    }
    phase = ConnectionPhase.syncing;
    notifyListeners();
    final link = ensureLink();
    try {
      await link.connectAndSecure(device);
      await _persistBridgeIdentity(device.id, device.name);
      lookingForBridge = false;
    } on BridgeLinkException catch (error) {
      lookingForBridge = false;
      // Bluetooth going off mid-connect is BLOCKED, not a generic failure.
      if (phase != ConnectionPhase.blocked) {
        // A stale bond is a named failure with the Forget/re-pair escape; it is
        // never an unexplained OS prompt on launch.
        phase = _isBondFailure(error)
            ? ConnectionPhase.failed
            : (hasSavedData ? ConnectionPhase.offline : ConnectionPhase.failed);
      }
    } catch (_) {
      lookingForBridge = false;
      if (phase != ConnectionPhase.blocked) {
        phase = hasSavedData ? ConnectionPhase.offline : ConnectionPhase.failed;
      }
    } finally {
      launchScanning = false;
      notifyListeners();
    }
  }

  bool _isBondFailure(BridgeLinkException error) {
    switch (error.failure) {
      case BridgeLinkFailure.bondRequired:
      case BridgeLinkFailure.bondFailed:
      case BridgeLinkFailure.bondCancelled:
        return true;
      case BridgeLinkFailure.protocolMismatch:
      case BridgeLinkFailure.notSecured:
      case BridgeLinkFailure.controlTimeout:
      case BridgeLinkFailure.syncTimeout:
      case BridgeLinkFailure.syncFailed:
      case BridgeLinkFailure.syncGap:
      case BridgeLinkFailure.notConnected:
      case BridgeLinkFailure.operationFailed:
        return false;
    }
  }

  Future<_LaunchScanResult> _scanForSavedBridge(SavedBridge saved) async {
    final client = bleClient;
    if (client == null) return const _LaunchScanResult();
    final completer = Completer<_LaunchScanResult>();
    StreamSubscription<BleDevice>? subscription;
    Timer? timeout;
    void finish(_LaunchScanResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    timeout = Timer(launchScanWindow, () async {
      await subscription?.cancel();
      await client.stopScan();
      finish(const _LaunchScanResult());
    });
    try {
      subscription = client
          .scan(timeout: launchScanWindow)
          .listen(
            (device) {
              if (!device.isCompatibleBridge) return;
              final match = selectPreferredBridge(
                <BleDevice>[device],
                rememberedDeviceId: saved.id,
                rememberedName: saved.name,
              );
              if (match == null) return;
              unawaited(subscription?.cancel());
              unawaited(client.stopScan());
              finish(_LaunchScanResult(device: match));
            },
            onError: (Object error) {
              final blocked = error is BleException ? error.appState : null;
              finish(_LaunchScanResult(blockedBy: blocked));
            },
            onDone: () => finish(const _LaunchScanResult()),
          );
    } on BleException catch (error) {
      finish(_LaunchScanResult(blockedBy: error.appState));
    } catch (_) {
      finish(const _LaunchScanResult());
    }
    final result = await completer.future;
    timeout.cancel();
    await subscription?.cancel();
    await client.stopScan();
    return result;
  }

  void _subscribePlatformStates() {
    _platformSubscription ??= bleClient?.platformStates.listen(
      _onPlatformState,
    );
  }

  void _onPlatformState(BleAppState state) {
    switch (state) {
      case BleAppState.ready:
        if (phase == ConnectionPhase.blocked &&
            hasSavedBridge &&
            link?.device == null) {
          unawaited(connectSavedBridge());
        }
        break;
      case BleAppState.bluetoothOff:
        _applyPlatformBlocked(state);
        break;
      case BleAppState.permissionNeeded:
      case BleAppState.permissionBlocked:
        _applyPlatformBlocked(state);
        break;
      case BleAppState.unsupportedPhone:
        _applyPlatformBlocked(state);
        break;
      case BleAppState.noResults:
      case BleAppState.pairingFailed:
      case BleAppState.promptTimeout:
      case BleAppState.staleBond:
      case BleAppState.phoneListFull:
      case BleAppState.connectionFailed:
      case BleAppState.gattError:
      case BleAppState.timeout:
        break;
    }
  }

  void _applyPlatformBlocked(BleAppState state) {
    switch (state) {
      case BleAppState.bluetoothOff:
        blockReason = BlockReason.bluetoothOff;
        break;
      case BleAppState.permissionNeeded:
        blockReason = BlockReason.permissionDenied;
        break;
      case BleAppState.permissionBlocked:
        blockReason = BlockReason.permissionBlocked;
        break;
      case BleAppState.unsupportedPhone:
        blockReason = BlockReason.unsupportedPhone;
        break;
      default:
        return;
    }
    launchScanning = false;
    lookingForBridge = false;
    phase = ConnectionPhase.blocked;
    // A blocked adapter is a named state, not a sync state: clear the sync card
    // and any backfill progress so the blocked notice is the only sync surface.
    syncState = SyncState.idle;
    syncProgressPercent = 0;
    _bridgeConnectedSince = null;
    _smokeXConnectedSince = null;
    notifyListeners();
  }

  void _onLinkBlocked(BlockReason reason) {
    blockReason = reason;
    launchScanning = false;
    lookingForBridge = false;
    syncState = SyncState.idle;
    syncProgressPercent = 0;
    notifyListeners();
  }

  Future<void> _persistBridgeIdentity(String id, String name) async {
    if (id.trim().isEmpty) return;
    rememberedBridgeId = id;
    rememberedBridgeName = name;
    final existing = savedBridge;
    savedBridge = SavedBridge(
      id: id,
      name: name,
      lastSeenMs: content.now.millisecondsSinceEpoch,
      generation: existing?.generation ?? 0,
      cursorAfter: existing?.cursorAfter,
      cursorBefore: existing?.cursorBefore,
      deviceMinSeq: existing?.deviceMinSeq,
      deviceMaxSeq: existing?.deviceMaxSeq,
    );
    final dao = sampleDao;
    if (dao == null) return;
    final stored = await dao.bridgeById(id);
    if (stored == null) {
      await dao.saveBridge(savedBridge!);
    } else {
      // Identity only: never regress the archive generation/cursors written by
      // the connectSync that preceded this touch.
      await dao.touchBridge(
        id: id,
        name: name,
        lastSeenMs: content.now.millisecondsSinceEpoch,
      );
    }
    final refreshed = await dao.bridgeById(id);
    if (refreshed != null) {
      savedBridge = refreshed;
      localMaxSeq = refreshed.cursorAfter;
    }
  }

  Future<void> _touchSavedIdentity() async {
    final id = rememberedBridgeId;
    final name = rememberedBridgeName;
    if (id == null || name == null) return;
    final dao = sampleDao;
    if (dao == null) return;
    try {
      await dao.touchBridge(
        id: id,
        name: name,
        lastSeenMs: content.now.millisecondsSinceEpoch,
      );
    } catch (_) {
      // A failed touch never breaks a healthy link; the next connect retries.
    }
  }

  Future<void> _clearSavedIdentity() async {
    final dao = sampleDao;
    final ids = <String>{?savedBridge?.id, ?rememberedBridgeId};
    savedBridge = null;
    rememberedBridgeId = null;
    rememberedBridgeName = null;
    if (dao == null) return;
    if (ids.isEmpty) {
      await dao.removeAllBridges();
      return;
    }
    for (final id in ids) {
      await dao.removeBridge(id);
    }
  }

  /// Creates the link procedures once and wires them to this controller.
  ///
  /// Setup calls it after the bond; Live pull-to-refresh and app resume reuse
  /// the same instance. Throws when no BLE client is configured.
  BridgeLink ensureLink({
    BridgeLinkSettings settings = const BridgeLinkSettings(),
    BridgeSyncSink? sink,
    DateTime Function()? nowUtc,
    Duration Function()? elapsed,
    Future<void> Function(Duration duration)? wait,
    BridgeLinkTimer Function(Duration duration, void Function() action)?
    schedule,
    Future<bool> Function()? bondPrompt,
  }) {
    final existing = link;
    if (existing != null) return existing;
    final client = bleClient;
    if (client == null) {
      throw StateError('BridgeController has no BleClient');
    }
    final created = BridgeLink(
      client: client,
      archive: _ensureArchive(),
      host: BridgeLinkHost(
        onPhase: _onLinkPhase,
        onLive: _onLinkLive,
        onInfo: _onLinkInfo,
        onStats: _onLinkStats,
        onConfig: _onLinkConfig,
        onSync: _onLinkSync,
        onReconnect: _onLinkReconnect,
        onRssi: _onLinkRssi,
        onBlocked: _onLinkBlocked,
        // The OS bond is started only by SetupFlow.pair(), after the approved
        // "look at the Bridge screen" instruction. A reconnect that finds a
        // stale bond therefore falls through to the named unreachable/Forget
        // path instead of raising an unexplained system prompt.
        onBondPrompt: bondPrompt ?? () async => false,
      ),
      settings: settings,
      sink: sink ?? recentHistory,
      localMaxSeq: () => localMaxSeq,
      onLocalMaxSeq: (seq) {
        localMaxSeq = seq;
        notifyListeners();
      },
      nowUtc: nowUtc,
      elapsed: elapsed,
      wait: wait,
      schedule: schedule,
    )..attach();
    link = created;
    return created;
  }

  ArchiveSyncCoordinator? _ensureArchive() {
    final dao = sampleDao;
    if (dao == null) return null;
    return _archive ??= ArchiveSyncCoordinator(
      dao: dao,
      now: () => content.now,
      onStatus: _onArchiveStatus,
      onBatch: _onArchiveBatch,
    );
  }

  /// The durable History reader, or null for review builds and tests that do
  /// not own a database.
  HistoryArchive? get historyArchive {
    final dao = sampleDao;
    if (dao == null) return null;
    return _historyArchive ??= HistoryArchive(dao: dao, now: () => content.now);
  }

  /// The explicit deletion seam, or null for review builds without a database.
  HistoryDeletionService? get historyDeletion {
    final dao = sampleDao;
    if (dao == null) return null;
    return _historyDeletion ??= HistoryDeletionService(
      dao: dao,
      now: () => content.now,
    );
  }

  /// Exposes the durable sync state for tests and later History tasks.
  ArchiveSyncCoordinator? get archiveSync => _archive;

  void _onArchiveStatus(SyncStatusSnapshot snapshot) {
    switch (snapshot.status) {
      case SyncStatus.idle:
        syncState = SyncState.idle;
        break;
      case SyncStatus.syncing:
        syncState = snapshot.phase == SyncPhase.backfill
            ? SyncState.backfill
            : SyncState.recent;
        break;
      case SyncStatus.partial:
        syncState = SyncState.backfill;
        break;
      case SyncStatus.complete:
        syncState = SyncState.complete;
        lastSyncedAt = content.now;
        historyRevision++;
        unawaited(refreshLocalHistorySummary());
        final hasArchive = snapshot.cursorAfter != null || phoneRecords > 0;
        hasSavedData = hasArchive;
        savedDataEmpty = !hasArchive;
        break;
      case SyncStatus.error:
        syncState = SyncState.error;
        break;
    }
    final cursor = snapshot.cursorAfter;
    if (cursor != null) localMaxSeq = cursor;
    notifyListeners();
  }

  void _onArchiveBatch(StoredSyncBatch batch) {
    if (batch.records.isEmpty) return;
    historyRevision++;
    // Keep the approved History shell fed from the same accepted batch; the
    // durable rows are already committed by the coordinator.
    unawaited(
      recentHistory.accept(
        BridgeSyncBatch(
          records: batch.records,
          startSeq: batch.records.first.seq,
          endSeq: batch.records.last.seq,
          nextSeq: batch.records.last.seq + 1,
          direction: batch.direction,
          generation: batch.generation,
        ),
      ),
    );
  }

  void _onLinkPhase(ConnectionPhase value) {
    final previous = phase;
    phase = value;
    final becameHealthy =
        (value == ConnectionPhase.live || value == ConnectionPhase.stale) &&
        previous != ConnectionPhase.live &&
        previous != ConnectionPhase.stale;
    if (becameHealthy) {
      lookingForBridge = false;
      blockReason = BlockReason.none;
      bridgeOff = false;
      unawaited(_touchSavedIdentity());
      if (_pendingUnitsWrite) {
        unawaited(_writeUnits(units));
      }
    }
    switch (value) {
      case ConnectionPhase.live:
      case ConnectionPhase.stale:
      case ConnectionPhase.syncing:
        // A new Bluetooth session starts the App/Bridge timer again. A plain
        // syncing pass on an already-healthy link keeps the existing timer.
        if (_bridgeConnectedSince == null ||
            previous == ConnectionPhase.reconnecting ||
            previous == ConnectionPhase.failed ||
            previous == ConnectionPhase.offline ||
            previous == ConnectionPhase.blocked ||
            previous == ConnectionPhase.setup) {
          _bridgeConnectedSince = DateTime.now();
          _smokeXConnectedSince = null;
          // A new link session has not observed Billows yet.
          billowsAttachment = BillowsAttachment.unknown;
          billowsSeenThisSession = false;
          billowsLastDetectedAt = null;
          billowsLostAt = null;
        }
        break;
      case ConnectionPhase.reconnecting:
      case ConnectionPhase.failed:
      case ConnectionPhase.offline:
      case ConnectionPhase.blocked:
      case ConnectionPhase.setup:
        lookingForBridge = false;
        _bridgeConnectedSince = null;
        _smokeXConnectedSince = null;
        // A stale phase must never leave sync/backfill progress on screen.
        syncState = SyncState.idle;
        syncProgressPercent = 0;
        break;
    }
    if (value == ConnectionPhase.syncing) {
      syncState = SyncState.recent;
      syncProgressPercent = 10;
    }
    notifyListeners();
  }

  void _onLinkRssi(int value) {
    bleRssi = value;
    notifyListeners();
  }

  void _onLinkLive(BridgeLiveUpdate update) {
    final live = update.live;
    liveReceivedAt = update.receivedAt;
    smokeXAgeOverride = null;
    liveProbeTemps = <double?>[
      for (var index = 0; index < 4; index++) live.tempF(index),
    ];
    batteryPercent = live.batteryPct == bleBatteryUnknown
        ? batteryPercent
        : live.batteryPct;
    rssi = live.rssiLora;
    storageOk = live.storageOk;
    smokeXStatus = live.smokePaired
        ? (live.smokeLive ? SmokeXStatus.pairedLive : SmokeXStatus.pairedLost)
        : SmokeXStatus.unpaired;
    smokeXLiveHint = live.smokeLive;
    if (live.smokePaired && live.smokeLive && live.ageS <= 90) {
      _smokeXConnectedSince ??= update.receivedAt;
    } else {
      _smokeXConnectedSince = null;
    }
    smokeXChannel4SetKnown = live.billowsTargetF10 != 0;
    if (live.billowsTargetF10 != 0) {
      smokeXChannel4SetF = (live.billowsTargetF10 / 10).round();
    }
    // The live flag is authoritative in both directions. Only a real attached
    // reading makes the Billows card appear; a stale previous session must not.
    final wasDetected = billowsDetected;
    billowsAttachment = live.billowsAttached
        ? BillowsAttachment.attached
        : BillowsAttachment.detached;
    if (live.billowsAttached) {
      billowsSeenThisSession = true;
      billowsLastDetectedAt = update.receivedAt;
      billowsLostAt = null;
    } else if (wasDetected) {
      // Keep the last attached time; this is the age shown for the lost state.
      billowsLostAt = update.receivedAt;
    }
    // Make the graph move as the readings arrive instead of waiting for the
    // next history sync.
    recentHistory.recordLive(
      seq: live.seq,
      time: update.receivedAt.toLocal().subtract(Duration(seconds: live.ageS)),
      tempsF: <double?>[
        for (var index = 0; index < 4; index++) live.tempF(index),
      ],
      clockValid: live.clockValid,
      billowsAttached: live.billowsAttached,
    );
    notifyListeners();
  }

  void _onLinkInfo(BridgeInfo info) {
    deviceId = info.deviceId;
    firmware = info.firmware;
    protocol = '${info.protoMajor}.${info.protoMinor}';
    // `caps.billows_observe` gates the Live card before the first paint.
    billowsObserveCap = info.billowsObserve;
  }

  /// Adopts the Bridge's stored config on connect. Local-only preferences are
  /// not overwritten: pick the Bridge's values for fields this session has not
  /// edited, and keep a queued units choice so it can be pushed to the OLED.
  void _onLinkConfig(BridgeConfig config) {
    if (_configWriteInFlight) return;
    if (config.deviceName.isNotEmpty) deviceName = config.deviceName;
    displayTimeoutSeconds = config.displayTimeoutSeconds;
    if (!_pendingUnitsWrite) {
      final adopted = config.units == 0 ? Units.celsius : Units.fahrenheit;
      if (adopted != units) {
        units = adopted;
        unawaited(_persistUnits(adopted));
      }
    }
    unitsSaveState = SettingsSaveState.idle;
    nameSaveState = SettingsSaveState.idle;
    timeoutSaveState = SettingsSaveState.idle;
    unitsSaveError = null;
    nameSaveError = null;
    timeoutSaveError = null;
    notifyListeners();
  }

  void _onLinkStats(BridgeStats stats) {
    bridgeRecords = stats.hasReadings ? stats.recordsStored : 0;
    if (stats.recordsCapacity > 0) {
      bridgeCapacity = stats.recordsCapacity;
    }
    bridgeGeneration = stats.generation;
    bridgeOldestReadingAt = _statsTime(stats.oldestUnixS);
    bridgeNewestReadingAt = _statsTime(stats.newestUnixS);
    notifyListeners();
  }

  DateTime? _statsTime(int unixS) {
    if (unixS <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      unixS * 1000,
      isUtc: true,
    ).toLocal();
  }

  void _onLinkSync(BridgeSyncProgress progress) {
    syncState = progress.state;
    syncProgressPercent = progress.percent;
    if (progress.state == SyncState.complete) {
      lastSyncedAt = DateTime.now();
    }
    if (progress.state == SyncState.complete && progress.storedRecords > 0) {
      hasSavedData = true;
      savedDataEmpty = false;
    }
    notifyListeners();
  }

  void _onLinkReconnect(int attempt, int total, Duration? nextDelay) {
    reconnectAttempts = total;
    if (attempt == 0) {
      nextReconnectIn = Duration.zero;
      return;
    }
    reconnectAttempt = attempt;
    nextReconnectIn = nextDelay ?? Duration.zero;
    notifyListeners();
  }

  /// Live pull-to-refresh. Cuts a reconnect wait short; otherwise reads `live`
  /// and catches up forward.
  Future<void> refreshLink() async {
    final current = link;
    if (current != null && current.device != null) {
      await current.pullToRefresh();
      return;
    }
    await retryConnection();
  }

  /// App resume: health check + forward sync, or resume the reconnect loop.
  Future<void> onAppResume() async {
    await link?.onAppResume();
  }

  ThemeMode _themeMode = ThemeMode.system;

  static const String themePreferenceKey = 'appearance.theme_mode';
  static const String unitsPreferenceKey = 'preferences.temperature_units';
  static const String changeWindowPreferenceKey =
      'preferences.live_change_window_minutes';

  /// Device locale (`en_US`, `de_DE`, …) used by the formatter layer. It is not
  /// persisted: the platform is the source.
  String localeName;

  /// Device 12/24-hour setting; the platform is the source.
  bool use24Hour;

  /// Applies the platform locale and clock convention and returns true when
  /// either changed, so the caller can repaint the pre-formatted view states.
  bool applyPlatformFormatting({
    required String localeName,
    required bool use24Hour,
  }) {
    final changed =
        this.localeName != localeName || this.use24Hour != use24Hour;
    this.localeName = localeName;
    this.use24Hour = use24Hour;
    return changed;
  }

  /// Repaints the pre-formatted view states after a locale/clock change. The
  /// platform pushes the new values in during a build, so the repaint is
  /// deferred by the caller to the next frame.
  void repaintForFormatting() => notifyListeners();

  /// Restores local-only preferences before the first frame. A missing or
  /// unreadable value keeps `System`, never a guessed theme.
  Future<void> loadLocalPreferences() async {
    try {
      final storedTheme = await repository.preferences.read(themePreferenceKey);
      final restoredTheme = switch (storedTheme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      if (restoredTheme != _themeMode) {
        _themeMode = restoredTheme;
        notifyListeners();
      }
    } catch (_) {
      // A broken preferences read must not block launch.
    }
    try {
      final storedUnits = await repository.preferences.read(unitsPreferenceKey);
      final restoredUnits = switch (storedUnits) {
        'celsius' => Units.celsius,
        'fahrenheit' => Units.fahrenheit,
        _ => null,
      };
      if (restoredUnits != null && restoredUnits != units) {
        // The Bridge's stored config remains authoritative once connected;
        // this is the honest value for the first frame and an offline launch.
        units = restoredUnits;
        notifyListeners();
      }
    } catch (_) {
      // Fall back to the default unit rather than blocking launch.
    }
    try {
      final storedWindow = await repository.preferences.read(
        changeWindowPreferenceKey,
      );
      final restoredWindow = int.tryParse(storedWindow ?? '');
      if (restoredWindow != null) {
        final bounded = restoredWindow.clamp(1, 60);
        if (bounded != tempChangeWindowMinutes) {
          tempChangeWindowMinutes = bounded;
          notifyListeners();
        }
      }
    } catch (_) {
      // Fall back to the default window rather than blocking launch.
    }
  }

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    unawaited(_persistTheme(_themeMode));
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    unawaited(_persistTheme(mode));
    notifyListeners();
  }

  Future<void> _persistTheme(ThemeMode mode) async {
    try {
      await repository.preferences.write(themePreferenceKey, mode.name);
    } catch (_) {
      // Appearance still applies for this session; the next tap retries.
    }
  }

  /// Units are a local presentation preference as well as a Bridge setting, so
  /// the choice survives relaunch even while the Bridge is out of range.
  Future<void> _persistUnits(Units value) async {
    try {
      await repository.preferences.write(
        unitsPreferenceKey,
        value == Units.celsius ? 'celsius' : 'fahrenheit',
      );
    } catch (_) {
      // The local change still applies for this session.
    }
  }

  Future<void> _persistChangeWindow(int minutes) async {
    try {
      await repository.preferences.write(
        changeWindowPreferenceKey,
        minutes.toString(),
      );
    } catch (_) {
      // The local change still applies for this session.
    }
  }

  AppTab tab = AppTab.live;
  ConnectionPhase phase = ConnectionPhase.live;
  BlockReason blockReason = BlockReason.none;
  ProbeHealth probeHealth = ProbeHealth.live;
  ProbePresence probePresence = ProbePresence.all;
  SmokeXStatus smokeXStatus = SmokeXStatus.pairedLive;
  bool storageOk = true;
  bool slowLink = false;
  SyncState syncState = SyncState.idle;
  int syncProgressPercent = 64;

  BillowsAttachment billowsAttachment = BillowsAttachment.attached;

  /// `caps.billows_observe` from the `info` read. A Bridge that does not decode
  /// Billows fields never shows the card or a loss notice.
  bool billowsObserveCap = true;

  /// Test/clock seam for the age of the newest valid X4 packet. Production
  /// fills this from the phone's receipt time (T35); leaving it null keeps the
  /// prototype-derived age for the approved baseline.
  Duration? smokeXAgeOverride;

  /// Phone receipt time of the newest `live` sample. When [smokeXAgeOverride]
  /// is null this is the source of the displayed age, so a skewed bridge clock
  /// cannot fake freshness (06 §6.3).
  DateTime? liveReceivedAt;

  /// Start of the current App/Bridge Bluetooth session. Cleared on every link
  /// loss, so the Live card's timer never accumulates across reconnects.
  DateTime? _bridgeConnectedSince = DateTime.now().subtract(
    const Duration(hours: 2, minutes: 14),
  );

  /// Start of the current Smoke X4 receive session, as seen through the Bridge.
  DateTime? _smokeXConnectedSince = DateTime.now().subtract(
    const Duration(hours: 2, minutes: 10),
  );

  /// RSSI of the phone's Bluetooth link to the Bridge. This is a different
  /// radio link from the Bridge→Smoke X4 LoRa RSSI in [rssi].
  int? bleRssi = -58;

  /// Probe temperatures from the newest `live` sample, in °F. `null` keeps the
  /// content-provided fixture values (review builds and pre-sync launches).
  List<double?>? liveProbeTemps;
  bool smokeXChannel4SetKnown = true;
  int smokeXChannel4SetF = 225;
  bool billowsSeenThisSession = true;

  /// Phone receipt time of the newest state packet that reported Billows
  /// attached. Null in fixture/review builds; production fills it from `live`.
  DateTime? billowsLastDetectedAt;

  /// Phone receipt time of the packet that first reported Billows detached, so
  /// the lost notice and connection log age from a real event, not a guess.
  DateTime? billowsLostAt;

  HistoryRange historyRange = HistoryRange.twentyFourHours;
  int? historyProbe;
  DateTimeRange? historyCustomRange;
  HistorySort historySort = HistorySort.probe;
  bool historyHasData = false;
  bool historyOneProbe = false;
  bool historyEstimated = false;
  bool historyMissingFromBridge = false;

  bool offlineCache = true;
  bool hasSavedBridge = true;
  bool hasSavedData = false;
  bool savedDataEmpty = false;

  /// True after the saved Bridge was forgotten or factory-reset while history
  /// on this phone remains. Setup names the entry as history from the old
  /// Bridge instead of implying it belongs to a currently configured device.
  bool historyOrphaned = false;

  /// Set when a best-effort forget could not be confirmed. Setup renders it so
  /// the user knows the Bridge may still hold the pairing.
  String? destructiveNotice;

  /// True after the Bridge accepted `power_off`. No screen may present the
  /// Bridge as reachable until a later connect succeeds.
  bool bridgeOff = false;

  Units units = Units.fahrenheit;

  /// Window used for the Live probe change indicator.
  int tempChangeWindowMinutes = 5;
  int displayTimeoutSeconds = 60;
  String deviceName = 'Backyard Bridge';

  SettingsSaveState saveState = SettingsSaveState.idle;

  /// Per-field write state. A field never shows `Saved` until the Bridge has
  /// accepted the whole struct and the read-back matches.
  SettingsSaveState unitsSaveState = SettingsSaveState.idle;
  SettingsSaveState nameSaveState = SettingsSaveState.idle;
  SettingsSaveState timeoutSaveState = SettingsSaveState.idle;
  String? unitsSaveError;
  String? nameSaveError;
  String? timeoutSaveError;

  /// A units choice made while offline is applied on this phone immediately and
  /// written to the Bridge on the next healthy connect.
  bool _pendingUnitsWrite = false;
  bool _configWriteInFlight = false;
  Future<void> _configChain = Future<void>.value();

  int bridgeRecords;
  int bridgeCapacity;
  int phoneRecords;
  String savedDataRange;
  String savedDataSize;

  /// Bridge `stats.oldest_unix_s` / `newest_unix_s`. Null until the Bridge has
  /// answered or when the field is 0 (unknown). These are Bridge-side values,
  /// never derived from the phone archive.
  DateTime? bridgeOldestReadingAt;
  DateTime? bridgeNewestReadingAt;

  /// Bridge generation from the last `stats` read. Used only to notice a clear
  /// boundary; a generation change never deletes phone history.
  int? bridgeGeneration;

  String deviceId = 'A4F2';
  String firmware = '0.1.0';
  String protocol = '1.0';
  int batteryPercent = 87;
  int rssi = -71;

  /// The BLE identity of the Bridge this phone last completed setup with.
  /// Persistence lands with the archive tasks; setup uses it to prefer the
  /// remembered advertisement by device ID, then by name.
  String? rememberedBridgeId;
  String? rememberedBridgeName;
  int? negotiatedMtu;

  /// The saved `bridge` row loaded on launch. `id` is the BLE address, `name`
  /// the last observed advertised name and `last_seen_ms` the ordering key.
  SavedBridge? savedBridge;

  /// Wall time of the newest archived reading, used by the offline-with-cache
  /// copy instead of a made-up age.
  DateTime? lastKnownReadingAt;

  /// A saved Bridge exists but is not connected. The shell stays on Live and
  /// offers a manual Connect instead of reopening Setup (06 §6.3).
  bool lookingForBridge = false;

  /// A launch scan is in flight; the Connect action is hidden until it ends.
  bool launchScanning = false;

  /// Foreground-only launch scan window, injectable for host tests.
  Duration launchScanWindow = bleScanTimeout;

  StreamSubscription<BleAppState>? _platformSubscription;

  /// The newest sequence stored on this phone. T35 uses it as the forward-sync
  /// cursor; T39–T41 replace it with the durable archive cursor.
  int? localMaxSeq;

  /// Phone time of the last completed sync, so History never shows a fixed
  /// "Synced 2 min ago" while background syncs keep running.
  DateTime? lastSyncedAt;

  /// The production link procedures over [bleClient]. Setup creates it after a
  /// bond; Live refresh/resume call into the same instance.
  BridgeLink? link;

  /// Real reconnect progress, so the approved copy names the actual attempt.
  int reconnectAttempt = 2;
  int reconnectAttempts = 6;
  Duration nextReconnectIn = const Duration(seconds: 4);

  bool get isConnected =>
      phase == ConnectionPhase.live ||
      phase == ConnectionPhase.stale ||
      phase == ConnectionPhase.syncing;

  bool get canEdit => isConnected;

  bool get isOffline =>
      phase == ConnectionPhase.offline ||
      phase == ConnectionPhase.failed ||
      phase == ConnectionPhase.reconnecting ||
      phase == ConnectionPhase.blocked;

  bool get billowsDetected => billowsAttachment == BillowsAttachment.attached;

  bool get billowsLostThisSession => billowsSeenThisSession && !billowsDetected;

  /// The last time the phone heard from the Bridge. A stale probe reading can
  /// still be accompanied by a healthy Bluetooth link.
  Duration? get bridgeLastContactAge {
    switch (phase) {
      case ConnectionPhase.live:
      case ConnectionPhase.stale:
        return const Duration(seconds: 4);
      case ConnectionPhase.syncing:
        return const Duration(seconds: 2);
      case ConnectionPhase.reconnecting:
        return const Duration(minutes: 2);
      case ConnectionPhase.failed:
      case ConnectionPhase.offline:
      case ConnectionPhase.blocked:
        final stored = lastKnownReadingAt;
        if (stored != null) {
          final age = DateTime.now().toUtc().difference(stored.toUtc());
          return age.isNegative ? Duration.zero : age;
        }
        return offlineCache ? const Duration(hours: 2) : null;
      case ConnectionPhase.setup:
        return null;
    }
  }

  Duration get bridgeConnectedFor {
    final since = _bridgeConnectedSince;
    if (since == null) return Duration.zero;
    final value = DateTime.now().difference(since);
    return value.isNegative ? Duration.zero : value;
  }

  /// Duration of the current App→Bridge Bluetooth session.
  String get appBridgeConnectedForLabel {
    if (!isConnected) {
      return phase == ConnectionPhase.reconnecting ? 'Reconnecting' : 'Offline';
    }
    return _compactDuration(bridgeConnectedFor);
  }

  Duration get smokeXConnectedFor {
    final since = _smokeXConnectedSince;
    if (since == null) return Duration.zero;
    final value = DateTime.now().difference(since);
    return value.isNegative ? Duration.zero : value;
  }

  /// Duration the Smoke X4 has been continuously delivering readings.
  String get smokeXConnectedForLabel {
    if (!isConnected) return 'Last known';
    switch (smokeXStatus) {
      case SmokeXStatus.unpaired:
        return 'Not paired';
      case SmokeXStatus.pairedLost:
        return 'Signal lost';
      case SmokeXStatus.pairedLive:
        if (!smokeXReceiving) return 'No readings';
        return _compactDuration(smokeXConnectedFor);
    }
  }

  /// Connected duration without seconds, for the compact Live status row.
  String get bridgeConnectedForLabel => _compactDuration(bridgeConnectedFor);

  /// The BLE link state, separate from Smoke X4 telemetry freshness.
  String get bridgeConnectedLabel {
    if (isConnected) return 'Bridge connected · $bridgeConnectedForLabel';
    if (lookingForBridge) return 'Looking for the Bridge…';
    switch (phase) {
      case ConnectionPhase.reconnecting:
        return 'Reconnecting… attempt $reconnectAttempt of $reconnectAttempts';
      case ConnectionPhase.blocked:
        return 'Blocked · $bridgeLinkDetail';
      case ConnectionPhase.setup:
        return 'Bridge not connected';
      case ConnectionPhase.failed:
      case ConnectionPhase.offline:
        if (!offlineCache) return 'Bridge disconnected · nothing saved yet';
        final age = bridgeLastContactAge;
        if (age == null) return 'Bridge not connected';
        return 'Bridge disconnected · last connected ${_proseDuration(age)} ago';
      case ConnectionPhase.live:
      case ConnectionPhase.stale:
      case ConnectionPhase.syncing:
        return 'Bridge connected · $bridgeConnectedForLabel';
    }
  }

  /// The Smoke X4 telemetry state. `Receiving readings` is only valid inside
  /// the 90 s fresh window; otherwise the text names the age.
  String get telemetryStatusLabel {
    if (phase == ConnectionPhase.setup) return 'No readings yet';
    if (isConnected) {
      final age = smokeXLastPacketAge;
      if (age == null) return 'No readings yet';
      if (smokeXReceiving && age <= const Duration(seconds: 90)) {
        return 'Sensor data received ${_shortDuration(age)} ago';
      }
      if (age <= const Duration(minutes: 10)) {
        return 'No readings for ${_proseDuration(age)}';
      }
      return 'Smoke X signal lost · ${_proseDuration(age)} ago';
    }
    if (offlineCache) {
      final age = bridgeLastContactAge;
      if (age == null) return 'Showing saved readings';
      return 'Showing saved readings · last reading ${_proseDuration(age)} ago';
    }
    return 'No readings yet';
  }

  Duration? get smokeXLastPacketAge {
    final override = smokeXAgeOverride;
    if (override != null) return override;
    final receivedAt = liveReceivedAt;
    if (receivedAt != null) {
      final age = DateTime.now().toUtc().difference(receivedAt);
      return age.isNegative ? Duration.zero : age;
    }
    if (!isConnected) {
      final bridgeAge = bridgeLastContactAge;
      if (bridgeAge == null) return null;
      return bridgeAge + const Duration(seconds: 12);
    }
    switch (smokeXStatus) {
      case SmokeXStatus.pairedLive:
        return phase == ConnectionPhase.stale
            ? const Duration(minutes: 4)
            : const Duration(seconds: 12);
      case SmokeXStatus.pairedLost:
        return const Duration(minutes: 14);
      case SmokeXStatus.unpaired:
        return null;
    }
  }

  bool get smokeXReceiving {
    if (!isConnected ||
        phase == ConnectionPhase.stale ||
        smokeXStatus != SmokeXStatus.pairedLive) {
      return false;
    }
    final age = smokeXLastPacketAge;
    return age != null && age <= const Duration(seconds: 90);
  }

  String get bridgeLinkStatusLabel {
    switch (phase) {
      case ConnectionPhase.live:
      case ConnectionPhase.stale:
        return 'Connected';
      case ConnectionPhase.syncing:
        return 'Connected · syncing';
      case ConnectionPhase.reconnecting:
        return 'Reconnecting';
      case ConnectionPhase.failed:
      case ConnectionPhase.offline:
        return 'Offline';
      case ConnectionPhase.blocked:
        return 'Blocked';
      case ConnectionPhase.setup:
        return 'Not connected';
    }
  }

  /// Settings uses this shorter line because the status LED already says
  /// `Connected`; repeating how long the link has been up adds no signal.
  String get bridgeLastContactDetail {
    if (isConnected) {
      final age = bridgeLastContactAge;
      if (age == null) return 'No contact yet';
      return 'Updated ${_shortDuration(age)} ago';
    }
    return bridgeLinkDetail;
  }

  /// Four cell-style bars, from weak (1) to excellent (4).
  int get signalBars => _barsForRssi(rssi);

  /// The Bluetooth link between this phone and the Bridge.
  int get bleSignalBars => _barsForRssi(bleRssi ?? -85);

  String get signalQualityLabel => _signalWord(signalBars);

  String get bleSignalQualityLabel => _signalWord(bleSignalBars);

  int _barsForRssi(int value) {
    if (value >= -60) return 4;
    if (value >= -70) return 3;
    if (value >= -80) return 2;
    return 1;
  }

  String _signalWord(int level) {
    switch (level) {
      case 4:
        return 'Excellent';
      case 3:
        return 'Good';
      case 2:
        return 'Fair';
      default:
        return 'Weak';
    }
  }

  String get bridgeLinkDetail {
    switch (phase) {
      case ConnectionPhase.live:
      case ConnectionPhase.stale:
      case ConnectionPhase.syncing:
        return 'Connected for ${_shortDuration(bridgeConnectedFor)} · updated ${_shortDuration(bridgeLastContactAge!)} ago';
      case ConnectionPhase.reconnecting:
        return 'Attempt $reconnectAttempt of $reconnectAttempts · next try in ${_shortDuration(nextReconnectIn)}';
      case ConnectionPhase.failed:
      case ConnectionPhase.offline:
        final age = bridgeLastContactAge;
        if (age == null) return 'Not connected';
        return 'Last connected ${_proseDuration(age)} ago';
      case ConnectionPhase.blocked:
        switch (blockReason) {
          case BlockReason.bluetoothOff:
            return 'Bluetooth is off';
          case BlockReason.permissionDenied:
          case BlockReason.permissionBlocked:
            return 'Bluetooth permission needed';
          case BlockReason.unsupportedPhone:
            return 'This phone cannot scan for Bluetooth LE';
          case BlockReason.none:
            return 'A connection is required';
        }
      case ConnectionPhase.setup:
        return 'Not paired with this phone';
    }
  }

  String get smokeXLinkStatusLabel {
    if (!isConnected) return 'Last known';
    if (smokeXStatus == SmokeXStatus.unpaired) return 'Not paired';
    final age = smokeXLastPacketAge;
    if (age != null && age <= const Duration(seconds: 90)) {
      return 'Receiving readings';
    }
    if (age != null && age <= const Duration(minutes: 10)) {
      return 'No readings';
    }
    return 'Signal lost';
  }

  String get smokeXLinkDetail {
    final age = smokeXLastPacketAge;
    if (age == null) return 'No readings yet';
    if (!isConnected) {
      return 'Last reading ${_proseDuration(age)} ago · last known';
    }
    return 'Updated ${_shortDuration(age)} ago';
  }

  String get lastSyncedLabel {
    final synced = lastSyncedAt;
    if (synced != null) {
      final age = DateTime.now().difference(synced);
      return 'Synced ${_proseDuration(age.isNegative ? Duration.zero : age)} ago';
    }
    if (isOffline) {
      final last = lastKnownReadingAt;
      if (last != null) {
        final age = DateTime.now().toUtc().difference(last.toUtc());
        return 'Synced ${_proseDuration(age.isNegative ? Duration.zero : age)} ago';
      }
      return offlineCache ? 'Synced 2 hr ago' : 'Not synced yet';
    }
    if (phase == ConnectionPhase.stale) return 'Synced 4 min ago';
    return 'Synced 2 min ago';
  }

  ProbeHealth get effectiveProbeHealth {
    if (smokeXStatus == SmokeXStatus.pairedLost) return ProbeHealth.stale;
    return probeHealth;
  }

  ProbeHealth get effectiveHealth {
    if (phase == ConnectionPhase.offline ||
        phase == ConnectionPhase.failed ||
        phase == ConnectionPhase.blocked ||
        phase == ConnectionPhase.setup) {
      return ProbeHealth.frozen;
    }
    if (phase == ConnectionPhase.reconnecting) return ProbeHealth.stale;
    return effectiveProbeHealth;
  }

  List<Probe> get probes {
    final base = liveProbeTemps ?? content.probeTemps;
    final health = effectiveHealth;
    return List<Probe>.generate(4, (index) {
      final presence = probePresence;
      final double? temp;
      if (presence == ProbePresence.none) {
        temp = null;
      } else if (presence == ProbePresence.detachedP3 && index == 2) {
        temp = null;
      } else {
        temp = base[index];
      }
      return Probe(number: index + 1, tempF: temp, health: health);
    });
  }

  bool probeHasHistory(int index) {
    if (recentHistory.hasAnyReadings) {
      return recentHistory.samples.any(
        (sample) => sample.tempsF[index] != null,
      );
    }
    if (!historyHasData) return false;
    return !historyOneProbe || index == 3;
  }

  /// Everything the phone has recorded. Custom ranges start here and can then
  /// be narrowed to any minute.
  DateTimeRange get entireHistoryRange {
    final recent = recentHistory.range;
    if (recent != null) {
      return DateTimeRange(start: recent.$1, end: recent.$2);
    }
    final window = content.historyWindow;
    return DateTimeRange(start: window.start, end: window.end);
  }

  /// One shared timeline for pairing, Bridge link and Billows events. Billows
  /// joins automatically, so a dropped fan appears beside the regular
  /// connection history instead of in a separate feature.
  List<ConnectionEvent> get connectionLog {
    final now = content.now;
    final events = <ConnectionEvent>[
      ConnectionEvent(
        title: 'Bridge connected',
        detail: 'Bluetooth · $deviceName ($deviceId)',
        time: now.subtract(bridgeConnectedFor),
        kind: ConnectionEventKind.bridgeConnected,
      ),
      ConnectionEvent(
        title: 'Smoke X paired',
        detail: 'The Bridge confirmed the pairing',
        time: now.subtract(bridgeConnectedFor).add(const Duration(minutes: 4)),
        kind: ConnectionEventKind.smokeXPaired,
      ),
    ];
    if (billowsSeenThisSession) {
      events.add(
        ConnectionEvent(
          title: 'Billows detected',
          detail: billowsDetected
              ? 'The Smoke X reports Billows detected'
              : 'Detected earlier this session · not detected now',
          time:
              billowsLastDetectedAt ??
              now.subtract(const Duration(seconds: 12)),
          kind: ConnectionEventKind.billowsConnected,
        ),
      );
    }
    if (billowsLostThisSession) {
      events.add(
        ConnectionEvent(
          title: 'Billows lost',
          detail: 'Was paired through the Smoke X · check fan power',
          time: billowsLostAt ?? now.subtract(const Duration(minutes: 12)),
          kind: ConnectionEventKind.billowsLost,
        ),
      );
    }
    if (phase == ConnectionPhase.offline || phase == ConnectionPhase.failed) {
      events.add(
        ConnectionEvent(
          title: 'Bridge disconnected',
          detail: 'Recording continues on the Bridge',
          time: now.subtract(bridgeLastContactAge ?? const Duration(hours: 2)),
          kind: ConnectionEventKind.bridgeLost,
        ),
      );
    }
    if (syncState == SyncState.complete) {
      events.add(
        ConnectionEvent(
          title: 'History synced',
          detail: 'Recent readings are on this phone',
          time: lastSyncedAt ?? now.subtract(const Duration(minutes: 2)),
          kind: ConnectionEventKind.sync,
        ),
      );
    }
    events.sort((a, b) => b.time.compareTo(a.time));
    return events;
  }

  List<ConnectionEvent> get billowsLog => connectionLog
      .where(
        (event) =>
            event.kind == ConnectionEventKind.billowsConnected ||
            event.kind == ConnectionEventKind.billowsLost,
      )
      .toList();

  String get unitsLabel => unitLabel(units);

  String get unitSuffix => unitLabel(units);

  double? toDisplayTemp(double? fahrenheit) {
    if (fahrenheit == null) return null;
    return toDisplayTemperature(fahrenheit, units);
  }

  String valueFor(double? fahrenheit) => temperatureValue(fahrenheit, units);

  String tempFor(double? fahrenheit) => temperatureText(fahrenheit, units);

  String get connectionTitle {
    if (lookingForBridge && !isConnected) return 'Looking for the Bridge…';
    switch (phase) {
      case ConnectionPhase.live:
        return 'Bridge connected';
      case ConnectionPhase.stale:
        return 'No readings';
      case ConnectionPhase.syncing:
        return 'Syncing saved readings';
      case ConnectionPhase.reconnecting:
        return 'Reconnecting…';
      case ConnectionPhase.failed:
        // A failed reconnect that still has saved readings keeps the honest
        // "saved readings" banner (T37): the chart is real cache, not live data.
        return offlineCache
            ? 'Showing saved readings'
            : 'Can’t reach the Bridge';
      case ConnectionPhase.offline:
        return offlineCache
            ? 'Showing saved readings'
            : 'Bridge disconnected · nothing saved yet';
      case ConnectionPhase.blocked:
        switch (blockReason) {
          case BlockReason.bluetoothOff:
            return 'Bluetooth is off';
          case BlockReason.permissionDenied:
          case BlockReason.permissionBlocked:
            return 'Bluetooth permission needed';
          case BlockReason.unsupportedPhone:
            return 'Phone not supported';
          case BlockReason.none:
            return 'Connection blocked';
        }
      case ConnectionPhase.setup:
        return 'Bridge not connected';
    }
  }

  String get connectionSubtitle {
    if (lookingForBridge && !isConnected) {
      if (!offlineCache) {
        return 'The Bridge was last connected ${_lastConnectedLabel()}. Nothing is saved on this phone yet.';
      }
      return 'Showing saved readings · last reading ${_lastConnectedLabel()}.';
    }
    switch (phase) {
      case ConnectionPhase.live:
        if (!smokeXLiveHint) {
          return 'Waiting for Smoke X readings';
        }
        return 'Receiving readings · updated 4s ago · battery $batteryPercent%';
      case ConnectionPhase.stale:
        return 'No readings for 4 min · the Bridge still answers';
      case ConnectionPhase.syncing:
        return syncState == SyncState.backfill
            ? 'Loading saved readings · ${slowLink ? 'slow connection' : 'in the background'}'
            : 'Syncing saved readings · last 15 minutes · $syncProgressPercent%';
      case ConnectionPhase.reconnecting:
        return 'Attempt $reconnectAttempt of $reconnectAttempts · next try in ${nextReconnectIn.inSeconds} sec';
      case ConnectionPhase.failed:
        return offlineCache
            ? 'Last reading ${_lastConnectedLabel()}'
            : 'Tap to retry. Recording continues on the Bridge.';
      case ConnectionPhase.offline:
        return offlineCache
            ? 'Last reading ${_lastConnectedLabel()}'
            : 'Nothing has been saved on this phone yet. Connect to the Bridge to see live values.';
      case ConnectionPhase.blocked:
        switch (blockReason) {
          case BlockReason.bluetoothOff:
            return 'Turn Bluetooth on to find your Bridge.';
          case BlockReason.permissionDenied:
            return 'Grant Bluetooth permission to scan.';
          case BlockReason.permissionBlocked:
            return 'Enable Bluetooth permission in Android settings.';
          case BlockReason.unsupportedPhone:
            return 'This phone cannot scan for Bluetooth LE.';
          case BlockReason.none:
            return 'A connection is required for this action.';
        }
      case ConnectionPhase.setup:
        return 'Set up a Bridge to see live readings.';
    }
  }

  bool smokeXLiveHint = true;

  String get smokeXLabel {
    if (smokeXStatus == SmokeXStatus.unpaired) return 'Not paired';
    if (!isConnected) return 'Last known';
    final age = smokeXLastPacketAge;
    if (smokeXStatus == SmokeXStatus.pairedLost ||
        (age != null && age > const Duration(minutes: 10))) {
      return 'Signal lost';
    }
    if (age != null && age <= const Duration(seconds: 90)) {
      return 'Receiving readings';
    }
    if (age != null) return 'No readings for ${_proseDuration(age)}';
    return 'No readings yet';
  }

  String get smokeXSubtitle {
    final age = smokeXLastPacketAge;
    if (age == null) return 'No readings yet. Put the Smoke X in SYNC mode.';
    if (!isConnected) {
      return 'Updated ${_shortDuration(age)} ago · last known';
    }
    if (smokeXStatus == SmokeXStatus.pairedLost ||
        age > const Duration(minutes: 10)) {
      return 'Updated ${_shortDuration(age)} ago. Put the Smoke X in SYNC mode.';
    }
    return 'Updated ${_shortDuration(age)} ago';
  }

  String get billowsAttachmentLabel {
    switch (billowsAttachment) {
      case BillowsAttachment.attached:
        return 'Detected';
      case BillowsAttachment.detached:
        return billowsSeenThisSession ? 'Lost this session' : 'Not detected';
      case BillowsAttachment.unknown:
        return 'Not detected';
    }
  }

  String get billowsLastDetectedLabel {
    final detectedAt = billowsLastDetectedAt;
    if (detectedAt != null) {
      final age = content.now.difference(detectedAt);
      return _ageLabel(age.isNegative ? Duration.zero : age);
    }
    // Fixture/review builds have no live timestamps; the approved baseline
    // still renders a relative age rather than a bare `Detected`.
    if (billowsDetected) {
      final age = smokeXLastPacketAge ?? bridgeLastContactAge;
      if (age != null) return _ageLabel(age);
    }
    if (billowsLostThisSession) {
      return _ageLabel(const Duration(minutes: 12));
    }
    return 'Not detected';
  }

  String get billowsSettingsSubtitle {
    if (!billowsSeenThisSession) {
      return 'Not detected · appears automatically when connected';
    }
    return 'Status only · $billowsAttachmentLabel';
  }

  String get billowsSourceLabel {
    return 'Smoke X4 (channel 4)';
  }

  String get displayTimeoutLabel {
    if (displayTimeoutSeconds == 0) return 'Never';
    if (displayTimeoutSeconds < 60) return '$displayTimeoutSeconds sec';
    return '${displayTimeoutSeconds ~/ 60} min';
  }

  String get themeModeLabel {
    switch (_themeMode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  // ---------------------------------------------------------------------------
  // Immutable view state consumed by the widget layer.
  // ---------------------------------------------------------------------------

  BillowsView get _billowsView => BillowsView(
    detected: billowsDetected,
    lostThisSession: billowsLostThisSession,
    seenThisSession: billowsSeenThisSession,
    setTempKnown: smokeXChannel4SetKnown,
    setTempLabel: isConnected ? 'Set temp' : 'Set temp (last known)',
    setTempText: smokeXChannel4SetKnown
        ? tempFor(smokeXChannel4SetF.toDouble())
        : '—',
    lastDetectedLabel: billowsLastDetectedLabel,
    attachmentLabel: billowsAttachmentLabel,
    settingsSubtitle: billowsSettingsSubtitle,
    sourceLabel: billowsSourceLabel,
  );

  LiveViewState get liveView {
    final temps = liveProbeTemps ?? content.probeTemps;
    final health = effectiveHealth;
    final probeViews = <ProbeView>[];
    for (var index = 0; index < 4; index++) {
      probeViews.add(_probeView(index, temps[index], health));
    }
    return LiveViewState(
      phase: phase,
      isConnected: isConnected,
      isOffline: isOffline,
      bridgeConnectedLabel: bridgeConnectedLabel,
      appBridgeConnectedForLabel: appBridgeConnectedForLabel,
      smokeXConnectedForLabel: smokeXConnectedForLabel,
      telemetryStatusLabel: telemetryStatusLabel,
      bridgeLinkStatusLabel: bridgeLinkStatusLabel,
      smokeXLinkStatusLabel: smokeXLinkStatusLabel,
      connectionTitle: connectionTitle,
      connectionSubtitle: connectionSubtitle,
      signalBars: signalBars,
      signalQualityLabel: signalQualityLabel,
      bleSignalBars: bleSignalBars,
      bleSignalQualityLabel: bleSignalQualityLabel,
      rssi: rssi,
      bleRssi: bleRssi,
      batteryPercent: batteryPercent,
      smokeXReceiving: smokeXReceiving,
      smokeXStatus: smokeXStatus,
      storageOk: storageOk,
      slowLink: slowLink,
      syncState: syncState,
      syncProgressPercent: syncProgressPercent,
      probes: List<ProbeView>.unmodifiable(probeViews),
      probePresence: probePresence,
      units: units,
      billows: billowsObserveCap && billowsDetected ? _billowsView : null,
      billowsLostThisSession: billowsObserveCap && billowsLostThisSession,
      showSavedReadings: offlineCache,
      lastSyncedLabel: lastSyncedLabel,
      lookingForBridge: lookingForBridge && !isConnected,
      launchScanning: launchScanning,
    );
  }

  ProbeView _probeView(int index, double? sourceTemp, ProbeHealth health) {
    final noCache = isOffline && !offlineCache;
    final double? temp;
    if (noCache || probePresence == ProbePresence.none) {
      temp = null;
    } else if (probePresence == ProbePresence.detachedP3 && index == 2) {
      temp = null;
    } else {
      temp = sourceTemp;
    }
    final connected = temp != null;
    final muted =
        !connected ||
        health == ProbeHealth.stale ||
        health == ProbeHealth.frozen;
    final history = noCache
        ? const <ChartPoint>[]
        : recentHistory.hasRecords
        ? recentHistory.sparkline(index)
        : content.sparkline(index, hasData: probeHasHistory(index));
    final points = history
        .where((point) => point.valueF != null)
        .toList(growable: false);
    final values = points.map((point) => point.valueF!).toList();
    final minValue = values.isEmpty ? null : values.reduce(math.min);
    final maxValue = values.isEmpty ? null : values.reduce(math.max);
    final cookRange = minValue == null || maxValue == null
        ? null
        : 'Min ${valueFor(minValue)}$unitSuffix  '
              'Max ${valueFor(maxValue)}$unitSuffix';
    final changeWindow = Duration(minutes: tempChangeWindowMinutes);
    final cutoff = content.now.subtract(changeWindow);
    final windowPoints = points
        .where((point) => !point.time.isBefore(cutoff))
        .toList(growable: false);
    final change = windowPoints.length >= 2
        ? windowPoints.last.valueF! - windowPoints.first.valueF!
        : null;
    final changeText = change == null ? null : _probeDeltaLabel(change);
    final changeDirection = change == null || change.abs() < 0.05
        ? 0
        : change > 0
        ? 1
        : -1;
    final status = _probeStatusText(connected, health);
    final delta = values.length >= 2 ? values.last - values.first : null;
    final trend = values.isEmpty
        ? ''
        : delta == null
        ? '1h'
        : '1h · ${_probeDeltaLabel(delta)}';
    final deltaText = delta == null ? null : _probeDeltaLabel(delta);
    return ProbeView(
      number: index + 1,
      tempF: temp,
      connected: connected,
      health: health,
      muted: muted,
      lastHour: history,
      valueText: valueFor(temp),
      unitSuffix: unitSuffix,
      statusText: status,
      trendText: trend,
      deltaText: deltaText,
      cookRangeText: cookRange,
      changeText: changeText,
      changeDirection: changeDirection,
      changeWindowLabel: '${tempChangeWindowMinutes}m',
      semanticsLabel: _probeSemantics(index, temp, status, change),
    );
  }

  String? _probeStatusText(bool connected, ProbeHealth health) {
    if (isOffline && !offlineCache) return null;
    if (!connected) {
      if (probePresence == ProbePresence.none) return null;
      return 'Not connected';
    }
    if (!isConnected) return null;
    switch (health) {
      case ProbeHealth.live:
        return null;
      case ProbeHealth.aging:
        return 'Updated 62s ago';
      case ProbeHealth.stale:
        return 'No readings for 4 min';
      case ProbeHealth.frozen:
        return 'No readings for 12 min';
    }
  }

  String _probeSemantics(
    int index,
    double? temp,
    String? status,
    double? delta,
  ) {
    final probe = index + 1;
    if (temp == null) return 'Probe $probe, not connected.';
    final window = '${tempChangeWindowMinutes}m';
    final trend = delta == null
        ? ''
        : delta.abs() < 0.05
        ? ', flat over the last $window'
        : ', ${delta > 0 ? 'up' : 'down'} ${_displayDelta(delta.abs()).toStringAsFixed(1)} degrees over the last $window';
    final String state;
    if (!isConnected || phase == ConnectionPhase.stale) {
      // Offline/stale values are last-known readings. Spoken copy must match the
      // approved saved-readings vocabulary, never `updated live`.
      final age = phase == ConnectionPhase.stale
          ? smokeXLastPacketAge
          : bridgeLastContactAge;
      state = age == null
          ? 'showing saved readings'
          : 'last reading ${_proseDuration(age)} ago, showing saved readings';
    } else {
      state = status ?? 'updated live';
    }
    return 'Probe $probe, ${tempFor(temp)}, $state$trend. Tap for History.';
  }

  double _displayDelta(double fahrenheitDelta) =>
      toDisplayTemperatureDelta(fahrenheitDelta, units);

  String _probeDeltaLabel(double fahrenheitDelta) =>
      temperatureDeltaText(fahrenheitDelta, units);

  HistoryViewState historyViewFor({bool hasGap = true}) {
    final useRecentHistory = recentHistory.hasRecords;
    final noCache = isOffline && !offlineCache;
    final HistoryFixture fixture;
    final bool hasAnyHistory;
    if (useRecentHistory) {
      fixture = recentHistory.fixture(
        range: historyRange,
        customStart: historyCustomRange?.start,
        customEnd: historyCustomRange?.end,
        empty: noCache,
        estimated: historyEstimated,
        missingFromBridge: historyMissingFromBridge,
      );
      hasAnyHistory = !noCache && recentHistory.hasAnyReadings;
    } else {
      fixture = content.history(
        historyRange,
        empty: noCache || !historyHasData,
        oneProbe: historyOneProbe,
        estimated: historyEstimated,
        missingFromBridge: historyMissingFromBridge,
        hasGap: hasGap,
        customStart: historyCustomRange?.start,
        customEnd: historyCustomRange?.end,
      );
      hasAnyHistory = !noCache && historyHasData;
    }
    final probes = historyProbe == null ? [1, 2, 3, 4] : [historyProbe!];
    final stats = probes
        .map((probe) => ProbeRangeStats.fromSeries(fixture.series[probe - 1]))
        .toList();
    final cooks = hasAnyHistory ? content.cooks() : const <CookSession>[];
    final activeCook = _currentCook(cooks);
    final cookReference = activeCook ?? (cooks.isEmpty ? null : cooks.first);
    _sortStats(stats, activeCook, cookReference);
    return HistoryViewState(
      range: historyRange,
      customRange: historyCustomRange,
      probe: historyProbe,
      sort: historySort,
      fixture: fixture,
      stats: List<ProbeRangeStats>.unmodifiable(stats),
      cooks: List<CookSession>.unmodifiable(cooks),
      activeCook: activeCook,
      cookReference: cookReference,
      now: content.now,
      estimated: historyEstimated,
      missingFromBridge: historyMissingFromBridge,
      offline: isOffline,
      hasAnyHistory: hasAnyHistory,
      oneProbe: historyOneProbe,
      units: units,
      lastSyncedLabel: lastSyncedLabel,
      entireHistoryRange: entireHistoryRange,
    );
  }

  HistoryViewState get historyView => historyViewFor();

  /// Loads the durable History window from the archive.
  ///
  /// Screens call this when a database exists; [historyViewFor] stays as the
  /// synchronous demo/fixture path. The returned object is the same immutable
  /// [HistoryViewState] either way, so the approved UI has one contract.
  Future<HistoryViewState> loadHistoryView({bool hasGap = true}) async {
    final archive = historyArchive;
    if (archive == null) return historyViewFor(hasGap: hasGap);

    final noCache = isOffline && !offlineCache;
    final data = await archive.load(
      range: historyRange,
      customStart: historyCustomRange?.start,
      customEnd: historyCustomRange?.end,
      empty: noCache,
    );
    var fixture = data.fixture;
    if (!hasGap && fixture.bands.isNotEmpty) {
      fixture = HistoryFixture(
        start: fixture.start,
        end: fixture.end,
        series: fixture.series,
        gapStart: fixture.start,
        gapEnd: fixture.start,
        gapReason: HistoryGapReason.noSignal,
        estimated: fixture.estimated,
        missingFromBridge: false,
        decimated: fixture.decimated,
      );
    }

    final probes = historyProbe == null ? [1, 2, 3, 4] : [historyProbe!];
    final stats = <ProbeRangeStats>[
      for (final probe in probes) data.stats[probe - 1],
    ];
    final cooks = data.hasAnyHistory ? data.cooks : const <CookSession>[];
    final activeCook = _currentCook(cooks);
    final cookReference = activeCook ?? (cooks.isEmpty ? null : cooks.first);
    _sortStats(stats, activeCook, cookReference);

    return HistoryViewState(
      range: historyRange,
      customRange: historyCustomRange,
      probe: historyProbe,
      sort: historySort,
      fixture: fixture,
      stats: List<ProbeRangeStats>.unmodifiable(stats),
      cooks: List<CookSession>.unmodifiable(cooks),
      activeCook: activeCook,
      cookReference: cookReference,
      now: content.now,
      estimated: fixture.estimated,
      missingFromBridge: fixture.missingFromBridge,
      offline: isOffline,
      hasAnyHistory: data.hasAnyHistory,
      oneProbe: historyOneProbe,
      units: units,
      lastSyncedLabel: lastSyncedLabel,
      entireHistoryRange: DateTimeRange(
        start: data.entireHistory.start,
        end: data.entireHistory.end,
      ),
    );
  }

  CookSession? _currentCook(List<CookSession> cooks) {
    if (cooks.isEmpty) return null;
    final latest = cooks.first;
    final sinceEnd = content.now.difference(latest.end);
    if (sinceEnd.isNegative && sinceEnd.inMinutes.abs() > 5) return null;
    if (sinceEnd.inMinutes > 15) return null;
    return latest;
  }

  void _sortStats(
    List<ProbeRangeStats> stats,
    CookSession? activeCook,
    CookSession? cookReference,
  ) {
    switch (historySort) {
      case HistorySort.probe:
        stats.sort((a, b) => a.probe.compareTo(b.probe));
        break;
      case HistorySort.hottest:
        stats.sort((a, b) {
          if (a.last == null && b.last == null) return 0;
          if (a.last == null) return 1;
          if (b.last == null) return -1;
          return b.last!.compareTo(a.last!);
        });
        break;
      case HistorySort.highestMax:
        stats.sort((a, b) {
          if (a.max == null && b.max == null) return 0;
          if (a.max == null) return 1;
          if (b.max == null) return -1;
          return b.max!.compareTo(a.max!);
        });
        break;
      case HistorySort.recent:
        stats.sort((a, b) {
          if (a.lastSampleAt == null && b.lastSampleAt == null) return 0;
          if (a.lastSampleAt == null) return 1;
          if (b.lastSampleAt == null) return -1;
          return b.lastSampleAt!.compareTo(a.lastSampleAt!);
        });
        break;
      case HistorySort.sinceCookStart:
        bool readingInCook(ProbeRangeStats stat) =>
            stat.lastSampleAt != null &&
            (cookReference == null ||
                !stat.lastSampleAt!.isBefore(cookReference.start));
        stats.sort((a, b) {
          final aInCook = readingInCook(a);
          final bInCook = readingInCook(b);
          if (aInCook != bInCook) return aInCook ? -1 : 1;
          if (a.lastSampleAt == null && b.lastSampleAt == null) {
            return a.probe.compareTo(b.probe);
          }
          if (a.lastSampleAt == null) return 1;
          if (b.lastSampleAt == null) return -1;
          return b.lastSampleAt!.compareTo(a.lastSampleAt!);
        });
        break;
    }
  }

  SetupViewState get setupView => SetupViewState(
    hasSavedData: hasSavedData,
    savedDataEmpty: savedDataEmpty,
    phoneRecords: phoneRecords,
    phoneRecordsLabel: commaInt(phoneRecords, locale: localeName),
    savedDataRange: savedDataRange,
    savedDataSize: savedDataSize,
    syncProgressPercent: syncProgressPercent,
    syncComplete: syncState == SyncState.complete,
    historyOrphaned: historyOrphaned,
    destructiveNotice: destructiveNotice,
  );

  SettingsViewState get settingsView => SettingsViewState(
    connected: isConnected,
    offline: isOffline,
    phase: phase,
    deviceName: deviceName,
    deviceId: deviceId,
    batteryPercent: batteryPercent,
    signalBars: signalBars,
    signalQualityLabel: signalQualityLabel,
    rssi: rssi,
    bridgeLinkStatusLabel: bridgeLinkStatusLabel,
    bridgeLastContactDetail: bridgeLastContactDetail,
    connectionSummary: bridgeConnectedLabel,
    themeModeLabel: themeModeLabel,
    units: units,
    unitsSaveState: unitsSaveState,
    unitsSaveError: unitsSaveError,
    tempChangeWindowMinutes: tempChangeWindowMinutes,
    phoneRecords: phoneRecords,
    bridgeRecords: bridgeRecords,
    bridgeCapacity: bridgeCapacity,
    bridgeOldestReadingAt: bridgeOldestReadingAt,
    bridgeNewestReadingAt: bridgeNewestReadingAt,
    phoneRecordsLabel: commaInt(phoneRecords, locale: localeName),
    bridgeRecordsLabel: commaInt(bridgeRecords, locale: localeName),
    savedDataRange: savedDataRange,
    savedDataSize: savedDataSize,
    savedDataEmpty: savedDataEmpty,
    firmware: firmware,
    hasSavedData: hasSavedData,
    localeName: localeName,
    use24Hour: use24Hour,
  );

  BridgeDetailsViewState get bridgeDetailsView => BridgeDetailsViewState(
    connected: isConnected,
    offline: isOffline,
    phase: phase,
    deviceName: deviceName,
    deviceId: deviceId,
    batteryPercent: batteryPercent,
    signalBars: signalBars,
    signalQualityLabel: signalQualityLabel,
    rssi: rssi,
    bridgeLinkStatusLabel: bridgeLinkStatusLabel,
    bridgeLastContactDetail: bridgeLastContactDetail,
    bridgeConnectedForLabel: bridgeConnectedForLabel,
    lastSyncedLabel: lastSyncedLabel,
    firmware: firmware,
    protocol: protocol,
    slowLink: slowLink,
    canEdit: canEdit,
    smokeXLabel: smokeXLabel,
    smokeXSubtitle: smokeXSubtitle,
    smokeXReceiving: smokeXReceiving,
    smokeXStatus: smokeXStatus,
    billows: _billowsView,
    displayTimeoutSeconds: displayTimeoutSeconds,
    displayTimeoutLabel: displayTimeoutLabel,
    nameSaveState: nameSaveState,
    nameSaveError: nameSaveError,
    timeoutSaveState: timeoutSaveState,
    timeoutSaveError: timeoutSaveError,
    bridgeRecords: bridgeRecords,
    bridgeCapacity: bridgeCapacity,
    phoneRecords: phoneRecords,
    savedDataRange: savedDataRange,
    savedDataSize: savedDataSize,
    savedDataEmpty: savedDataEmpty,
    connectionLog: List<ConnectionEvent>.unmodifiable(connectionLog),
    billowsLog: List<ConnectionEvent>.unmodifiable(billowsLog),
  );

  /// Units apply on this phone immediately. The Bridge write is the only thing
  /// the UI may report as saved; offline it is queued for the next connect.
  void setUnits(Units value) {
    final changed = units != value;
    units = value;
    unitsSaveError = null;
    unitsSaveState = SettingsSaveState.idle;
    if (changed) unawaited(_persistUnits(value));
    notifyListeners();
    if (!canEdit) {
      _pendingUnitsWrite = true;
      return;
    }
    if (link == null && bleClient == null) {
      unitsSaveState = SettingsSaveState.saved;
      notifyListeners();
      return;
    }
    unawaited(_writeUnits(value));
  }

  Future<void> _writeUnits(Units value) async {
    if (!canEdit) {
      _pendingUnitsWrite = true;
      return;
    }
    unitsSaveState = SettingsSaveState.saving;
    notifyListeners();
    try {
      final applied = await _writeWholeConfig(
        (config) => config.copyWith(units: value == Units.celsius ? 0 : 1),
      );
      _pendingUnitsWrite = false;
      final appliedUnits = applied.units == 0
          ? Units.celsius
          : Units.fahrenheit;
      if (appliedUnits != units) {
        units = appliedUnits;
        unawaited(_persistUnits(appliedUnits));
      }
      unitsSaveState = SettingsSaveState.saved;
      unitsSaveError = null;
    } on BridgeConfigException catch (error) {
      unitsSaveState = SettingsSaveState.error;
      unitsSaveError = bridgeRefusalMessage(error.status);
    } on BridgeLinkException {
      unitsSaveState = SettingsSaveState.error;
      unitsSaveError = bridgeRefusalMessage(BridgeConfigStatus.failed);
    } finally {
      notifyListeners();
    }
  }

  void setTempChangeWindowMinutes(int value) {
    final bounded = value.clamp(1, 60);
    final changed = bounded != tempChangeWindowMinutes;
    tempChangeWindowMinutes = bounded;
    if (changed) unawaited(_persistChangeWindow(bounded));
    notifyListeners();
  }

  /// Applies a screen timeout only after the Bridge accepted the whole config.
  Future<void> setDisplayTimeout(int value) async {
    if (!{0, 30, 60, 120}.contains(value)) {
      timeoutSaveState = SettingsSaveState.error;
      timeoutSaveError = bridgeRefusalMessage(BridgeConfigStatus.invalid);
      notifyListeners();
      return;
    }
    if (!canEdit) return;
    if (link == null && bleClient == null) {
      displayTimeoutSeconds = value;
      timeoutSaveState = SettingsSaveState.saved;
      timeoutSaveError = null;
      notifyListeners();
      return;
    }
    timeoutSaveState = SettingsSaveState.saving;
    timeoutSaveError = null;
    notifyListeners();
    try {
      final applied = await _writeWholeConfig(
        (config) => config.copyWith(displayTimeoutSeconds: value),
      );
      displayTimeoutSeconds = applied.displayTimeoutSeconds;
      timeoutSaveState = SettingsSaveState.saved;
    } on BridgeConfigException catch (error) {
      timeoutSaveState = SettingsSaveState.error;
      timeoutSaveError = bridgeRefusalMessage(error.status);
    } on BridgeLinkException {
      timeoutSaveState = SettingsSaveState.error;
      timeoutSaveError = bridgeRefusalMessage(BridgeConfigStatus.failed);
    } finally {
      notifyListeners();
    }
  }

  /// Saves the app-facing label. The Bridge's Bluetooth name does not change.
  Future<void> setDeviceName(String value) async {
    final name = value.trim();
    if (name.isEmpty) {
      nameSaveState = SettingsSaveState.error;
      nameSaveError = 'Enter a name for the Bridge.';
      notifyListeners();
      return;
    }
    if (utf8.encode(name).length > BridgeConfig.maxNameBytes) {
      nameSaveState = SettingsSaveState.error;
      nameSaveError = 'Use 15 characters or fewer.';
      notifyListeners();
      return;
    }
    if (!canEdit) return;
    if (link == null && bleClient == null) {
      deviceName = name;
      if (rememberedBridgeName != null) rememberedBridgeName = name;
      nameSaveState = SettingsSaveState.saved;
      nameSaveError = null;
      notifyListeners();
      return;
    }
    nameSaveState = SettingsSaveState.saving;
    nameSaveError = null;
    notifyListeners();
    try {
      final applied = await _writeWholeConfig(
        (config) => config.copyWith(deviceName: name),
      );
      deviceName = applied.deviceName;
      if (rememberedBridgeName != null) rememberedBridgeName = name;
      nameSaveState = SettingsSaveState.saved;
    } on BridgeConfigException catch (error) {
      nameSaveState = SettingsSaveState.error;
      nameSaveError = bridgeRefusalMessage(error.status);
    } on BridgeLinkException {
      nameSaveState = SettingsSaveState.error;
      nameSaveError = bridgeRefusalMessage(BridgeConfigStatus.failed);
    } finally {
      notifyListeners();
    }
  }

  /// Reads, mutates exactly one field and writes the whole 80-byte struct. Writes
  /// are serialised so two quick taps cannot interleave read-modify-write.
  Future<BridgeConfig> _writeWholeConfig(
    BridgeConfig Function(BridgeConfig config) mutate,
  ) {
    final result = _configChain.then((_) async {
      final current = link;
      if (current == null || !canEdit) {
        throw const BridgeConfigException(
          BridgeConfigStatus.failed,
          'the Bridge is not connected',
        );
      }
      _configWriteInFlight = true;
      try {
        final existing = await current.readConfig();
        return await current.writeConfig(mutate(existing));
      } finally {
        _configWriteInFlight = false;
      }
    });
    _configChain = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Approved per-status copy. The branch is always the Bridge's status.
  String bridgeRefusalMessage(BridgeConfigStatus status) {
    switch (status) {
      case BridgeConfigStatus.invalid:
        return 'The Bridge refused this value. Check it and try again.';
      case BridgeConfigStatus.unsupported:
        return 'The Bridge doesn’t support this setting.';
      case BridgeConfigStatus.busy:
        return 'The Bridge is busy. Try again in a moment.';
      case BridgeConfigStatus.unauthorized:
        return 'This phone isn’t authorized. Reconnect to the Bridge.';
      case BridgeConfigStatus.failed:
        return 'The change didn’t reach the Bridge. Try again.';
      case BridgeConfigStatus.notFound:
        return 'The Bridge couldn’t find that setting.';
      case BridgeConfigStatus.storage:
        return 'The Bridge couldn’t save it. Its storage may be full.';
      case BridgeConfigStatus.ok:
        return '';
    }
  }

  void setHistoryRange(HistoryRange value) {
    historyRange = value;
    if (value != HistoryRange.custom) {
      historyCustomRange = null;
    }
    notifyListeners();
  }

  void setHistoryProbe(int? value) {
    historyProbe = value;
    notifyListeners();
  }

  void setHistoryCustomRange(DateTimeRange value) {
    historyCustomRange = value;
    historyRange = HistoryRange.custom;
    notifyListeners();
  }

  void setHistorySort(HistorySort value) {
    historySort = value;
    notifyListeners();
  }

  void openProbeHistory(int index) {
    historyProbe = index + 1;
    historyRange = HistoryRange.oneHour;
    tab = AppTab.history;
    notifyListeners();
  }

  void setTab(AppTab value) {
    tab = value;
    notifyListeners();
  }

  void setBlocked(BlockReason reason) {
    phase = ConnectionPhase.blocked;
    blockReason = reason;
    notifyListeners();
  }

  void disconnect() {
    phase = ConnectionPhase.offline;
    offlineCache = true;
    liveReceivedAt = null;
    syncState = SyncState.idle;
    _bridgeConnectedSince = null;
    _smokeXConnectedSince = null;
    notifyListeners();
  }

  /// The only re-pair entry point. It clears the Smoke X4 radio pairing on the
  /// Bridge; the screen shows the SYNC steps only after an `ok` result.
  Future<BridgeConfigStatus> startRePair() async {
    if (!canEdit) return BridgeConfigStatus.failed;
    final current = link;
    if (current == null) return BridgeConfigStatus.failed;
    try {
      final result = await current.sendControl(BridgeControlOp.unpairSmokeX);
      if (result.status == BridgeResultStatus.ok) {
        smokeXStatus = SmokeXStatus.unpaired;
        smokeXLiveHint = false;
        notifyListeners();
      }
      return BridgeConfigStatus.fromWire(result.status.wire) ??
          BridgeConfigStatus.failed;
    } on BridgeLinkException {
      return BridgeConfigStatus.failed;
    }
  }

  void wake() {
    bridgeOff = false;
    phase = ConnectionPhase.offline;
    offlineCache = hasSavedData || phoneRecords > 0;
    notifyListeners();
  }

  void simulateSync() {
    syncState = SyncState.recent;
    phase = ConnectionPhase.syncing;
    syncProgressPercent = 35;
    notifyListeners();
    Future<void>.delayed(const Duration(milliseconds: 850), () {
      syncProgressPercent = 72;
      notifyListeners();
    });
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      syncState = SyncState.complete;
      syncProgressPercent = 100;
      phase = ConnectionPhase.live;
      notifyListeners();
    });
  }

  void simulateSave() {
    saveState = SettingsSaveState.saving;
    notifyListeners();
    Future<void>.delayed(const Duration(milliseconds: 750), () {
      saveState = SettingsSaveState.saved;
      notifyListeners();
    });
  }

  /// The manual Retry/Connect action. A live link resumes its bounded
  /// reconnect budget; a saved Bridge that was not found runs the launch scan
  /// again. It never pretends a link exists.
  Future<void> retryConnection() async {
    final current = link;
    if (current != null && current.device != null) {
      await current.retryNow();
      return;
    }
    if (hasSavedBridge) await connectSavedBridge();
  }

  void completeSetup() {
    phase = ConnectionPhase.live;
    hasSavedBridge = true;
    historyOrphaned = false;
    bridgeOff = false;
    destructiveNotice = null;
    probeHealth = ProbeHealth.live;
    probePresence = ProbePresence.all;
    smokeXStatus = SmokeXStatus.pairedLive;
    smokeXLiveHint = true;
    syncState = SyncState.complete;
    tab = AppTab.live;
    _bridgeConnectedSince ??= DateTime.now();
    // The first live read already started the Smoke X4 timer. Keep it rather
    // than resetting it when the setup screen hands over to Live.
    if (smokeXStatus == SmokeXStatus.pairedLive) {
      _smokeXConnectedSince ??= DateTime.now();
    }
    notifyListeners();
  }

  /// Starts the production setup route on a phone with no saved Bridge.
  void beginSetup() {
    hasSavedBridge = false;
    savedBridge = null;
    lookingForBridge = false;
    launchScanning = false;
    final hasOrphanedHistory = phoneRecords > 0 || hasSavedData;
    offlineCache = hasOrphanedHistory;
    savedDataEmpty = !hasOrphanedHistory;
    historyOrphaned = hasOrphanedHistory;
    bridgeOff = false;
    phase = ConnectionPhase.setup;
    tab = AppTab.live;
    _bridgeConnectedSince = null;
    _smokeXConnectedSince = null;
    // Nothing has been observed by this app session yet. Billows only becomes
    // visible after the Bridge reports a genuinely attached unit.
    billowsAttachment = BillowsAttachment.unknown;
    billowsSeenThisSession = false;
    billowsLastDetectedAt = null;
    billowsLostAt = null;
    notifyListeners();
  }

  /// Records the Bridge the OS bond succeeded with, so the next scan prefers
  /// it by device ID and then by name.
  void rememberBridge({String? deviceId, String? deviceName, int? mtu}) {
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      rememberedBridgeId = deviceId.trim();
    }
    if (deviceName != null && deviceName.trim().isNotEmpty) {
      rememberedBridgeName = deviceName.trim();
    }
    historyOrphaned = false;
    bridgeOff = false;
    destructiveNotice = null;
    negotiatedMtu = mtu;
    final id = rememberedBridgeId;
    final name = rememberedBridgeName;
    if (id != null && name != null) {
      unawaited(_persistBridgeIdentity(id, name));
    }
    notifyListeners();
  }

  /// Confirms-forget implementation (05 §5.12, 06 §6.7).
  ///
  /// Local-first: the saved connection is cleared immediately and phone history
  /// is kept. The `forget_phone` write is best-effort; when the Bridge answers
  /// `ok` or the link drops first, the OS bond is removed too. When neither can
  /// be confirmed, [destructiveNotice] explains that the Bridge may still hold
  /// the pairing.
  Future<DestructiveOutcome> forgetPhone() async {
    final current = link;
    _clearSavedConnectionLocally();
    DestructiveOutcome outcome = DestructiveOutcome.unavailable;
    if (current != null) {
      outcome = await _attemptDestructive(current, BridgeControlOp.forgetPhone);
    } else {
      // Review/demo path or an already-detached link: apply the local outcome.
      outcome = DestructiveOutcome.success;
    }
    if (outcome.landed) {
      destructiveNotice = null;
      await _removeLocalBond();
    } else {
      destructiveNotice = 'The Bridge may still have this phone paired. You can pair again later from another phone.';
    }
    current?.abandon();
    notifyListeners();
    return outcome;
  }

  /// Factory reset (05 §5.12). The phone-local connection and bond are cleared
  /// only after the Bridge answers `ok` or the expected disconnect; phone
  /// history is kept and Setup names it as orphaned.
  Future<DestructiveOutcome> factoryReset() async {
    final current = link;
    DestructiveOutcome outcome = DestructiveOutcome.unavailable;
    if (current != null) {
      outcome = await _attemptDestructive(
        current,
        BridgeControlOp.factoryReset,
      );
    } else {
      // Review/demo path or an already-detached link: apply the local outcome.
      outcome = DestructiveOutcome.success;
    }
    if (outcome.landed) {
      current?.abandon();
      await _removeLocalBond();
      destructiveNotice = null;
      _clearSavedConnectionLocally();
    }
    return outcome;
  }

  /// Power off (05 §5.12). A disconnect after a delivered request is success.
  /// The saved Bridge identity stays so a PRG wake can reconnect, but the app
  /// never reports it reachable while it is off.
  Future<DestructiveOutcome> powerOff() async {
    final current = link;
    DestructiveOutcome outcome = DestructiveOutcome.unavailable;
    if (current != null) {
      outcome = await _attemptDestructive(current, BridgeControlOp.powerOff);
    } else {
      // Review/demo path or an already-detached link: apply the local outcome.
      outcome = DestructiveOutcome.success;
    }
    if (outcome.landed) {
      current?.abandon();
      bridgeOff = true;
      phase = ConnectionPhase.offline;
      offlineCache = hasSavedData || phoneRecords > 0;
      _bridgeConnectedSince = null;
      _smokeXConnectedSince = null;
      notifyListeners();
    }
    return outcome;
  }

  /// `clear_history` outcome. Only an `ok` result changes the displayed Bridge
  /// figures; the phone copy and the Bridge config/pairing are untouched. The
  /// next stats read carries the new generation boundary.
  Future<DestructiveOutcome> clearBridgeHistory() async {
    final current = link;
    DestructiveOutcome outcome = DestructiveOutcome.unavailable;
    if (current != null) {
      outcome = await _attemptDestructive(
        current,
        BridgeControlOp.clearHistory,
        disconnectIsSuccess: false,
      );
    } else {
      // Review/demo path or an already-detached link: apply the local outcome.
      outcome = DestructiveOutcome.success;
    }
    if (outcome == DestructiveOutcome.success) {
      bridgeRecords = 0;
      bridgeOldestReadingAt = null;
      bridgeNewestReadingAt = null;
      notifyListeners();
    }
    return outcome;
  }

  /// Sends one destructive control op and maps the result / link drop.
  Future<DestructiveOutcome> _attemptDestructive(
    BridgeLink current,
    BridgeControlOp op, {
    bool disconnectIsSuccess = true,
  }) async {
    final attempt = await current.attemptControl(op);
    final result = attempt.result;
    if (result != null) {
      return result.status == BridgeResultStatus.ok
          ? DestructiveOutcome.success
          : DestructiveOutcome.failed;
    }
    final error = attempt.error;
    final disconnected =
        attempt.written &&
        ((error is BridgeLinkException &&
                error.failure == BridgeLinkFailure.notConnected) ||
            _linkGone);
    if (disconnected) {
      return disconnectIsSuccess
          ? DestructiveOutcome.disconnected
          : DestructiveOutcome.failed;
    }
    if (attempt.timedOut) {
      // The result can no longer arrive after a reboot/sleep. A sent request
      // with the link already gone is the expected success; a link that is
      // still up did not act.
      return _linkGone && disconnectIsSuccess
          ? DestructiveOutcome.disconnected
          : DestructiveOutcome.timedOut;
    }
    return DestructiveOutcome.failed;
  }

  bool get _linkGone {
    if (bleClient?.connectionState == BleConnectionState.disconnected) {
      return true;
    }
    final value = link?.phase;
    return value == ConnectionPhase.reconnecting ||
        value == ConnectionPhase.offline ||
        value == ConnectionPhase.failed;
  }

  Future<void> _removeLocalBond() async {
    final client = bleClient;
    if (client == null) return;
    try {
      await client.removeBond();
    } catch (_) {
      // The saved identity is already gone; a failed OS bond removal is named
      // by the Setup notice rather than blocking the local outcome.
    }
  }

  /// Clears the saved connection and returns to Setup while keeping every
  /// reading on this phone. Shared by forget and factory reset.
  void _clearSavedConnectionLocally() {
    hasSavedBridge = false;
    final hasOrphanedHistory = phoneRecords > 0 || hasSavedData;
    hasSavedData = hasOrphanedHistory;
    savedDataEmpty = !hasOrphanedHistory;
    offlineCache = hasOrphanedHistory;
    historyOrphaned = hasOrphanedHistory;
    phase = ConnectionPhase.setup;
    lookingForBridge = false;
    launchScanning = false;
    localMaxSeq = null;
    bridgeOff = false;
    _bridgeConnectedSince = null;
    _smokeXConnectedSince = null;
    unawaited(_clearSavedIdentity());
    notifyListeners();
  }

  /// Builds the counted plan the delete sheet shows. The same plan is passed to
  /// [applyLocalDeletion] after confirmation, so the stated loss is the loss.
  Future<HistoryDeletionPlan> planLocalDeletion(
    HistoryDeletionScope scope,
  ) async {
    final service = historyDeletion;
    if (service == null) return _simulatedDeletionPlan(scope);
    return service.plan(scope);
  }

  /// Applies one already-confirmed plan. An empty plan never calls the DAO.
  Future<HistoryDeletionOutcome> applyLocalDeletion(
    HistoryDeletionPlan plan,
  ) async {
    final service = historyDeletion;
    if (service == null) {
      _applySimulatedDeletion(plan);
      return HistoryDeletionOutcome(
        plan: plan,
        deletion: const HistoryDeletion(
          samplesDeleted: 0,
          gapsDeleted: 0,
          gapsTrimmed: 0,
        ),
      );
    }
    final outcome = await service.delete(plan);
    await refreshLocalHistorySummary();
    historyHasData = phoneRecords > 0;
    // History's read model reloads on this revision; deletion does not wait for
    // a sync batch to become visible.
    historyRevision++;
    notifyListeners();
    return outcome;
  }

  /// Lab/screenshot compatibility. Production UI calls [planLocalDeletion] then
  /// [applyLocalDeletion]; this wrapper is otherwise equivalent.
  Future<HistoryDeletionOutcome> deleteLocalData(String scope) async {
    final plan = await planLocalDeletion(_scopeFromWire(scope));
    return applyLocalDeletion(plan);
  }

  HistoryDeletionScope _scopeFromWire(String scope) => switch (scope) {
    '30' => HistoryDeletionScope.olderThan30Days,
    '90' => HistoryDeletionScope.olderThan90Days,
    _ => HistoryDeletionScope.all,
  };

  HistoryDeletionPlan _simulatedDeletionPlan(HistoryDeletionScope scope) {
    final count = switch (scope) {
      HistoryDeletionScope.olderThan30Days =>
        phoneRecords > 12430 ? 12430 : phoneRecords,
      HistoryDeletionScope.olderThan90Days => phoneRecords,
      HistoryDeletionScope.all => phoneRecords,
    };
    final range = switch (scope) {
      HistoryDeletionScope.olderThan30Days => 'Sep 25 – Oct 24, 2026',
      HistoryDeletionScope.olderThan90Days => 'Jul 27 – Oct 24, 2026',
      HistoryDeletionScope.all => savedDataRange,
    };
    return HistoryDeletionPlan(
      scope: scope,
      fromMs: 0,
      toMs: 0,
      count: count,
      rangeLabelOverride: range,
    );
  }

  void _applySimulatedDeletion(HistoryDeletionPlan plan) {
    switch (plan.scope) {
      case HistoryDeletionScope.olderThan30Days:
        phoneRecords = (phoneRecords - plan.count).clamp(0, 999999);
        break;
      case HistoryDeletionScope.olderThan90Days:
      case HistoryDeletionScope.all:
        phoneRecords = 0;
        savedDataEmpty = true;
        break;
    }
    historyHasData = phoneRecords > 0;
    historyRevision++;
    notifyListeners();
  }

  String _lastConnectedLabel() {
    final age = bridgeLastContactAge;
    if (age == null) return 'earlier';
    return '${_proseDuration(age)} ago';
  }

  String _compactDuration(Duration duration) {
    if (duration.inSeconds < 60) return '${duration.inSeconds}s';
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours == 0) return '${minutes}m';
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  String _shortDuration(Duration duration) {
    if (duration.inSeconds < 60) return '${duration.inSeconds}s';
    if (duration.inMinutes < 60) return '${duration.inMinutes}m';
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  String _ageLabel(Duration duration) {
    if (duration.inSeconds < 60) return '${duration.inSeconds}s ago';
    return '${_proseDuration(duration)} ago';
  }

  String _proseDuration(Duration duration) {
    if (duration.inSeconds < 60) return '${duration.inSeconds} sec';
    if (duration.inMinutes < 60) return '${duration.inMinutes} min';
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return minutes == 0 ? '$hours hr' : '$hours hr $minutes min';
  }

  void reset({bool keepTheme = true}) {
    final theme = _themeMode;
    tab = AppTab.live;
    phase = ConnectionPhase.live;
    blockReason = BlockReason.none;
    probeHealth = ProbeHealth.live;
    probePresence = ProbePresence.all;
    smokeXStatus = SmokeXStatus.pairedLive;
    smokeXLiveHint = true;
    storageOk = true;
    slowLink = false;
    syncState = SyncState.idle;
    syncProgressPercent = 64;
    billowsAttachment = BillowsAttachment.attached;
    billowsObserveCap = true;
    smokeXAgeOverride = null;
    liveReceivedAt = null;
    liveProbeTemps = null;
    localMaxSeq = null;
    lastSyncedAt = null;
    reconnectAttempt = 2;
    reconnectAttempts = 6;
    nextReconnectIn = const Duration(seconds: 4);
    smokeXChannel4SetKnown = true;
    smokeXChannel4SetF = 225;
    billowsSeenThisSession = true;
    billowsLastDetectedAt = null;
    billowsLostAt = null;
    bleRssi = -58;
    _bridgeConnectedSince = DateTime.now().subtract(
      const Duration(hours: 2, minutes: 14),
    );
    _smokeXConnectedSince = DateTime.now().subtract(
      const Duration(hours: 2, minutes: 10),
    );
    historyRange = HistoryRange.twentyFourHours;
    historyProbe = null;
    historyCustomRange = null;
    historySort = HistorySort.probe;
    historyHasData = true;
    historyOneProbe = false;
    historyEstimated = false;
    historyMissingFromBridge = false;
    offlineCache = true;
    hasSavedBridge = true;
    hasSavedData = false;
    savedDataEmpty = false;
    units = Units.fahrenheit;
    tempChangeWindowMinutes = 5;
    displayTimeoutSeconds = 60;
    deviceName = 'Backyard Bridge';
    saveState = SettingsSaveState.idle;
    bridgeRecords = content.bridgeRecords;
    bridgeCapacity = content.bridgeCapacity;
    bridgeOldestReadingAt = null;
    bridgeNewestReadingAt = null;
    bridgeGeneration = null;
    phoneRecords = content.phoneRecords;
    savedDataRange = content.savedDataRange;
    savedDataSize = content.savedDataSize;
    if (keepTheme) _themeMode = theme;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_platformSubscription?.cancel() ?? Future<void>.value());
    _platformSubscription = null;
    unawaited(link?.dispose() ?? Future<void>.value());
    unawaited(repository.close());
    unawaited(bleClient?.dispose() ?? Future<void>.value());
    super.dispose();
  }
}

class _LaunchScanResult {
  const _LaunchScanResult({this.device, this.blockedBy});

  final BleDevice? device;
  final BleAppState? blockedBy;
}
