/// N16.3 — accessibility.
///
/// Three claims: the temperature readouts carry a spoken label (and an absent
/// probe says "No reading", never "0"); the ink contrasts in all three themes;
/// and the text-scale reflow ladder holds at 200 % — a temperature is never
/// scaled to fit (research notes §9.2).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/temps/temps.dart';

import '../support/load_fonts.dart';

const int _t0ms = 1700000000000;

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUpAll(loadAppFonts);

  group('spoken temperatures (I3)', () {
    late MockBridgeRepository repo;
    late MockPrefsRepository prefs;

    setUp(() {
      repo = MockBridgeRepository(nowMs: _t0ms);
      prefs = MockPrefsRepository();
    });
    tearDown(() async {
      await repo.dispose();
      await prefs.dispose();
    });

    Widget harness(Widget child) => ProviderScope(
      overrides: [
        bridgeRepositoryProvider.overrideWithValue(repo),
        prefsProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        theme: SmokeThemeData.dark(),
        home: Scaffold(body: child),
      ),
    );

    testWidgets('a live probe reads its value and unit', (tester) async {
      await repo.selectScenario('running');
      tester.view
        ..physicalSize = const Size(390, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(const TempsPage()));
      await tester.pumpAndSettle();

      final temp = tester.widget<Text>(
        find.byKey(const ValueKey<String>('temps-temp-1')),
      );
      expect(temp.semanticsLabel, '164.2 degrees Fahrenheit');
    });

    testWidgets('an unplugged probe reads "No reading", never "0"', (
      tester,
    ) async {
      await repo.selectScenario('idle');
      tester.view
        ..physicalSize = const Size(390, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(
          SingleChildScrollView(
            child: ProbeSheetBody(jack: ProbeJack.two, onDone: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final temp = tester.widget<Text>(
        find.byKey(const ValueKey<String>('probe-sheet-temp')),
      );
      expect(temp.semanticsLabel, 'No reading');
      expect(temp.semanticsLabel, isNot(contains('0')));
    });
  });

  group('contrast in all three themes (I14)', () {
    final combos = <String, ThemeData>{
      'dark': SmokeThemeData.dark(),
      'light': SmokeThemeData.light(),
      'daylight': SmokeThemeData.dark(profile: SmokeProfile.daylight),
    };

    for (final combo in combos.entries) {
      test('${combo.key} keeps body ink legible on every surface', () {
        final t = combo.value.extension<SmokeTokens>()!;
        for (final surface in <Color>[t.bg, t.surface, t.card]) {
          expect(
            _contrast(t.textHi, surface),
            greaterThanOrEqualTo(4.5),
            reason: 'textHi on $surface (${combo.key})',
          );
          expect(
            _contrast(t.textBody, surface),
            greaterThanOrEqualTo(4.5),
            reason: 'textBody on $surface (${combo.key})',
          );
        }
        // Small captions still clear the 3:1 non-text/large-text bar.
        expect(
          _contrast(t.textMuted, t.bg),
          greaterThanOrEqualTo(3.0),
          reason: 'textMuted (${combo.key})',
        );
      });
    }
  });

  group('text-scale reflow (N3.10)', () {
    test(
      '200 % demotes the hero and drops the gauge — never shrinks a number',
      () {
        const scale = SmokeTextScale(2.0);
        expect(scale.heroSize, SmokeTextScale.heroDemoted);
        expect(scale.heroSize, lessThan(SmokeTextScale.heroBase));
        expect(scale.gaugeVisible, isFalse);
        expect(scale.heroDemotedNow, isTrue);
      },
    );

    testWidgets('a temperature renders at 200 % without an overflow error', (
      tester,
    ) async {
      final repo = MockBridgeRepository(nowMs: _t0ms);
      final prefs = MockPrefsRepository();
      addTearDown(repo.dispose);
      addTearDown(prefs.dispose);
      await repo.selectScenario('running');

      tester.view
        ..physicalSize = const Size(390, 2000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bridgeRepositoryProvider.overrideWithValue(repo),
            prefsProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            theme: SmokeThemeData.dark(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 2000),
                textScaler: TextScaler.linear(2),
              ),
              child: const Scaffold(body: TempsPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A clipped/overflowing readout throws during layout.
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('temps-temp-1')),
        findsOneWidget,
      );
    });
  });
}
