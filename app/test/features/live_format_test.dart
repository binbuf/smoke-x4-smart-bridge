/// N5 — the Live screen's pure projections.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/content/catalog.dart';
import 'package:smoke_bridge/data/model/cook_state.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/live/live_format.dart';

void main() {
  group('fmtStopwatch', () {
    test('pads HH:MM:SS and clamps at zero', () {
      expect(fmtStopwatch(0), '00:00:00');
      expect(fmtStopwatch(1000), '00:00:01');
      expect(fmtStopwatch(61000), '00:01:01');
      expect(fmtStopwatch(4 * 3600000 + 12 * 60000), '04:12:00');
      expect(fmtStopwatch(-5000), '00:00:00');
    });
  });

  group('fmtDuration', () {
    test('hours, minutes, seconds', () {
      expect(fmtDuration(0), '0s');
      expect(fmtDuration(12000), '12s');
      expect(fmtDuration(38 * 60000), '38m');
      expect(fmtDuration(4 * 3600000 + 12 * 60000), '4h 12m');
    });
  });

  group('fmtClock', () {
    test('12-hour label', () {
      expect(fmtClock(DateTime(2026, 9, 21, 9, 41)), '9:41 AM');
      expect(fmtClock(DateTime(2026, 9, 21, 13, 5)), '1:05 PM');
      expect(fmtClock(DateTime(2026, 9, 21)), '12:00 AM');
      expect(fmtClock(DateTime(2026, 9, 21, 12)), '12:00 PM');
    });
  });

  group('fmtEta', () {
    test('minutes and hours', () {
      expect(fmtEta(null), isNull);
      expect(fmtEta(0), '<1 min');
      expect(fmtEta(38), '38 min');
      expect(fmtEta(60), '1h');
      expect(fmtEta(65), '1h 5m');
    });
  });

  group('tempParts (I3)', () {
    test('absent is an em dash, never zero', () {
      final parts = tempParts(null, TempUnit.fahrenheit);
      expect(parts.num, '—');
      expect(parts.dec, '');
      expect(parts.unit, '');
    });

    test('splits number, decimal and unit', () {
      final f = tempParts(1642, TempUnit.fahrenheit);
      expect(f.num, '164');
      expect(f.dec, '.2');
      expect(f.unit, '° F');

      final c = tempParts(1642, TempUnit.celsius);
      expect(c.num, '73');
      expect(c.dec, '.4');
      expect(c.unit, '° C');
    });
  });

  group('probeName', () {
    const cook = CookState(
      active: true,
      items: [
        CookItem(presetId: 'beef_brisket', jack: ProbeJack.one, addedAtMs: 0),
      ],
    );

    test('grate, unused and catalog names', () {
      expect(
        probeName(
          const ProbeState(jack: ProbeJack.four, role: ProbeRole.pit),
          cook,
          kCatalogTable,
        ),
        'Grate · jack 4',
      );
      expect(
        probeName(const ProbeState(jack: ProbeJack.two), cook, kCatalogTable),
        'Jack 2 · unused',
      );
      final entry = kCatalogTable.byId('beef_brisket')!;
      expect(
        probeName(
          const ProbeState(jack: ProbeJack.one, role: ProbeRole.food),
          cook,
          kCatalogTable,
        ),
        entry.name,
      );
      expect(
        probeName(
          const ProbeState(jack: ProbeJack.three, role: ProbeRole.food),
          cook,
          kCatalogTable,
        ),
        'Probe 3',
      );
    });
  });
}
