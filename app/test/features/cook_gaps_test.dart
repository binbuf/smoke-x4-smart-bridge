/// §E.5 — the two kinds of hole, told apart.
///
/// A buffer rollover is data **nobody has any more**; a connectivity hole is
/// data **arriving on the next sync**. They look identical on a chart, and
/// rendering them the same would tell someone to wait for something that is
/// never coming. So this file pins that they differ three ways over — texture,
/// status chrome, and words — because a reader only ever notices one of them
/// first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/features/cooks/cook_gaps_card.dart';
import 'package:smoke_bridge/features/sessions/sessions_screen.dart';

import '../support/shapes.dart';

const int _startedUnixMs = 1784755815000;

const _lost = RecordedGap(
  fromT: 3600,
  toT: 6120,
  reason: GapReason.bufferRollover,
);
const _waiting = RecordedGap(
  fromT: 9000,
  toT: 10080,
  reason: GapReason.connectivity,
);

Widget _host(List<RecordedGap> gaps, {int? startedUnixMs = _startedUnixMs}) =>
    MaterialApp(
      theme: SmokeTheme.dark,
      home: Scaffold(
        body: CookGapsCard(gaps: gaps, startedUnixMs: startedUnixMs),
      ),
    );

Color? _fillOf(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(
    find.descendant(of: find.byKey(key), matching: find.byType(Container)).first,
  );
  return (container.decoration! as BoxDecoration).color;
}

void main() {
  testWidgets('both kinds render as two separate, differently-worded blocks', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const [_lost, _waiting]));
    await tester.pump();

    expect(find.byKey(const Key('cook-gaps')), findsOneWidget);
    expect(find.byKey(const Key('gap-lost')), findsOneWidget);
    expect(find.byKey(const Key('gap-waiting')), findsOneWidget);

    // The words: what it costs the reader, not what the mechanism was.
    expect(find.text('Lost for good'), findsOneWidget);
    expect(find.text('Waiting on the bridge'), findsOneWidget);
    expect(find.textContaining('gone for good'), findsOneWidget);
    expect(find.textContaining('arrive on the next sync'), findsOneWidget);
    // Never the mechanism.
    expect(find.textContaining('ring buffer'), findsNothing);
    expect(find.textContaining('rollover'), findsNothing);
  });

  testWidgets('the two kinds do not share an icon', (tester) async {
    await tester.pumpWidget(_host(const [_lost, _waiting]));
    await tester.pump();

    // A status hue never carries meaning alone: each block leads with an icon
    // AND a word, and the icons differ.
    expect(
      find.descendant(
        of: find.byKey(const Key('gap-lost')),
        matching: find.byIcon(Icons.warning_amber_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('gap-waiting')),
        matching: find.byIcon(Icons.cloud_sync_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the two kinds do not share a status hue', (tester) async {
    await tester.pumpWidget(_host(const [_lost, _waiting]));
    await tester.pump();

    final lost = _fillOf(tester, const Key('gap-lost'));
    final waiting = _fillOf(tester, const Key('gap-waiting'));
    expect(lost, StatusPalette.fill(StatusRole.warning));
    expect(waiting, StatusPalette.fill(StatusRole.info));
    expect(lost, isNot(waiting));
    // Green is transport health and nothing else.
    expect(lost, isNot(StatusPalette.fill(StatusRole.positive)));
    expect(waiting, isNot(StatusPalette.fill(StatusRole.positive)));
  });

  testWidgets('the two kinds do not share a texture', (tester) async {
    await tester.pumpWidget(_host(const [_lost, _waiting]));
    await tester.pump();

    // Hatch for gone, dots for coming — the same two marks the chart draws, so
    // the card reads the way the chart does.
    expect(
      find.descendant(
        of: find.byKey(const Key('gap-lost')),
        matching: find.byKey(const Key('gap-mark-hatched')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('gap-waiting')),
        matching: find.byKey(const Key('gap-mark-dots')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('gap-lost')),
        matching: find.byKey(const Key('gap-mark-dots')),
      ),
      findsNothing,
    );
  });

  testWidgets('one kind alone does not imply the other exists', (tester) async {
    await tester.pumpWidget(_host(const [_waiting]));
    await tester.pump();

    expect(find.byKey(const Key('gap-waiting')), findsOneWidget);
    expect(find.byKey(const Key('gap-lost')), findsNothing);
    expect(find.textContaining('gone for good'), findsNothing);
  });

  testWidgets('each hole names when it happened and how long it lasted', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const [_lost]));
    await tester.pump();

    expect(find.byKey(const Key('gap-row-3600')), findsOneWidget);
    expect(find.textContaining('42m'), findsWidgets);
  });

  testWidgets('a bridge with no clock gets elapsed times, never 1970', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const [_lost], startedUnixMs: null));
    await tester.pump();

    expect(find.textContaining('01:00:00 → 01:42:00'), findsOneWidget);
    expect(find.textContaining('1970'), findsNothing);
  });

  testWidgets('no gaps at all renders nothing, not an empty heading', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const []));
    await tester.pump();

    expect(find.byKey(const Key('cook-gaps')), findsNothing);
    expect(find.text('GAPS IN RECORDING'), findsNothing);
  });

  testWidgets('the statistics table tells them apart too', (tester) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final samples = syntheticCook(hours: 3);
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: Scaffold(
          body: SessionDetailView(
            session: sessionFor(samples),
            samples: samples,
            probes: pitAndFood,
            gaps: const [_lost, _waiting],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('Gaps — lost for good'),
      find.byKey(const Key('session-detail')),
      const Offset(0, -300),
    );

    expect(find.text('Gaps — lost for good'), findsOneWidget);
    expect(find.text('Gaps — not synced yet'), findsOneWidget);
    // The undifferentiated row is gone when the caller knows which is which.
    expect(find.text('Gaps in recording'), findsNothing);
  });
}
