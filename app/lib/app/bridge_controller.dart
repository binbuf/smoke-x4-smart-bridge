import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/ble/ble_client.dart';
import '../data/ble/bridge_codecs.dart';
import '../data/ble/bridge_link.dart';
import '../data/ble/bridge_protocol.dart';
import '../data/db/sample_dao.dart';
import '../data/recent_history_store.dart';
import '../data/repository.dart';
import '../data/sync/archive_sync.dart';
import '../domain/content.dart';
import '../domain/models.dart';
import 'formatters.dart';
import 'view_state.dart';

export '../domain/models.dart';

/// The app's control seam.
///
/// Owns navigation, theme and the state the approved shell renders. Data access
/// goes through [BridgeRepository] and [BridgeContent]; widgets render immutable
/// view state from [liveView], [historyView], [setupView], [settingsView] and
/// [bridgeDetailsView], never these mutable fields.
class BridgeController extends ChangeNotifier {
  BridgeController({
    this.repository = const EmptyBridgeRepository(),
    this.content = const EmptyBridgeContent(),
    this.bleClient,
    this.sampleDao,
  }) : bridgeRecords = content.bridgeRecords,
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
    notifyListeners();
  }

  /// Loads the saved Bridge and the last-known archive before the first frame.
  ///
  /// A saved Bridge keeps the approved shell (Live), never Setup. With no saved
  /// Bridge, this is a first install and Setup remains the owner of pairing.
  Future<void> prepareLaunch({Duration? scanWindow}) async {
    if (scanWindow != null) launchScanWindow = scanWindow;
    final dao = sampleDao;
    SavedBridge? saved;
    if (dao != null) {
      saved = await dao.savedBridge();
      final newest = await dao.newestSamples(limit: 1);
      if (newest.isNotEmpty) {
        final row = newest.single;
        liveProbeTemps = <double?>[
          for (final value in row.tempsF10)
            value == null ? null : value / 10,
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
    notifyListeners();
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
      subscription = client.scan(timeout: launchScanWindow).listen(
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
    _bridgeConnectedSince = null;
    _smokeXConnectedSince = null;
    notifyListeners();
  }

  void _onLinkBlocked(BlockReason reason) {
    blockReason = reason;
    launchScanning = false;
    lookingForBridge = false;
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
      await dao.touchBridge(
        id: id,
        name: name,
        lastSeenMs: content.now.millisecondsSinceEpoch,
        generation: existing?.generation,
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
        final hasArchive =
            snapshot.cursorAfter != null || phoneRecords > 0;
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
      unawaited(_touchSavedIdentity());
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
        break;
    }
    if (value == ConnectionPhase.syncing) {
      syncState = SyncState.recent;
      syncProgressPercent = 10;
    } else if (value == ConnectionPhase.reconnecting) {
      syncState = SyncState.idle;
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
    billowsAttachment = live.billowsAttached
        ? BillowsAttachment.attached
        : BillowsAttachment.detached;
    if (live.billowsAttached) billowsSeenThisSession = true;
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

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
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

  Units units = Units.fahrenheit;

  /// Window used for the Live probe change indicator.
  int tempChangeWindowMinutes = 5;
  int displayTimeoutSeconds = 60;
  String deviceName = 'Backyard Bridge';

  SettingsSaveState saveState = SettingsSaveState.idle;

  int bridgeRecords;
  int bridgeCapacity;
  int phoneRecords;
  String savedDataRange;
  String savedDataSize;

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
      return 'Smoke X4 signal lost · ${_proseDuration(age)} ago';
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
        title: 'Smoke X4 paired',
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
              ? 'The Smoke X4 reports Billows attached'
              : 'Attached earlier this session · not detected now',
          time: billowsDetected
              ? now.subtract(const Duration(seconds: 12))
              : now.subtract(const Duration(minutes: 12)),
          kind: ConnectionEventKind.billowsConnected,
        ),
      );
    }
    if (billowsLostThisSession) {
      events.add(
        ConnectionEvent(
          title: 'Billows lost',
          detail: 'Was paired through the Smoke X4 · check fan power',
          time: now.subtract(const Duration(minutes: 12)),
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

  String get unitsLabel => units == Units.fahrenheit ? '°F' : '°C';

  String get unitSuffix => units == Units.fahrenheit ? '°F' : '°C';

  double? toDisplayTemp(double? fahrenheit) {
    if (fahrenheit == null) return null;
    return units == Units.fahrenheit ? fahrenheit : (fahrenheit - 32) * 5 / 9;
  }

  String valueFor(double? fahrenheit) {
    final value = toDisplayTemp(fahrenheit);
    if (value == null) return '—';
    return value.toStringAsFixed(1);
  }

  String tempFor(double? fahrenheit) => '${valueFor(fahrenheit)}$unitSuffix';

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
        return 'Can’t reach the Bridge';
      case ConnectionPhase.offline:
        return offlineCache
            ? 'Showing saved readings'
            : 'Can’t reach the Bridge';
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
          return 'Waiting for Smoke X4 readings';
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
        return 'Tap to retry. Recording continues on the Bridge.';
      case ConnectionPhase.offline:
        return offlineCache
            ? 'Last reading ${_lastConnectedLabel()}'
            : 'Nothing has been saved on this phone yet';
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
    if (!isConnected) return 'Paired · last known';
    final age = smokeXLastPacketAge;
    if (smokeXStatus == SmokeXStatus.pairedLost) return 'Signal lost';
    if (age != null && age <= const Duration(seconds: 90)) return 'Receiving';
    return 'No readings';
  }

  String get smokeXSubtitle {
    final age = smokeXLastPacketAge;
    if (age == null) return 'No readings yet. Put the Smoke X4 in SYNC mode.';
    if (!isConnected) {
      return 'Last reading ${_proseDuration(age)} ago · last known';
    }
    if (smokeXStatus == SmokeXStatus.pairedLost ||
        age > const Duration(minutes: 10)) {
      return 'No readings for ${_proseDuration(age)}. Put the Smoke X4 in SYNC mode.';
    }
    if (age <= const Duration(seconds: 90)) {
      return 'Updated ${_shortDuration(age)} ago';
    }
    return 'No readings for ${_proseDuration(age)}';
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
    final state = status ?? 'updated live';
    return 'Probe $probe, ${tempFor(temp)}, $state$trend. Tap for History.';
  }

  double _displayDelta(double fahrenheitDelta) =>
      units == Units.fahrenheit ? fahrenheitDelta : fahrenheitDelta * 5 / 9;

  String _probeDeltaLabel(double fahrenheitDelta) {
    final value = _displayDelta(fahrenheitDelta);
    final sign = value > 0
        ? '+'
        : value < 0
        ? '-'
        : '±';
    return '$sign${value.abs().toStringAsFixed(1)}$unitSuffix';
  }

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
    phoneRecordsLabel: commaInt(phoneRecords),
    savedDataRange: savedDataRange,
    savedDataSize: savedDataSize,
    syncProgressPercent: syncProgressPercent,
    syncComplete: syncState == SyncState.complete,
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
    themeModeLabel: themeModeLabel,
    units: units,
    tempChangeWindowMinutes: tempChangeWindowMinutes,
    phoneRecords: phoneRecords,
    bridgeRecords: bridgeRecords,
    bridgeCapacity: bridgeCapacity,
    phoneRecordsLabel: commaInt(phoneRecords),
    bridgeRecordsLabel: commaInt(bridgeRecords),
    savedDataRange: savedDataRange,
    savedDataSize: savedDataSize,
    savedDataEmpty: savedDataEmpty,
    firmware: firmware,
    hasSavedData: hasSavedData,
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
    bridgeRecords: bridgeRecords,
    bridgeCapacity: bridgeCapacity,
    phoneRecords: phoneRecords,
    savedDataRange: savedDataRange,
    savedDataSize: savedDataSize,
    savedDataEmpty: savedDataEmpty,
    connectionLog: List<ConnectionEvent>.unmodifiable(connectionLog),
    billowsLog: List<ConnectionEvent>.unmodifiable(billowsLog),
  );

  void setUnits(Units value) {
    units = value;
    notifyListeners();
  }

  void setTempChangeWindowMinutes(int value) {
    tempChangeWindowMinutes = value.clamp(1, 60);
    notifyListeners();
  }

  void setDisplayTimeout(int value) {
    displayTimeoutSeconds = value;
    notifyListeners();
  }

  void setDeviceName(String value) {
    deviceName = value;
    notifyListeners();
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

  void startRePair() {
    smokeXStatus = SmokeXStatus.pairedLost;
    notifyListeners();
  }

  void wake() {
    phase = ConnectionPhase.live;
    smokeXLiveHint = true;
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
    phase = ConnectionPhase.setup;
    tab = AppTab.live;
    _bridgeConnectedSince = null;
    _smokeXConnectedSince = null;
    // Nothing has been observed by this app session yet. Billows only becomes
    // visible after the Bridge reports a genuinely attached unit.
    billowsAttachment = BillowsAttachment.unknown;
    billowsSeenThisSession = false;
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
    negotiatedMtu = mtu;
    final id = rememberedBridgeId;
    final name = rememberedBridgeName;
    if (id != null && name != null) {
      unawaited(_persistBridgeIdentity(id, name));
    }
    notifyListeners();
  }

  void forgetPhone() {
    link?.abandon();
    hasSavedBridge = false;
    final hasOrphanedHistory = phoneRecords > 0 || hasSavedData;
    hasSavedData = hasOrphanedHistory;
    savedDataEmpty = !hasOrphanedHistory;
    offlineCache = hasOrphanedHistory;
    phase = ConnectionPhase.setup;
    lookingForBridge = false;
    launchScanning = false;
    localMaxSeq = null;
    _bridgeConnectedSince = null;
    _smokeXConnectedSince = null;
    unawaited(_clearSavedIdentity());
    notifyListeners();
  }

  void factoryReset() {
    link?.abandon();
    hasSavedBridge = false;
    final hasOrphanedHistory = phoneRecords > 0 || hasSavedData;
    savedDataEmpty = !hasOrphanedHistory;
    offlineCache = hasOrphanedHistory;
    phase = ConnectionPhase.setup;
    lookingForBridge = false;
    launchScanning = false;
    localMaxSeq = null;
    _bridgeConnectedSince = null;
    _smokeXConnectedSince = null;
    unawaited(_clearSavedIdentity());
    notifyListeners();
  }

  void clearBridgeHistory() {
    bridgeRecords = 0;
    notifyListeners();
  }

  void deleteLocalData(String scope) {
    switch (scope) {
      case '30':
        phoneRecords = (phoneRecords - 12430).clamp(0, 999999);
        break;
      case '90':
        phoneRecords = 0;
        break;
      default:
        phoneRecords = 0;
        savedDataEmpty = true;
        break;
    }
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
