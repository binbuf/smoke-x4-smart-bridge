import 'package:flutter/material.dart';

enum AppTab { live, history, settings }

enum ConnectionPhase {
  live,
  stale,
  syncing,
  reconnecting,
  failed,
  offline,
  blocked,
  setup,
}

enum BlockReason {
  none,
  bluetoothOff,
  permissionDenied,
  permissionBlocked,
  unsupportedPhone,
}

enum ProbeHealth { live, aging, stale, frozen }

enum ProbePresence { all, detachedP3, none }

enum BillowsAttachment { unknown, attached, detached }

enum Units { fahrenheit, celsius }

enum HistoryRange { oneHour, sixHours, twentyFourHours, twoDays, custom }

enum ConnectionEventKind {
  bridgeConnected,
  bridgeLost,
  smokeXPaired,
  smokeXLost,
  billowsConnected,
  billowsLost,
  repair,
  sync,
}

class ConnectionEvent {
  const ConnectionEvent({
    required this.title,
    required this.detail,
    required this.time,
    required this.kind,
  });

  final String title;
  final String detail;
  final DateTime time;
  final ConnectionEventKind kind;
}

enum HistorySort { probe, hottest, highestMax, recent, sinceCookStart }

enum SyncState { idle, recent, backfill, complete, error }

enum SmokeXStatus { pairedLive, pairedLost, unpaired }

enum SettingsSaveState { idle, saving, saved, error }

enum SetupStep {
  noBridge,
  permissionPrimer,
  bluetoothOff,
  permissionDenied,
  permissionBlocked,
  unsupportedPhone,
  scanning,
  noResults,
  results,
  protocolMismatch,
  passkey,
  bonding,
  bondWrongCode,
  bondTimeout,
  bondStale,
  bondStoreFull,
  firstSync,
  savedData,
}

class Probe {
  const Probe({
    required this.number,
    required this.tempF,
    required this.health,
  });

  final int number;
  final double? tempF;
  final ProbeHealth health;

  bool get connected => tempF != null;
}

/// UI-only state for the clickable prototype. It intentionally contains no BLE,
/// database, permission, or sync code. Every value can be set by the scenario
/// lab so the whole product can be reviewed on a desktop or emulator.
class PrototypeController extends ChangeNotifier {
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
  bool smokeXChannel4SetKnown = true;
  int smokeXChannel4SetF = 225;
  bool billowsSeenThisSession = true;

  HistoryRange historyRange = HistoryRange.twentyFourHours;
  int? historyProbe;
  DateTimeRange? historyCustomRange;
  HistorySort historySort = HistorySort.probe;
  bool historyHasData = true;
  bool historyOneProbe = false;
  bool historyEstimated = false;
  bool historyMissingFromBridge = false;

  bool offlineCache = true;
  bool hasSavedBridge = true;
  bool hasSavedData = false;
  bool savedDataEmpty = false;

  Units units = Units.fahrenheit;
  int displayTimeoutSeconds = 60;
  String deviceName = 'Backyard Bridge';

  SettingsSaveState saveState = SettingsSaveState.idle;

  int bridgeRecords = 24810;
  int bridgeCapacity = 338400;
  int phoneRecords = 128430;
  String savedDataRange = 'Sep 1 – Oct 24, 2026';
  String savedDataSize = '9.2 MB';

  String deviceId = 'A4F2';
  String firmware = '0.1.0';
  String protocol = '1.0';
  int batteryPercent = 87;
  int rssi = -71;

  bool get isConnected =>
      phase == ConnectionPhase.live ||
      phase == ConnectionPhase.stale ||
      phase == ConnectionPhase.syncing;

  bool get canEdit => isConnected;

  bool get isOffline =>
      phase == ConnectionPhase.offline ||
      phase == ConnectionPhase.failed ||
      phase == ConnectionPhase.reconnecting;

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
        return const Duration(hours: 2);
      case ConnectionPhase.blocked:
        return const Duration(hours: 2);
      case ConnectionPhase.setup:
        return null;
    }
  }

  Duration get bridgeConnectedFor => const Duration(hours: 2, minutes: 14);

  /// Connected duration without seconds, for the compact Live status row.
  String get bridgeConnectedForLabel {
    final value = bridgeConnectedFor;
    final hours = value.inHours;
    final minutes = value.inMinutes % 60;
    if (hours == 0) return '${minutes}m';
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  /// The BLE link state, separate from Smoke X4 telemetry freshness.
  String get bridgeConnectedLabel {
    if (isConnected) return 'Bridge connected · $bridgeConnectedForLabel';
    switch (phase) {
      case ConnectionPhase.reconnecting:
        return 'Reconnecting… attempt 2 of 6';
      case ConnectionPhase.blocked:
        return 'Blocked · $bridgeLinkDetail';
      case ConnectionPhase.setup:
        return 'Bridge not connected';
      case ConnectionPhase.failed:
      case ConnectionPhase.offline:
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
        return 'Receiving readings · updated ${_shortDuration(age)} ago';
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
  int get signalBars {
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    return 1;
  }

  String get signalQualityLabel {
    switch (signalBars) {
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
        return 'Attempt 2 of 6 · next try in 4 sec';
      case ConnectionPhase.failed:
      case ConnectionPhase.offline:
        return 'Last connected ${_proseDuration(bridgeLastContactAge!)} ago';
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
    if (isOffline) return 'Synced 2 hr ago';
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
    const base = <double?>[165.2, 164.0, 151.4, 225.0];
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
    if (!historyHasData) return false;
    return !historyOneProbe || index == 3;
  }

  /// Everything the phone has recorded. Custom ranges start here and can then
  /// be narrowed to any minute.
  DateTimeRange get entireHistoryRange => DateTimeRange(
    start: DateTime(2026, 9, 1),
    end: DateTime(2026, 10, 25, 18, 30),
  );

  /// One shared timeline for pairing, Bridge link and Billows events. Billows
  /// joins automatically, so a dropped fan appears beside the regular
  /// connection history instead of in a separate feature.
  List<ConnectionEvent> get connectionLog {
    final now = DateTime(2026, 10, 25, 18, 30);
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
          time: now.subtract(const Duration(minutes: 2)),
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
            : 'Syncing the last 24 hours · $syncProgressPercent%';
      case ConnectionPhase.reconnecting:
        return 'Attempt 2 of 6 · next try in 4 sec';
      case ConnectionPhase.failed:
        return 'Tap to retry. Recording continues on the Bridge.';
      case ConnectionPhase.offline:
        return offlineCache
            ? 'Last reading 2 hr ago'
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

  void setUnits(Units value) {
    units = value;
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

  void retryConnection() {
    phase = ConnectionPhase.reconnecting;
    notifyListeners();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      phase = ConnectionPhase.live;
      syncState = SyncState.complete;
      notifyListeners();
    });
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
    notifyListeners();
  }

  void forgetPhone() {
    hasSavedBridge = false;
    hasSavedData = true;
    savedDataEmpty = false;
    phase = ConnectionPhase.setup;
    notifyListeners();
  }

  void factoryReset() {
    hasSavedBridge = false;
    hasSavedData = true;
    savedDataEmpty = false;
    phase = ConnectionPhase.setup;
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
    smokeXChannel4SetKnown = true;
    smokeXChannel4SetF = 225;
    billowsSeenThisSession = true;
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
    displayTimeoutSeconds = 60;
    deviceName = 'Backyard Bridge';
    saveState = SettingsSaveState.idle;
    bridgeRecords = 24810;
    phoneRecords = 128430;
    if (keepTheme) _themeMode = theme;
    notifyListeners();
  }
}
