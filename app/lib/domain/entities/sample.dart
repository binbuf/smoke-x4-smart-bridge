/// N1.4 — the raw sample stream the analysis engines consume.
///
/// A `Sample` is what the bridge recorded: seconds into the session and up to
/// four tenths-°F readings. A detached jack is `null` in [tempsF10], which is
/// why no engine can accidentally average a probe into zero.
///
/// **[unixMs] is nullable on purpose (I11).** A bridge whose clock was never set
/// stores `null`, never a fabricated timestamp. The app projects a wall-clock
/// time only when the session header supplies one.
library;

import 'probe.dart';

/// One decoded state message.
class Sample {
  const Sample({
    required this.t,
    required this.tempsF10,
    this.unixMs,
    this.billows = false,
    this.newAlarm = false,
    this.sourceCelsius = false,
    this.rssi = 0,
  });

  /// Seconds since session start (monotonic, never wall-clock).
  final int t;

  /// Up to four entries; tenths-°F; `null` = detached or invalid.
  final List<int?> tempsF10;

  /// Wall clock when the session header knows one; **null when it does not**.
  final int? unixMs;

  final bool billows;
  final bool newAlarm;

  /// Provenance only — the values are already canonical °F.
  final bool sourceCelsius;

  final int rssi;

  /// The reading for [jack], or `null` when detached. There is no "or zero"
  /// path here by design (I3).
  int? tempFor(ProbeJack jack) {
    final index = jack.n - 1;
    if (index < 0 || index >= tempsF10.length) {
      return null;
    }
    return tempsF10[index];
  }

  @override
  String toString() => 'Sample(t: $t, tempsF10: $tempsF10)';
}
