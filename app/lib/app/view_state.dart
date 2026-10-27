import 'package:flutter/material.dart' show DateTimeRange;

import '../domain/models.dart';
import 'formatters.dart';

/// Immutable state the Live screen renders. Screens must read these fields
/// instead of the controller's mutable prototype-shaped fields.
class LiveViewState {
  const LiveViewState({
    required this.phase,
    required this.isConnected,
    required this.isOffline,
    required this.bridgeConnectedLabel,
    required this.telemetryStatusLabel,
    required this.bridgeLinkStatusLabel,
    required this.smokeXLinkStatusLabel,
    required this.connectionTitle,
    required this.connectionSubtitle,
    required this.signalBars,
    required this.signalQualityLabel,
    required this.rssi,
    required this.batteryPercent,
    required this.smokeXReceiving,
    required this.smokeXStatus,
    required this.storageOk,
    required this.slowLink,
    required this.syncState,
    required this.syncProgressPercent,
    required this.probes,
    required this.probePresence,
    required this.units,
    required this.billows,
    required this.billowsLostThisSession,
    required this.showSavedReadings,
    required this.lastSyncedLabel,
  });

  final ConnectionPhase phase;
  final bool isConnected;
  final bool isOffline;
  final String bridgeConnectedLabel;
  final String telemetryStatusLabel;
  final String bridgeLinkStatusLabel;
  final String smokeXLinkStatusLabel;
  final String connectionTitle;
  final String connectionSubtitle;
  final int signalBars;
  final String signalQualityLabel;
  final int rssi;
  final int batteryPercent;
  final bool smokeXReceiving;
  final SmokeXStatus smokeXStatus;
  final bool storageOk;
  final bool slowLink;
  final SyncState syncState;
  final int syncProgressPercent;
  final List<ProbeView> probes;
  final ProbePresence probePresence;
  final Units units;
  /// `null` when the card must not render: Billows was never detected or the
  /// Bridge reports `caps.billows_observe = 0`.
  final BillowsView? billows;
  final bool billowsLostThisSession;

  /// True when the offline surface is backed by saved readings. False means
  /// "nothing saved yet": probe values must render empty, never as current.
  final bool showSavedReadings;
  final String lastSyncedLabel;

  String get unitSuffix => unitLabel(units);

  bool get hasProbes => probes.any((probe) => probe.connected);
}

/// One Live probe tile. Values are pre-formatted so the widget only lays out
/// text and draws the supplied sparkline.
class ProbeView {
  const ProbeView({
    required this.number,
    required this.tempF,
    required this.connected,
    required this.health,
    required this.muted,
    required this.lastHour,
    required this.valueText,
    required this.unitSuffix,
    required this.statusText,
    required this.trendText,
    required this.deltaText,
    required this.semanticsLabel,
  });

  final int number;
  final double? tempF;
  final bool connected;
  final ProbeHealth health;
  final bool muted;
  final List<ChartPoint> lastHour;
  final String valueText;
  final String unitSuffix;
  final String? statusText;
  final String trendText;
  final String? deltaText;
  final String semanticsLabel;

  String get tempLabel => connected ? '$valueText$unitSuffix' : '—';
}

class BillowsView {
  const BillowsView({
    required this.detected,
    required this.lostThisSession,
    required this.seenThisSession,
    required this.setTempKnown,
    required this.setTempLabel,
    required this.setTempText,
    required this.lastDetectedLabel,
    required this.attachmentLabel,
    required this.settingsSubtitle,
    required this.sourceLabel,
  });

  final bool detected;
  final bool lostThisSession;
  final bool seenThisSession;
  final bool setTempKnown;
  final String setTempLabel;
  final String setTempText;
  final String lastDetectedLabel;
  final String attachmentLabel;
  final String settingsSubtitle;
  final String sourceLabel;
}

/// Immutable History state, including the filtered/sorted summary rows.
class HistoryViewState {
  const HistoryViewState({
    required this.range,
    required this.customRange,
    required this.probe,
    required this.sort,
    required this.fixture,
    required this.stats,
    required this.cooks,
    required this.activeCook,
    required this.cookReference,
    required this.now,
    required this.estimated,
    required this.missingFromBridge,
    required this.offline,
    required this.hasAnyHistory,
    required this.oneProbe,
    required this.units,
    required this.lastSyncedLabel,
    required this.entireHistoryRange,
  });

  final HistoryRange range;
  final DateTimeRange? customRange;
  final int? probe;
  final HistorySort sort;
  final HistoryFixture fixture;
  final List<ProbeRangeStats> stats;
  final List<CookSession> cooks;
  final CookSession? activeCook;
  final CookSession? cookReference;
  final DateTime now;
  final bool estimated;
  final bool missingFromBridge;
  final bool offline;
  final bool hasAnyHistory;
  final bool oneProbe;
  final Units units;
  final String lastSyncedLabel;
  final DateTimeRange entireHistoryRange;

  String get unitsLabel => unitLabel(units);

  String get rangeChipLabel => range == HistoryRange.custom
      ? 'Custom'
      : historyChipLabel(range);

  String get probeLabel => probe == null ? 'All probes' : 'P$probe';

  bool get hasActiveFilters =>
      probe != null || range != HistoryRange.twentyFourHours || customRange != null;

  bool seriesHasValues(int index) => fixture.seriesHasValues(index);

  bool get hasValues => fixture.hasValues;

  bool get noData => !fixture.hasValues;

  bool get noProbeData =>
      probe != null && !fixture.seriesHasValues(probe! - 1);

  int get probeCount => probe == null ? 4 : 1;

  int get dataProbeCount => probe == null
      ? fixture.series
            .where((series) => series.points.any((p) => p.valueF != null))
            .length
      : (fixture.seriesHasValues(probe! - 1) ? 1 : 0);

  String get probeMeta {
    final count = probeCount;
    final label = '$count ${count == 1 ? 'probe' : 'probes'}';
    if (dataProbeCount == count) return label;
    return '$dataProbeCount of $label';
  }

  String windowLabel({required bool use24Hour}) => historyWindowLabel(
    range,
    fixture.start,
    fixture.end,
    use24Hour: use24Hour,
  );

  String valueFor(double? fahrenheit) {
    if (fahrenheit == null) return '—';
    final value = units == Units.fahrenheit
        ? fahrenheit
        : (fahrenheit - 32) * 5 / 9;
    return value.toStringAsFixed(1);
  }

  String tempFor(double? fahrenheit) {
    if (fahrenheit == null) return '—';
    return '${valueFor(fahrenheit)}${unitLabel(units)}';
  }

  List<CookSession> get visibleCooks => cooks.take(3).toList();

  bool isCookSelected(CookSession cook) {
    final range = customRange;
    if (range == null) return false;
    return range.start.difference(cook.start).inMinutes.abs() < 1 &&
        range.end.difference(cook.end).inMinutes.abs() < 1;
  }

  bool isCookInProgress(CookSession cook) {
    final current = activeCook;
    if (current == null) return false;
    return current.start == cook.start && current.end == cook.end;
  }

  String get sortLabel {
    switch (sort) {
      case HistorySort.probe:
        return 'Probe order';
      case HistorySort.hottest:
        return 'Hottest';
      case HistorySort.highestMax:
        return 'Highest';
      case HistorySort.recent:
        return 'Latest reading';
      case HistorySort.sinceCookStart:
        return 'Since cook start';
    }
  }

  String get cookSortDetail {
    final reference = cookReference;
    if (reference == null) return 'No cook detected in this history.';
    final elapsed = durationShort(now.difference(reference.start));
    if (activeCook != null) return 'Cook started $elapsed ago · in progress';
    return 'Last cook started $elapsed ago';
  }
}

class SetupViewState {
  const SetupViewState({
    required this.hasSavedData,
    required this.savedDataEmpty,
    required this.phoneRecords,
    required this.phoneRecordsLabel,
    required this.savedDataRange,
    required this.savedDataSize,
    required this.syncProgressPercent,
  });

  final bool hasSavedData;
  final bool savedDataEmpty;
  final int phoneRecords;
  final String phoneRecordsLabel;
  final String savedDataRange;
  final String savedDataSize;
  final int syncProgressPercent;

  bool get hasSavedHistory => hasSavedData || !savedDataEmpty;

  String get syncProgressLabel => '$syncProgressPercent%';
}

class SettingsViewState {
  const SettingsViewState({
    required this.connected,
    required this.offline,
    required this.phase,
    required this.deviceName,
    required this.deviceId,
    required this.batteryPercent,
    required this.signalBars,
    required this.signalQualityLabel,
    required this.rssi,
    required this.bridgeLinkStatusLabel,
    required this.bridgeLastContactDetail,
    required this.themeModeLabel,
    required this.units,
    required this.phoneRecords,
    required this.bridgeRecords,
    required this.bridgeCapacity,
    required this.phoneRecordsLabel,
    required this.bridgeRecordsLabel,
    required this.savedDataRange,
    required this.savedDataSize,
    required this.savedDataEmpty,
    required this.firmware,
    required this.hasSavedData,
  });

  final bool connected;
  final bool offline;
  final ConnectionPhase phase;
  final String deviceName;
  final String deviceId;
  final int batteryPercent;
  final int signalBars;
  final String signalQualityLabel;
  final int rssi;
  final String bridgeLinkStatusLabel;
  final String bridgeLastContactDetail;
  final String themeModeLabel;
  final Units units;
  final int phoneRecords;
  final int bridgeRecords;
  final int bridgeCapacity;
  final String phoneRecordsLabel;
  final String bridgeRecordsLabel;
  final String savedDataRange;
  final String savedDataSize;
  final bool savedDataEmpty;
  final String firmware;
  final bool hasSavedData;

  bool get canEdit => connected;

  bool get canClearBridgeHistory => connected;

  double get bridgeFraction =>
      bridgeCapacity == 0 ? 0 : bridgeRecords / bridgeCapacity;

  String get bridgeFractionLabel =>
      '${(bridgeFraction * 100).toStringAsFixed(1)}%';

  bool get localHistoryEmpty => savedDataEmpty || phoneRecords == 0;
}

/// The Bridge details and its status-only child screens (Billows, storage,
/// About) render from this snapshot.
class BridgeDetailsViewState {
  const BridgeDetailsViewState({
    required this.connected,
    required this.offline,
    required this.phase,
    required this.deviceName,
    required this.deviceId,
    required this.batteryPercent,
    required this.signalBars,
    required this.signalQualityLabel,
    required this.rssi,
    required this.bridgeLinkStatusLabel,
    required this.bridgeLastContactDetail,
    required this.bridgeConnectedForLabel,
    required this.lastSyncedLabel,
    required this.firmware,
    required this.protocol,
    required this.slowLink,
    required this.canEdit,
    required this.smokeXLabel,
    required this.smokeXSubtitle,
    required this.smokeXReceiving,
    required this.smokeXStatus,
    required this.billows,
    required this.displayTimeoutSeconds,
    required this.displayTimeoutLabel,
    required this.bridgeRecords,
    required this.bridgeCapacity,
    required this.phoneRecords,
    required this.savedDataRange,
    required this.savedDataSize,
    required this.savedDataEmpty,
    required this.connectionLog,
    required this.billowsLog,
  });

  final bool connected;
  final bool offline;
  final ConnectionPhase phase;
  final String deviceName;
  final String deviceId;
  final int batteryPercent;
  final int signalBars;
  final String signalQualityLabel;
  final int rssi;
  final String bridgeLinkStatusLabel;
  final String bridgeLastContactDetail;
  final String bridgeConnectedForLabel;
  final String lastSyncedLabel;
  final String firmware;
  final String protocol;
  final bool slowLink;
  final bool canEdit;
  final String smokeXLabel;
  final String smokeXSubtitle;
  final bool smokeXReceiving;
  final SmokeXStatus smokeXStatus;
  final BillowsView billows;
  final int displayTimeoutSeconds;
  final String displayTimeoutLabel;
  final int bridgeRecords;
  final int bridgeCapacity;
  final int phoneRecords;
  final String savedDataRange;
  final String savedDataSize;
  final bool savedDataEmpty;
  final List<ConnectionEvent> connectionLog;
  final List<ConnectionEvent> billowsLog;

  String get timeoutSubtitle {
    if (displayTimeoutSeconds == 0) return 'Screen stays on';
    return '$displayTimeoutLabel · screen turns off';
  }

  String get lastSyncedValue => lastSyncedLabel.replaceFirst('Synced ', '');

  String get mtuLabel => slowLink ? '23 · slow connection' : '247';

  double get bridgeFraction =>
      bridgeCapacity == 0 ? 0 : bridgeRecords / bridgeCapacity;

  String get bridgeFractionLabel =>
      '${(bridgeFraction * 100).toStringAsFixed(1)}%';
}
