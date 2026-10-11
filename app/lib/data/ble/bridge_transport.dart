/// The `BridgeTransport` contract — BLE-only.
///
/// One interface, one production implementation ([BleTransport]) plus test
/// fakes. Screens talk to the repository, never to this type directly; the
/// transport is the *wire*, the repository is the *app model*. Keeping the
/// interface lets the sync engine and repository be driven by a fake with no
/// radio.
///
/// Nothing here imports Flutter, so the whole layer is host-testable.
library;

import '../../domain/domain.dart';

/// A wire-level failure with a protocol error `code`, or an app-level
/// pseudo-code (`network` / `timeout` / `malformed` / `unsupported`).
class TransportException implements Exception {
  const TransportException(this.code, this.message, {this.detail, this.status});

  final String code;
  final String message;
  final Object? detail;
  final int? status;

  @override
  String toString() =>
      'TransportException($code${status == null ? '' : ' · $status'}): $message';
}

/// The capability is not available on this transport (e.g. a Wi-Fi-only op).
class TransportUnsupported extends TransportException {
  const TransportUnsupported(String feature)
    : super('unsupported', 'this transport cannot $feature');
}

/// Why a connection attempt could not produce a live link.
///
/// Each one is a *different user action*, which is the whole reason the enum
/// exists: "it just won't connect" is the bug report every one of these
/// distinctions was written to prevent.
enum ConnectionProblem {
  /// A runtime permission was refused. Retry (the OS may prompt again).
  permissions,

  /// A permission was permanently refused ("don't ask again"): only the app's
  /// settings screen can change it.
  permissionsPermanentlyDenied,

  /// The phone's Bluetooth radio is off.
  bluetoothOff,

  /// No bridge advertising the service was found.
  notFound,

  /// The bridge no longer recognizes this phone's bond and the OS refused to
  /// forget it, so only the Bluetooth settings screen can break the dead key.
  staleBond,

  /// Anything else — a dropped link, a GATT failure, a bad scan.
  failed,
}

/// A connection attempt that ended in a specific, actionable reason.
class BridgeConnectionException implements Exception {
  const BridgeConnectionException(this.problem, this.message);

  final ConnectionProblem problem;
  final String message;

  @override
  String toString() => 'BridgeConnectionException(${problem.name}): $message';
}

/// The runtime permissions Android needs to scan and connect, by API level.
///
/// Pure and shared with the platform channel: the Dart side decides the list so
/// the single source of truth for "what does BLE need on this OS" is one
/// function, and the Kotlin side only maps names to `Manifest.permission`
/// constants it is handed. API 31 split the old location requirement into the
/// Nearby Devices pair; below that, scanning still needs location.
List<String> androidBlePermissions(int sdkInt) => sdkInt >= 31
    ? const ['BLUETOOTH_SCAN', 'BLUETOOTH_CONNECT']
    : const ['ACCESS_FINE_LOCATION'];

/// The unencrypted identity card (`device_info`).
class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.model,
    required this.fw,
    required this.probes,
    required this.historyFull,
  });

  /// ASCII hex, e.g. `A4F2` — matches the advertising name suffix.
  final String id;
  final String model;
  final String fw;

  /// 2 or 4.
  final int probes;

  /// `caps` b6 — whether this bridge serves full history over BLE.
  final bool historyFull;
}

/// The current probe state, from one `live_state` (16 B, §5.7).
class LiveSnapshot {
  const LiveSnapshot({
    required this.paired,
    required this.clockValid,
    required this.tempsF10,
    required this.socPct,
    required this.rssiLora,
  });

  final bool paired;

  /// Whether the bridge believes it has a wall clock.
  final bool clockValid;

  /// Four entries; tenths-°F; `null` = detached or invalid (never 0).
  final List<int?> tempsF10;

  /// Battery SoC, or null when the device cannot report one.
  final int? socPct;

  /// dBm of the last LoRa state message.
  final int rssiLora;

  /// Convenience: the reading at 0-based [index], or null.
  int? tempAt(int index) =>
      index >= 0 && index < tempsF10.length ? tempsF10[index] : null;
}

/// The OLED status strip's clock width: `set_cook_clock` is refused `invalid`
/// beyond this (99:59, `ble-gatt.md` §5.6.8). The value is an *age*, not a
/// start timestamp.
const int cookClockMaxS = 359940;

/// The bridge's BLE surface, as this app uses it.
abstract interface class BridgeTransport {
  /// A stable label for logs/UI (`BLE`).
  String get label;

  /// Fires once when an *established* link drops underneath us — the phone
  /// walked away, the bridge reset, the radio died. A deliberate [close] must
  /// not emit, so the owner can tell "I hung up" from "we were cut off".
  Stream<void> get disconnects;

  /// Release the link. Idempotent.
  Future<void> close();

  /// Read the unencrypted identity card and latch `caps.history_full`.
  Future<DeviceIdentity> deviceInfo();

  /// Read `live_state` once.
  Future<LiveSnapshot> readLive();

  /// `live_state` notifications, one per decoded LoRa packet (~30 s) plus on
  /// any alarm transition.
  Stream<LiveSnapshot> get liveUpdates;

  /// The session list (`history_ctrl` `req = sessions`).
  Future<List<SessionInfo>> sessions();

  /// A slice of a session's samples, streamed in batches.
  ///
  /// [fromT]/[toT] are seconds into the session; [stride] decimates.
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int? toT,
    int stride = 1,
  });

  /// `set_time` — so the bridge's sessions carry a wall clock.
  Future<void> setTime(int unixMs, {int? tzOffsetMin});

  /// Declare the elapsed time the device's OLED shows (`set_cook_clock`, op 14).
  ///
  /// This is the **glass**, not recording (op 14 is not `session_start`): the
  /// bridge records continuously and has no concept of a cook, so it shows a
  /// clock only while the app declares one. `elapsedS` is how old the cook is
  /// *now*, clamped to [cookClockMaxS]; re-sending is the intended flow (it is
  /// the same write whether it starts or corrects the clock).
  ///
  /// There is no BLE read for this clock — the phone is the source of truth
  /// while it holds the cook, and re-sends on reconnect because the bridge
  /// forgets it across a reboot.
  Future<void> setCookClock(int elapsedS);

  /// Blank the device screen's clock (`clear_cook_clock`, op 15).
  Future<void> clearCookClock();

  /// The connected link's RSSI in dBm (the phone ↔ bridge hop). Throws when
  /// there is no connection to measure.
  Future<int> readRssi();

  /// Remove this phone's OS-level pairing with the bridge (Android's
  /// `removeBond`). Used by "Forget bridge" and by the automatic stale-bond
  /// heal. It touches the *radio bond only* — the on-device cache is a separate
  /// copy and is never cleared here.
  Future<void> forget();
}
