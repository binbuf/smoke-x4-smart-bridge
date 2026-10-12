/// The four physical jacks on the Smoke X4, 1..4.
///
/// The slim app treats jacks generically: the BLE contract carries no per-probe
/// name or role (`history_session` is a lossy projection of the header), so a
/// jack is just its number and its position in `Sample.tempsF10`.
library;

enum ProbeJack {
  one(1),
  two(2),
  three(3),
  four(4);

  const ProbeJack(this.n);

  /// 1..4, matching the wire and `Sample.tempsF10` ordering.
  final int n;

  /// Parses a 1..4 value, or returns null when out of range.
  static ProbeJack? fromN(int n) {
    for (final j in ProbeJack.values) {
      if (j.n == n) {
        return j;
      }
    }
    return null;
  }

  /// The jack at `index` in a 4-element list (0-based), or null.
  static ProbeJack? fromIndex(int index) =>
      index >= 0 && index < ProbeJack.values.length
      ? ProbeJack.values[index]
      : null;
}
