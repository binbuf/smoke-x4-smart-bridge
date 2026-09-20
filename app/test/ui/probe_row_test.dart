/// `ProbeStripRow`, after §17.3 B — the row four of which *are* `/live`.
///
/// The row went from *swatch · name · state word · number · chevron* to
/// **badge · food glyph · name · role chip · readout · trend · chevron**, with a
/// second line carrying the target and the estimate. That is a lot of new
/// content on the densest surface in the app, so what is pinned here is the two
/// things density can cost you:
///
///  1. **it still cannot overflow.** The row spends width in an explicit
///     priority order — the number is measured first and never gives way, then
///     the name, then the sparkline — and the pieces that do not fit are absent
///     rather than clipped. Checked at 360 / 600 / 840 dp and at 200 % text;
///  2. **it still tells the truth.** Derived values (the trend, the sparkline,
///     the estimate) disappear the moment the reading behind them goes stale;
///     the *target* does not, because a target is a setting. A detached jack
///     renders in place with `—` and the word *unplugged*, never a `0`.
///
/// The identity marks themselves — that the avatar never moves with state, that
/// the badge numeral is legible on all four jacks — are pinned in
/// `test/design/identity_channel_test.dart`, which is where the rule they obey
/// is written down.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/analysis/analysis.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/ui/probe/food_avatar.dart';
import 'package:smoke_bridge/ui/probe/jack_badge.dart';
import 'package:smoke_bridge/ui/probe/probe_freshness.dart';
import 'package:smoke_bridge/ui/probe/probe_strip_row.dart';
import 'package:smoke_bridge/ui/probe/sparkline.dart';

import '../support/load_fonts.dart';

ProbeView _pit({int? tempF10 = 2542}) => ProbeView(
  probe: 1,
  role: ProbeRole.pit,
  name: 'Pit',
  tempF10: tempF10,
  rateFPerHr: 18.8,
  recent: [for (var i = 0; i < 20; i++) (t: i * 60, f: 240.0 + i)],
);

ProbeView _food({
  int? tempF10 = 1632,
  int? targetF10 = 2030,
  EtaResult? eta,
  String name = 'Brisket flat',
}) => ProbeView(
  probe: 2,
  role: ProbeRole.food,
  name: name,
  tempF10: tempF10,
  targetF10: targetF10,
  rateFPerHr: 12.4,
  eta: eta,
  recent: [for (var i = 0; i < 20; i++) (t: i * 60, f: 150.0 + i)],
);

Future<void> _pump(
  WidgetTester tester,
  ProbeView view, {
  ProbeFreshness freshness = ProbeFreshness.live,
  double width = 400,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = Size(width, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: Size(width, 900),
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        theme: SmokeTheme.dark,
        home: Scaffold(
          body: ProbeStripRow(view: view, freshness: freshness),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  group('the row leads with identity', () {
    testWidgets('badge, avatar, then the name — in that order', (tester) async {
      await _pump(tester, _food());
      expect(find.byType(JackBadge), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byType(FoodAvatar), findsOneWidget);
      expect(find.text('BRISKET FLAT'), findsOneWidget);

      // Left to right, and the number is to the right of all of it.
      final badge = tester.getCenter(find.byType(JackBadge)).dx;
      final avatar = tester.getCenter(find.byType(FoodAvatar)).dx;
      final name = tester.getCenter(find.text('BRISKET FLAT')).dx;
      expect(badge, lessThan(avatar));
      expect(avatar, lessThan(name));
    });

    testWidgets('the name resolves the glyph when there is no cook', (
      tester,
    ) async {
      // Instrument mode has no preset and no hazard — the name the user typed
      // is the only identity there is, and it is theirs rather than a guess.
      await _pump(tester, _food(name: 'Spare ribs'));
      expect(
        tester.widget<FoodAvatar>(find.byType(FoodAvatar)).glyph,
        FoodGlyph.ribs,
      );
      await _pump(tester, _pit());
      expect(
        tester.widget<FoodAvatar>(find.byType(FoodAvatar)).glyph,
        FoodGlyph.pit,
      );
    });

    testWidgets('the role chip never repeats the name', (tester) async {
      // `PIT [PIT]` is the redundancy §16.5 bans in a row subtitle, and a chip
      // is not exempt from it.
      await _pump(tester, _pit(), width: 840);
      expect(find.text('PIT'), findsOneWidget);
      // A food probe named after its cut earns the word.
      await _pump(tester, _food(), width: 840);
      expect(find.text('FOOD'), findsOneWidget);
    });
  });

  group('the second line (§17.3 B)', () {
    testWidgets('trend, target and estimate, in that order', (tester) async {
      await _pump(
        tester,
        _food(
          eta: const EtaRange(
            Duration(hours: 2),
            Duration(hours: 2, minutes: 30),
          ),
        ),
      );
      // The rate rides under the name as a chip — the arrow is a *shape*,
      // which is what survives a monochrome screenshot and a colour-blind
      // reader — and the settings take the second line.
      expect(find.text('+12.4°/hr'), findsOneWidget);
      expect(find.text('Target 203° · ready in 2h – 2h 30m'), findsOneWidget);
    });

    testWidgets('a refusal states its reason rather than vanishing', (
      tester,
    ) async {
      // §D.5: a refusal is an answer. An estimate that quietly disappeared
      // mid-cook is the silent failure §16.2 is written against.
      await _pump(
        tester,
        _food(
          eta: const EtaUnavailable(EtaUnavailableReason.stalled),
        ),
      );
      expect(
        find.text('Target 203° · No estimate while it is in a stall.'),
        findsOneWidget,
      );
    });

    testWidgets('no target, no second line — not an empty one', (tester) async {
      await _pump(tester, _food(targetF10: null));
      expect(find.textContaining('Target'), findsNothing);
    });

    testWidgets('the pit has a band, not a target, so it has no line', (
      tester,
    ) async {
      await _pump(tester, _pit());
      expect(find.textContaining('Target'), findsNothing);
    });
  });

  group('derived values die with the reading, settings do not', () {
    testWidgets('stale removes the trend, the spark and the estimate', (
      tester,
    ) async {
      const eta = EtaRange(Duration(hours: 2), Duration(hours: 2));
      await _pump(tester, _food(eta: eta), width: 840);
      expect(find.textContaining('°/hr'), findsOneWidget);
      expect(find.byType(Sparkline), findsOneWidget);
      expect(find.textContaining('ready in'), findsOneWidget);

      await _pump(
        tester,
        _food(eta: eta),
        freshness: ProbeFreshness.stale,
        width: 840,
      );
      expect(find.textContaining('°/hr'), findsNothing);
      expect(find.byType(Sparkline), findsNothing);
      expect(find.textContaining('ready in'), findsNothing);
      // …and the target survives, because a target is a setting.
      expect(find.text('Target 203°'), findsOneWidget);
    });

    testWidgets('detached renders in place, as "—" and a word', (tester) async {
      await _pump(tester, _food(tempF10: null));
      expect(find.text('—'), findsOneWidget);
      expect(find.text('unplugged'), findsOneWidget);
      expect(find.byType(FoodAvatar), findsOneWidget);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data, isNot('0'));
        expect(text.data, isNot('0.0'));
      }
    });
  });

  group('it cannot overflow', () {
    for (final width in [360.0, 600.0, 840.0]) {
      testWidgets('clean at ${width.round()} dp', (tester) async {
        await _pump(
          tester,
          _food(
            eta: const EtaRange(Duration(hours: 2), Duration(hours: 3)),
          ),
          width: width,
        );
        expect(tester.takeException(), isNull);
        // The number is the content and is always present, whole.
        expect(find.text('163'), findsOneWidget);
      });

      testWidgets('clean at ${width.round()} dp, 200 % text', (tester) async {
        await _pump(
          tester,
          _food(
            eta: const EtaRange(Duration(hours: 2), Duration(hours: 3)),
          ),
          width: width,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('163'), findsOneWidget);
      });
    }

    testWidgets('a four-digit reading at 360 dp keeps the number, drops the '
        'sparkline', (tester) async {
      // The priority order, at its worst case: the wire clamps to 572.0 °F, so
      // four tabular glyphs plus a unit is the widest a row can be asked for.
      await _pump(tester, _pit(tempF10: 5720), width: 360);
      expect(tester.takeException(), isNull);
      expect(find.text('572'), findsOneWidget);
      expect(find.byType(Sparkline), findsNothing);
    });
  });
}
