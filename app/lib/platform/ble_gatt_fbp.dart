/// A6.1 (production half) — [BleGattClient] over `flutter_blue_plus`.
///
/// The seam's whole purpose is that everything above it — `BleTransport`,
/// the reassembler, the onboarding wizard — is tested against the Dart
/// fake with no radio. This file is the part that only a phone can prove,
/// and it is deliberately the thinnest thing that can work: find the
/// service, map characteristics by their 16-bit slot, translate the
/// plugin's failures into the typed conditions the app knows how to
/// render. No decisions live here.
///
/// Android reality that shapes the code (05 §5.8, A6 epic flag):
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

import '../data/transport/ble_gatt.dart';
import '../data/transport/ble_transport.dart';
import '../data/transport/bridge_transport.dart';

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
  /// boundary (the onboarding wizard does) then keeps being dragged back
  /// to the find step from under whatever screen the user moved on to.
  ///
  /// Board-found on the first real run: the Wi-Fi picker and the bridge
  /// list fought each other and the screen flickered blank. The Dart fake
  /// returns a stream that ends on its own, which is exactly why the test
  /// suite could not see it — so [FakePeripheral] now has a
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
        // keeps the promise the manifest's `neverForLocation` makes (A6.6,
        // 05 §5.8.3).
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
        'this device does not expose the Bridge Control Service',
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
      throw const BleStateException('removeBond() with no device');
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
  /// stale-bond stall must read as "re-pair", not as "no signal" (A24.11).
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
  /// them apart (A6.4).
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

  /// A GATT op that STALLS is Android silently retrying security. The
  /// board-found case (A24.11): a stale OS bond against a factory-reset
  /// bridge never errors — the stack re-tries the dead key while the app
  /// waits forever. Bounding every op and reading the stall through the
  /// bond state turns "it just hangs" into the same typed answers the
  /// error path already gives.
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
      // `result`, and a silently-dropped write would strand the wizard.
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
    // Chunks arrive exactly as the firmware sent them; reassembly is
    // A6.3's job one layer up, because the boundary is a property of the
    // payload rather than of the link.
    _notifySubs[slot] = c.onValueReceived.listen(
      (v) => ctl.add(Uint8List.fromList(v)),
      onError: ctl.addError,
    );
    unawaited(
      c.setNotifyValue(true).timeout(_opTimeout).catchError((Object e) {
        // The CCCD write needs encryption, so a stale bond stalls or
        // auth-fails right here — route it through the same bond-aware
        // mapping as reads and writes (A24.11).
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

/// N15.3 — the production BLE lane opener.
///
/// Scans for the bridge's service UUID, connects, bonds (the OS owns the
/// passkey dialog; the digits are on the bridge's OLED), negotiates the MTU and
/// hands back a started [BleTransport]. Returns null on any failure so the
/// connection race simply falls through to the HTTP lanes — a missing BLE radio
/// is a lane miss, never an error page.
Future<BridgeTransport?> openBleTransport({
  Duration scanTimeout = const Duration(seconds: 8),
  int mtu = 247,
}) async {
  final client = FlutterBlueGattClient();
  try {
    final adv = await client.scan(timeout: scanTimeout).first;
    await client.connect(adv.deviceId);
    if (client.bondState != BleBondState.bonded) {
      try {
        await client.bond();
      } on BleException {
        // An existing OS bond makes createBond() a no-op or a refusal; the
        // link still works, so keep going and let the first encrypted read
        // report a stale bond if that is the real condition.
      }
    }
    await client.requestMtu(mtu);
    final transport = BleTransport(client);
    await transport.start();
    return transport;
  } on Object {
    await client.dispose();
    return null;
  }
}
