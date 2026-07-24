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

/// What a given transport can do. `BleTransport` (M3) carries live state and
/// a 2-hour preview but no full history in v1; HTTP and the mock carry
/// everything.
@freezed
abstract class BridgeCapabilities with _$BridgeCapabilities {
  const factory BridgeCapabilities({
    @Default(true) bool liveState,
    @Default(false) bool fullHistory,
    @Default(false) bool historyPreview,
    @Default(false) bool config,
    @Default(false) bool ota,
  }) = _BridgeCapabilities;
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

/// Control verbs, mirroring `device_control` / the POST endpoints.
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
}

/// The configurable surface (a subset in M0; grows with the settings work).
@freezed
abstract class BridgeConfig with _$BridgeConfig {
  const factory BridgeConfig({String? displayUnits, List<Probe>? probes}) =
      _BridgeConfig;
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

  Future<void> close();
}
