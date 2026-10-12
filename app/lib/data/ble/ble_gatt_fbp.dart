/// [BleGattClient] over `flutter_blue_plus` — the production half of the seam.
///
/// The seam's whole purpose is that everything above it — `BleTransport` and
/// the notification reassembler — is tested against the Dart fake with no
/// radio. This file is the part that only a phone can prove,
/// and it is deliberately the thinnest thing that can work: find the
/// service, map characteristics by their 16-bit slot, translate the
/// plugin's failures into the typed conditions the app knows how to
/// render. No decisions live here.
///
/// Android reality that shapes the code (ble-gatt §3):
///
///  * The **passkey dialog is owned by the OS**. `createBond()` returns
///    when the user has dealt with it; we never see the digits, which is
///    exactly why the bridge shows them on its OLED.
///  * `connect()` on Android does not imply service discovery, and
///    `discoverServices()` must not run before the link is up.
///  * A bond we hold that the peer threw away (a factory-reset bridge)
///    surfaces as an authentication failure on the first encrypted read —
///    NOT as a connect failure. That is mapped to
///    [BleRebondRequiredException], because "it just won't connect" is the
///    bug report this whole distinction exists to prevent.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../platform/ble_permissions.dart';
import '../local/app_prefs.dart';
import 'ble_gatt.dart';
import 'ble_transport.dart';
import 'bridge_transport.dart';

class FlutterBlueGattClient implements BleGattClient {
  FlutterBlueGattClient();

  BluetoothDevice? _device;
  final _chars = <int, BluetoothCharacteristic>{};
  final _notifyCtls = <int, StreamController<Uint8List>>{};
  final _notifySubs = <int, StreamSubscription<List<int>>>{};
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final _connCtl = StreamController<BleConnectionState>.broadcast();
  final _bondCtl = StreamController<BleBondState>.broadcast();
  StreamSubscription<BluetoothBondState>? _bondSub;

  BleConnectionState _conn = BleConnectionState.disconnected;
  BleBondState _bond = BleBondState.none;
  int _mtu = 23;

  // ── scanning ───────────────────────────────────────────────────────

  Future<void> Function()? _endScan;

  /// **This stream MUST terminate.** `FlutterBluePlus.onScanResults` is a
  /// long-lived stream that never closes, so an `await for` over it runs
  /// forever — and a caller that treats "the scan ended" as a step
  /// boundary keeps being dragged back to the find step from under whatever
  /// the user moved on to.
  ///
  /// The Dart fake returns a stream that ends on its own, which is exactly
  /// why the test suite could not see this — so [FakePeripheral] has a
  /// `continuousScan` mode that reproduces the real plugin's behaviour.
  ///
  /// Ends on: the timeout, [stopScan], or the listener cancelling.
  @override
  Stream<BleAdvertisement> scan({
    Duration timeout = const Duration(seconds: 8),
  }) {
    final ctl = StreamController<BleAdvertisement>();
    StreamSubscription<List<ScanResult>>? sub;
    Timer? timer;
    var finished = false;

    Future<void> finish() async {
      if (finished) {
        return;
      }
      finished = true;
      timer?.cancel();
      await sub?.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } on Object {
        // Stopping a scan that already stopped is not a failure.
      }
      if (!ctl.isClosed) {
        await ctl.close();
      }
    }

    _endScan = finish;
    ctl.onCancel = finish;
    ctl.onListen = () async {
      sub = FlutterBluePlus.onScanResults.listen((batch) {
        for (final r in batch) {
          if (ctl.isClosed) {
            return;
          }
          ctl.add(
            BleAdvertisement(
              deviceId: r.device.remoteId.str,
              name: r.advertisementData.advName.isEmpty
                  ? null
                  : r.advertisementData.advName,
              // The §2.3 status blob is the payload AFTER the company id,
              // and the plugin has already split the id off for us.
              manufacturerData: _blobOf(r.advertisementData),
              rssi: r.rssi,
            ),
          );
        }
      }, onError: ctl.addError);
      timer = Timer(timeout, finish);
      try {
        // Filtered by OUR service UUID, so the list is bridges and nothing
        // else. `androidUsesFineLocation` stays at its `false` default, which
        // keeps the promise the manifest's `neverForLocation` makes.
        await FlutterBluePlus.startScan(
          withServices: [Guid(bridgeUuid(BridgeChar.service))],
          timeout: timeout,
        );
      } on Object catch (e) {
        ctl.addError(e);
        await finish();
      }
    };
    return ctl.stream;
  }

  static Uint8List? _blobOf(AdvertisementData adv) {
    final bytes = adv.manufacturerData[bridgeCompanyId];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> stopScan() async {
    final end = _endScan;
    _endScan = null;
    if (end != null) {
      await end();
      return;
    }
    await FlutterBluePlus.stopScan();
  }

  // ── connection ─────────────────────────────────────────────────────

  @override
  BleConnectionState get connectionState => _conn;

  @override
  Stream<BleConnectionState> get connectionStates => _connCtl.stream;

  void _setConn(BleConnectionState s) {
    _conn = s;
    if (!_connCtl.isClosed) {
      _connCtl.add(s);
    }
  }

  @override
  Future<void> connect(String deviceId) async {
    if (_conn == BleConnectionState.connected) {
      throw const BleStateException('already connected');
    }
    final device = BluetoothDevice.fromId(deviceId);
    _device = device;
    _setConn(BleConnectionState.connecting);

    _connSub ??= device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        _mtu = 23;
        _setConn(BleConnectionState.disconnected);
      }
    });
    _bondSub ??= device.bondState.listen((s) {
      _setBond(switch (s) {
        BluetoothBondState.none => BleBondState.none,
        BluetoothBondState.bonding => BleBondState.bonding,
        BluetoothBondState.bonded => BleBondState.bonded,
      });
    });

    try {
      // `mtu: null` because WE own the MTU strategy: ble-gatt §4 asks for
      // 247 (history_preview's 244 + 3 in one PDU), not the plugin's 512
      // default, and requestMtu() below is the tested path.
      //
      // LICENSE: flutter_blue_plus 2.3.10 requires this declaration at
      // the call site. `nonprofit` covers personal use, which is what this
      // project is. **If the bridge is ever sold or shipped commercially,
      // this must become License.commercial and be paid for** — see the
      // package's LICENSE.
      await device.connect(license: License.nonprofit, mtu: null);
    } on FlutterBluePlusException catch (e) {
      _setConn(BleConnectionState.disconnected);
      throw BleConnectionLostException('connect failed: ${e.description}');
    }
    _setConn(BleConnectionState.connected);
    await _discover(device);
  }

  /// Maps every characteristic of our service by its 16-bit slot, so the
  /// layers above never see a Guid.
  Future<void> _discover(BluetoothDevice device) async {
    final serviceUuid = Guid(bridgeUuid(BridgeChar.service));
    final services = await device.discoverServices();
    final svc = services.where((s) => s.uuid == serviceUuid).firstOrNull;
    if (svc == null) {
      throw const BleStateException(
        'not a Smoke Bridge (no Bridge Control Service)',
      );
    }
    _chars.clear();
    for (final c in svc.characteristics) {
      // The base UUID differs only in bytes 2..3; recover the slot.
      final hex = c.uuid.str.replaceAll('-', '');
      _chars[int.parse(hex.substring(4, 8), radix: 16)] = c;
    }
  }

  @override
  Future<void> disconnect() async {
    for (final s in _notifySubs.values) {
      await s.cancel();
    }
    _notifySubs.clear();
    await _device?.disconnect();
    _setConn(BleConnectionState.disconnected);
  }

  // ── bonding ────────────────────────────────────────────────────────

  @override
  BleBondState get bondState => _bond;

  @override
  Stream<BleBondState> get bondStates => _bondCtl.stream;

  void _setBond(BleBondState s) {
    _bond = s;
    if (!_bondCtl.isClosed) {
      _bondCtl.add(s);
    }
  }

  @override
  Future<void> bond() async {
    final device = _device;
    if (device == null || _conn != BleConnectionState.connected) {
      throw const BleStateException('bond() while disconnected');
    }
    _setBond(BleBondState.bonding);
    try {
      // The OS shows the six-digit prompt here; the user reads the code
      // off the bridge's OLED. We observe, we do not ask.
      await device.createBond();
    } on FlutterBluePlusException catch (e) {
      _setBond(BleBondState.failed);
      throw BleBondRejectedException('pairing failed: ${e.description}');
    }
    _setBond(BleBondState.bonded);
  }

  @override
  Future<void> removeBond() async {
    final device = _device;
    if (device == null) {
      throw const BleStateException('removeBond() with no bridge');
    }
    try {
      // Android-only plugin call (reflection over the hidden API). Where it
      // is refused, the caller's fallback is the manual Bluetooth-settings
      // route — this must throw, not lie.
      await device.removeBond();
    } on FlutterBluePlusException catch (e) {
      throw BleStateException('could not remove the bond: ${e.description}');
    }
    _setBond(BleBondState.none);
  }

  @override
  Future<int> requestMtu(int mtu) async {
    final device = _device;
    if (device == null) {
      return _mtu;
    }
    try {
      // A refusal is a legitimate answer, not an error: live_state is
      // 16 B precisely so 23 still works (ble-gatt §4, R7).
      _mtu = await device.requestMtu(mtu);
    } on FlutterBluePlusException {
      _mtu = device.mtuNow;
    }
    return _mtu;
  }

  @override
  int get mtu => _mtu;

  // ── attributes ─────────────────────────────────────────────────────

  /// Routed through the same bond-aware mapping as every other GATT op: a
  /// stale-bond stall must read as "re-pair", not as "no signal".
  @override
  Future<int> readRssi() async {
    final device = _device;
    if (device == null || _conn != BleConnectionState.connected) {
      throw const BleStateException('readRssi() while disconnected');
    }
    try {
      return await device.readRssi().timeout(_opTimeout);
    } on TimeoutException {
      _mapStall();
    } on FlutterBluePlusException catch (e) {
      _mapGattFailure(e);
    }
  }

  BluetoothCharacteristic _charFor(int slot) {
    final c = _chars[slot];
    if (c == null) {
      throw BleStateException(
        'characteristic 0x${slot.toRadixString(16)} not discovered',
      );
    }
    return c;
  }

  /// The plugin reports both "you are not bonded" and "the peer forgot
  /// you" as GATT auth errors. They are the same code and completely
  /// different problems, so the bond state we are holding is what tells
  /// them apart.
  Never _mapGattFailure(FlutterBluePlusException e) {
    final desc = e.description?.toLowerCase() ?? '';
    final isAuth =
        desc.contains('auth') ||
        desc.contains('encrypt') ||
        desc.contains('insufficient');
    if (isAuth) {
      if (_bond == BleBondState.bonded) {
        // We hold a key the bridge no longer has: it was factory-reset.
        throw const BleRebondRequiredException();
      }
      throw const BleNotBondedException();
    }
    if (_conn != BleConnectionState.connected) {
      throw const BleConnectionLostException();
    }
    throw BleStateException(e.description ?? 'GATT operation failed');
  }

  /// A GATT op that STALLS is Android silently retrying security. A stale OS
  /// bond against a factory-reset bridge never errors — the stack re-tries the
  /// dead key while the app waits forever. Bounding every op and reading the
  /// stall through the bond state turns "it just hangs" into the same typed
  /// answers the error path already gives.
  static const _opTimeout = Duration(seconds: 12);

  Never _mapStall() {
    if (_bond == BleBondState.bonded) {
      // We hold a key the bridge no longer honours: it was factory-reset.
      throw const BleRebondRequiredException();
    }
    if (_conn != BleConnectionState.connected) {
      throw const BleConnectionLostException();
    }
    throw const BleStateException('GATT operation timed out');
  }

  @override
  Future<Uint8List> read(int slot) async {
    try {
      return Uint8List.fromList(
        await _charFor(slot).read().timeout(_opTimeout),
      );
    } on TimeoutException {
      _mapStall();
    } on FlutterBluePlusException catch (e) {
      _mapGattFailure(e);
    }
  }

  @override
  Future<void> write(int slot, Uint8List value) async {
    try {
      // With response: every write on this contract is answered on
      // `result`, and a silently-dropped write would strand a command.
      await _charFor(slot).write(value).timeout(_opTimeout);
    } on TimeoutException {
      _mapStall();
    } on FlutterBluePlusException catch (e) {
      _mapGattFailure(e);
    }
  }

  @override
  Stream<Uint8List> subscribe(int slot) {
    final existing = _notifyCtls[slot];
    if (existing != null) {
      return existing.stream;
    }
    final ctl = StreamController<Uint8List>.broadcast();
    _notifyCtls[slot] = ctl;
    final c = _charFor(slot);
    // Chunks arrive exactly as the firmware sent them; reassembly happens
    // one layer up, because the boundary is a property of the
    // payload rather than of the link.
    _notifySubs[slot] = c.onValueReceived.listen(
      (v) => ctl.add(Uint8List.fromList(v)),
      onError: ctl.addError,
    );
    unawaited(
      c.setNotifyValue(true).timeout(_opTimeout).catchError((Object e) {
        // The CCCD write needs encryption, so a stale bond stalls or
        // auth-fails right here — route it through the same bond-aware
        // mapping as reads and writes.
        if (_bond == BleBondState.bonded &&
            (e is TimeoutException || e is FlutterBluePlusException)) {
          ctl.addError(const BleRebondRequiredException());
        } else if (e is FlutterBluePlusException || e is TimeoutException) {
          ctl.addError(
            const BleNotBondedException('could not enable notifications'),
          );
        } else {
          ctl.addError(e);
        }
        return false;
      }),
    );
    return ctl.stream;
  }

  @override
  Future<void> dispose() async {
    for (final s in _notifySubs.values) {
      await s.cancel();
    }
    _notifySubs.clear();
    await _connSub?.cancel();
    await _bondSub?.cancel();
    for (final c in _notifyCtls.values) {
      await c.close();
    }
    _notifyCtls.clear();
    await _connCtl.close();
    await _bondCtl.close();
    try {
      await _device?.disconnect();
    } on Object {
      // Disposing is a guaranteed-release path, never a thrower.
    }
  }
}

/// The production BLE lane opener.
///
/// In order: **permissions** (Android 12+ gates scan/connect, and the plugin
/// never asks) → **adapter state** (a scan with the radio off means nothing) →
/// **a remembered bridge** if one was used last time, else a scan → **connect,
/// bond and an encrypted probe**. Only a link that survives the probe is handed
/// back, which is what makes a factory-reset bridge's stale bond surface *here*,
/// where it can still be healed, instead of later as a dead reading.
///
/// Every failure is a [BridgeConnectionException] with a
/// [ConnectionProblem] the UI can act on — never a bare `null` that reads as
/// "it just won't connect".
Future<BleTransport> openBleTransport({
  Duration scanTimeout = const Duration(seconds: 8),
  int mtu = 247,
  AppPrefs? prefs,
}) async {
  final store = prefs ?? AppPrefs();

  final perm = await ensureBlePermissions();
  if (!perm.granted) {
    throw BridgeConnectionException(
      perm.permanentlyDenied
          ? ConnectionProblem.permissionsPermanentlyDenied
          : ConnectionProblem.permissions,
      'Smoke Bridge needs Bluetooth permission to find your bridge.',
    );
  }

  try {
    final state = await FlutterBluePlus.adapterState.first.timeout(
      const Duration(seconds: 3),
    );
    if (state == BluetoothAdapterState.off) {
      throw const BridgeConnectionException(
        ConnectionProblem.bluetoothOff,
        'Bluetooth is off. Turn it on to connect to your bridge.',
      );
    }
  } on BridgeConnectionException {
    rethrow;
  } on Object {
    // A platform that cannot report adapter state is left to the scan itself.
  }

  final client = FlutterBlueGattClient();
  try {
    final known = await store.readLastBridgeId();
    final deviceId = await _candidate(client, known, scanTimeout);
    if (deviceId == null) {
      throw const BridgeConnectionException(
        ConnectionProblem.notFound,
        "Couldn't find your bridge. Check that it is powered on and nearby.",
      );
    }

    try {
      final transport = await _connectAndHeal(client, deviceId, mtu);
      await store.writeLastBridgeId(deviceId);
      return transport;
    } on BleException {
      // The remembered bridge failed: a fresh scan may still find it (or a
      // replacement) under a new address. Only worth it when we used a known id.
      if (known != null && deviceId == known) {
        final scanned = await _scanForDeviceId(client, scanTimeout);
        if (scanned != null && scanned != deviceId) {
          final transport = await _connectAndHeal(client, scanned, mtu);
          await store.writeLastBridgeId(scanned);
          return transport;
        }
      }
      rethrow;
    }
  } on BridgeConnectionException {
    await client.dispose();
    rethrow;
  } on BleException catch (e) {
    await client.dispose();
    throw BridgeConnectionException(ConnectionProblem.failed, e.message);
  } on Object {
    await client.dispose();
    throw const BridgeConnectionException(
      ConnectionProblem.failed,
      'The bridge could not be reached.',
    );
  }
}

/// The remembered bridge if the OS still knows it, else a scan. Reconnecting to
/// a bonded device does not need a scan, which is what makes "pair once" feel
/// instant on the second launch.
Future<String?> _candidate(
  FlutterBlueGattClient client,
  String? known,
  Duration scanTimeout,
) async {
  if (known != null && await _isSystemDevice(known)) {
    return known;
  }
  // The remembered bridge may be present without the OS still listing it as a
  // system device (a cleared bond, a rebooted adapter). A scan is then the only
  // way in, and it must not settle for whichever bridge advertises first.
  return _scanForDeviceId(client, scanTimeout, preferId: known);
}

Future<bool> _isSystemDevice(String deviceId) async {
  try {
    final devices = await FlutterBluePlus.systemDevices([
      Guid(bridgeUuid(BridgeChar.service)),
    ]);
    return devices.any((d) => d.remoteId.str == deviceId);
  } on Object {
    return false;
  }
}

/// Choose the bridge to connect to when more than one is advertising.
///
/// The remembered one wins if it is present — its OS handle *is* the value the
/// advertisement carries, so matching [preferId] is exact. Otherwise a name
/// match is honoured, then the strongest signal (the best proxy for "nearest"),
/// then the first seen. Pure, so the preference is testable with no radio.
BleAdvertisement? selectBridge(
  List<BleAdvertisement> ads, {
  String? preferId,
  String? preferName,
}) {
  if (ads.isEmpty) {
    return null;
  }
  if (preferId != null) {
    for (final a in ads) {
      if (a.deviceId == preferId) {
        return a;
      }
    }
  }
  if (preferName != null) {
    for (final a in ads) {
      if (a.name == preferName) {
        return a;
      }
    }
  }
  var best = ads.first;
  for (final a in ads.skip(1)) {
    if (a.rssi > best.rssi) {
      best = a;
    }
  }
  return best;
}

/// The id of the bridge to connect to, over a bounded scan.
///
/// When a [preferId]/[preferName] is given, the scan is awaited to the timeout
/// (or returns early the instant the wanted bridge appears) so the choice is
/// deliberate rather than "first wins". With no preference the first
/// advertisement is returned immediately, preserving the fast first connect.
Future<String?> _scanForDeviceId(
  FlutterBlueGattClient client,
  Duration timeout, {
  String? preferId,
  String? preferName,
}) async {
  final preference = preferId != null || preferName != null;
  final seen = <BleAdvertisement>[];
  try {
    await for (final adv in client.scan(timeout: timeout)) {
      if (preferId != null && adv.deviceId == preferId) {
        return adv.deviceId;
      }
      if (preferName != null && adv.name == preferName) {
        return adv.deviceId;
      }
      if (!preference) {
        return adv.deviceId;
      }
      seen.add(adv);
    }
  } on Object {
    // A scan that ends in error still leaves whatever was already seen.
  }
  return selectBridge(
    seen,
    preferId: preferId,
    preferName: preferName,
  )?.deviceId;
}

/// Connect, bond and probe, healing a stale bond once automatically.
Future<BleTransport> _connectAndHeal(
  FlutterBlueGattClient client,
  String deviceId,
  int mtu,
) async {
  try {
    return await _freshConnect(client, deviceId, mtu);
  } on BleRebondRequiredException {
    // We hold a key the bridge no longer does — it was factory-reset since we
    // paired. Drop the dead bond and pair fresh, once.
    try {
      await client.removeBond();
    } on BleException {
      throw const BridgeConnectionException(
        ConnectionProblem.staleBond,
        'The bridge no longer recognizes this phone, and the OS would not '
        'forget the stale pairing. Forget "SmokeBridge" in Bluetooth settings, '
        'then try again.',
      );
    }
    return _freshConnect(client, deviceId, mtu);
  } on BleNotBondedException {
    // The OS reported bonded and then disagreed on an encrypted read. Bond
    // explicitly, then probe again.
    await client.bond();
    return _freshConnect(client, deviceId, mtu);
  }
}

/// One connect→bond→MTU→probe pass. Assumes a disconnected client; it drops any
/// lingering link first so a retry after a failed attempt is clean.
Future<BleTransport> _freshConnect(
  FlutterBlueGattClient client,
  String deviceId,
  int mtu,
) async {
  if (client.connectionState == BleConnectionState.connected) {
    await client.disconnect();
  }
  await client.connect(deviceId);
  if (client.bondState != BleBondState.bonded) {
    try {
      await client.bond();
    } on BleBondRejectedException {
      rethrow;
    } on BleException {
      // An existing OS bond makes createBond() a no-op or a refusal; the link
      // still works, so let the encrypted probe report the real condition.
    }
  }
  await client.requestMtu(mtu);
  // Probe an encrypted characteristic now, so a stale bond surfaces where it
  // can still be healed.
  await client.read(BridgeChar.liveState);
  final transport = BleTransport(client);
  await transport.start();
  return transport;
}
