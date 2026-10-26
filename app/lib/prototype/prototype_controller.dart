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

enum BillowsMode { disabled, observe, control }

enum BillowsAttachment { unknown, attached, detached }

enum Units { fahrenheit, celsius }

enum HistoryRange { oneHour, sixHours, twentyFourHours, sevenDays, all, custom }

enum HistorySort { jack, hottest, largestChange, recent }

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

  bool billowsControlCapability = false;
  BillowsMode billowsMode = BillowsMode.observe;
  BillowsAttachment billowsAttachment = BillowsAttachment.attached;
  bool billowsTargetKnown = true;
  int billowsTargetF = 225;

  HistoryRange historyRange = HistoryRange.twentyFourHours;
  int? historyProbe;
  DateTimeRange? historyCustomRange;
  HistorySort historySort = HistorySort.jack;
  bool daysNewestFirst = true;
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

  bool get isBillowsControl =>
      billowsControlCapability && billowsMode == BillowsMode.control;

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

  String tempFor(double? fahrenheit) => '${valueFor(fahrenheit)} $unitSuffix';

  String get connectionTitle {
    switch (phase) {
      case ConnectionPhase.live:
        return 'Connected';
      case ConnectionPhase.stale:
        return 'No new readings';
      case ConnectionPhase.syncing:
        return 'Syncing';
      case ConnectionPhase.reconnecting:
        return 'Reconnecting…';
      case ConnectionPhase.failed:
        return 'Can’t reach the bridge';
      case ConnectionPhase.offline:
        return offlineCache
            ? 'Showing last saved readings'
            : 'Can’t reach the bridge';
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
        return 'Not connected';
    }
  }

  String get connectionChipLabel {
    switch (phase) {
      case ConnectionPhase.live:
        return 'Connected · 4s';
      case ConnectionPhase.stale:
        return 'No new data · 4m';
      case ConnectionPhase.syncing:
        return 'Syncing';
      case ConnectionPhase.reconnecting:
        return 'Reconnecting';
      case ConnectionPhase.failed:
        return 'Can’t reach bridge';
      case ConnectionPhase.offline:
        return 'Offline';
      case ConnectionPhase.blocked:
        return 'Action needed';
      case ConnectionPhase.setup:
        return 'Not connected';
    }
  }

  String get connectionSubtitle {
    switch (phase) {
      case ConnectionPhase.live:
        if (!smokeXLiveHint) {
          return 'Bridge connected · waiting for the Smoke X4';
        }
        return 'Updated 4s ago · battery $batteryPercent%';
      case ConnectionPhase.stale:
        return 'Last reading 4m ago · the bridge still answers';
      case ConnectionPhase.syncing:
        return syncState == SyncState.backfill
            ? 'Loading older history · ${slowLink ? 'slow Bluetooth link' : 'in the background'}'
            : 'Catching up the last 24 hours · $syncProgressPercent%';
      case ConnectionPhase.reconnecting:
        return 'Attempt 2 of 6 · next try in 4 s';
      case ConnectionPhase.failed:
        return 'Tap to retry. Recording continues on the bridge.';
      case ConnectionPhase.offline:
        return offlineCache
            ? 'Last sync 2 h ago'
            : 'Nothing has been saved on this phone yet';
      case ConnectionPhase.blocked:
        switch (blockReason) {
          case BlockReason.bluetoothOff:
            return 'Turn Bluetooth on to find your bridge.';
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
        return 'Set up a bridge to see live readings.';
    }
  }

  bool smokeXLiveHint = true;

  String get smokeXLabel {
    switch (smokeXStatus) {
      case SmokeXStatus.pairedLive:
        return 'Paired · live';
      case SmokeXStatus.pairedLost:
        return 'Paired · lost 14m';
      case SmokeXStatus.unpaired:
        return 'Not paired';
    }
  }

  String get smokeXSubtitle {
    switch (smokeXStatus) {
      case SmokeXStatus.pairedLive:
        return 'Signal good · last packet 12 s ago';
      case SmokeXStatus.pairedLost:
        return 'Last packet 14 minutes ago. Put the Smoke X4 in SYNC.';
      case SmokeXStatus.unpaired:
        return 'Scanning 915/920 MHz. Put the Smoke X4 in SYNC.';
    }
  }

  String get billowsModeLabel {
    switch (billowsMode) {
      case BillowsMode.disabled:
        return 'Off';
      case BillowsMode.observe:
        return 'Monitor only';
      case BillowsMode.control:
        return 'Control';
    }
  }

  String get billowsAttachmentLabel {
    switch (billowsAttachment) {
      case BillowsAttachment.attached:
        return 'Connected';
      case BillowsAttachment.detached:
        return 'Not connected';
      case BillowsAttachment.unknown:
        return 'Unknown';
    }
  }

  String get billowsSourceLabel {
    if (billowsMode == BillowsMode.disabled) {
      return 'Billows monitoring is off.';
    }
    if (isBillowsControl) {
      return 'Controlled by the bridge';
    }
    return 'Set target on Smoke X4';
  }

  String get displayTimeoutLabel {
    if (displayTimeoutSeconds == 0) return 'Never';
    return '$displayTimeoutSeconds s';
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

  void setBillowsMode(BillowsMode value) {
    billowsMode = value;
    notifyListeners();
  }

  void setBillowsTarget(int value) {
    billowsTargetF = value;
    notifyListeners();
  }

  void setHistoryRange(HistoryRange value) {
    historyRange = value;
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

  void toggleDaysSort() {
    daysNewestFirst = !daysNewestFirst;
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
    billowsControlCapability = false;
    billowsMode = BillowsMode.observe;
    billowsAttachment = BillowsAttachment.attached;
    billowsTargetKnown = true;
    billowsTargetF = 225;
    historyRange = HistoryRange.twentyFourHours;
    historyProbe = null;
    historyCustomRange = null;
    historySort = HistorySort.jack;
    daysNewestFirst = true;
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
