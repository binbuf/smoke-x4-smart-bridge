/// A2.2 — table tests. The null cases are the ones that matter.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';

List<TempPoint> series(
  int fromT,
  int toT,
  double? Function(int t) f, {
  int stepS = 30,
}) =>
    [for (var t = fromT; t <= toT; t += stepS) (t: t, f: f(t))];

void main() {
  test('a perfectly linear rise fits exactly', () {
    // 1 °F/min = 60 °F/hr.
    final s = series(0, 600, (t) => 100 + t / 60);
    expect(rateOfChange(s), closeTo(60, 1e-9));
  });

  test('a flat series reads zero', () {
    final s = series(0, 600, (t) => 225.0);
    expect(rateOfChange(s), closeTo(0, 1e-9));
  });

  test('a falling series reads negative', () {
    final s = series(0, 600, (t) => 250 - t / 120);
    expect(rateOfChange(s), closeTo(-30, 1e-9));
  });

  test('null: fewer than 12 valid samples in the window', () {
    // 20 samples, 11 of them detached → 9 valid.
    var i = 0;
    final s = series(30, 600, (t) => (i++ % 2 == 0 && i <= 22) ? null : 200.0);
    final valid = s.where((p) => p.f != null).length;
    expect(valid, lessThan(12));
    expect(rateOfChange(s), isNull);
  });

  test('12 valid samples with small gaps is enough', () {
    // Nulls scattered so no valid-to-valid delta exceeds 60 s.
    final nullTs = {30, 90, 150, 210, 270, 330, 390, 450};
    final s = series(30, 600, (t) => nullTs.contains(t) ? null : 180.0);
    expect(s.where((p) => p.f != null).length, 12);
    expect(rateOfChange(s), isNotNull);
  });

  test('null: the window spans a gap > 2 min', () {
    // A 270 s hole (packets lost) in an otherwise dense window.
    final s = [
      ...series(0, 240, (t) => 150.0),
      ...series(510, 600, (t) => 150.0),
    ];
    expect(s.where((p) => p.f != null).length,
        greaterThanOrEqualTo(rateMinValidSamples));
    expect(rateOfChange(s), isNull);
  });

  test('boundary: a gap of exactly 120 s is NOT a gap', () {
    final s = [
      ...series(0, 300, (t) => 150.0),
      ...series(420, 600, (t) => 150.0), // 420 − 300 = 120
    ];
    expect(rateOfChange(s), isNotNull);
  });

  test('only the trailing 10-minute window is used', () {
    // An hour of steep rise, then 10 minutes flat: the flat wins.
    final s = [
      ...series(0, 3000, (t) => 100 + t / 10),
      ...series(3030, 3600, (t) => 400.0),
    ];
    expect(rateOfChange(s), closeTo(0, 1e-9));
  });

  test('empty series is null, not a crash', () {
    expect(rateOfChange(const []), isNull);
  });
}
