import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/bridge_controller.dart';
import '../../data/ble/ble_client.dart';
import '../../data/ble/bridge_codecs.dart';
import '../../data/ble/bridge_link.dart';

/// The production setup state machine.
///
/// Every state in 13 §13.4 is owned here; the screen only lays out the approved
/// copy. The flow talks to [BleClient] and never imports a radio plugin, so the
/// widget tests drive it with the scripted fake.
class SetupFlow extends ChangeNotifier {
  SetupFlow({
    required this.controller,
    this.frozenStep,
    List<ScannedBridge>? frozenBridges,
  }) : _frozen = frozenStep != null,
       _bridges = List<ScannedBridge>.of(
         frozenBridges ?? const <ScannedBridge>[],
       ),
       step = frozenStep ?? SetupStep.noBridge;

  /// A frozen flow used by the Experimental lab and screenshots. It never
  /// touches the radio and never advances, so every state can be inspected.
  factory SetupFlow.frozen({
    required BridgeController controller,
    required SetupStep step,
    List<ScannedBridge>? bridges,
  }) {
    return SetupFlow(
      controller: controller,
      frozenStep: step,
      frozenBridges: bridges,
    );
  }

  final BridgeController controller;
  final bool _frozen;
  final SetupStep? frozenStep;

  SetupStep step;
  List<ScannedBridge> _bridges;
  BlePlatformStatus? platform;
  BridgeInfo? bridgeInfo;
  ScannedBridge? selected;
  bool connecting = false;
  bool scanning = false;
  int bondProgress = 0;
  int wrongCodeFailures = 0;

  StreamSubscription<BleDevice>? _scanSubscription;
  Timer? _scanTimer;
  bool _scanFinished = false;
  bool _disposed = false;

  List<ScannedBridge> get bridges => List<ScannedBridge>.unmodifiable(_bridges);

  bool get isFrozen => _frozen;

  BleClient? get client => controller.bleClient;

  bool _isRemembered(ScannedBridge bridge) {
    final id = controller.rememberedBridgeId?.toLowerCase();
    final name = controller.rememberedBridgeName?.toLowerCase();
    if (id != null && id.isNotEmpty && bridge.id.toLowerCase() == id) {
      return true;
    }
    return name != null && name.isNotEmpty && bridge.name.toLowerCase() == name;
  }

  bool isRemembered(ScannedBridge bridge) => _isRemembered(bridge);

  void _setStep(SetupStep value) {
    if (_disposed) return;
    step = value;
    notifyListeners();
  }

  /// The first `Find bridge` tap. Checks hardware, adapter and permission
  /// before doing anything else (06 §6.4).
  Future<void> findBridge() async {
    if (_frozen) return;
    final client = this.client;
    if (client == null) {
      _setStep(SetupStep.unsupportedPhone);
      return;
    }
    try {
      final status = await client.platformStatus();
      platform = status;
      _routePlatformStatus(status);
    } on BleException catch (error) {
      _applyFailure(error.appState);
    } catch (_) {
      _setStep(SetupStep.unsupportedPhone);
    }
  }

  void _routePlatformStatus(BlePlatformStatus status) {
    switch (status.state) {
      case BleAppState.ready:
        _beginScan();
        break;
      case BleAppState.bluetoothOff:
        _setStep(SetupStep.bluetoothOff);
        break;
      case BleAppState.permissionNeeded:
        _setStep(SetupStep.permissionPrimer);
        break;
      case BleAppState.permissionBlocked:
        _setStep(SetupStep.permissionBlocked);
        break;
      case BleAppState.unsupportedPhone:
        _setStep(SetupStep.unsupportedPhone);
        break;
      default:
        _setStep(SetupStep.permissionPrimer);
    }
  }

  /// `Continue` / `Grant permission`. Only this path requests the runtime
  /// permission; `Find bridge` merely checks it.
  Future<void> requestPermissionAndScan() async {
    if (_frozen) return;
    final client = this.client;
    if (client == null) {
      _setStep(SetupStep.unsupportedPhone);
      return;
    }
    try {
      final permission = await client.requestPermissions();
      switch (permission) {
        case BlePermissionState.granted:
          final status = await client.platformStatus();
          platform = status;
          _routePlatformStatus(status);
          break;
        case BlePermissionState.permanentlyDenied:
          _setStep(SetupStep.permissionBlocked);
          break;
        case BlePermissionState.denied:
        case BlePermissionState.notDetermined:
          _setStep(SetupStep.permissionDenied);
          break;
      }
    } on BleException catch (error) {
      _applyFailure(error.appState);
    }
  }

  /// `Check again` after the user returns from Android settings.
  Future<void> checkAgain() => findBridge();

  Future<void> _beginScan() async {
    final client = this.client;
    if (client == null) {
      _setStep(SetupStep.unsupportedPhone);
      return;
    }
    await _stopScan();
    _scanFinished = false;
    _bridges = <ScannedBridge>[];
    scanning = true;
    _setStep(SetupStep.scanning);
    _scanTimer?.cancel();
    _scanTimer = Timer(bleScanTimeout, () async {
      await client.stopScan();
      _finishScan();
    });
    try {
      _scanSubscription = client
          .scan(timeout: bleScanTimeout)
          .listen(
            _onAdvertisement,
            onError: (Object error) {
              if (error is BleException) {
                _applyFailure(error.appState);
              } else {
                _finishScan();
              }
            },
            onDone: _finishScan,
          );
    } on BleException catch (error) {
      _applyFailure(error.appState);
    }
  }

  void _onAdvertisement(BleDevice device) {
    if (_scanFinished || _disposed) return;
    final row = scannedBridgeFor(device);
    if (row == null) return;
    final index = _bridges.indexWhere((item) => item.id == row.id);
    if (index >= 0) {
      _bridges[index] = row;
    } else {
      _bridges.add(row);
    }
    notifyListeners();
  }

  void _finishScan() {
    if (_scanFinished) return;
    _scanFinished = true;
    scanning = false;
    _scanTimer?.cancel();
    unawaited(_scanSubscription?.cancel());
    _scanSubscription = null;
    if (_disposed) return;
    if (step != SetupStep.scanning) return;
    _sortBridges();
    _setStep(_bridges.isEmpty ? SetupStep.noResults : SetupStep.results);
  }

  void _sortBridges() {
    _bridges.sort((a, b) {
      final rememberedA = _isRemembered(a);
      final rememberedB = _isRemembered(b);
      if (rememberedA != rememberedB) return rememberedA ? -1 : 1;
      if (a.requiresNewerApp != b.requiresNewerApp) {
        return a.requiresNewerApp ? 1 : -1;
      }
      return 0;
    });
  }

  /// `Cancel` during scanning. The last remembered bridge is not auto-connected.
  Future<void> cancelScan() async {
    if (_frozen) return;
    await _stopScan();
    _scanFinished = true;
    _setStep(SetupStep.noBridge);
  }

  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    final client = this.client;
    if (client != null) {
      try {
        await client.stopScan();
      } catch (_) {
        // Cancelling a foreground scan is best-effort.
      }
    }
  }

  /// Selects a result row. Protocol-mismatch rows never connect; compatible
  /// rows connect and read `info` before any bond is started.
  Future<void> select(ScannedBridge row) async {
    if (_frozen || connecting) return;
    selected = row;
    if (row.requiresNewerApp) {
      _setStep(SetupStep.protocolMismatch);
      return;
    }
    final client = this.client;
    if (client == null) {
      _setStep(SetupStep.unsupportedPhone);
      return;
    }
    connecting = true;
    notifyListeners();
    var keepLink = false;
    try {
      await client.connect(row.device);
      final info = BridgeInfo.decode(
        await client.read(bleInfoCharacteristicUuid),
      );
      bridgeInfo = info;
      if (!info.isCompatible) {
        _setStep(SetupStep.protocolMismatch);
        return;
      }
      if (info.bondsFree == 0) {
        // Do not start the OS bond just to discover the store is full.
        _setStep(SetupStep.bondStoreFull);
        return;
      }
      keepLink = true;
      _setStep(SetupStep.passkey);
    } on FormatException {
      _setStep(SetupStep.protocolMismatch);
    } on BleException catch (error) {
      _applyFailure(error.appState);
    } catch (_) {
      _setStep(SetupStep.connectionFailed);
    } finally {
      // A failed select must not leave the Bridge's single connection slot
      // occupied; that also stops its advertising/BT indicator.
      if (!keepLink &&
          client.connectionState != BleConnectionState.disconnected) {
        try {
          await client.disconnect();
        } catch (_) {
          // Closing a failed setup attempt is best-effort.
        }
      }
      connecting = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// `Pair`: the instruction has been shown, so now start the OS bond. The app
  /// never supplies a passkey; Android owns the dialog.
  Future<void> pair() async {
    if (_frozen) return;
    final client = this.client;
    if (client == null) {
      _setStep(SetupStep.unsupportedPhone);
      return;
    }
    bondProgress = 0;
    _setStep(SetupStep.bonding);
    try {
      final result = await client.bond();
      _handleBondResult(result);
    } on BleException catch (error) {
      _applyFailure(error.appState);
    } catch (_) {
      _setStep(SetupStep.bondWrongCode);
    }
  }

  void _handleBondResult(BleBondState result) {
    switch (result) {
      case BleBondState.bonded:
        unawaited(_afterBond());
        break;
      case BleBondState.wrongPasskey:
        _recordWrongCode();
        break;
      case BleBondState.timeout:
        _setStep(SetupStep.bondTimeout);
        break;
      case BleBondState.bondStoreFull:
        _setStep(SetupStep.bondStoreFull);
        break;
      case BleBondState.none:
      case BleBondState.bonding:
      case BleBondState.failed:
        _setStep(SetupStep.bondWrongCode);
        break;
    }
  }

  void _recordWrongCode() {
    wrongCodeFailures++;
    _setStep(SetupStep.bondWrongCode);
  }

  Future<void> _afterBond() async {
    final device = selected?.device;
    if (client == null || device == null) return;
    bondProgress = 1;
    notifyListeners();
    // T35: MTU → subscribe → read live → set_time → recent sync. The bond and
    // the passkey instruction already happened on the approved setup screens.
    try {
      final link = controller.ensureLink();
      await link.completeFirstConnect(device, info: bridgeInfo);
      controller.rememberBridge(
        deviceId: selected?.id,
        deviceName: selected?.name,
        mtu: link.negotiatedMtu,
      );
    } on BridgeLinkException catch (error) {
      await _disconnectQuietly();
      if (_disposed) return;
      switch (error.failure) {
        case BridgeLinkFailure.protocolMismatch:
          _setStep(SetupStep.protocolMismatch);
          break;
        case BridgeLinkFailure.bondFailed:
        case BridgeLinkFailure.bondRequired:
        case BridgeLinkFailure.bondCancelled:
          _recordWrongCode();
          break;
        case BridgeLinkFailure.notConnected:
        case BridgeLinkFailure.notSecured:
        case BridgeLinkFailure.controlTimeout:
        case BridgeLinkFailure.syncTimeout:
        case BridgeLinkFailure.syncFailed:
        case BridgeLinkFailure.syncGap:
        case BridgeLinkFailure.operationFailed:
          _setStep(SetupStep.connectionFailed);
          break;
      }
      return;
    } on FormatException {
      await _disconnectQuietly();
      _setStep(SetupStep.protocolMismatch);
      return;
    } catch (_) {
      await _disconnectQuietly();
      _setStep(SetupStep.connectionFailed);
      return;
    }
    if (_disposed) return;
    bondProgress = 2;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_disposed) return;
    bondProgress = 3;
    _setStep(SetupStep.firstSync);
  }

  /// `Forget and re-pair`: remove the stale OS bond, then show the instruction
  /// again. Never bond from this screen without the approved block first.
  Future<void> forgetAndRepair() async {
    if (_frozen) return;
    final client = this.client;
    if (client == null) return;
    try {
      await client.removeBond();
    } catch (_) {
      // Android may already have removed it; the retry path is the same.
    }
    _setStep(SetupStep.passkey);
  }

  void showSavedData() => _setStep(SetupStep.savedData);

  void backToStart() => _setStep(SetupStep.noBridge);

  void protocolMismatch() => _setStep(SetupStep.protocolMismatch);

  void _applyFailure(BleAppState state) {
    switch (state) {
      case BleAppState.ready:
        break;
      case BleAppState.bluetoothOff:
        _setStep(SetupStep.bluetoothOff);
        break;
      case BleAppState.permissionNeeded:
        _setStep(SetupStep.permissionDenied);
        break;
      case BleAppState.permissionBlocked:
        _setStep(SetupStep.permissionBlocked);
        break;
      case BleAppState.unsupportedPhone:
        _setStep(SetupStep.unsupportedPhone);
        break;
      case BleAppState.noResults:
        _setStep(SetupStep.noResults);
        break;
      case BleAppState.pairingFailed:
        _recordWrongCode();
        break;
      case BleAppState.promptTimeout:
        _setStep(SetupStep.bondTimeout);
        break;
      case BleAppState.staleBond:
        _setStep(SetupStep.bondStale);
        break;
      case BleAppState.phoneListFull:
        _setStep(SetupStep.bondStoreFull);
        break;
      case BleAppState.connectionFailed:
      case BleAppState.gattError:
      case BleAppState.timeout:
        _setStep(SetupStep.connectionFailed);
        break;
    }
  }

  Future<void> _disconnectQuietly() async {
    final client = this.client;
    if (client == null) return;
    if (client.connectionState == BleConnectionState.disconnected) return;
    try {
      await client.disconnect();
    } catch (_) {
      // Best effort: failure recovery must not throw another setup error.
    }
  }

  /// Retry the selected Bridge without making the user scan again.
  Future<void> retryConnection() async {
    final row = selected;
    if (row != null) {
      await select(row);
    } else {
      await findBridge();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scanTimer?.cancel();
    unawaited(_scanSubscription?.cancel());
    super.dispose();
  }
}
