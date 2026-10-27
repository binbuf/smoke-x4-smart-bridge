import 'dart:async';
import 'dart:typed_data';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/data/ble/ble_client.dart';
import 'package:smoke_bridge/data/repository.dart';
import 'package:smoke_bridge/domain/content.dart';

import 'codecs.dart' as proto;
import 'fake_ble_client.dart';
import 'fake_bridge.dart';

/// Test-only bridge link: drives the scripted BLE client and folds the decoded
/// `live` notification back into a [BridgeController].
///
/// This is the widget-test counterpart of the production link procedures that
/// land in M2. It intentionally lives in `test/support/`, never in `lib/`.
class FakeBridgeSession {
  FakeBridgeSession({
    FakeBridge? bridge,
    List<BleDevice>? advertisements,
    this.passkey = '418302',
    BridgeRepository repository = const EmptyBridgeRepository(),
  }) : bridge = bridge ?? FakeBridge(),
       _content = _FakeLiveContent() {
    client = FakeBleClient(
      server: this.bridge,
      advertisements:
          advertisements ?? <BleDevice>[this.bridge.advertisement()],
      expectedPasskey: passkey,
    );
    controller = BridgeController(
      repository: repository,
      content: _content,
      bleClient: client,
    )..phase = ConnectionPhase.setup;
    _connectionSubscription = client.connectionStates.listen(_onConnection);
    _liveSubscription = client
        .notifications(proto.bleCharacteristicByName('live').uuid)
        .listen(_onLive);
  }

  final FakeBridge bridge;
  final String passkey;
  final _FakeLiveContent _content;
  late final FakeBleClient client;
  late final BridgeController controller;

  StreamSubscription<BleConnectionState>? _connectionSubscription;
  StreamSubscription<Uint8List>? _liveSubscription;
  bool _disposed = false;

  /// Runs the scripted scan and returns the bridge advertisement.
  Future<BleDevice> scan() async {
    final devices = await client.scan().toList();
    return devices.firstWhere(
      (device) => device.isSmokeBridge,
      orElse: () =>
          throw StateError('script contained no bridge advertisement'),
    );
  }

  Future<void> connect(BleDevice device) => client.connect(device);

  Future<BleBondState> bond() => client.bond(passkey: passkey);

  Future<void> subscribeLive() => client.setNotify(
    proto.bleCharacteristicByName('live').uuid,
    enabled: true,
  );

  /// Publishes one live sample. The controller updates when the notification
  /// listener runs.
  Future<void> publishLiveSample({
    List<int>? tempsF10,
    int? seq,
    int? batteryPct,
    int? rssiLora,
    int? ageS,
  }) async {
    bridge.publishLive(
      tempsF10: tempsF10,
      seq: seq,
      batteryPct: batteryPct,
      rssiLora: rssiLora,
      ageS: ageS,
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> disconnect() => client.disconnect();

  void _onConnection(BleConnectionState state) {
    if (_disposed) return;
    switch (state) {
      case BleConnectionState.connected:
        controller.phase = ConnectionPhase.syncing;
        controller.syncState = SyncState.recent;
        break;
      case BleConnectionState.disconnected:
        controller.disconnect();
        break;
      case BleConnectionState.connecting:
      case BleConnectionState.disconnecting:
        return;
    }
    controller.notifyListeners();
  }

  void _onLive(Uint8List bytes) {
    if (_disposed) return;
    try {
      final live = proto.Live.decode(bytes);
      _content.probeTemps = <double?>[
        for (var index = 0; index < 4; index++)
          live.tempOrNull(index) == null
              ? null
              : live.tempOrNull(index)! / 10.0,
      ];
      controller
        ..phase = ConnectionPhase.live
        ..probeHealth = ProbeHealth.live
        ..smokeXStatus = SmokeXStatus.pairedLive
        ..smokeXLiveHint = true
        ..storageOk = live.storageOk
        ..batteryPercent = live.batteryPct
        ..rssi = live.rssiLora
        ..syncState = SyncState.complete
        ..syncProgressPercent = 100
        ..billowsAttachment = live.billowsAttached
            ? BillowsAttachment.attached
            : controller.billowsAttachment
        ..billowsSeenThisSession =
            controller.billowsSeenThisSession || live.billowsAttached
        ..smokeXChannel4SetKnown = live.billowsTargetF10 != 0
        ..smokeXChannel4SetF = (live.billowsTargetF10 / 10).round()
        ..notifyListeners();
    } on RangeError {
      // A truncated notification is a test-script bug; the next sample would
      // overwrite it. Never fabricate probe values from a bad frame.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _liveSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await client.dispose();
    controller.dispose();
    await bridge.dispose();
  }
}

/// Live-only content backed by notifications. History, cooks and saved data
/// stay empty until the archive tasks land.
class _FakeLiveContent implements BridgeContent {
  @override
  List<double?> probeTemps = const <double?>[null, null, null, null];

  @override
  DateTime get now => DateTime(2026, 10, 26, 12);

  @override
  HistoryWindow get historyWindow =>
      HistoryWindow(start: now.subtract(const Duration(hours: 1)), end: now);

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
      series: const <ChartSeries>[
        ChartSeries(0, <ChartPoint>[]),
        ChartSeries(1, <ChartPoint>[]),
        ChartSeries(2, <ChartPoint>[]),
        ChartSeries(3, <ChartPoint>[]),
      ],
      gapStart: start,
      gapEnd: start,
      gapReason: HistoryGapReason.noSignal,
      estimated: estimated,
      missingFromBridge: missingFromBridge,
    );
  }

  @override
  List<CookSession> cooks() => const <CookSession>[];
}
