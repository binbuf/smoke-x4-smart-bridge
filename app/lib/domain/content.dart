import 'models.dart';

/// The business-data seam behind the view models.
///
/// T06 keeps the UI on the approved baseline: production supplies
/// [EmptyBridgeContent] until M2/M3 wire BLE and SQLite, while review builds and
/// tests inject the fixture-backed adapter from `lib/debug/`. Widgets never see
/// this interface; they only see immutable view state.
abstract interface class BridgeContent {
  DateTime get now;

  /// Four probe temperatures in P1–P4 order. `null` means detached/unavailable.
  List<double?> get probeTemps;

  /// All history currently known to the app. Custom ranges start here.
  HistoryWindow get historyWindow;

  int get bridgeRecords;
  int get bridgeCapacity;
  int get phoneRecords;
  String get savedDataRange;
  String get savedDataSize;

  List<ChartPoint> sparkline(int probe, {required bool hasData});

  HistoryFixture history(
    HistoryRange range, {
    required bool empty,
    required bool oneProbe,
    required bool estimated,
    required bool missingFromBridge,
    required bool hasGap,
    DateTime? customStart,
    DateTime? customEnd,
  });

  List<CookSession> cooks();
}

/// Flutter-free start/end pair so the domain layer does not import widgets.
class HistoryWindow {
  const HistoryWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}

/// The honest production default before the BLE and archive tasks land: no
/// fixture values, no invented probes and no history.
class EmptyBridgeContent implements BridgeContent {
  const EmptyBridgeContent();

  @override
  DateTime get now => DateTime.now();

  @override
  List<double?> get probeTemps => const [null, null, null, null];

  @override
  HistoryWindow get historyWindow {
    final end = now;
    return HistoryWindow(
      start: end.subtract(const Duration(hours: 1)),
      end: end,
    );
  }

  @override
  int get bridgeRecords => 0;

  @override
  int get bridgeCapacity => 0;

  @override
  int get phoneRecords => 0;

  @override
  String get savedDataRange => '—';

  @override
  String get savedDataSize => '0 B';

  @override
  List<ChartPoint> sparkline(int probe, {required bool hasData}) => const [];

  @override
  HistoryFixture history(
    HistoryRange range, {
    required bool empty,
    required bool oneProbe,
    required bool estimated,
    required bool missingFromBridge,
    required bool hasGap,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final window = historyWindow;
    final start = customStart ?? window.start;
    final end = customEnd ?? window.end;
    return HistoryFixture(
      start: start,
      end: end,
      series: const [
        ChartSeries(0, []),
        ChartSeries(1, []),
        ChartSeries(2, []),
        ChartSeries(3, []),
      ],
      gapStart: start,
      gapEnd: start,
      gapReason: HistoryGapReason.noSignal,
      estimated: estimated,
      missingFromBridge: missingFromBridge,
    );
  }

  @override
  List<CookSession> cooks() => const [];
}
