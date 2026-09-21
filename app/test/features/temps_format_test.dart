/// N6 — the Temps screen's pure projections.
///
/// Pins the grouping rules, the prototype's exact trend/freshness strings, the
/// phase ladder, the I3/I4 meta cells and the floor-clamped pull notice.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/content/catalog.dart';
import 'package:smoke_bridge/data/model/cook_state.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/temps/temps_format.dart';

ProbeState _probe({
  ProbeJack jack = ProbeJack.one,
  ProbeRole role = ProbeRole.food,
  bool attached = true,
  Freshness freshness = Freshness.live,
  int? tempF10,
  int? targetF10,
  int? pullF10,
  double? trendFPerHr,
  bool stalled = false,
  int? peakF10,
  int? lowF10,
  int? avgF10,
  int? etaMin,
  List<int> spark = const [],
}) => ProbeState(
  jack: jack,
  role: role,
  attached: attached,
  freshness: freshness,
  tempF10: tempF10,
  targetF10: targetF10,
  pullF10: pullF10,
  trendFPerHr: trendFPerHr,
  stalled: stalled,
  peakF10: peakF10,
  lowF10: lowF10,
  avgF10: avgF10,
  etaMin: etaMin,
  spark: spark,
);

void main() {
  group('grouping (viewTemps)', () {
    test('attached in-use probes get a card', () {
      final probes = <ProbeState>[
        _probe(),
        _probe(jack: ProbeJack.four, role: ProbeRole.pit),
        _probe(jack: ProbeJack.two, attached: false),
        _probe(jack: ProbeJack.three, role: ProbeRole.unused),
      ];
      expect(attachedProbes(probes).map((p) => p.jack.n), <int>[1, 4]);
    });

    test('detached and unused probes are "not attached"', () {
      final probes = <ProbeState>[
        _probe(),
        _probe(jack: ProbeJack.four, role: ProbeRole.pit),
        _probe(jack: ProbeJack.two, attached: false),
        _probe(jack: ProbeJack.three, role: ProbeRole.unused),
      ];
      expect(detachedProbes(probes).map((p) => p.jack.n), <int>[2, 3]);
    });

    test('probeFor falls back to a detached default', () {
      final found = probeFor(<ProbeState>[
        _probe(jack: ProbeJack.two, tempF10: 1200),
      ], ProbeJack.two);
      expect(found.tempF10, 1200);
      final missing = probeFor(const <ProbeState>[], ProbeJack.three);
      expect(missing.jack, ProbeJack.three);
      expect(missing.attached, isFalse);
      expect(missing.tempF10, isNull);
    });

    test('cookEntryFor finds the assigned cut', () {
      const cook = CookState(
        items: <CookItem>[
          CookItem(presetId: 'beef_brisket', jack: ProbeJack.one, addedAtMs: 0),
        ],
      );
      expect(
        cookEntryFor(cook, kCatalogTable, ProbeJack.one)?.id,
        'beef_brisket',
      );
      expect(cookEntryFor(cook, kCatalogTable, ProbeJack.two), isNull);
    });
  });

  group('header / freshness words', () {
    test('updatedWord follows the connection', () {
      expect(updatedWord(connected: true), 'live');
      expect(updatedWord(connected: false), 'stale');
    });

    test('probeFreshnessWord reproduces the prototype ladder', () {
      expect(probeFreshnessWord(Freshness.live), 'Live');
      expect(probeFreshnessWord(Freshness.aging), 'Aging');
      expect(probeFreshnessWord(Freshness.frozen), 'Stale');
      expect(probeFreshnessWord(Freshness.stale), '—');
      expect(probeFreshnessWord(Freshness.unknown), '—');
    });
  });

  group('phase track (N6.8)', () {
    test('below the pull is Approaching', () {
      expect(probePhaseIndex(tempF10: 1642, pullF10: 1930, targetF10: 2010), 0);
    });

    test('at the pull is Pull now', () {
      expect(probePhaseIndex(tempF10: 1950, pullF10: 1930, targetF10: 2010), 1);
    });

    test(
      'at the target jumps straight to Ready (Resting is never current)',
      () {
        expect(
          probePhaseIndex(tempF10: 2010, pullF10: 1930, targetF10: 2010),
          3,
        );
        expect(
          probePhaseIndex(tempF10: 2050, pullF10: 1930, targetF10: 2010),
          3,
        );
      },
    );

    test('a missing pull falls back to the target', () {
      // With pull == target, Pull now is unreachable: crossing the pull *is*
      // crossing the target, which the ladder maps straight to Ready.
      expect(probePhaseIndex(tempF10: 2010, pullF10: null, targetF10: 2010), 3);
      expect(probePhaseIndex(tempF10: 2000, pullF10: null, targetF10: 2010), 0);
    });

    test('an absent reading or target is Approaching', () {
      expect(probePhaseIndex(tempF10: null, pullF10: 1930, targetF10: 2010), 0);
      expect(probePhaseIndex(tempF10: 2000, pullF10: 1930, targetF10: null), 0);
    });
  });

  group('trend chip', () {
    test('a null rate is the flat stale chip', () {
      final trend = trendFor(null);
      expect(trend.direction, TrendDirection.flat);
      expect(trend.label, 'stale');
    });

    test('a near-zero rate is flat', () {
      final trend = trendFor(0.4);
      expect(trend.direction, TrendDirection.flat);
      expect(trend.label, '~0° F/hr');
    });

    test('rising and falling rates carry a direction and one decimal', () {
      final up = trendFor(6.2);
      expect(up.direction, TrendDirection.up);
      expect(up.label, '6.2° F/hr');
      final down = trendFor(-4.1);
      expect(down.direction, TrendDirection.down);
      expect(down.label, '4.1° F/hr');
    });
  });

  group('meta cells (N6.4)', () {
    const cook = CookState(
      active: true,
      pitBandMinF10: 2250,
      pitBandMaxF10: 2750,
      grateTargetF10: 2500,
    );

    test('a grate probe shows pit band + status + High/Avg', () {
      final cells = tempMetaCells(
        probe: _probe(
          jack: ProbeJack.four,
          role: ProbeRole.pit,
          tempF10: 2486,
          peakF10: 2610,
          avgF10: 2493,
        ),
        cook: cook,
        unit: TempUnit.fahrenheit,
        isGrate: true,
      );
      expect(cells.map((c) => c.label), <String>[
        'Pit band',
        'Status',
        'High',
        'Avg',
      ]);
      expect(cells[0].value, '225–275°');
      expect(cells[1].value, 'In band');
      expect(cells[2].value, '261° F');
      expect(cells[3].value, '249° F');
    });

    test('a grate probe out of band says Out', () {
      final cells = tempMetaCells(
        probe: _probe(jack: ProbeJack.four, role: ProbeRole.pit, tempF10: 924),
        cook: cook,
        unit: TempUnit.fahrenheit,
        isGrate: true,
      );
      expect(cells[1].value, 'Out');
    });

    test('a targeted food probe shows Target/Pull/ETA then High/Avg', () {
      final cells = tempMetaCells(
        probe: _probe(
          tempF10: 1724,
          targetF10: 1950,
          pullF10: 1950,
          etaMin: 38,
          peakF10: 1724,
          avgF10: 1187,
        ),
        cook: cook,
        unit: TempUnit.fahrenheit,
        isGrate: false,
      );
      expect(cells.map((c) => c.label), <String>[
        'Target',
        'Pull at',
        'ETA',
        'High',
        'Avg',
      ]);
      expect(cells[0].value, '195° F');
      expect(cells[1].value, '195° F');
      expect(cells[2].value, '38 min');
    });

    test('a stalled live probe with no ETA says Stalled', () {
      final cells = tempMetaCells(
        probe: _probe(
          tempF10: 1642,
          targetF10: 2010,
          pullF10: 1930,
          stalled: true,
        ),
        cook: cook,
        unit: TempUnit.fahrenheit,
        isGrate: false,
      );
      expect(cells[2].value, 'Stalled');
    });

    test('a frozen reading removes the ETA (I4)', () {
      final cells = tempMetaCells(
        probe: _probe(
          tempF10: 1763,
          targetF10: 2010,
          pullF10: 1930,
          freshness: Freshness.frozen,
          etaMin: 38,
        ),
        cook: cook,
        unit: TempUnit.fahrenheit,
        isGrate: false,
      );
      expect(cells[2].value, '—');
    });

    test('an untargeted food probe shows only High/Avg', () {
      final cells = tempMetaCells(
        probe: _probe(tempF10: 681),
        cook: cook,
        unit: TempUnit.fahrenheit,
        isGrate: false,
      );
      expect(cells.map((c) => c.label), <String>['High', 'Avg']);
    });

    test('absent history is an em dash, never zero (I3)', () {
      final cells = tempMetaCells(
        probe: _probe(tempF10: 681),
        cook: cook,
        unit: TempUnit.fahrenheit,
        isGrate: false,
      );
      expect(cells[0].value, '—');
      expect(cells[1].value, '—');
    });
  });

  group('unit formatting', () {
    test('fmtTempUnit converts for display and dashes absent values', () {
      expect(fmtTempUnit(null, TempUnit.fahrenheit), '—');
      expect(fmtTempUnit(2010, TempUnit.fahrenheit), '201° F');
      expect(fmtTempUnit(2010, TempUnit.celsius), '94° C');
    });
  });

  group('target editor (N6.11, I12)', () {
    test('the pull notice never crosses a safety floor', () {
      final sausage = kCatalogTable.byId('pork_sausage')!;
      final doneness = selectedDoneness(sausage, 1600);
      // Ground meat floors at 160 °F; the 8° carryover must not pull below it.
      expect(pullForDoneness(sausage, doneness), 1600);
      expect(
        fmtTempUnit(pullForDoneness(sausage, doneness), TempUnit.fahrenheit),
        '160° F',
      );
    });

    test('selectedDoneness matches the target, else the default', () {
      final brisket = kCatalogTable.byId('beef_brisket')!;
      expect(selectedDoneness(brisket, 1950).id, 'sliceable');
      expect(selectedDoneness(brisket, 2010).id, 'tender');
      expect(selectedDoneness(brisket, 9999).id, brisket.defaultDonenessId);
    });
  });
}
