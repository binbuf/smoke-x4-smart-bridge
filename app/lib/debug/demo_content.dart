import '../app/bridge_controller.dart';
import '../data/repository.dart';
import '../domain/content.dart';
import 'fixtures.dart';

/// Fixture-backed content adapter. Only tests, the screenshot generator and the
/// debug Experimental lab may construct this.
class DemoBridgeContent implements BridgeContent {
  const DemoBridgeContent();

  @override
  DateTime get now => fixtureNow;

  @override
  List<double?> get probeTemps => const [165.2, 164.0, 151.4, 225.0];

  @override
  HistoryWindow get historyWindow => HistoryWindow(
    start: DateTime(2026, 9, 1),
    end: DateTime(2026, 10, 25, 18, 30),
  );

  @override
  int get bridgeRecords => 24810;

  @override
  int get bridgeCapacity => 338400;

  @override
  int get phoneRecords => 128430;

  @override
  String get savedDataRange => 'Sep 1 – Oct 24, 2026';

  @override
  String get savedDataSize => '9.2 MB';

  @override
  List<ChartPoint> sparkline(int probe, {required bool hasData}) =>
      buildSparklinePoints(probe, hasData: hasData);

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
  }) => buildHistoryFixture(
    range,
    empty: empty,
    oneProbe: oneProbe,
    estimated: estimated,
    missingFromBridge: missingFromBridge,
    hasGap: hasGap,
    customStart: customStart,
    customEnd: customEnd,
  );

  @override
  List<CookSession> cooks() => buildCookSessions();
}

/// Test/review controller seeded with the approved prototype fixtures.
BridgeController demoBridgeController({
  BridgeRepository? repository,
}) {
  return BridgeController(
    repository: repository ?? EmptyBridgeRepository(),
    content: const DemoBridgeContent(),
  )..historyHasData = true;
}
