/// A2.7 — unit conversion and gap detection (design 04 §4.2, 08 §8.7).
library;

/// Tenths-°C → canonical tenths-°F: `F10 = C10 × 9 / 5 + 320`, rounded to
/// nearest. 0.1 °C is a finer step than 0.1 °F, so converting on write loses
/// no resolution.
int c10ToF10(int c10) => ((c10 * 9) / 5).round() + 320;

/// Tenths-°F → tenths-°C, rounded to nearest.
int f10ToC10(int f10) => (((f10 - 320) * 5) / 9).round();

/// A reception gap: no samples between [fromT] and [toT] (exclusive ends of
/// the surrounding samples).
typedef Gap = ({int fromT, int toT});

/// Gaps in an ordered `t` sequence. A delta strictly greater than
/// [thresholdS] (default 45 s — 1.5× the nominal 30 s cadence) means packets
/// were missed, and the chart must draw a break, not a line across the hole.
List<Gap> findGaps(Iterable<int> ts, {int thresholdS = 45}) {
  final gaps = <Gap>[];
  int? prev;
  for (final t in ts) {
    if (prev != null && t - prev > thresholdS) {
      gaps.add((fromT: prev, toT: t));
    }
    prev = t;
  }
  return gaps;
}
