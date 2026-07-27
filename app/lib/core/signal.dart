/// Radio signal strength, in the words people actually use.
///
/// dBm is the honest unit and the screen shows it, but "−67 dBm" answers a
/// question nobody asked. What the user wants to know is *should I move
/// something*, so every reading is also rendered as one of four levels and a
/// bar count.
///
/// **The two radios do not share a scale.** −70 dBm is a comfortable Wi-Fi
/// link and a marginal BLE one: Bluetooth transmits at a fraction of the
/// power, so its whole usable range sits lower. One shared threshold table
/// would either call healthy Bluetooth "weak" or call failing Wi-Fi "good",
/// and both are worse than no label at all.
///
/// The bands are deliberately **coarse**. RSSI jitters several dB between
/// consecutive reads with nothing physically moving, and a meter that flips
/// between three and four bars once a second reads as a fault rather than as
/// a measurement.
library;

/// Which radio a reading came from — the two have different usable ranges.
enum SignalKind { bluetooth, wifi }

/// Four levels, worst to best. There is no `none`: a link with no signal is
/// a link that is *down*, which the screen says in words rather than
/// rendering as zero bars on a live connection.
enum SignalLevel { weak, fair, good, excellent }

/// dBm → level. Values are clamped rather than rejected: a radio that reports
/// something absurd is still telling us it is very strong or very weak.
SignalLevel signalLevel(int dbm, {required SignalKind kind}) {
  final t = switch (kind) {
    // Bluetooth LE: −40 is in-hand, −70 is a room away, below −90 drops.
    SignalKind.bluetooth => (excellent: -60, good: -72, fair: -84),
    // Wi-Fi: −50 is beside the router, −80 is where throughput collapses.
    SignalKind.wifi => (excellent: -55, good: -67, fair: -78),
  };
  if (dbm >= t.excellent) {
    return SignalLevel.excellent;
  }
  if (dbm >= t.good) {
    return SignalLevel.good;
  }
  if (dbm >= t.fair) {
    return SignalLevel.fair;
  }
  return SignalLevel.weak;
}

/// 1..4, for the bar glyph. Never 0 — see [SignalLevel].
int signalBars(int dbm, {required SignalKind kind}) =>
    signalLevel(dbm, kind: kind).index + 1;

/// The one word beside the number.
String signalLabel(SignalLevel level) => switch (level) {
  SignalLevel.weak => 'Weak',
  SignalLevel.fair => 'Fair',
  SignalLevel.good => 'Good',
  SignalLevel.excellent => 'Excellent',
};

/// `−67 dBm`, with a real minus sign (U+2212) rather than a hyphen, because
/// the rest of the app's numbers are set in the same typography.
String formatDbm(int? dbm) => dbm == null ? '—' : '−${dbm.abs()} dBm';

/// The advice that goes with a reading, or empty when there is nothing worth
/// saying. A healthy link gets no advice — an app that comments on everything
/// teaches people to ignore it.
String signalAdvice(SignalLevel level, {required SignalKind kind}) =>
    switch (level) {
      SignalLevel.weak => switch (kind) {
        SignalKind.bluetooth =>
          'Weak — stay closer to the bridge, or connect it to Wi-Fi.',
        SignalKind.wifi =>
          'Weak — the bridge may drop off. Move it closer to the router.',
      },
      SignalLevel.fair => '',
      SignalLevel.good => '',
      SignalLevel.excellent => '',
    };
