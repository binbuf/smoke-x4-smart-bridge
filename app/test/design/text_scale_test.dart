/// The large-text ladder (design 14 §14.5.1 + §14.10, newapp §H.2).
///
/// Two rules that look like a contradiction and are not:
///
///  * a temperature is **never scaled to fit** — the hero is 96 pt, the same
///    96 pt on the card beside it, and the same 96 pt one frame later when the
///    probe crosses 99 → 100 °F;
///  * text scale is **honoured**, and §H.2 wants the hero to *"grow and reflow
///    the gauge rather than clip"*.
///
/// They are reconciled by deciding what the scaler buys: room for everything
/// that is prose, paid for by the gauge, which is the flexible child by
/// §14.5.1's own words. What is pinned here is that the payment happens in
/// that order — gauge first, number last — and that nothing ever clips.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';

void main() {
  test('at normal text the hero is the spec, unchanged', () {
    final m = SmokeTextScale.metricsFor(1.0);
    expect(m.number, SmokeType.heroTemp);
    expect(m.number.fontSize, 96);
    expect(m.unit, SmokeType.heroUnit);
    expect(m.gauge, SmokeTextScale.gaugeFull);
    expect(m.stacked, isFalse);
  });

  test('a scaler below 1 never grows the gauge past its designed size', () {
    expect(SmokeTextScale.metricsFor(0.85).gauge, SmokeTextScale.gaugeFull);
  });

  test('the gauge pays first — the number does not move below 1.3', () {
    for (final s in [1.05, 1.15, 1.29]) {
      final m = SmokeTextScale.metricsFor(s);
      expect(
        m.number,
        SmokeType.heroTemp,
        reason: 'the number moved at $s, before the gauge had finished paying',
      );
      expect(m.gauge, lessThan(SmokeTextScale.gaugeFull));
      expect(
        m.gauge,
        greaterThanOrEqualTo(SmokeTextScale.gaugeMin),
        reason:
            'a gauge below ${SmokeTextScale.gaugeMin} cannot separate its pull '
            'tick from its value dot, so it is dropped rather than drawn badly',
      );
    }
  });

  test('the give-back is monotonic — no scale makes the gauge bigger', () {
    double? previous;
    for (var s = 1.0; s < SmokeTextScale.reflowAt; s += 0.02) {
      final g = SmokeTextScale.metricsFor(s).gauge!;
      if (previous != null) {
        expect(g, lessThanOrEqualTo(previous + 1e-9), reason: 'at scale $s');
      }
      previous = g;
    }
  });

  test('at 1.3 the gauge is dropped, not drawn at zero', () {
    final m = SmokeTextScale.metricsFor(SmokeTextScale.reflowAt);
    expect(
      m.gauge,
      isNull,
      reason:
          'an empty ring says "there is a target and you are at zero", which '
          'is false — §14.7.3',
    );
    expect(m.showsGauge, isFalse);
  });

  test('past 1.3 the hero demotes to bigTemp and the chips stack', () {
    final m = SmokeTextScale.metricsFor(2.0);
    expect(m.number, SmokeType.bigTemp);
    expect(m.unit, SmokeType.displayS);
    expect(m.stacked, isTrue);
    // Deliberately a *smaller* declared size: past 1.3 every label around the
    // number is 1.3× or more and the card has run out of width, so the honest
    // move is to give the room to the words that grew.
    expect(m.number.fontSize! < SmokeType.heroTemp.fontSize!, isTrue);
  });

  test('every step is one of the fourteen type styles — no fifteenth', () {
    const scale = [0.9, 1.0, 1.1, 1.3, 2.0];
    const named = [
      SmokeType.heroTemp,
      SmokeType.bigTemp,
      SmokeType.heroUnit,
      SmokeType.displayS,
    ];
    for (final s in scale) {
      final m = SmokeTextScale.metricsFor(s);
      expect(named, contains(m.number), reason: 'number at $s');
      expect(named, contains(m.unit), reason: 'unit at $s');
    }
  });

  testWidgets('the factor is read off the size the labels actually use', (
    tester,
  ) async {
    late double factor;
    late bool large;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: Builder(
          builder: (context) {
            factor = SmokeTextScale.factorOf(context);
            large = SmokeTextScale.isLarge(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(factor, closeTo(1.5, 1e-6));
    expect(large, isTrue);
  });

  testWidgets('a temperature rendered unscaled ignores the user scaler', (
    tester,
  ) async {
    late double effective;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: SmokeType.unscaled(
          child: Builder(
            builder: (context) {
              effective = MediaQuery.textScalerOf(context).scale(96);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(
      effective,
      96,
      reason:
          'the hero must print the same glyph height as the card beside it, at '
          'every accessibility setting — §14.5.1',
    );
  });
}
