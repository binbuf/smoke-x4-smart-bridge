/// N1.1 — temperatures at the domain boundary.
///
/// **Storage is canonical tenths of °F, always.** A unit picker never rewrites
/// a sample; it only changes how a value is *displayed* ([toDisplay]). That is
/// the whole reason this type exists: an untyped `double` could be °C or °F and
/// nothing would catch the mix-up.
///
/// **Absent is not zero (I3).** The wire carries two sentinels for a probe that
/// is detached or invalid; both decode to [absent], whose display is an em dash
/// and whose numeric value is `null` — never `0`.
library;

/// Which scale a readout is shown in.
enum TempUnit {
  fahrenheit('° F'),
  celsius('° C');

  const TempUnit(this.suffix);

  /// The literal appended after the number: `72.4° F`.
  final String suffix;
}

/// `TEMP_DETACHED` from the wire contract (`protocol/records.yaml`).
const int tempDetachedSentinel = -32768;

/// `TEMP_INVALID` from the wire contract.
const int tempInvalidSentinel = -32767;

/// Tenths-°C → canonical tenths-°F, rounded to nearest.
int c10ToF10(int c10) => ((c10 * 9) / 5).round() + 320;

/// Tenths-°F → tenths-°C, rounded to nearest.
int f10ToC10(int f10) => (((f10 - 320) * 5) / 9).round();

/// One temperature reading, canonical tenths-°F or absent.
class TempValue {
  const TempValue._(this.f10);

  /// No reading yet, or a probe that is detached/invalid.
  const TempValue.absent() : f10 = null;

  /// Decodes a wire value, folding both sentinels into [absent]. A `null` raw
  /// value means the field was not present at all and is also absent.
  factory TempValue.fromWire(int? raw) {
    if (raw == null ||
        raw == tempDetachedSentinel ||
        raw == tempInvalidSentinel) {
      return const TempValue.absent();
    }
    return TempValue._(raw);
  }

  /// A present value, already known good (not a sentinel).
  factory TempValue.ofF10(int f10) => TempValue._(f10);

  /// Canonical tenths-°F; `null` when absent.
  final int? f10;

  bool get isPresent => f10 != null;
  bool get isAbsent => f10 == null;

  /// The value in [unit], or `null` when absent. This is the only conversion
  /// point; nothing downstream stores a converted number.
  double? toDisplay(TempUnit unit) {
    final v = f10;
    if (v == null) {
      return null;
    }
    return unit == TempUnit.fahrenheit ? v / 10 : ((v - 320) * 5 / 9) / 10;
  }

  /// Shorthand for the canonical scale.
  double? get toF => f10 == null ? null : f10! / 10;

  /// Shorthand for the metric scale.
  double? get toC => toDisplay(TempUnit.celsius);

  /// `72.4° F` / `22.4° C`, or `—` when absent. One decimal is the device's
  /// resolution; printing more would be precision the sensor does not have.
  String format(TempUnit unit) {
    final d = toDisplay(unit);
    if (d == null) {
      return '—';
    }
    return '${d.toStringAsFixed(1)}${unit.suffix}';
  }

  @override
  bool operator ==(Object other) => other is TempValue && other.f10 == f10;

  @override
  int get hashCode => f10.hashCode;

  @override
  String toString() => f10 == null ? 'TempValue.absent()' : 'TempValue($f10)';
}
