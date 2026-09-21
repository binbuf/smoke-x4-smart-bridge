/// N3.12 — food identity discs.
///
/// The catalog uses 18 food identities plus `ambient`, `pit` and `unstated`
/// (the research notes' "13 glyphs" is stale — see `newui/PROGRESS.md` T03).
/// A disc is an **identity** fill: it may be saturated and may carry a word,
/// because it never encodes state. It must not be used to show freshness,
/// alarm severity or transport health.
///
/// Two registers (`components_research_notes.md` §3.7): `vivid` for surfaces
/// where no cook exists yet (onboarding, catalog) and `disciplined` for a
/// running cook, where the disc desaturates so the live board stays
/// ink-and-chrome.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// A food identity.
enum FoodGlyph {
  brisket,
  beef,
  steak,
  pork,
  ribs,
  poultry,
  wholeBird,
  fish,
  shellfish,
  game,
  ground,
  egg,
  veg,
  potato,
  cheese,
  bread,
  fruit,
  side,
  ambient,
  pit,
  unstated;

  /// Parse the catalog's glyph string, falling back to [unstated].
  static FoodGlyph parse(String? value) {
    for (final glyph in FoodGlyph.values) {
      if (glyph.name == value) {
        return glyph;
      }
    }
    return FoodGlyph.unstated;
  }
}

/// How saturated a disc is.
enum FoodAvatarRegister {
  /// For a running cook: ink-and-chrome.
  disciplined,

  /// For onboarding/catalog: warm and saturated.
  vivid,
}

/// The disc size.
enum FoodAvatarSize {
  sm(30, 14),
  md(38, 18),
  lg(52, 26),
  xl(64, 32);

  const FoodAvatarSize(this.diameter, this.fontSize);

  final double diameter;
  final double fontSize;
}

/// A round food-identity disc.
class FoodAvatar extends StatelessWidget {
  const FoodAvatar(
    this.glyph, {
    super.key,
    this.register = FoodAvatarRegister.vivid,
    this.size = FoodAvatarSize.md,
  });

  final FoodGlyph glyph;
  final FoodAvatarRegister register;
  final FoodAvatarSize size;

  static const Map<FoodGlyph, String> _emoji = <FoodGlyph, String>{
    FoodGlyph.brisket: '🥩',
    FoodGlyph.beef: '🥩',
    FoodGlyph.steak: '🥩',
    FoodGlyph.pork: '🍖',
    FoodGlyph.ribs: '🍖',
    FoodGlyph.poultry: '🍗',
    FoodGlyph.wholeBird: '🦃',
    FoodGlyph.fish: '🐟',
    FoodGlyph.shellfish: '🦐',
    FoodGlyph.game: '🦌',
    FoodGlyph.ground: '🍔',
    FoodGlyph.egg: '🥚',
    FoodGlyph.veg: '🥦',
    FoodGlyph.potato: '🥔',
    FoodGlyph.cheese: '🧀',
    FoodGlyph.bread: '🍞',
    FoodGlyph.fruit: '🍑',
    FoodGlyph.side: '🍲',
    FoodGlyph.ambient: '🥔',
    FoodGlyph.pit: '🔥',
    FoodGlyph.unstated: '🍽️',
  };

  static const Map<FoodGlyph, (Color, Color)> _gradient =
      <FoodGlyph, (Color, Color)>{
        FoodGlyph.brisket: (Color(0xFFE4573A), Color(0xFFA73722)),
        FoodGlyph.beef: (Color(0xFFC96A4B), Color(0xFF8C3E28)),
        FoodGlyph.steak: (Color(0xFFE4573A), Color(0xFF9E2F1C)),
        FoodGlyph.pork: (Color(0xFFE86A9B), Color(0xFFA83A63)),
        FoodGlyph.ribs: (Color(0xFFC98552), Color(0xFF8A4F2C)),
        FoodGlyph.poultry: (Color(0xFFE39A3E), Color(0xFFB06A18)),
        FoodGlyph.wholeBird: (Color(0xFFE8CB5C), Color(0xFFB39A2C)),
        FoodGlyph.fish: (Color(0xFF3BB6CE), Color(0xFF1E7C91)),
        FoodGlyph.shellfish: (Color(0xFFF08A5D), Color(0xFFC24E2A)),
        FoodGlyph.game: (Color(0xFFA06A4B), Color(0xFF6E4028)),
        FoodGlyph.ground: (Color(0xFFC98552), Color(0xFF8A4F2C)),
        FoodGlyph.egg: (Color(0xFFE8CB5C), Color(0xFFB39A2C)),
        FoodGlyph.veg: (Color(0xFF6DBE45), Color(0xFF3E8A2A)),
        FoodGlyph.potato: (Color(0xFFC9A86A), Color(0xFF8A6E3A)),
        FoodGlyph.cheese: (Color(0xFFF2C14E), Color(0xFFC8912A)),
        FoodGlyph.bread: (Color(0xFFD8A85E), Color(0xFFA87A34)),
        FoodGlyph.fruit: (Color(0xFFF08A4B), Color(0xFFC25A2A)),
        FoodGlyph.side: (Color(0xFF9AA38A), Color(0xFF66705A)),
        FoodGlyph.ambient: (Color(0xFFA8A093), Color(0xFF6E675C)),
        FoodGlyph.pit: (Color(0xFFFF8A3D), Color(0xFFB23A12)),
        FoodGlyph.unstated: (Color(0xFF5E717E), Color(0xFF3A4750)),
      };

  /// The two gradient stops for this glyph in this register.
  static (Color, Color) stopsFor(FoodGlyph glyph, FoodAvatarRegister register) {
    final vivid = _gradient[glyph]!;
    if (register == FoodAvatarRegister.vivid) {
      return vivid;
    }
    Color desaturate(Color c) => HSLColor.fromColor(c)
        .withSaturation(
          (HSLColor.fromColor(c).saturation * 0.35).clamp(0.0, 1.0),
        )
        .toColor();
    return (desaturate(vivid.$1), desaturate(vivid.$2));
  }

  /// The emoji for this glyph.
  static String emojiFor(FoodGlyph glyph) => _emoji[glyph]!;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final (start, end) = stopsFor(glyph, register);
    return Semantics(
      label: '${glyph.name} food',
      child: Container(
        width: size.diameter,
        height: size.diameter,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[start, end],
          ),
          border: Border.all(color: tokens.tint(tokens.info, 0.18)),
        ),
        child: Text(emojiFor(glyph), style: TextStyle(fontSize: size.fontSize)),
      ),
    );
  }
}
