/// The settings tree is in the design system (newapp §F, §I.1 Phase 5).
///
/// §F names those pages as "the largest visual inconsistency in the app": four
/// files, ~76 Material-default rows, not one token between them. The fix was
/// not to hand-restyle seventy-six widgets but to say what a row *is*, once, in
/// the theme — so what this file pins is that the theme actually says it, and
/// that the daylight profile says it too.
///
/// Pinned here rather than in a golden because a golden proves two builds match
/// each other; these assertions prove the build matches the **token set**,
/// which is the property that was missing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';

void main() {
  for (final (name, theme, tokens) in [
    ('dark', SmokeTheme.dark, SmokeTokens.dark),
    ('daylight', SmokeTheme.daylight, SmokeTokens.daylight),
  ]) {
    group('$name profile', () {
      test('a list row uses the type scale, not Material defaults', () {
        final tile = theme.listTileTheme;
        expect(tile.titleTextStyle?.fontFamily, SmokeType.title.fontFamily);
        expect(tile.titleTextStyle?.color, tokens.textHi);
        expect(
          tile.subtitleTextStyle?.color,
          tokens.textBody,
          reason:
              'a settings subtitle is usually the VALUE — muting it would '
              'make the answer quieter than the question',
        );
      });

      test('a row is a control-radius shape, not a square Material tile', () {
        final shape = theme.listTileTheme.shape;
        expect(shape, isA<RoundedRectangleBorder>());
        expect(
          (shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(SmokeTokens.radiusControl),
        );
      });

      test('form fields are filled insets with the control radius', () {
        final input = theme.inputDecorationTheme;
        expect(input.filled, isTrue);
        expect(input.fillColor, tokens.cardSubtle);
        final border = input.enabledBorder;
        expect(
          border,
          isA<OutlineInputBorder>(),
          reason:
              'Material’s default underline reads as a different app on the '
              'same screen',
        );
        expect(
          (border! as OutlineInputBorder).borderRadius,
          BorderRadius.circular(SmokeTokens.radiusControl),
        );
      });

      test('a switch is chrome in the pit hue, never the positive one', () {
        // Green is transport health. A settings page of green switches would
        // compete with the one chip that means "connected" (§14.6).
        final on = theme.switchTheme.thumbColor?.resolve({
          WidgetState.selected,
        });
        expect(on, StatusPalette.pit);
        expect(on, isNot(StatusPalette.positive));
      });

      test('a disabled switch is chromeDim — present, and visibly inert', () {
        expect(
          theme.switchTheme.thumbColor?.resolve({WidgetState.disabled}),
          tokens.chromeDim,
          reason:
              'a control that cannot work is disabled with its reason, so it '
              'has to LOOK disabled',
        );
      });

      test('segmented buttons use the chip radius and the label scale', () {
        final style = theme.segmentedButtonTheme.style!;
        expect(
          style.textStyle?.resolve({})?.fontFamily,
          SmokeType.labelSm.fontFamily,
        );
        final shape = style.shape?.resolve({});
        expect(
          (shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(SmokeTokens.radiusChip),
        );
      });

      test('sheets and dialogs sit on surface with the card radius', () {
        expect(theme.bottomSheetTheme.backgroundColor, tokens.surface);
        expect(theme.bottomSheetTheme.modalBarrierColor, tokens.scrim);
        expect(theme.dialogTheme.backgroundColor, tokens.surface);
        expect(
          (theme.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(SmokeTokens.radiusCard),
        );
      });

      test('the token extension travels with the theme', () {
        // The whole point of a ThemeExtension: the daylight profile reaches
        // the settings pages without a second styling pass.
        expect(theme.extension<SmokeTokens>(), tokens);
      });
    });
  }

  group('the two profiles differ where §14.3.3 says they should', () {
    test('daylight lifts the ink and kills the glows', () {
      expect(SmokeTokens.daylight.glowsEnabled, isFalse);
      expect(SmokeTokens.daylight.shadowCard, isNull);
      expect(SmokeTokens.dark.glowsEnabled, isTrue);
    });

    test('daylight is NOT a light theme — the surfaces are unchanged', () {
      // A white screen outdoors at night is worse than a high-contrast dark
      // one, and the eye adapts to the field rather than to the page.
      expect(SmokeTokens.daylight.bg, SmokeTokens.dark.bg);
      expect(SmokeTokens.daylight.card, SmokeTokens.dark.card);
      expect(SmokeTheme.daylight.scaffoldBackgroundColor, SmokeTokens.dark.bg);
    });

    test('daylight hairlines are thicker in alpha — thin lines vanish in sun',
        () {
      expect(
        SmokeTokens.daylight.hairline.a,
        greaterThan(SmokeTokens.dark.hairline.a),
      );
    });
  });
}
