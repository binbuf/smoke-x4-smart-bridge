/// History as list-detail on a wide window (design 13 §13.3, §13.5.4).
///
/// On a phone, opening a cook is a navigation. From 600 dp it is a
/// **selection**: list on the left, detail on the right, one screen. That is
/// the canonical layout for this flow, and on this app it is also the fix for
/// the context loss — on a tablet or an unfolded Fold there is no navigation
/// left to lose context in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/sessions/sessions_screen.dart';

import '../support/load_fonts.dart';

const _rows = [
  SessionListRow(session: CookSession(id: 27, name: 'Brisket', closed: true)),
  SessionListRow(session: CookSession(id: 28, name: 'Pork butt')),
];

Widget _host({int? selectedId, ValueChanged<CookSession>? onOpen}) =>
    MaterialApp(
      theme: SmokeTheme.dark,
      home: Scaffold(
        body: SessionsListView(
          rows: _rows,
          selectedId: selectedId,
          onOpen: onOpen,
        ),
      ),
    );

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a selected row is marked as selected', (tester) async {
    await tester.pumpWidget(_host(selectedId: 27));
    await tester.pump();

    final selected = tester.widget<ListTile>(
      find.ancestor(of: find.text('Brisket'), matching: find.byType(ListTile)),
    );
    final other = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Pork butt'),
        matching: find.byType(ListTile),
      ),
    );
    expect(selected.selected, isTrue);
    expect(other.selected, isFalse);
  });

  testWidgets('with no selection nothing is marked — the compact case', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    for (final name in ['Brisket', 'Pork butt']) {
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
      );
      expect(tile.selected, isFalse, reason: name);
    }
  });

  testWidgets('an open session reads as Recording, not "cooking"', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    // The bridge records whether or not a cook was ever set up (§13.7.6), so
    // an open session means recording — it does not mean somebody is cooking.
    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('cooking'), findsNothing);
  });

  testWidgets('tapping a row reports the cook, whatever the layout does next', (
    tester,
  ) async {
    final opened = <int>[];
    await tester.pumpWidget(_host(onOpen: (s) => opened.add(s.id)));
    await tester.pump();

    await tester.tap(find.text('Brisket'));
    await tester.pump();
    expect(opened, [27]);
  });
}
