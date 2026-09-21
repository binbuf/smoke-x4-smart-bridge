/// N3.11 — the icon set contract.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';

void main() {
  test('every prototype icon name has a glyph', () {
    expect(SmokeIcons.count, greaterThanOrEqualTo(60));
    for (final glyph in SmokeGlyph.values) {
      expect(
        SmokeIcons.data(glyph),
        isA<IconData>(),
        reason: '$glyph has no mapped glyph',
      );
    }
  });

  test('byName resolves the prototype string names', () {
    const names = <String>[
      'bluetooth',
      'wifi',
      'wifiOff',
      'router',
      'thermometer',
      'flame',
      'alertTriangle',
      'chevronRight',
      'zoomIn',
      'qr',
      'star',
    ];
    for (final name in names) {
      expect(
        SmokeIcons.byName(name),
        isNotNull,
        reason: 'ICON_PATHS.$name is not ported',
      );
    }
    expect(SmokeIcons.byName('not-an-icon'), isNull);
  });

  testWidgets('SmokeIcon draws the mapped glyph', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: SmokeIcon(SmokeGlyph.flame, size: 20)),
      ),
    );
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.local_fire_department);
    expect(icon.size, 20);
  });
}
