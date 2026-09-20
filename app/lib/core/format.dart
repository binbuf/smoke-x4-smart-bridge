/// Display formatting — the last place a value is a number and the first
/// place it is a string.
///
/// One rule runs through all of it: **a detached probe is `—`, never 0.**
/// Every function here takes a nullable and returns the em dash for null,
/// so no call site has to remember. That invariant is enforced on the
/// wire, in the firmware, in drift, and in the domain; this file is where
/// it reaches the glass.
library;

import '../domain/analysis/analysis.dart';

/// The em dash, once, so the goldens and the tests agree on which one.
const String noValue = '—';

/// Tenths-°F → `243.4°` (or `117.4°` in °C). **A25: one decimal, always.**
///
/// The Smoke X base and its receiver both read to a tenth, and an app that
/// says `82°` while the device in your hand says `81.8°` reads as a different
/// number, not a rounded one — the whole-degree rule this file used to hold
/// cost more trust than the jitter it saved. The wire, the firmware and the
/// cache have carried tenths since M0; this is the display finally telling
/// the truth they hold. Where the digit would dominate (the headline slot),
/// [AnimatedTemp] renders it typographically subordinate rather than dropping
/// it.
String formatTemp(int? f10, {bool celsius = false}) {
  if (f10 == null) {
    return noValue;
  }
  final v = celsius ? f10ToC10(f10) : f10;
  return '${(v / 10).toStringAsFixed(1)}°';
}

/// Explicit alias of [formatTemp], kept for the call sites that always meant
/// "the tenth matters here" (exports, crosshair readouts, alarm values).
String formatTempPrecise(int? f10, {bool celsius = false}) =>
    formatTemp(f10, celsius: celsius);

/// A **setpoint** — a target or an alarm band — which the user typed rather
/// than the probe measured. `203°`, not `203.0°`; a tenth appears only when
/// one was actually set (`203.5°`). Precision the user did not ask for reads
/// as noise on a number they chose.
String formatSetpoint(int? f10, {bool celsius = false}) {
  if (f10 == null) {
    return noValue;
  }
  final v = celsius ? f10ToC10(f10) : f10;
  final whole = (v / 10).truncate();
  return v % 10 == 0 ? '$whole°' : '${(v / 10).toStringAsFixed(1)}°';
}

/// °F/hr, to one decimal. §9.4: the underlying resolution is 0.1 °F over
/// ten minutes, so anything under ±0.6 °F/hr is at the edge of meaningful
/// and is rendered as `~0` rather than as false precision.
String formatRate(double? fPerHr) {
  if (fPerHr == null) {
    return noValue;
  }
  if (fPerHr.abs() < 0.6) {
    return '~0°/hr';
  }
  final sign = fPerHr > 0 ? '+' : '';
  return '$sign${fPerHr.toStringAsFixed(1)}°/hr';
}

/// `04:12:30`. Elapsed cook time, which is what the header shows when the
/// bridge has no clock — and what it shows anyway, because "four hours
/// in" is the question people are actually asking.
String formatElapsed(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${sec.toString().padLeft(2, '0')}';
}

/// `6h 20m`, `45m`, `<1m` — durations people read, not durations machines
/// print.
String formatDuration(int seconds) {
  if (seconds < 60) {
    return '<1m';
  }
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h == 0) {
    return '${m}m';
  }
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// The §9.4 ETA's **answer**: `2h`, `2h – 2h 30m`. Never `6h 23m` — the
/// physics does not support that precision, and the false confidence is
/// what makes people trust it and then get burned.
///
/// It does not say "ETA", because every call site sits under a label that
/// already did. The single function this replaced returned
/// `'ETA 2h – 2h 30m'`, which a "Ready in" strip rendered as *"Ready in ·
/// ETA 2h – 2h 30m"* — the same word twice, one of them redundant.
String formatEtaSpan(EtaRange eta) => eta.low == eta.high
    ? formatDuration(eta.low.inSeconds)
    : '${formatDuration(eta.low.inSeconds)} – '
          '${formatDuration(eta.high.inSeconds)}';

/// The §9.4 ETA's **refusal**, as one sentence that states its own reason
/// (newapp §D.5, 16 §16.4 rules 3 and 5).
///
/// A refusal is an answer, not an error — but it is emphatically **not a
/// value**, and keeping the two in one function is how the app came to
/// render *"Ready in · ETA unavailable — holding steady"*: a label promising
/// a duration, answered by a sentence explaining there is not one. The types
/// are separated so a call site has to choose, and choosing is the fix.
///
/// Each says what the app knows and why it will not guess. §D.5's own
/// example — *"Not enough steady data to estimate — pit swinging"* — is the
/// register.
String formatEtaRefusal(EtaUnavailable eta) => switch (eta.reason) {
  EtaUnavailableReason.stalled => 'No estimate while it is in a stall.',
  EtaUnavailableReason.targetAtOrAbovePit =>
    'No estimate — the pit is not hotter than the target.',
  EtaUnavailableReason.insufficientHistory =>
    'No estimate yet — not enough history.',
  EtaUnavailableReason.slopeTooFlat =>
    'No estimate — the temperature is holding steady.',
  EtaUnavailableReason.notApproaching =>
    'No estimate — the temperature is falling.',
};

/// ISO-8601 in UTC with milliseconds and a `Z` —
/// `2026-07-21T12:00:00.000Z`. This is not a style choice: it is
/// byte-identical to `csv_sink`'s `%04d-%02u-%02uT%02d:%02d:%02d.%03uZ`
/// in `app_api_sessions.c`, and to the sim's `toIso8601String()`. Two
/// spellings of the same export is how a support conversation becomes
/// unanswerable.
///
/// Empty when the bridge had no clock — an epoch date is a lie the CSV
/// would carry forever.
String formatIso8601(int? unixMs) => unixMs == null
    ? ''
    : DateTime.fromMillisecondsSinceEpoch(
        unixMs,
        isUtc: true,
      ).toIso8601String();

/// `Sat 19 Jul, 14:32`, or an empty string when there is no clock.
String formatSessionDate(int? unixMs) {
  if (unixMs == null) {
    return '';
  }
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = DateTime.fromMillisecondsSinceEpoch(unixMs).toLocal();
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}, '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
