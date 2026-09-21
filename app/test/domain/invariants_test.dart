/// The must-not-regress invariants from `newui/tasks/N1-domain.md`, each named
/// in the test so a regression points at the rule it broke.
library;

import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('I3 — absent is not zero: detached decodes to null, never 0', () {
    expect(TempValue.fromWire(tempDetachedSentinel).toF, isNull);
    expect(TempValue.fromWire(tempInvalidSentinel).toF, isNull);
    expect(
      detachedReading(ProbeJack.three).temp.toDisplay(TempUnit.fahrenheit),
      isNull,
    );

    const sample = Sample(t: 0, tempsF10: [null, null, null, null]);
    expect(sample.tempFor(ProbeJack.one), isNull);

    final stats = cookStats(
      const [
        Sample(t: 0, tempsF10: [null, null, null, null]),
      ],
      probeConfig: const [Probe(jack: ProbeJack.one)],
    );
    expect(
      stats.probes.firstWhere((p) => p.jack == ProbeJack.one).peakF,
      isNull,
    );
  });

  test('I4 — stale removes derived values rather than greying them', () {
    expect(Freshness.live.showsDerived, isTrue);
    expect(Freshness.aging.showsDerived, isTrue);
    expect(Freshness.stale.showsDerived, isFalse);
    expect(Freshness.frozen.showsDerived, isFalse);

    // The stale threshold is exactly the ladder's ≤600 s / >600 s split.
    expect(Freshness.fromAge(600), Freshness.stale);
    expect(Freshness.fromAge(601), Freshness.frozen);
  });

  test('I11 — a bridge with no clock stores null, never a fabricated time', () {
    const noClock = Sample(t: 0, tempsF10: [1000, null, null, null]);
    expect(noClock.unixMs, isNull);

    final anchors = candidateAnchors(
      samples: const [
        Sample(t: 0, tempsF10: [1000, null, null, null]),
      ],
      sessionStartUnixMs: null,
    );
    expect(anchors, isEmpty, reason: 'no clock means no offered anchor times');
  });

  test('I12 — food safety is a hard gate; an unsafe target is refused', () {
    expect(
      () => CookPlan(
        presetId: 'custom',
        title: 'Chicken',
        hazard: HazardClass.poultry,
        doneness: 'Done',
        probes: [
          PlanProbe(
            jack: ProbeJack.one,
            isPit: false,
            name: 'Chicken',
            targetF10: 1400, // below the 165 °F poultry floor
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('carryover — poultry is always zero, by rule', () {
    for (final thickness in CutThickness.values) {
      expect(
        carryoverFor(hazard: HazardClass.poultry, thickness: thickness),
        0,
      );
    }
    // And it is the thickness, not the doneness, that moves a roast.
    final roast = carryoverFor(
      hazard: HazardClass.wholeMuscleRedMeat,
      thickness: CutThickness.thick,
    );
    expect(roast, greaterThan(0));
  });
}
