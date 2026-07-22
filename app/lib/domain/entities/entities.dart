/// Domain entities (A2.1, design 08 §8.3).
///
/// Pure Dart — this library (and everything under `domain/`) imports nothing
/// from Flutter. That is a hard rule, enforced in CI by a grep (T1.6).
///
/// Temperatures at the domain boundary are tenths of °F (`int`), matching the
/// wire, with `null` — never a number — for a detached probe.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'entities.freezed.dart';

/// The role a user assigns to a probe; the hardware does not distinguish.
enum ProbeRole { unused, pit, food, ambient }

/// Mark kinds, matching the wire values of `mark_rec.kind`.
enum MarkKind {
  note,
  wrapped,
  lidOpen,
  fuel,
  probeMoved,
  alarm,
  phaseChange,
  autoDetected,
}

enum AlarmSeverity { info, warning, critical }

/// A probe's configured identity (name/role/target). Live values travel in
/// [Sample]s; the two meet in the UI, not here.
@freezed
abstract class Probe with _$Probe {
  const factory Probe({
    /// 1..4 — the physical jack on the base station.
    required int n,
    @Default('') String name,
    @Default(ProbeRole.unused) ProbeRole role,

    /// Tenths °F; null = no target set.
    int? targetF10,
    @Default(false) bool alarmEnabled,
  }) = _Probe;
}

/// One decoded state message: seconds-into-session plus up to four
/// temperatures. A detached probe is `null` in [tempsF10] — structurally
/// incapable of surfacing as 0.
@freezed
abstract class Sample with _$Sample {
  const factory Sample({
    /// Seconds since session start (monotonic, never wall-clock).
    required int t,

    /// Length 4; tenths °F; null = detached or invalid.
    required List<int?> tempsF10,
    @Default(false) bool billows,
    @Default(false) bool newAlarm,

    /// Provenance only — the values are already canonical °F.
    @Default(false) bool sourceCelsius,
    @Default(0) int rssi,
  }) = _Sample;
}

/// A bounded run of samples with a header, name, marks, and stats.
@freezed
abstract class CookSession with _$CookSession {
  const factory CookSession({
    required int id,
    @Default('') String name,

    /// Unix ms; null while the bridge had no clock (clock_valid unset).
    int? startedUnixMs,

    /// Unix ms; null while the session is open.
    int? endedUnixMs,
    @Default(30) int samplePeriodS,
    @Default(0) int sampleCount,
    @Default(4) int numProbes,
    @Default(<Probe>[]) List<Probe> probes,
    @Default(false) bool closed,
    @Default(false) bool pinned,
  }) = _CookSession;
}

/// A user- or firmware-placed annotation on the session timeline.
@freezed
abstract class Mark with _$Mark {
  const factory Mark({
    /// Seconds since session start.
    required int t,
    required MarkKind kind,

    /// 0 = whole cook, 1..4 = a specific probe.
    @Default(0) int probe,
    @Default('') String text,
  }) = _Mark;
}

/// One alarm instance as the device reports it. The device is the source of
/// truth for alarm state; the app mirrors and acknowledges (09 §9.1).
@freezed
abstract class Alarm with _$Alarm {
  const factory Alarm({
    required int id,
    required String rule,

    /// 0 = whole cook, 1..4 = a specific probe.
    @Default(0) int probe,
    int? valueF10,
    int? sinceUnixMs,
    @Default(AlarmSeverity.warning) AlarmSeverity severity,
    @Default(false) bool acked,
  }) = _Alarm;
}

/// The current probe state plus the recent in-RAM window (a domain
/// projection of `GET /api/v1/live` / the BLE `live_state` notify).
@freezed
abstract class LiveState with _$LiveState {
  const factory LiveState({
    /// Seconds into the active session; 0 when none.
    required int t,

    /// Wall clock, when the bridge knows it.
    int? unixMs,

    /// Length 4; tenths °F; null = detached — never 0.
    required List<int?> tempsF10,
    @Default(false) bool billows,
    @Default(<Sample>[]) List<Sample> recent,
  }) = _LiveState;
}

/// The dashboard-header snapshot of the bridge (a domain projection of
/// `GET /api/v1/status`).
@freezed
abstract class BridgeStatus with _$BridgeStatus {
  const factory BridgeStatus({
    required String deviceId,
    @Default('') String model,
    @Default('') String fw,
    @Default(0) int uptimeS,
    @Default(false) bool paired,
    @Default(0) int numProbes,

    /// Seconds since the last valid state message; null = never.
    int? lastPacketSAgo,
    @Default(false) bool baseLost,
    @Default(false) bool sessionActive,
    int? activeSessionId,
    @Default(0) int storageFreePct,

    /// 0–100; null when battery reporting is unavailable (R6).
    int? socPct,
    @Default(false) bool charging,
    @Default(<Alarm>[]) List<Alarm> alarms,
  }) = _BridgeStatus;
}
