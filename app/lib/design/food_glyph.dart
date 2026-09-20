/// The **identity channel** — what is cooking, drawn (design 17 §17.2, §17.3 A).
///
/// This file exists because of one sentence of user feedback after a bench
/// session: *"The UI/UX of the app is still extremely poor. Looking nothing like
/// the 3 big apps."* The teardown in §17.1 found the gap is not layout, spacing
/// or copy — it is that **every competitor puts food on the screen and we put
/// none**. A probe here was a coloured rule, a name and a number. That is an
/// instrument panel, and it is why the app read as a lab tool.
///
/// ## Why this is allowed to exist at all
///
/// §16.5 is the app's most-broken rule and the one this codebase defends
/// hardest: a **series hue** is only ever a mark, a **status hue** is only ever
/// chrome with an icon and a word, and green means transport health. A saturated
/// circle with a cow in it looks, at first glance, like exactly the thing those
/// rules forbid.
///
/// It is not, and §17.2 says why: **those rules are about status, and food
/// identity is not status.** They exist so a colour never lies about how the
/// cook is going. A brisket glyph makes no claim about temperature, freshness or
/// link health, so it cannot violate a rule about what a colour *means*. §17.2
/// therefore names a third colour channel alongside series and status:
///
/// | Channel | Carries | May it fill? | May it carry a word? |
/// |---|---|---|---|
/// | Series | which probe | mark only, ≤12 dp, or ≤16 % tint | no |
/// | Status | how it is going | 12–16 % fill, 22–35 % border | with an icon *and* a word |
/// | **Identity** | *what is cooking*, *which jack* | **yes** | yes |
///
/// The invariant that makes it safe is stated here so no future change can lose
/// it: **an identity hue never encodes state.** The same brisket avatar renders
/// whether the cook is perfect or ruined, live or four hours frozen, alarmed or
/// quiet. `test/design/identity_channel_test.dart` pins exactly that.
///
/// ## Vector, never photographic
///
/// TempPro puts a circular *photograph* of the dish on every row. We do not, and
/// §17.4 gives the three reasons: photos need licensing, they blow up the
/// bundle, and they cannot be tinted for the daylight profile. **MEATER's bold
/// animal glyphs are the model** — but drawn as *filled* silhouettes rather than
/// MEATER's line art, because these render at 20–34 dp inside a list row where a
/// 2 dp outline closes up into a blob, while a silhouette stays legible.
///
/// ## Material where Material is good, hand-rolled where it is not
///
/// Five glyphs are Material icons because Material genuinely has them — a
/// burger, an egg, a flame, a thermometer, a fork and knife. Eight are paths in
/// this file because Material has no cow, no pig, no chicken, no fish, no rack
/// of ribs, no brisket and no bone-in steak, and an app about barbecue that
/// draws `restaurant_rounded` for all of them has not done the work.
///
/// Paths are authored in a **0–100 design box** and scaled at paint time, so the
/// same geometry serves a 20 dp compact card and a 44 dp cook-detail header. Eye
/// and nostril holes use [PathFillType.evenOdd]: a single-colour silhouette
/// cannot say "eye" any other way, and it is the eyes that turn a rounded blob
/// into an animal.
library;

import 'package:flutter/material.dart';

import '../domain/entities/entities.dart' show ProbeRole;
import '../domain/plan/hazard.dart';

/// One drawable food identity.
///
/// The set covers every [HazardClass] — including `unstated` and `egg`, both of
/// which were added to the hazard table late and are exactly the cases a glyph
/// registry silently drops — plus the presets §17.3 A names by hand: brisket,
/// pork butt, poultry, steak, fish, ribs, and a pit/ambient mark.
enum FoodGlyph {
  /// Generic red meat: a cow's head. The [HazardClass.wholeMuscleRedMeat]
  /// default, and what a chuck roast or an unnamed beef cut gets.
  beef('beef'),

  /// A sliced slab with its fat cap — the cut this whole product is bought for.
  brisket('brisket'),

  /// Bone-in, the bone on the leading edge. Distinct from [brisket] on purpose:
  /// two slabs of meat that differ only in outline are one glyph, not two.
  steak('steak'),

  /// A pig's head. Covers shoulder, butt and loin — [HazardClass.pork].
  pork('pork'),

  /// A rack, spine and four bones.
  ribs('ribs'),

  /// A chicken's head, comb and wattle — [HazardClass.poultry].
  poultry('poultry'),

  /// A whole roast bird, drumsticks up. The turkey preset, and anything a user
  /// names "whole bird".
  wholeBird('whole bird'),

  /// [HazardClass.fish].
  fish('fish'),

  /// [HazardClass.ground] — Material's burger, which is the honest picture of
  /// the hazard: grinding is what puts the surface on the inside.
  ground('ground meat'),

  /// [HazardClass.egg] — quiche, frittata, strata.
  egg('egg dish'),

  /// The fire, not the food. A pit is the one probe on a cooker that is not
  /// something you eat, and it wears a flame rather than a protein.
  pit('pit'),

  /// The room, not the fire. [ProbeRole.ambient].
  ambient('ambient'),

  /// **Nobody has said what this is.** Not an error and not a placeholder — it
  /// is [HazardClass.unstated], a real answer a user may choose, and the honest
  /// picture of it is cutlery: food, unspecified.
  unstated('food');

  const FoodGlyph(this.label);

  /// Speakable. A shape alone is exactly as bad as a hue alone for a screen
  /// reader (14 §14.10), so every avatar announces this.
  final String label;

  /// The Material icon for the five glyphs Material draws well, or null for the
  /// eight this file draws itself.
  IconData? get icon => switch (this) {
    FoodGlyph.ground => Icons.lunch_dining_rounded,
    FoodGlyph.egg => Icons.egg_alt_rounded,
    FoodGlyph.pit => Icons.local_fire_department_rounded,
    FoodGlyph.ambient => Icons.thermostat_rounded,
    FoodGlyph.unstated => Icons.restaurant_rounded,
    _ => null,
  };

  /// True while nothing has actually been said about this probe or cook.
  ///
  /// Callers use it to decide whether an avatar is worth the space: a fork and
  /// knife on four identical rows is decoration, and this codebase does not
  /// ship decoration.
  bool get isNeutral => this == FoodGlyph.unstated;

  // ── the registry ─────────────────────────────────────────────────────

  /// The glyph a [HazardClass] earns on its own.
  ///
  /// This is the coarse answer — a hazard class knows "pork", never "ribs" — so
  /// [forPresetId] and [forName] are consulted first wherever they have
  /// something to say.
  static FoodGlyph forHazard(HazardClass h) => switch (h) {
    HazardClass.wholeMuscleRedMeat => FoodGlyph.beef,
    HazardClass.poultry => FoodGlyph.poultry,
    HazardClass.ground => FoodGlyph.ground,
    HazardClass.pork => FoodGlyph.pork,
    HazardClass.fish => FoodGlyph.fish,
    HazardClass.egg => FoodGlyph.egg,
    HazardClass.unstated => FoodGlyph.unstated,
  };

  /// The glyph for a preset id from `domain/plan/presets.dart`.
  ///
  /// Written as an explicit table rather than by importing `Presets`, so this
  /// file stays a *values* file with no dependency on the preset library — and
  /// so a new preset is a compile-clean addition that
  /// `test/design/identity_channel_test.dart` catches as a **named** gap rather
  /// than silently drawing cutlery. Unknown ids return null; the caller falls
  /// back to the hazard.
  static FoodGlyph? forPresetId(String? id) => switch (id) {
    'beef_brisket' => FoodGlyph.brisket,
    'beef_ribeye' => FoodGlyph.steak,
    'beef_prime_rib' => FoodGlyph.steak,
    'beef_chuck' => FoodGlyph.beef,
    'beef_burger' => FoodGlyph.ground,
    'pork_butt' => FoodGlyph.pork,
    'pork_ribs' => FoodGlyph.ribs,
    'pork_loin' => FoodGlyph.pork,
    'poultry_whole' => FoodGlyph.wholeBird,
    'poultry_breast' => FoodGlyph.poultry,
    'poultry_thigh' => FoodGlyph.poultry,
    'fish_salmon' => FoodGlyph.fish,
    'egg_bake' => FoodGlyph.egg,
    'egg_casserole' => FoodGlyph.egg,
    _ => null,
  };

  /// The glyph a **name** implies, or null when it implies nothing.
  ///
  /// **This is not the app guessing at a fact.** §16.6 forbids rendering a
  /// default as a device fact, and that rule is about temperatures, modes and
  /// battery levels — things the app must have *read*. A name is something the
  /// user typed, and drawing a brisket beside a probe called "Brisket flat" is a
  /// restatement of their own word, not a claim about what is on the jack. It is
  /// also the only identity available in instrument mode, where there is no cook
  /// and therefore no preset and no hazard.
  ///
  /// Matched on **word boundaries**, most specific first, so "Beef ribs" is ribs
  /// and "Pork ribs" is ribs rather than either being generic meat. Anything
  /// unrecognised — "Probe 3", "Left side", "Jim's" — returns null, and null is
  /// the right answer: the app does not know, and cutlery says so.
  static FoodGlyph? forName(String name) {
    final n = name.toLowerCase();
    bool has(List<String> tokens) =>
        tokens.any((t) => RegExp('\\b${RegExp.escape(t)}\\b').hasMatch(n));

    // Ambient before pit: a probe called "Ambient" is measuring the room, and a
    // flame would say it is measuring the fire.
    if (has(const ['ambient', 'room', 'outside', 'air', 'weather'])) {
      return FoodGlyph.ambient;
    }
    if (has(const [
      'pit',
      'grate',
      'grill',
      'smoker',
      'chamber',
      'dome',
      'oven',
      'cooker',
      'firebox',
    ])) {
      return FoodGlyph.pit;
    }
    if (has(const ['brisket', 'point', 'flat', 'packer'])) {
      return FoodGlyph.brisket;
    }
    if (has(const ['ribs', 'rib', 'spare', 'baby back', 'babyback'])) {
      return FoodGlyph.ribs;
    }
    if (has(const [
      'steak',
      'ribeye',
      'rib-eye',
      'sirloin',
      'filet',
      'fillet steak',
      'tri-tip',
      'tritip',
      'porterhouse',
      't-bone',
      'strip',
      'prime rib',
    ])) {
      return FoodGlyph.steak;
    }
    if (has(const ['whole bird', 'turkey', 'whole chicken', 'spatchcock'])) {
      return FoodGlyph.wholeBird;
    }
    if (has(const [
      'chicken',
      'poultry',
      'duck',
      'bird',
      'wings',
      'wing',
      'thigh',
      'thighs',
      'drumstick',
    ])) {
      return FoodGlyph.poultry;
    }
    if (has(const [
      'pork',
      'butt',
      'shoulder',
      'boston',
      'loin',
      'ham',
      'bacon',
      'belly',
    ])) {
      return FoodGlyph.pork;
    }
    if (has(const [
      'fish',
      'salmon',
      'tuna',
      'trout',
      'cod',
      'halibut',
      'shrimp',
      'prawn',
      'seafood',
    ])) {
      return FoodGlyph.fish;
    }
    if (has(const [
      'burger',
      'burgers',
      'patty',
      'patties',
      'ground',
      'mince',
      'meatloaf',
      'sausage',
    ])) {
      return FoodGlyph.ground;
    }
    if (has(const [
      'egg',
      'eggs',
      'quiche',
      'frittata',
      'strata',
      'casserole',
    ])) {
      return FoodGlyph.egg;
    }
    if (has(const ['beef', 'chuck', 'roast', 'lamb', 'venison', 'game'])) {
      return FoodGlyph.beef;
    }
    return null;
  }

  /// The glyph for one probe, resolving the four sources in order of how much
  /// each actually knows: the **role** first for the two probes that are not
  /// food at all, then the cook's preset, then the per-jack hazard, then the
  /// name the user typed.
  static FoodGlyph forProbe({
    required ProbeRole role,
    required String name,
    String? presetId,
    HazardClass? hazard,
  }) {
    if (role == ProbeRole.pit) {
      return FoodGlyph.pit;
    }
    if (role == ProbeRole.ambient) {
      return FoodGlyph.ambient;
    }
    // A name beats a preset here, and deliberately: a four-jack cook runs one
    // preset across probes the user has named individually ("Point", "Flat",
    // "Ribs"), and taking the preset would draw the same avatar four times.
    return forName(name) ??
        forPresetId(presetId) ??
        (hazard == null ? FoodGlyph.unstated : forHazard(hazard));
  }

  /// The glyph for a whole cook — the `/cooks` row and the detail header.
  ///
  /// Preset first here, because a cook's preset *is* its subject; the name is
  /// the fallback for a cook built by hand ("Wings, Sunday") and the hazard the
  /// fallback after that.
  static FoodGlyph forCook({
    String? presetId,
    HazardClass hazard = HazardClass.unstated,
    String name = '',
  }) =>
      forPresetId(presetId) ??
      forName(name) ??
      forHazard(hazard);
}

/// The identity palette (§17.2, §17.5) — the third channel's hues, in **two
/// registers**.
///
/// **Deliberately not the series palette and not the status palette.** Those two
/// are validated against each other so an alarm can never be mistaken for a
/// chart line; a third set that borrowed from either would undo that in one
/// step. These are *food* colours — smoked brick, ash, ochre — chosen so the
/// channel reads as a different kind of thing at a glance, before any rule is
/// consulted. They are also the one part of this app allowed to look warm.
///
/// ## Two registers, because §17.5 says the rule is proportional
///
/// §16.5's austerity is a guard against exactly one failure: **colour lying
/// about how the cook is going.** That failure needs live state to fail about,
/// so §17.5 makes the discipline scale with the screen:
///
/// | Screen state | Register | Set |
/// |---|---|---|
/// | no session, no live readings — the empty reader, the preset picker, the cook sheet, an empty `/cooks`, anything pre-connection | **rich** | [vivid] |
/// | a cook running, or readings on screen | **strict §16.5** | [of] |
///
/// The two sets are the *same nine families* at two intensities, on purpose:
/// the transition between them has to read as one thing cooling rather than as
/// two unrelated palettes swapping. [FoodAvatar] tweens between them, so a cook
/// starting is a **designed moment** — the screen visibly steps down from
/// *choosing* to *watching*, which is the shift the user is making.
///
/// Two things hold in both registers, and neither is negotiable: the hero
/// temperature is never a hue, and **colour is never the sole carrier of
/// meaning** — every avatar carries a glyph, and every glyph has a spoken
/// [FoodGlyph.label].
///
/// **Grouped by protein family, not by preset.** Nine hues, not thirteen: beef
/// and brisket and steak share a brick, pork and ribs share a mulberry. A
/// palette with a hue per glyph would be a rainbow, and the *glyph* is what
/// names the cut — the hue only has to name the family, which is exactly what a
/// person scanning a list of past cooks is sorting by.
///
/// ### Measured, and the measurement is what makes it a set
///
/// Two floors, both asserted in `test/design/identity_channel_test.dart` rather
/// than claimed here, so a retune is a red test and not a paragraph:
///
///  * **≥3:1 against `card` #161C2A.** The avatar is a graphic, and a graphic
///    that sinks into the card it sits on is not an identity mark;
///  * **≥4.5:1 for `textHi` on the fill.** Strictly this is a graphic too, and
///    WCAG would allow 3:1 — but the glyphs carry interior detail at 20 dp
///    (eyes, nostrils, the grain slits in a brisket), so the text floor is used
///    as a deliberate margin rather than the graphics one.
///
/// Those two bracket the luminance of every hue into **L ∈ 0.135 … 0.173**, and
/// all nine were tuned to land at ≈0.158 — which turns a constraint into the
/// best property this palette has: **no avatar outshouts another.** A list of
/// ten cooks reads as ten equal marks you scan by shape and family, not as one
/// bright yellow row and nine dim ones. It is also why the set is earthy rather
/// than MEATER-vivid: at this luminance a saturated yellow is an ochre and a
/// saturated cyan is a smoked teal, and leaning into that is a better look on
/// obsidian than fighting it.
abstract final class IdentityPalette {
  /// Beef, brisket, steak, and the burger that came off one — smoked brick.
  static const Color brick = Color(0xFFA75A45);

  /// Pork and ribs — mulberry. The pink a pig actually is, at this luminance.
  static const Color mulberry = Color(0xFFA55768);

  /// Poultry and whole birds — ochre. Well clear of `warning` #FAB219, which is
  /// a bright signal yellow; this is what that yellow looks like browned.
  static const Color ochre = Color(0xFF8C6832);

  /// Fish — smoked teal. The one cool food hue; series blue #3987E5 is far more
  /// saturated and twice as bright.
  static const Color teal = Color(0xFF45777E);

  /// Ground meat — umber.
  static const Color umber = Color(0xFF8C674D);

  /// Egg dishes — wheat.
  static const Color wheat = Color(0xFF806D43);

  /// The pit — warm ash. **Neutral on purpose.** The obvious choice is the
  /// brand ember, and it is wrong: `StatusPalette.pit` is the app's one accent,
  /// spent on primary actions and the passkey well, and an ember circle on every
  /// pit row would make the accent mean "pit" instead of "act here".
  static const Color ash = Color(0xFF746E65);

  /// Ambient — cool slate. The room, told apart from the fire.
  static const Color slate = Color(0xFF5E717E);

  /// Nothing stated — stone. Recessive by design: this is the avatar that
  /// should be the least interesting thing on the row.
  static const Color stone = Color(0xFF686F7B);

  /// The fill for a glyph.
  static Color of(FoodGlyph g) => switch (g) {
    FoodGlyph.beef || FoodGlyph.brisket || FoodGlyph.steak => brick,
    FoodGlyph.pork || FoodGlyph.ribs => mulberry,
    FoodGlyph.poultry || FoodGlyph.wholeBird => ochre,
    FoodGlyph.fish => teal,
    FoodGlyph.ground => umber,
    FoodGlyph.egg => wheat,
    FoodGlyph.pit => ash,
    FoodGlyph.ambient => slate,
    FoodGlyph.unstated => stone,
  };

  /// Every disciplined hue, for the contrast test and for a picker that wants
  /// to show the family before the cut.
  static const List<Color> all = [
    brick,
    mulberry,
    ochre,
    teal,
    umber,
    wheat,
    ash,
    slate,
    stone,
  ];

  // ── the rich register (§17.5) ────────────────────────────────────────
  //
  // The same nine families, unmuted. These are what `Meater-1` looks like:
  // saturated circular category marks, big, with the glyph in near-black.
  //
  // **Near-black, not white, and that is what buys the saturation.** The
  // disciplined set is capped at L ≈ 0.158 because a white glyph needs it;
  // inverting the ink inverts the constraint — a fill only has to be *bright*
  // (L ≥ 0.187) for near-black to clear 4.5:1 — and a yellow is finally allowed
  // to be yellow instead of an olive. [FoodAvatar] picks the ink with [inkOn]
  // rather than hard-coding either one, so the same rule serves both registers
  // and a retune cannot quietly ship an unreadable glyph.

  /// Beef, brisket, steak, burgers — paprika.
  static const Color brickVivid = Color(0xFFE4573A);

  /// Pork and ribs.
  static const Color mulberryVivid = Color(0xFFE86A9B);

  /// Poultry and whole birds — golden.
  static const Color ochreVivid = Color(0xFFE39A3E);

  /// Fish.
  static const Color tealVivid = Color(0xFF3BB6CE);

  /// Ground meat — copper.
  static const Color umberVivid = Color(0xFFC98552);

  /// Egg dishes — yolk.
  static const Color wheatVivid = Color(0xFFE8CB5C);

  /// The pit. Still neutral, even rich: a pit is not a category anybody
  /// *chooses*, so it does not compete with the proteins in a picker.
  static const Color ashVivid = Color(0xFFA8A093);

  /// Ambient — sky.
  static const Color slateVivid = Color(0xFF68A9CC);

  /// Nothing stated.
  static const Color stoneVivid = Color(0xFF9AA3B0);

  /// The **rich-register** fill for a glyph (§17.5). Legal only where nothing
  /// on screen is claiming a temperature.
  static Color vivid(FoodGlyph g) => switch (g) {
    FoodGlyph.beef || FoodGlyph.brisket || FoodGlyph.steak => brickVivid,
    FoodGlyph.pork || FoodGlyph.ribs => mulberryVivid,
    FoodGlyph.poultry || FoodGlyph.wholeBird => ochreVivid,
    FoodGlyph.fish => tealVivid,
    FoodGlyph.ground => umberVivid,
    FoodGlyph.egg => wheatVivid,
    FoodGlyph.pit => ashVivid,
    FoodGlyph.ambient => slateVivid,
    FoodGlyph.unstated => stoneVivid,
  };

  static const List<Color> allVivid = [
    brickVivid,
    mulberryVivid,
    ochreVivid,
    tealVivid,
    umberVivid,
    wheatVivid,
    ashVivid,
    slateVivid,
    stoneVivid,
  ];

  /// The fill for [g] in whichever register the surface is in.
  static Color fill(FoodGlyph g, {required bool vivid}) =>
      vivid ? IdentityPalette.vivid(g) : of(g);

  /// Whichever of [light] and [dark] reads better on [fill].
  ///
  /// This exists for the **jack badge** (§17.2's first sanctioned extension of
  /// the series channel), and it is measurement rather than taste. A numeral on
  /// a series hue has no single safe ink: against `bg` the four slots measure
  /// 5.13 / 6.37 / 4.03 / 5.47, and against white 3.88 / 3.13 / 4.94 / 3.64 —
  /// so near-black fails on green and white fails on the other three. Picking
  /// per hue lands every slot at 4.9:1 or better, which is what a 12 pt numeral
  /// needs. Hard-coding either one would ship a badge nobody can read on one
  /// jack in four.
  static Color inkOn(Color fill, {required Color light, required Color dark}) {
    final l = fill.computeLuminance();
    final withDark = (l + 0.05) / (dark.computeLuminance() + 0.05);
    final withLight = (light.computeLuminance() + 0.05) / (l + 0.05);
    return withDark >= withLight ? dark : light;
  }
}

// ── geometry ─────────────────────────────────────────────────────────────────

/// The box every path below is authored in. Scaled at paint time.
const double foodGlyphBox = 100;

/// The filled silhouette for [glyph], in a [foodGlyphBox]-square box.
///
/// Returns null for the glyphs Material already draws — a caller renders
/// [FoodGlyph.icon] instead. Splitting it this way rather than tracing our own
/// burger means the five Material glyphs inherit icon-font hinting and the
/// `--tree-shake-icons` pass, and it keeps this file to the eight shapes that
/// genuinely had to be drawn.
///
/// Fill type is [PathFillType.evenOdd] throughout: the eyes, nostrils and grain
/// slits are *holes*, and a single-colour silhouette has no other way to carry
/// interior detail.
Path? foodGlyphPath(FoodGlyph glyph) => switch (glyph) {
  FoodGlyph.beef => _beef(),
  FoodGlyph.brisket => _brisket(),
  FoodGlyph.steak => _steak(),
  FoodGlyph.pork => _pork(),
  FoodGlyph.ribs => _ribs(),
  FoodGlyph.poultry => _poultry(),
  FoodGlyph.wholeBird => _wholeBird(),
  FoodGlyph.fish => _fish(),
  _ => null,
};

Path _hollow() => Path()..fillType = PathFillType.evenOdd;

void _eye(Path p, double cx, double cy, double r) =>
    p.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));

/// A cow's head: horns out, ears down, muzzle narrowing to a chin.
Path _beef() {
  final p = _hollow();
  // Skull and muzzle.
  p
    ..moveTo(50, 22)
    ..cubicTo(67, 22, 78, 33, 78, 48)
    ..cubicTo(78, 58, 74, 64, 69, 68)
    ..cubicTo(67, 82, 60, 92, 50, 92)
    ..cubicTo(40, 92, 33, 82, 31, 68)
    ..cubicTo(26, 64, 22, 58, 22, 48)
    ..cubicTo(22, 33, 33, 22, 50, 22)
    ..close()
    // Left horn.
    ..moveTo(30, 28)
    ..cubicTo(20, 20, 9, 20, 5, 27)
    ..cubicTo(12, 25, 20, 28, 27, 36)
    ..close()
    // Right horn.
    ..moveTo(70, 28)
    ..cubicTo(80, 20, 91, 20, 95, 27)
    ..cubicTo(88, 25, 80, 28, 73, 36)
    ..close()
    // Left ear.
    ..moveTo(26, 42)
    ..cubicTo(16, 40, 8, 46, 10, 53)
    ..cubicTo(15, 57, 23, 54, 27, 50)
    ..close()
    // Right ear.
    ..moveTo(74, 42)
    ..cubicTo(84, 40, 92, 46, 90, 53)
    ..cubicTo(85, 57, 77, 54, 73, 50)
    ..close();
  _eye(p, 39, 50, 4.2);
  _eye(p, 61, 50, 4.2);
  // Nostrils, which is what makes it a cow rather than a bear.
  p
    ..addOval(Rect.fromLTWH(42, 72, 5, 7))
    ..addOval(Rect.fromLTWH(53, 72, 5, 7));
  return p;
}

/// A sliced packer brisket, seen from the side: thick at the point, tapering to
/// the flat, with three cuts through it.
///
/// **The slits run across the grain, and that is not a detail.** The first
/// version drew them as three *horizontal* bars inside a round slab, which at
/// 26 dp is a speech bubble with text in it — rendered and looked at, which is
/// the only way that gets caught. Vertical cuts through a horizontal wedge read
/// as slices, because that is the direction a brisket is actually carved.
Path _brisket() {
  final p = _hollow();
  p
    ..moveTo(8, 58)
    ..cubicTo(4, 38, 16, 24, 36, 22)
    ..cubicTo(58, 20, 80, 28, 93, 40)
    ..cubicTo(97, 45, 92, 52, 82, 56)
    ..cubicTo(60, 68, 32, 76, 16, 72)
    ..cubicTo(10, 70, 8, 64, 8, 58)
    ..close();
  // Three cuts. They run past the slab at both ends on purpose — even-odd only
  // subtracts where the two overlap, so the slits follow the wedge's own edges
  // instead of needing to be clipped to them by hand.
  for (final x in const [24.0, 40.0, 56.0]) {
    p.addRRect(
      RRect.fromLTRBR(x, 8, x + 5, 88, const Radius.circular(2.5)),
    );
  }
  return p;
}

/// Bone-in, bone leading. The bone is the whole point: it is what tells this
/// apart from [_brisket] at 20 dp.
Path _steak() {
  final p = _hollow();
  p
    // The meat.
    ..moveTo(34, 26)
    ..cubicTo(52, 16, 78, 20, 88, 36)
    ..cubicTo(97, 51, 88, 71, 68, 79)
    ..cubicTo(48, 87, 28, 78, 26, 62)
    ..cubicTo(25, 52, 28, 34, 34, 26)
    ..close()
    // The bone, a T on the leading edge.
    ..moveTo(36, 28)
    ..lineTo(20, 22)
    ..cubicTo(9, 20, 3, 30, 10, 37)
    ..cubicTo(4, 45, 8, 56, 18, 56)
    ..lineTo(34, 52)
    ..cubicTo(30, 44, 31, 34, 36, 28)
    ..close()
    // The eye of fat.
    ..addOval(Rect.fromCircle(center: const Offset(62, 50), radius: 8));
  return p;
}

/// A pig's head. Ears up, snout forward, and the nostrils do the work.
Path _pork() {
  final p = _hollow();
  p
    ..addOval(const Rect.fromLTRB(18, 30, 82, 88))
    // Left ear.
    ..moveTo(24, 40)
    ..lineTo(28, 14)
    ..lineTo(46, 32)
    ..close()
    // Right ear.
    ..moveTo(76, 40)
    ..lineTo(72, 14)
    ..lineTo(54, 32)
    ..close();
  _eye(p, 36, 50, 4.4);
  _eye(p, 64, 50, 4.4);
  // The snout: an outlined disc (a ring cut through the head) with two
  // nostrils inside it. Even-odd nests correctly — ring, then holes back to
  // solid — which is what lets one colour carry three levels of detail.
  p
    ..addOval(Rect.fromCircle(center: const Offset(50, 70), radius: 15))
    ..addOval(Rect.fromCircle(center: const Offset(50, 70), radius: 11.5))
    ..addOval(Rect.fromLTWH(43, 65, 4.5, 9))
    ..addOval(Rect.fromLTWH(52.5, 65, 4.5, 9));
  return p;
}

/// A rack: the spine band, four bones hanging off it.
Path _ribs() {
  final p = _hollow();
  p.addRRect(
    RRect.fromLTRBR(12, 22, 88, 46, const Radius.circular(9)),
  );
  for (var i = 0; i < 4; i++) {
    final x = 17.0 + i * 18.0;
    p.addRRect(
      RRect.fromLTRBR(x, 42, x + 13, 84, const Radius.circular(6.5)),
    );
  }
  // Two slits in the band, so it reads as meat over bone rather than a comb.
  p
    ..addRRect(
      RRect.fromLTRBR(22, 30, 78, 33.5, const Radius.circular(1.8)),
    )
    ..addRRect(
      RRect.fromLTRBR(26, 37, 74, 40.5, const Radius.circular(1.8)),
    );
  return p;
}

/// A chicken's head in profile: comb, beak, wattle.
Path _poultry() {
  final p = _hollow();
  p
    ..addOval(const Rect.fromLTRB(24, 32, 74, 82))
    // Comb — three bumps.
    ..moveTo(34, 36)
    ..cubicTo(33, 24, 43, 22, 45, 30)
    ..cubicTo(47, 20, 57, 21, 57, 31)
    ..cubicTo(60, 23, 68, 26, 66, 36)
    ..close()
    // Beak.
    ..moveTo(70, 50)
    ..lineTo(95, 57)
    ..lineTo(70, 64)
    ..close()
    // Wattle.
    ..addOval(const Rect.fromLTRB(58, 74, 72, 92));
  _eye(p, 58, 48, 4.4);
  return p;
}

/// A drumstick — meat, shaft, knuckle.
///
/// **Not the whole roast bird it started as.** That was an oval with two lumps
/// on top, and at 26 dp it read as a bread roll; rendered side by side with the
/// other twelve it was the only one nobody could name. A drumstick is the
/// universally legible poultry silhouette, and it is unmistakably *not* the
/// chicken's head that [_poultry] draws, which is the distinction this glyph
/// exists to make.
Path _wholeBird() {
  final p = _hollow();
  p
    // The meat: a teardrop leaning into the shaft.
    ..moveTo(14, 44)
    ..cubicTo(9, 23, 28, 7, 48, 12)
    ..cubicTo(67, 17, 73, 39, 60, 53)
    ..cubicTo(49, 64, 22, 62, 14, 44)
    ..close()
    // The shaft: a 12 dp bar down the 45° diagonal.
    ..moveTo(52.2, 47.8)
    ..lineTo(80.2, 73.8)
    ..lineTo(71.8, 82.2)
    ..lineTo(43.8, 56.2)
    ..close()
    // The knuckle: two lobes, which is what says *bone* rather than *stick*.
    ..addOval(Rect.fromCircle(center: const Offset(83, 71), radius: 9.5))
    ..addOval(Rect.fromCircle(center: const Offset(71, 83), radius: 9.5));
  return p;
}

/// A fish: body, forked tail, eye.
Path _fish() {
  final p = _hollow();
  p
    ..moveTo(8, 52)
    ..cubicTo(20, 26, 54, 22, 74, 44)
    ..cubicTo(56, 74, 22, 76, 8, 52)
    ..close()
    // Tail.
    ..moveTo(72, 42)
    ..lineTo(94, 24)
    ..lineTo(90, 50)
    ..lineTo(96, 74)
    ..lineTo(70, 58)
    ..close()
    // Dorsal fin.
    ..moveTo(36, 26)
    ..cubicTo(40, 12, 54, 12, 58, 24)
    ..cubicTo(50, 22, 42, 23, 36, 26)
    ..close();
  _eye(p, 24, 44, 4.4);
  return p;
}
