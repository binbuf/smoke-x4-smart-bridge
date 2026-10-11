import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('TempValue', () {
    test('folds both wire sentinels into absent, never zero', () {
      expect(TempValue.fromWire(tempDetachedSentinel).isAbsent, isTrue);
      expect(TempValue.fromWire(tempInvalidSentinel).isAbsent, isTrue);
      expect(TempValue.fromWire(null).isAbsent, isTrue);
      expect(TempValue.fromWire(tempDetachedSentinel).toF, isNull);
    });

    test('formats in the requested unit and an em dash when absent', () {
      expect(TempValue.ofF10(724).format(TempUnit.fahrenheit), '72.4° F');
      expect(TempValue.ofF10(724).format(TempUnit.celsius), '22.4° C');
      expect(const TempValue.absent().format(TempUnit.fahrenheit), '—');
    });
  });

  group('Freshness ladder', () {
    test('buckets by age', () {
      expect(Freshness.fromAge(10), Freshness.live);
      expect(Freshness.fromAge(60), Freshness.aging);
      expect(Freshness.fromAge(300), Freshness.stale);
      expect(Freshness.fromAge(601), Freshness.frozen);
      expect(Freshness.fromAge(null), Freshness.unknown);
    });

    test('a lost base station outranks a fresh phone link', () {
      expect(Freshness.fromAge(5, baseLost: true), Freshness.frozen);
    });

    test('derived values are only shown while live or aging', () {
      expect(Freshness.live.canShowDerived, isTrue);
      expect(Freshness.aging.canShowDerived, isTrue);
      expect(Freshness.stale.canShowDerived, isFalse);
    });
  });
}
