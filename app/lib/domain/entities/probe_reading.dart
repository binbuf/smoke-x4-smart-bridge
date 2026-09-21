/// N1.4 — the live reading for one probe, as the UI consumes it.
///
/// Every field beyond [jack] and [attached] is nullable or defaulted, because a
/// probe can be detached (no temp), have no history yet (no peak/low/avg), be
/// moving too slowly to estimate (no trend, no ETA) or be stale (derived values
/// removed). **Absent is null, never zero (I3).**
///
/// The projection that builds these values lives in the shell; this is the
/// value object the probe widgets render.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../analysis/eta.dart';
import '../entities/freshness.dart';
import '../entities/probe.dart';
import '../units/temp_value.dart';

part 'probe_reading.freezed.dart';

@freezed
abstract class ProbeReading with _$ProbeReading {
  const factory ProbeReading({
    required ProbeJack jack,

    /// False for an unplugged or unused jack. Never rendered as `0°`.
    @Default(false) bool attached,

    /// The current reading; [TempValue.absent] when detached.
    @Default(TempValue.absent()) TempValue temp,

    /// How current the reading is. Gates every derived value below via
    /// [Freshness.showsDerived].
    @Default(Freshness.unknown) Freshness freshness,

    /// °F per hour, or null when unknown/stale.
    double? trendFPerHr,

    @Default(false) bool stalled,

    /// Tenths °F over the session, or null when the probe has no history.
    int? peakF10,
    int? lowF10,
    int? avgF10,

    /// The ETA range or a named refusal; null when none was requested.
    EtaResult? eta,

    /// Recent readings for the sparkline, tenths °F.
    @Default(<int>[]) List<int> spark,
  }) = _ProbeReading;
}

/// Convenience: a detached reading for [jack], with nothing derived.
extension ProbeReadingDetached on ProbeReading {
  bool get hasTemp => temp.isPresent;
}

/// Builds a detached reading — the shape the UI renders as "— / Unplugged".
ProbeReading detachedReading(ProbeJack jack) => ProbeReading(jack: jack);
