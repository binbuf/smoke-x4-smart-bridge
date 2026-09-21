/// N1.1 — temperatures and units.
///
/// Pins the storage/display split and sentinel handling: conversion happens
/// only at the display edge, and a detached probe is absent, never `0`.
library;

import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('storage is canonical tenths-°F', () {
    test('a present value keeps its canonical tenths', () {
      final v = TempValue.ofF10(724);
      expect(v.f10, 724);
      expect(v.isPresent, isTrue);
      expect(v.toF, closeTo(72.4, 1e-9));
    });

    test('toDisplay converts only at the edge', () {
      final v = TempValue.ofF10(724);
      // Both reads come from the same stored value; neither rewrites it.
      expect(v.toDisplay(TempUnit.fahrenheit), closeTo(72.4, 1e-9));
      expect(v.toDisplay(TempUnit.celsius), closeTo(22.4, 0.05));
      expect(v.f10, 724);
    });

    test('format is `72.4° F` and `22.4° C`', () {
      final v = TempValue.ofF10(724);
      expect(v.format(TempUnit.fahrenheit), '72.4° F');
      expect(v.format(TempUnit.celsius), '22.4° C');
    });
  });

  group('sentinels are absent, not zero (I3)', () {
    test('both wire sentinels decode to absent', () {
      expect(TempValue.fromWire(tempDetachedSentinel).isAbsent, isTrue);
      expect(TempValue.fromWire(tempInvalidSentinel).isAbsent, isTrue);
      expect(TempValue.fromWire(null).isAbsent, isTrue);
    });

    test('absent has no number and renders an em dash', () {
      const v = TempValue.absent();
      expect(v.f10, isNull);
      expect(v.toF, isNull);
      expect(v.toDisplay(TempUnit.fahrenheit), isNull);
      expect(v.format(TempUnit.fahrenheit), '—');
      expect(v.format(TempUnit.celsius), '—');
    });

    test('a real value is never confused with a sentinel', () {
      expect(TempValue.fromWire(724).isPresent, isTrue);
      expect(TempValue.fromWire(0).isPresent, isTrue);
      expect(TempValue.fromWire(0).toF, 0);
    });
  });

  group('scale conversion helpers', () {
    test('c10ToF10 and f10ToC10 round-trip within a tenth', () {
      expect(c10ToF10(224), 723);
      expect(f10ToC10(723), 224);
      // 0.1 °C is finer than 0.1 °F, so nearest rounding stays within a step.
      for (final c10 in [0, 100, -180, 375]) {
        expect((f10ToC10(c10ToF10(c10)) - c10).abs() <= 1, isTrue);
      }
    });
  });
}
