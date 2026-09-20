/// THE IDENTITY CHANNEL (design 17 §17.2, §17.3 A) — the permission slip, and
/// the conditions on it.
///
/// §17.2 adds a **third colour channel** beside series and status, and it is
/// the only one allowed to fill a shape, carry a word and look warm. The whole
/// argument for it is one sentence:
///
/// > Identity never encodes state. A brisket avatar is the same whether the
/// > cook is perfect or ruined. That is precisely what makes it safe.
///
/// An argument that lives only in a document is an argument that survives until
/// the first plausible-looking pull request adds `freshness` to [FoodAvatar] so
/// a stale row "reads better". So it lives here instead, as three groups:
///
///  1. **invariance** — the avatar's own fill and glyph do not move with
///     freshness, with an alarm, with the link, or with a target being reached.
///     This is the group that matters; the rest are hygiene;
///  2. **contrast** — a fill this size has floors, and they are measured with
///     the same WCAG maths `series_channels_test.dart` uses rather than
///     asserted in a doc comment;
///  3. **coverage** — every [HazardClass] and every shipped preset resolves to
///     a drawn glyph, so adding a protein is a red test rather than a silent
///     fork and knife.
///
/// One thing this file deliberately does **not** defend: a [StaleVeil] above an
/// avatar still desaturates it. The veil is a statement about a whole region of
/// readings, and a circle that stayed saturated inside one would make the
/// region look half-live. Invariance is a property of the widget's own
/// configuration, and that is what is asserted.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/hazard.dart';
import 'package:smoke_bridge/domain/plan/presets.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/ui/probe/food_avatar.dart';
import 'package:smoke_bridge/ui/probe/jack_badge.dart';
import 'package:smoke_bridge/ui/probe/probe_freshness.dart';
import 'package:smoke_bridge/ui/probe/probe_strip_row.dart';

import '../support/load_fonts.dart';

// ── colour maths, so nothing here is taken on faith ──────────────────────

double _linear(double channel) => channel <= 0.03928
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

// ── fixtures ─────────────────────────────────────────────────────────────

Widget _host(Widget child, {double width = 400}) => MaterialApp(
  theme: SmokeTheme.dark,
  home: Scaffold(
    body: Center(child: SizedBox(width: width, child: child)),
  ),
);

ProbeView _view({
  int? tempF10 = 1632,
  int? targetF10 = 2030,
  Alarm? alarm,
  String name = 'Brisket flat',
}) => ProbeView(
  probe: 2,
  role: ProbeRole.food,
  name: name,
  tempF10: tempF10,
  targetF10: targetF10,
  rateFPerHr: 12,
  alarm: alarm,
);

/// The identity fill actually painted under [root], as a set — read off the
/// element tree so a `switch` inside a build method is what gets checked,
/// rather than what one constructor was handed.
Set<Color> _fills(WidgetTester tester, Finder root) {
  final found = <Color>{};
  void walk(Element e) {
    if (e.widget case Container(:final BoxDecoration decoration)) {
      if (decoration.color case final c?) {
        found.add(c);
      }
    }
    e.visitChildElements(walk);
  }

  walk(tester.element(root));
  return found;
}

void main() {
  setUpAll(loadAppFonts);

  // ── 1. invariance: the whole reason this channel is legal ──────────────

  group('the identity avatar never encodes state', () {
    testWidgets('freshness does not change the glyph or its fill', (
      tester,
    ) async {
      FoodGlyph? glyph;
      Set<Color>? fills;

      for (final freshness in ProbeFreshness.values) {
        await tester.pumpWidget(
          _host(
            ProbeStripRow(
              view: _view(),
              freshness: freshness,
              glyph: FoodGlyph.brisket,
            ),
          ),
        );
        final avatar = tester.widget<FoodAvatar>(find.byType(FoodAvatar));
        final painted = _fills(tester, find.byType(FoodAvatar));

        glyph ??= avatar.glyph;
        fills ??= painted;
        expect(
          avatar.glyph,
          glyph,
          reason: '$freshness must not change what is on the probe',
        );
        expect(
          painted,
          fills,
          reason: 'a stale reading is a fact about the reading, not about '
              'the food — $freshness repainted the avatar',
        );
        expect(painted, contains(IdentityPalette.of(FoodGlyph.brisket)));
      }
    });

    testWidgets('an alarm does not change the glyph or its fill', (
      tester,
    ) async {
      const alarm = Alarm(
        id: 7,
        rule: 'pit_out_of_band',
        probe: 2,
        valueF10: 2900,
        severity: AlarmSeverity.critical,
      );
      final rendered = <Set<Color>>[];
      for (final a in [null, alarm]) {
        await tester.pumpWidget(
          _host(
            ProbeStripRow(
              view: _view(alarm: a),
              freshness: ProbeFreshness.live,
              glyph: FoodGlyph.brisket,
            ),
          ),
        );
        expect(
          tester.widget<FoodAvatar>(find.byType(FoodAvatar)).glyph,
          FoodGlyph.brisket,
        );
        rendered.add(_fills(tester, find.byType(FoodAvatar)));
      }
      expect(
        rendered.first,
        rendered.last,
        reason: 'an alarm is chrome with an icon and a word (§16.5); it is '
            'not a repaint of what is cooking',
      );
    });

    testWidgets('reaching the target does not change it either', (
      tester,
    ) async {
      final rendered = <Set<Color>>[];
      // Below target, then past it — the one state change most likely to
      // tempt a future author into "let it go green".
      for (final temp in [1632, 2100]) {
        await tester.pumpWidget(
          _host(
            ProbeStripRow(
              view: _view(tempF10: temp),
              freshness: ProbeFreshness.live,
              glyph: FoodGlyph.brisket,
            ),
          ),
        );
        rendered.add(_fills(tester, find.byType(FoodAvatar)));
      }
      expect(rendered.first, rendered.last);
      expect(
        rendered.first.any(
          (c) =>
              c.r == StatusPalette.positive.r &&
              c.g == StatusPalette.positive.g &&
              c.b == StatusPalette.positive.b,
        ),
        isFalse,
        reason: 'green is transport health and nothing else',
      );
    });

    testWidgets('a detached probe keeps its identity, in place', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ProbeStripRow(
            view: _view(tempF10: null),
            freshness: ProbeFreshness.live,
            glyph: FoodGlyph.brisket,
          ),
        ),
      );
      // Still there, still brisket — the row dims to 45 %, it does not empty.
      expect(
        tester.widget<FoodAvatar>(find.byType(FoodAvatar)).glyph,
        FoodGlyph.brisket,
      );
      expect(find.text('unplugged'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    test('the widget has no way to be told about state', () {
      // The structural half of the argument: an avatar that cannot see
      // freshness cannot be made to react to it by accident. If this ever
      // needs relaxing, §17.2's permission slip needs rewriting first.
      const avatar = FoodAvatar(glyph: FoodGlyph.beef);
      expect(avatar.glyph, FoodGlyph.beef);
      expect(avatar.size, 34);
    });
  });

  // ── 2. contrast: a fill this size has floors ───────────────────────────

  group('the identity palette is measured', () {
    const card = Color(0xFF161C2A);
    const textHi = Color(0xFFF8FAFC);

    // Both of these collect and then assert, rather than asserting per hue:
    // a retune that breaks three hues should print three lines, not the first
    // one and a re-run.
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

    test('every hue clears 3:1 on `card` — it is a shape, not a wash', () {
      final bad = [
        for (final hue in IdentityPalette.all)
          if (_contrast(hue, card) < 3.0)
            '${hex(hue)} ${_contrast(hue, card).toStringAsFixed(2)}:1',
      ];
      expect(
        bad,
        isEmpty,
        reason: 'these hues disappear into the card they are drawn on',
      );
    });

    test('every hue carries `textHi` at 4.5:1 — the glyph is fine detail', () {
      final bad = [
        for (final hue in IdentityPalette.all)
          if (_contrast(textHi, hue) < 4.5)
            '${hex(hue)} ${_contrast(textHi, hue).toStringAsFixed(2)}:1',
      ];
      expect(
        bad,
        isEmpty,
        reason: 'the glyph inside these is a 20 dp silhouette, not a slab',
      );
    });

    test('no avatar outshouts another', () {
      // The property the two floors above buy, and the one worth defending on
      // its own: a `/cooks` list of ten reads as ten equal marks. A hue two
      // steps brighter than its neighbours would make one cook look important.
      final ls = IdentityPalette.all.map(_luminance).toList()..sort();
      expect(
        (ls.last + 0.05) / (ls.first + 0.05),
        lessThan(1.1),
        reason: 'one identity hue is materially brighter than the rest',
      );
    });

    test('every glyph resolves to a hue in both registers', () {
      for (final g in FoodGlyph.values) {
        expect(IdentityPalette.all, contains(IdentityPalette.of(g)));
        expect(IdentityPalette.allVivid, contains(IdentityPalette.vivid(g)));
        expect(
          IdentityPalette.fill(g, vivid: true),
          IdentityPalette.vivid(g),
        );
        expect(IdentityPalette.fill(g, vivid: false), IdentityPalette.of(g));
      }
    });

    test('identity hues are none of the four series hues', () {
      // The channels must be told apart at a glance, which is most of why the
      // identity set is earthy and the series set is not.
      final series = {for (var p = 1; p <= 4; p++) ProbePalette.hue(p)};
      for (final hue in IdentityPalette.all) {
        expect(series, isNot(contains(hue)));
      }
    });

    test('identity hues are none of the status hues', () {
      final status = {
        StatusPalette.critical,
        StatusPalette.warning,
        StatusPalette.positive,
        StatusPalette.info,
        StatusPalette.pit,
      };
      for (final hue in [...IdentityPalette.all, ...IdentityPalette.allVivid]) {
        expect(status, isNot(contains(hue)));
      }
    });
  });

  // ── §17.5: the rich register, and the moment between the two ───────────

  group('the rich register is legal, and still measured', () {
    const card = Color(0xFF161C2A);
    const textHi = Color(0xFFF8FAFC);
    const bg = Color(0xFF07090E);

    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

    test('every vivid hue carries its glyph at 4.5:1', () {
      // §17.5 relaxes the *rule*, never the legibility floor. The ink is picked
      // per fill, so this checks whichever one the avatar will actually use.
      final bad = [
        for (final hue in IdentityPalette.allVivid)
          if (_contrast(
                IdentityPalette.inkOn(hue, light: textHi, dark: bg),
                hue,
              ) <
              4.5)
            hex(hue),
      ];
      expect(bad, isEmpty);
    });

    test('every vivid hue clears 3:1 on `card`', () {
      final bad = [
        for (final hue in IdentityPalette.allVivid)
          if (_contrast(hue, card) < 3.0) hex(hue),
      ];
      expect(bad, isEmpty);
    });

    test('the rich register picks ONE ink for the whole set', () {
      // Not a contrast requirement — a family requirement. Five circles in a
      // picker with three white glyphs and two black ones reads as a bug, and
      // that is easy to reintroduce by retuning one hue.
      final inks = {
        for (final hue in IdentityPalette.allVivid)
          IdentityPalette.inkOn(hue, light: textHi, dark: bg),
      };
      expect(inks, hasLength(1), reason: 'the vivid set uses mixed glyph ink');
      // …and the disciplined set picks the other one, which is the whole
      // reason the vivid set is allowed to be saturated at all.
      final quiet = {
        for (final hue in IdentityPalette.all)
          IdentityPalette.inkOn(hue, light: textHi, dark: bg),
      };
      expect(quiet, hasLength(1));
      expect(quiet.single, isNot(inks.single));
    });

    test('vivid really is brighter — the registers are visibly apart', () {
      for (final g in FoodGlyph.values) {
        expect(
          _luminance(IdentityPalette.vivid(g)),
          greaterThan(_luminance(IdentityPalette.of(g)) * 1.3),
          reason: '${g.name} barely changes register',
        );
      }
    });

    testWidgets('the reader cools when a jack starts reading', (tester) async {
      // §17.5's designed moment, at the seam it actually happens on. The row
      // is handed `vivid` by the screen, and the screen's rule is "is anything
      // here claiming a temperature".
      Color fillOf() => (tester
                  .widgetList<Container>(
                    find.descendant(
                      of: find.byType(FoodAvatar),
                      matching: find.byType(Container),
                    ),
                  )
                  .first
                  .decoration!
              as BoxDecoration)
          .color!;

      await tester.pumpWidget(
        _host(
          ProbeStripRow(
            view: _view(tempF10: null, targetF10: null),
            freshness: ProbeFreshness.unknown,
            glyph: FoodGlyph.brisket,
            vivid: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fillOf(), IdentityPalette.vivid(FoodGlyph.brisket));

      // A reading lands: same probe, same food, colder screen.
      await tester.pumpWidget(
        _host(
          ProbeStripRow(
            view: _view(),
            freshness: ProbeFreshness.live,
            glyph: FoodGlyph.brisket,
          ),
        ),
      );
      // Mid-tween it is neither endpoint — the step-down is animated, not cut.
      await tester.pump(const Duration(milliseconds: 100));
      final mid = fillOf();
      expect(mid, isNot(IdentityPalette.vivid(FoodGlyph.brisket)));
      expect(mid, isNot(IdentityPalette.of(FoodGlyph.brisket)));

      await tester.pumpAndSettle();
      expect(fillOf(), IdentityPalette.of(FoodGlyph.brisket));
    });
  });

  group('the jack badge numeral is legible on all four jacks', () {
    const bg = Color(0xFF07090E);
    const textHi = Color(0xFFF8FAFC);

    test('the chosen ink clears 4.5:1 on every series hue', () {
      // The measured reason [IdentityPalette.inkOn] exists: near-black fails on
      // slot 3 and white fails on the other three, so neither may be hard-coded.
      for (var jack = 1; jack <= 4; jack++) {
        final hue = ProbePalette.hue(jack);
        final ink = IdentityPalette.inkOn(hue, light: textHi, dark: bg);
        expect(
          _contrast(ink, hue),
          greaterThanOrEqualTo(4.5),
          reason: 'the "$jack" on jack $jack is unreadable',
        );
      }
    });

    testWidgets('and it renders the number, on the jack’s own hue', (
      tester,
    ) async {
      for (var jack = 1; jack <= 4; jack++) {
        await tester.pumpWidget(_host(JackBadge(jack: jack)));
        expect(find.text('$jack'), findsOneWidget);
        final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
        expect(
          (box.decoration as BoxDecoration).color,
          ProbePalette.hue(jack),
        );
      }
    });

    testWidgets('the numeral does not take the OS text scale', (tester) async {
      // A digit doubled inside a fixed 26 dp disc clips rather than informs —
      // the same reasoning §14.5.1 applies to a temperature, applied to a mark.
      final widths = <double>[];
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: _host(const JackBadge(jack: 3)),
          ),
        );
        widths.add(tester.getSize(find.byType(JackBadge)).width);
      }
      expect(widths.first, widths.last);
    });
  });

  // ── 3. coverage: adding a protein must be a red test, not a shrug ──────

  group('the registry covers everything that ships', () {
    test('every HazardClass has a glyph, and only `unstated` is neutral', () {
      for (final h in HazardClass.values) {
        final g = FoodGlyph.forHazard(h);
        expect(
          g.isNeutral,
          h == HazardClass.unstated,
          reason: '${h.name} resolved to ${g.name}',
        );
      }
    });

    test('every shipped preset has a specific glyph', () {
      for (final p in Presets.all) {
        final g = FoodGlyph.forPresetId(p.id);
        expect(g, isNotNull, reason: '${p.id} has no glyph');
        expect(g!.isNeutral, isFalse, reason: '${p.id} fell back to cutlery');
      }
    });

    test('every glyph is drawable — a Material icon or a path', () {
      for (final g in FoodGlyph.values) {
        expect(
          g.icon != null || foodGlyphPath(g) != null,
          isTrue,
          reason: '${g.name} has neither an icon nor geometry',
        );
        expect(g.label, isNotEmpty, reason: 'a shape needs a spoken name');
      }
    });

    test('a name is read most-specific first', () {
      // "Beef ribs" is ribs, not beef — the reason the token table is ordered
      // rather than alphabetical.
      expect(FoodGlyph.forName('Beef ribs'), FoodGlyph.ribs);
      expect(FoodGlyph.forName('Pork ribs'), FoodGlyph.ribs);
      expect(FoodGlyph.forName('Brisket flat'), FoodGlyph.brisket);
      expect(FoodGlyph.forName('Whole turkey'), FoodGlyph.wholeBird);
      expect(FoodGlyph.forName('Chicken thighs'), FoodGlyph.poultry);
      expect(FoodGlyph.forName('Salmon fillet'), FoodGlyph.fish);
      // Ambient before pit: a probe measuring the room must not wear a flame.
      expect(FoodGlyph.forName('Ambient'), FoodGlyph.ambient);
      expect(FoodGlyph.forName('Pit'), FoodGlyph.pit);
      expect(FoodGlyph.forName('Grate temp'), FoodGlyph.pit);
    });

    test('a name that says nothing returns nothing', () {
      // The honest answer, and the reason `forName` is nullable: the app does
      // not know, so it must not invent a cow.
      expect(FoodGlyph.forName('Probe 3'), isNull);
      expect(FoodGlyph.forName(''), isNull);
      expect(FoodGlyph.forName('Left side'), isNull);
    });

    test('a probe resolves role first, then name, then preset, then hazard', () {
      // The pit is never food, whatever the cook is.
      expect(
        FoodGlyph.forProbe(
          role: ProbeRole.pit,
          name: 'Pit',
          presetId: 'beef_brisket',
          hazard: HazardClass.wholeMuscleRedMeat,
        ),
        FoodGlyph.pit,
      );
      // A named jack beats the plan's preset — a four-jack brisket cook must
      // not draw the same avatar four times.
      expect(
        FoodGlyph.forProbe(
          role: ProbeRole.food,
          name: 'Ribs',
          presetId: 'beef_brisket',
        ),
        FoodGlyph.ribs,
      );
      // An unnamed jack takes the cook's preset.
      expect(
        FoodGlyph.forProbe(
          role: ProbeRole.food,
          name: 'Probe 2',
          presetId: 'beef_brisket',
        ),
        FoodGlyph.brisket,
      );
      // Nothing said at all is `unstated`, not a guess.
      expect(
        FoodGlyph.forProbe(role: ProbeRole.food, name: 'Probe 2'),
        FoodGlyph.unstated,
      );
    });

    test('a cook resolves preset first, then name, then hazard', () {
      expect(
        FoodGlyph.forCook(presetId: 'pork_ribs', name: 'Sunday'),
        FoodGlyph.ribs,
      );
      expect(
        FoodGlyph.forCook(name: 'Wings for the game'),
        FoodGlyph.poultry,
      );
      expect(
        FoodGlyph.forCook(hazard: HazardClass.fish),
        FoodGlyph.fish,
      );
      expect(FoodGlyph.forCook(), FoodGlyph.unstated);
    });
  });
}
