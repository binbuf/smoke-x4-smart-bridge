/// A3.1 — the transport abstraction (design 08 §8.1).
///
/// **The UI never knows how it is talking to the bridge.** The dashboard,
/// the chart, and the session list are written once against this interface;
/// a capability flag drives the two places the difference is visible (the
/// chart's "connected over Bluetooth — full history needs Wi-Fi" notice and
/// the cache-backed session list).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/entities.dart';

part 'bridge_transport.freezed.dart';

/// What a given transport can do. HTTP and the mock carry everything;
/// `BleTransport` (M3) carries live state, a 2-hour preview, and — against
/// a bridge whose firmware serves ble-gatt §5.10 — full history too. It
/// reads [fullHistory] off the device rather than declaring it, so the flag
/// stays accurate in front of an older bridge.
@freezed
abstract class BridgeCapabilities with _$BridgeCapabilities {
  const factory BridgeCapabilities({
    @Default(true) bool liveState,
    @Default(false) bool fullHistory,
    @Default(false) bool historyPreview,
    @Default(false) bool config,
    @Default(false) bool ota,

    /// Home Assistant / MQTT config (05 §5.7). HTTP-only: the broker lives on
    /// the Wi-Fi LAN, so BLE reports false and its settings page explains it.
    @Default(false) bool mqtt,
  }) = _BridgeCapabilities;
}

/// A16 — the bridge's MQTT / Home Assistant publisher config. The password is
/// **write-only**: [MqttConfig] never carries it back (the device never
/// returns it), and [BridgeTransport.setMqttConfig] omitting it keeps the
/// stored one. [connected] is read-only truth from the device.
class MqttConfig {
  const MqttConfig({
    this.enabled = false,
    this.host = '',
    this.port = 1883,
    this.user = '',
    this.prefix = 'smokebridge',
    this.haDiscovery = true,
    this.connected = false,
  });

  final bool enabled;
  final String host;
  final int port;
  final String user;
  final String prefix;
  final bool haDiscovery;
  final bool connected;
}

/// A26 — how strong the link is, as the transport in use can *actually*
/// measure it.
///
/// **Two different hops, never conflated**, because a phone can only measure
/// one of them and the bridge can only measure the other:
///
///   * [linkDbm] — **phone ↔ bridge**. Only Bluetooth answers this: the GATT
///     connection has an RSSI the phone reads directly. On Wi-Fi the phone's
///     own radio sits behind a location-permission-gated Android API this app
///     deliberately does not hold (A6.6 promised `neverForLocation`), so it
///     stays null rather than being guessed at.
///   * [wifiDbm] — **bridge ↔ router**, from `net.rssi`. Meaningful only while
///     the bridge is a Wi-Fi *client*; when it hosts its own network there is
///     no upstream AP at all and the firmware reports 0.
///   * [apClients] — devices joined to the bridge's hosted network. In AP mode
///     this is the only thing the bridge can say about the link, because the
///     signal it would need to report is the *phone's*, which it cannot see.
///
/// Every field is nullable and **absent means unknown, never zero** — the same
/// rule the battery percentage and the detached probe have followed since M0.
class LinkSignal {
  const LinkSignal({
    this.linkDbm,
    this.wifiDbm,
    this.ssid = '',
    this.apClients,
  });

  /// A reachable bridge that can measure nothing. Distinct from a failed
  /// read, which throws.
  static const LinkSignal unknown = LinkSignal();

  final int? linkDbm;
  final int? wifiDbm;

  /// The network the bridge is on — the one it joined, or the one it hosts.
  final String ssid;
  final int? apClients;

  bool get isEmpty => linkDbm == null && wifiDbm == null && apClients == null;
}

/// A refusal the device stated in words, whatever transport carried it.
///
/// Lives here rather than in `http_transport.dart` so a caller can catch "the
/// bridge said no, and here is why" without knowing which lane it is on — the
/// §E.3 mode-switch wizard has to distinguish that from "the link died mid
/// switch", and it runs over BLE as readily as over Wi-Fi.
abstract interface class BridgeRefusal implements Exception {
  String get message;
}

/// Push events, as a sealed union so a `switch` over variants is exhaustive —
/// adding a variant without handling it everywhere fails analysis.
@freezed
sealed class BridgeEvent with _$BridgeEvent {
  const factory BridgeEvent.sample(Sample sample) = BridgeSampleEvent;
  const factory BridgeEvent.alarm({
    required Alarm alarm,
    required AlarmAction action,
  }) = BridgeAlarmEvent;
  const factory BridgeEvent.session({
    required SessionAction action,
    required int sessionId,
    String? name,
  }) = BridgeSessionEvent;
  const factory BridgeEvent.net({
    required String mode,
    required String state,
    String? ip,
  }) = BridgeNetEvent;
  const factory BridgeEvent.power({
    required int socPct,
    required bool charging,
    @Default(false) bool saver,
  }) = BridgePowerEvent;

  /// A5.2: the §6.3 frames the WebSocket carries beyond the original five.
  const factory BridgeEvent.pairing({
    required bool paired,
    String? deviceId,
    @Default(0) int numProbes,
  }) = BridgePairingEvent;
  const factory BridgeEvent.ota({required String phase, @Default(0) int pct}) =
      BridgeOtaEvent;
}

enum AlarmAction { raised, cleared, acked }

enum SessionAction { started, ended, renamed }

/// 01 §1.6's saver profile. Tri-state on the wire (`battery_saver` over
/// HTTP, `set_battery_saver` op 12 over BLE) — `auto` engages below 20 % and
/// releases at 30 %, which a bool cannot express.
enum BatterySaverMode { off, on, auto }

/// Hosted AP or joined STA (05 §5.4).
enum NetworkMode { ap, sta }

/// Which transport to prefer when more than one can reach the bridge
/// (05 §5.7). `auto` takes whichever connects first — BLE shows data
/// instantly, Wi-Fi upgrades in for full history/config/OTA. `ble`/`wifi`
/// only bias the launch race's tiebreak; **neither is an exclusion** — a
/// phone that can reach the bridge just one way still connects that way.
enum PreferredTransport { auto, ble, wifi }

/// Control verbs, mirroring `device_control` / the POST endpoints.
///
/// D15 moved every control off the device's button, so this union is now the
/// *only* way most of these happen at all.
@freezed
sealed class ControlCommand with _$ControlCommand {
  const factory ControlCommand.sessionStart() = StartSessionCommand;
  const factory ControlCommand.sessionStop() = StopSessionCommand;
  const factory ControlCommand.mark({
    required MarkKind kind,
    @Default(0) int probe,
    @Default('') String text,
  }) = MarkCommand;
  const factory ControlCommand.pair() = PairCommand;
  const factory ControlCommand.unpair() = UnpairCommand;
  const factory ControlCommand.setTime({required int unixMs}) = SetTimeCommand;
  const factory ControlCommand.ackAlarm({required int alarmId}) =
      AckAlarmCommand;

  /// Reboot. `device_control` op 7 · `POST /api/v1/restart`.
  const factory ControlCommand.reboot() = RebootCommand;

  /// Wipe config, sessions and BLE bonds, then reboot. Irreversible, and it
  /// forgets this phone's bond: op 8 · `POST /api/v1/factory-reset`.
  const factory ControlCommand.factoryReset() = FactoryResetCommand;

  /// Deep sleep. op 13 · `POST /api/v1/power-off`. **Nothing remote can undo
  /// this** — waking the bridge needs a physical PRG hold (07 §7.4), which is
  /// why every caller must confirm first.
  const factory ControlCommand.powerOff() = PowerOffCommand;
}

/// What the device says its own settings are (`GET /api/v1/config/device`).
///
/// **The read half that was missing.** `BridgeConfig` could only ever be
/// written, so the settings tree had no way to learn the display timeout, the
/// status LED, the retention limit or the battery-saver mode — and rendered
/// constructor defaults in their place, which is the single class of bug §F
/// and §I.0 are most insistent about. With no read there was also no read-back,
/// so a units write could only ever report "sent", never "saved".
///
/// Every field is **nullable, and null means the device did not say** — not
/// zero, not false, not a default. A transport that cannot ask returns
/// [DeviceConfig.unknown], which renders as "—" the whole way down.
@immutable
class DeviceConfig {
  const DeviceConfig({
    this.displayUnits,
    this.displayTimeoutS,
    this.ledEnabled,
    this.batterySaver,
    this.maxSessions,
    this.minFreePct,
  });

  /// Nothing known. Distinct from a device that answered with defaults.
  static const DeviceConfig unknown = DeviceConfig();

  /// `'F'` or `'C'`.
  final String? displayUnits;
  final int? displayTimeoutS;
  final bool? ledEnabled;
  final BatterySaverMode? batterySaver;
  final int? maxSessions;
  final int? minFreePct;

  bool get isEmpty =>
      displayUnits == null &&
      displayTimeoutS == null &&
      ledEnabled == null &&
      batterySaver == null &&
      maxSessions == null &&
      minFreePct == null;

  /// Whether the device is running what we asked for — **three answers, not
  /// two**.
  ///
  /// * `true` — it reported the value we sent. Saved.
  /// * `false` — it reported something *else*. The device refused or clamped,
  ///   and the user needs to see what it actually has.
  /// * `null` — it **said nothing about this field**. Not agreement, not
  ///   refusal: no answer.
  ///
  /// The two-valued version of this was a trap, and the settings tree hit it
  /// immediately. Bluetooth answers [DeviceConfig.unknown] to everything, so a
  /// `bool` collapsed "this lane cannot read" into "the bridge rejected your
  /// change" — the app accusing the device of refusing edits it was never
  /// asked about. Absent is not disagreement, here as everywhere else.
  ///
  /// Compares **only the fields that were sent**, so a device reporting the
  /// other five is not a mismatch — the same rule `probeWriteWasHonoured`
  /// follows.
  bool? honoured(BridgeConfig sent) {
    var sawAnswer = false;
    if (sent.displayUnits != null) {
      if (displayUnits == null) {
        return null;
      }
      sawAnswer = true;
      if (displayUnits != sent.displayUnits) {
        return false;
      }
    }
    if (sent.batterySaver != null) {
      if (batterySaver == null) {
        return null;
      }
      sawAnswer = true;
      if (batterySaver != sent.batterySaver) {
        return false;
      }
    }
    if (sent.displayTimeoutS != null) {
      if (displayTimeoutS == null) {
        return null;
      }
      sawAnswer = true;
      if (displayTimeoutS != sent.displayTimeoutS) {
        return false;
      }
    }
    if (sent.ledEnabled != null) {
      if (ledEnabled == null) {
        return null;
      }
      sawAnswer = true;
      if (ledEnabled != sent.ledEnabled) {
        return false;
      }
    }
    if (sent.maxSessions != null) {
      if (maxSessions == null) {
        return null;
      }
      sawAnswer = true;
      if (maxSessions != sent.maxSessions) {
        return false;
      }
    }
    // Nothing comparable was sent: there is no verdict to give.
    return sawAnswer ? true : null;
  }
}

/// The configurable surface (a subset in M0; grows with the settings work).
@freezed
abstract class BridgeConfig with _$BridgeConfig {
  const factory BridgeConfig({
    String? displayUnits,
    List<Probe>? probes,
    BatterySaverMode? batterySaver,

    /// The bridge's own OLED timeout, seconds. The firmware has taken this
    /// since F13; nothing could send it.
    int? displayTimeoutS,

    /// The status LED. Likewise.
    bool? ledEnabled,

    /// How many cooks the bridge keeps before the oldest are dropped.
    int? maxSessions,
  }) = _BridgeConfig;
}

/// A12.6 — a firmware image the user chose, as a length and a byte stream.
///
/// The picker that produces one is **not** in v1 (SAF, a plugin, an
/// Android integration `flutter test` cannot run). This type is the seam
/// it will plug into: with no [FirmwareImageSource] registered the firmware
/// screen explains where to get an image instead of showing a dead button,
/// and the transport underneath is finished and tested for whenever the
/// picker lands.
class FirmwareImage {
  const FirmwareImage({
    required this.name,
    required this.lengthBytes,
    required this.bytes,
  });

  final String name;
  final int lengthBytes;
  final Stream<List<int>> bytes;
}

/// Returns the image the user picked, or null if they cancelled.
typedef FirmwareImageSource = Future<FirmwareImage?> Function();

/// The one interface every screen talks to (08 §8.1). Implementations:
/// `HttpTransport` (M1+), `BleTransport` (M3), `MockTransport` (here).
abstract interface class BridgeTransport {
  BridgeCapabilities get capabilities;

  /// Push stream: sample · alarm · session · net · power.
  Stream<BridgeEvent> get events;

  Future<BridgeStatus> status();

  /// A26 — the strength of the link this transport is using (05 §5.7).
  ///
  /// Throws exactly like [status] when the bridge cannot be reached — a
  /// signal read is a round trip and a screen that renders a stale dBm as
  /// current is the same lie as a stale IP address. A bridge that answers but
  /// can measure nothing returns [LinkSignal.unknown], which is a state the
  /// Bridge tab renders in words rather than an error.
  Future<LinkSignal> signal();

  Future<LiveState> live({Duration window = const Duration(hours: 1)});

  Future<List<CookSession>> sessions();

  /// Streamed history for [sessionId], in batches. Full-fidelity when
  /// [bucketS] is null.
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int? toT,
    int? bucketS,
  });

  Future<void> control(ControlCommand cmd);

  Future<void> configure(BridgeConfig cfg);

  /// Read the device's own settings back (`GET /api/v1/config/device`).
  ///
  /// This is what turns a settings row from a guess into a fact, and what lets
  /// a write say "Saved" instead of "Sent". A transport that cannot ask returns
  /// [DeviceConfig.unknown] rather than throwing: an unreadable setting is a
  /// row that says "—", not a screen that fails.
  Future<DeviceConfig> deviceConfig();

  /// A12.3 — switch between hosting an AP and joining a network (05 §5.4).
  ///
  /// Returns the **AP PSK** when the switch generated one, or `''`. That is
  /// why this is not a [BridgeConfig] field: the device answers *before* it
  /// reconfigures and hands back credentials the user must read to rejoin,
  /// and a `void configure` would throw them away.
  ///
  /// Both real transports implement it — HTTP via `POST /api/v1/config/wifi`,
  /// BLE via the `wifi_config` characteristic — because provisioning has to
  /// work on whichever one is currently reachable.
  /// [revertAfterS] arms §E.3's rollback: the device snapshots what it is
  /// running and puts it back unless [commitNetworkMode] arrives in time. 0 is
  /// the old fire-and-forget behaviour, which is right for guided setup with a
  /// human watching it and wrong for a switch fired from settings.
  Future<String> applyNetwork({
    required NetworkMode mode,
    String ssid = '',
    String psk = '',
    int revertAfterS = 0,
  });

  /// A12.6 — stream a firmware image to `POST /api/v1/ota` (F14.5).
  ///
  /// Only [HttpTransport] implements it; BLE and the mock throw
  /// [UnsupportedError], which is why `capabilities.ota` gates the button.
  /// Progress is NOT reported here — it arrives on [events] as
  /// [BridgeOtaEvent]s, because the device is authoritative about its own
  /// phase.
  ///
  /// [force] carries `?force=1`. Without it the bridge refuses with `409
  /// session_active` while a cook is running — nobody should discover a
  /// bad flash fourteen hours into a brisket.
  Future<void> uploadFirmware(
    Stream<List<int>> image, {
    required int lengthBytes,
    bool force = false,
  });

  /// A16 — read the MQTT / Home Assistant publisher config (05 §5.7). HTTP
  /// via `GET /api/v1/config/mqtt`; BLE throws [BridgeUnsupportedException]
  /// because the broker is only reachable over the Wi-Fi LAN.
  Future<MqttConfig> mqttConfig();

  /// newapp §E.3 — confirm a mode change so the device keeps it.
  ///
  /// Sent on the **new** network after a real `GET /status` 200. Throws when
  /// there was nothing to confirm (the device answers 409), which is how the
  /// wizard tells "the switch stuck" from "there was never a switch".
  Future<void> commitNetworkMode();

  /// newapp §G.3 — the device's alarm configuration, exactly as it reports it
  /// (`GET /api/v1/config/alarms`, 06 §6.2).
  ///
  /// `{"rules": [{rule, enabled, severity}, ...], "pit_band_f10": ..., ...}` —
  /// a rules array plus twelve global tunables. This is the **read-back** half
  /// of the write-then-verify pattern, and it is why the rule editor can say
  /// "Saved to the bridge" and mean it: nothing in this app reports success on
  /// the strength of a return value alone.
  ///
  /// A transport that cannot carry rules throws [BridgeUnsupportedException],
  /// which the editor renders as a disabled row with its reason rather than a
  /// live switch that writes nothing.
  Future<Map<String, Object?>> alarmConfig();

  /// newapp §G.3 — a **merge patch**: absent fields are left alone. Verify with
  /// [alarmConfig]; never assume.
  Future<void> setAlarmConfig(Map<String, Object?> patch);

  /// A16 — update it via `POST /api/v1/config/mqtt`. Every field is optional:
  /// an omitted field keeps the device's stored value, and [password] omitted
  /// keeps the stored password (it is never sent back on a read).
  Future<void> setMqttConfig({
    bool? enabled,
    String? host,
    int? port,
    String? user,
    String? password,
    String? prefix,
    bool? haDiscovery,
  });

  Future<void> close();
}
