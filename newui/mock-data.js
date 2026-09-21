/* ============================================================================
 * mock-data.js — Smoke X4 Smart Bridge (new UI prototype)
 * ----------------------------------------------------------------------------
 * Static mock objects for the whole app. Nothing here talks to a real bridge.
 *
 * BUSINESS LOGIC NOTES FOR THE FLUTTER PORT
 * -----------------------------------------
 * This file is the *shape* of the app's data, not a transport. When this is
 * rebuilt in Flutter:
 *   - `MOCK.CATALOG`      -> the preset library (domain/plan/presets.dart)
 *   - `MOCK.TIMELINES`    -> per-cut expected-cook database. Derived from each
 *                            catalog entry's `tl`; synthesized when absent so
 *                            EVERY cut has an expectation. See NOTES.md §4.
 *   - `MOCK.STYLES`       -> cook-style packs (Texas / Kālua / 3-2-1 …). These
 *                            set pit band, wrap, spritz, target and timeline
 *                            together. This is the biggest new content system.
 *   - `MOCK.SCENARIOS`    -> every UI situation the app must handle, including
 *                            the full dual-link connection matrix (BLE + Wi-Fi).
 *   - `MOCK.HISTORY`      -> past cooks (CookAnnotation windows over samples).
 *   - `MOCK.EVENTS`       -> the mock event bus catalogue (dev panel fires them).
 *
 * INVARIANTS CARRIED FROM THE RESEARCH NOTES (do not break these in Flutter):
 *   I1  The bridge is a listener, never a transmitter (only one LoRa ack ever).
 *   I2  The device is authoritative. The app mirrors device alarms; it does not
 *       re-decide them. App-tier alarms are clearly labelled "Insight".
 *   I3  Absent != zero. A detached probe renders as "— / unplugged", never 0.
 *   I4  Never present stale data as current. Derived values (ETA, trend) are
 *       REMOVED when data is stale, not greyed out.
 *   I5  No dead controls. Disabled controls state their reason on screen.
 *   I10 The bridge is the source of truth for what was recorded; the app only
 *       annotates a window over it.
 *   I12 Food safety is a hard gate (targets below a class floor are refused).
 *   I14 One ember primary action per screen.
 * ========================================================================== */

(function () {
  'use strict';

  const F = (v) => v; // identity, documented for clarity: storage is °F

  // ── Catalog ───────────────────────────────────────────────────────────
  // `glyph` drives the placeholder avatar (replaced by real images later).
  // `tl` is the timeline seed for this cut (see normalizeTimeline below).
  //   total  [lo, hi] minutes pre-rest
  //   stall  [minF, maxF, durLo, durHi]
  //   wrap   [tempF, label, note]
  //   spritz minutes between spritzes
  //   turn   { elapsedMin, note } | null
  //   rest   minutes
  //   on     note for the opening phase
  //   pull   note for the pull phase
  // Doneness targets are POST-REST finals; carryover is applied in app.js.
  // Red meat defaults to medium rare per the brief.
  const CATALOG = [
    // ── Beef ───────────────────────────────────────────────────────────
    { id: 'beef_brisket', category: 'Beef', name: 'Texas Brisket', glyph: 'brisket', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [225, 275], blurb: 'Low and slow until the collagen gives.',
      doneness: [ { id: 'sliceable', label: 'Sliceable', targetF: 195 }, { id: 'tender', label: 'Tender', targetF: 201 }, { id: 'shred', label: 'Pitmaster shred', targetF: 203 } ], defaultDoneness: 'tender',
      tl: { total: [600, 840], stall: [150, 170, 120, 240], wrap: [165, 'Wrap in butcher paper', 'The Texas crutch — speeds the stall and protects the bark.'], spritz: 45, rest: 60, on: 'Fat side up, point toward the fire.', pull: 'Butter-smooth in the flat.' } },
    { id: 'beef_ribeye', category: 'Beef', name: 'Ribeye Steak', glyph: 'steak', hazard: 'wholeMuscleRedMeat', thickness: 'thin', pitBand: [200, 250], blurb: 'A whole-muscle cut — cook it to the doneness you like.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 }, { id: 'medwell', label: 'Medium well', targetF: 155 }, { id: 'well', label: 'Well done', targetF: 165 } ], defaultDoneness: 'medrare',
      tl: { total: [12, 20], turn: { elapsedMin: 5, note: 'Flip once for even char.' }, rest: 5, on: 'Hot and fast, then indirect.', pull: 'Pull early — carryover finishes it.' } },
    { id: 'beef_prime_rib', category: 'Beef', name: 'Prime Rib Roast', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [225, 275], blurb: 'Thick roast — it keeps climbing off the heat.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 }, { id: 'medwell', label: 'Medium well', targetF: 155 }, { id: 'well', label: 'Well done', targetF: 165 } ], defaultDoneness: 'medrare',
      tl: { total: [180, 300], stall: [110, 125, 30, 60], spritz: 60, rest: 30, on: 'Low and indirect.', pull: 'Thick roast coasts 5–10°F.' } },
    { id: 'beef_chuck', category: 'Beef', name: 'Chuck Roast', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [250, 275], blurb: 'Braise-tender — treat it like a small brisket.',
      doneness: [ { id: 'sliceable', label: 'Sliceable', targetF: 195 }, { id: 'shred', label: 'Shreddable', targetF: 205 } ], defaultDoneness: 'shred',
      tl: { total: [300, 420], stall: [150, 165, 60, 120], wrap: [165, 'Wrap', 'Foil to braise-tender.'], spritz: 60, rest: 30, on: 'Treat like a small brisket.' } },
    { id: 'beef_burger', category: 'Beef', name: 'Burgers', glyph: 'ground', hazard: 'ground', thickness: 'thin', pitBand: [325, 375], blurb: 'Ground beef finishes at 160°F — grinding mixes bacteria through.',
      doneness: [ { id: 'done', label: 'Done (160°F)', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [8, 14], turn: { elapsedMin: 4, note: 'Flip once.' }, rest: 3, on: 'Hot and fast over high heat.' } },
    { id: 'beef_shortribs', category: 'Beef', name: 'Beef Short Ribs', glyph: 'ribs', hazard: 'wholeMuscleRedMeat', thickness: 'medium', pitBand: [250, 275], blurb: 'Braise-tender, rich and beefy.',
      doneness: [ { id: 'tender', label: 'Probe-tender', targetF: 200 }, { id: 'shred', label: 'Fall-apart', targetF: 205 } ], defaultDoneness: 'tender',
      tl: { total: [300, 420], stall: [150, 165, 60, 120], wrap: [165, 'Wrap', 'Braise until the collagen gives.'], spritz: 60, rest: 20, on: 'Low and slow.' } },
    { id: 'beef_tritip', category: 'Beef', name: 'Tri-Tip', glyph: 'steak', hazard: 'wholeMuscleRedMeat', thickness: 'medium', pitBand: [225, 275], blurb: 'Reverse-sear, then slice across the grain.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ], defaultDoneness: 'medrare',
      tl: { total: [45, 90], turn: { elapsedMin: 20, note: 'Flip at the halfway mark.' }, rest: 10, on: 'Indirect first, then a hard sear.', pull: 'Medium rare, then sear.' } },
    { id: 'beef_flank', category: 'Beef', name: 'Flank Steak', glyph: 'steak', hazard: 'wholeMuscleRedMeat', thickness: 'thin', pitBand: [225, 275], blurb: 'Lean and flat — quick cook, slice thin across the grain.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ], defaultDoneness: 'medrare',
      tl: { total: [15, 30], turn: { elapsedMin: 7, note: 'Flip once.' }, rest: 8, on: 'Hot and fast.' } },
    { id: 'beef_skirt', category: 'Beef', name: 'Skirt Steak', glyph: 'steak', hazard: 'wholeMuscleRedMeat', thickness: 'thin', pitBand: [250, 300], blurb: 'For fajitas — char hard and rest briefly.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ], defaultDoneness: 'medrare',
      tl: { total: [10, 20], turn: { elapsedMin: 5, note: 'Flip once.' }, rest: 5, on: 'Very hot, very quick.' } },
    { id: 'beef_picanha', category: 'Beef', name: 'Picanha', glyph: 'steak', hazard: 'wholeMuscleRedMeat', thickness: 'medium', pitBand: [225, 275], blurb: 'Fat cap up, skewered or roasted, sliced like steak.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ], defaultDoneness: 'medrare',
      tl: { total: [45, 80], turn: { elapsedMin: 20, note: 'Rotate for even fat rendering.' }, rest: 10, on: 'Fat cap up, indirect.' } },
    { id: 'beef_denver', category: 'Beef', name: 'Denver Steak', glyph: 'steak', hazard: 'wholeMuscleRedMeat', thickness: 'thin', pitBand: [300, 350], blurb: 'Well-marbled, quick sear.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ], defaultDoneness: 'medrare',
      tl: { total: [8, 16], turn: { elapsedMin: 4, note: 'Flip once.' }, rest: 5, on: 'Hot and fast.' } },
    { id: 'beef_backribs', category: 'Beef', name: 'Beef Back Ribs', glyph: 'ribs', hazard: 'wholeMuscleRedMeat', thickness: 'thin', pitBand: [250, 275], blurb: 'Less meat than short ribs — smoke and wrap.',
      doneness: [ { id: 'tender', label: 'Probe-tender', targetF: 200 } ], defaultDoneness: 'tender',
      tl: { total: [240, 360], stall: [150, 165, 45, 90], wrap: [165, 'Wrap', 'Tenderness comes from the wrap.'], spritz: 45, rest: 20, on: 'Bone side down.' } },
    { id: 'beef_pastrami', category: 'Beef', name: 'Smoked Pastrami', glyph: 'brisket', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [225, 275], blurb: 'Cured brisket flat, smoked then steamed.',
      doneness: [ { id: 'tender', label: 'Slice-tender', targetF: 203 } ], defaultDoneness: 'tender',
      tl: { total: [480, 720], stall: [150, 170, 90, 180], wrap: [165, 'Wrap & steam', 'Foil with a splash of stock to finish.'], spritz: null, rest: 60, on: 'Rinse the cure, season, and smoke.' } },
    { id: 'beef_meatloaf', category: 'Beef', name: 'Smoked Meatloaf', glyph: 'ground', hazard: 'ground', thickness: 'medium', pitBand: [250, 300], blurb: 'Ground beef floor applies — 160°F.',
      doneness: [ { id: 'done', label: 'Done (160°F)', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [60, 90], rest: 10, on: 'On a rack so the fat drains.' } },
    { id: 'beef_tenderloin', category: 'Beef', name: 'Beef Tenderloin', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [225, 275], blurb: 'Lean and luxurious — do not overshoot.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ], defaultDoneness: 'medrare',
      tl: { total: [45, 75], spritz: null, rest: 20, on: 'Sear, then indirect to finish.', pull: 'Pull early and rest.' } },

    // ── Pork ───────────────────────────────────────────────────────────
    { id: 'pork_butt', category: 'Pork', name: 'Pork Shoulder', glyph: 'pork', hazard: 'pork', thickness: 'thick', pitBand: [225, 275], blurb: 'Boston butt — pull it apart at 201°F.',
      doneness: [ { id: 'sliceable', label: 'Sliceable', targetF: 185 }, { id: 'pulled', label: 'Pulled', targetF: 201 } ], defaultDoneness: 'pulled',
      tl: { total: [480, 720], stall: [150, 170, 120, 240], wrap: [165, 'Wrap in foil', 'The hot-and-fast trick once the bark is set.'], spritz: 60, rest: 60, on: 'Fat cap up.', pull: 'Probe slides in like warm butter.' } },
    { id: 'pork_ribs', category: 'Pork', name: 'Spare Ribs', glyph: 'ribs', hazard: 'pork', thickness: 'thin', pitBand: [225, 275], blurb: 'Bend-test tender — bark set, meat pulled back from the bone.',
      doneness: [ { id: 'tender', label: 'Bite-tender', targetF: 195 }, { id: 'falloff', label: 'Fall-off-bone', targetF: 203 } ], defaultDoneness: 'tender',
      tl: { total: [240, 360], wrap: [165, 'Wrap (3-2-1)', 'Optional: 3h smoke, 2h wrapped, 1h sauced.'], spritz: 45, rest: 15, on: 'Bone side down.' } },
    { id: 'pork_babyback', category: 'Pork', name: 'Baby Back Ribs', glyph: 'ribs', hazard: 'pork', thickness: 'thin', pitBand: [225, 275], blurb: 'Shorter cook, leaner, a touch sweeter.',
      doneness: [ { id: 'tender', label: 'Bite-tender', targetF: 190 }, { id: 'falloff', label: 'Fall-off-bone', targetF: 200 } ], defaultDoneness: 'tender',
      tl: { total: [180, 300], wrap: [165, 'Wrap (2-2-1)', 'Shorter cook than spare ribs.'], spritz: 45, rest: 15, on: 'Bone side down.' } },
    { id: 'pork_loin', category: 'Pork', name: 'Pork Loin', glyph: 'pork', hazard: 'pork', thickness: 'medium', pitBand: [250, 300], blurb: 'A lean cut — pull at 145°F and rest for juicy slices.',
      doneness: [ { id: 'juicy', label: 'Juicy (145°F + rest)', targetF: 145 }, { id: 'well', label: 'Well done', targetF: 160 } ], defaultDoneness: 'juicy',
      tl: { total: [60, 120], spritz: 30, turn: { elapsedMin: 30, note: 'Rotate for even colour.' }, rest: 10, on: 'Lean — do not overcook.' } },
    { id: 'pork_belly', category: 'Pork', name: 'Pork Belly Burnt Ends', glyph: 'pork', hazard: 'pork', thickness: 'medium', pitBand: [250, 275], blurb: 'Cubed, sauced, and back on the heat.',
      doneness: [ { id: 'tender', label: 'Probe-tender', targetF: 200 } ], defaultDoneness: 'tender',
      tl: { total: [150, 210], stall: [150, 165, 30, 60], wrap: [165, 'Wrap', 'Then cube and sauce for burnt ends.'], spritz: 45, rest: 15, on: 'Skin side up.' } },
    { id: 'pork_sausage', category: 'Pork', name: 'Sausages & Brats', glyph: 'ground', hazard: 'ground', thickness: 'thin', pitBand: [225, 275], blurb: 'Indirect heat so the casings do not blow out.',
      doneness: [ { id: 'done', label: 'Done (160°F)', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [45, 90], turn: { elapsedMin: 20, note: 'Roll for even browning.' }, rest: 5, on: 'Indirect to avoid blowout.' } },
    { id: 'pork_chops', category: 'Pork', name: 'Pork Chops', glyph: 'pork', hazard: 'pork', thickness: 'medium', pitBand: [250, 300], blurb: 'Brine, sear, and pull at 145°F.',
      doneness: [ { id: 'juicy', label: 'Juicy (145°F)', targetF: 145 }, { id: 'well', label: 'Well done', targetF: 160 } ], defaultDoneness: 'juicy',
      tl: { total: [20, 40], turn: { elapsedMin: 10, note: 'Flip once.' }, rest: 5, on: 'Hot and fast, then indirect.' } },
    { id: 'pork_tenderloin', category: 'Pork', name: 'Pork Tenderloin', glyph: 'pork', hazard: 'pork', thickness: 'thin', pitBand: [275, 325], blurb: 'Small and lean — fast and easy to overshoot.',
      doneness: [ { id: 'juicy', label: 'Juicy (145°F)', targetF: 145 } ], defaultDoneness: 'juicy',
      tl: { total: [30, 50], turn: { elapsedMin: 15, note: 'Rotate for even colour.' }, rest: 8, on: 'Sear, then indirect.' } },
    { id: 'pork_ham', category: 'Pork', name: 'Smoked Ham', glyph: 'pork', hazard: 'pork', thickness: 'thick', pitBand: [225, 275], blurb: 'Already cured — you are warming and glazing, not cooking through.',
      doneness: [ { id: 'warm', label: 'Warmed (140°F)', targetF: 140 } ], defaultDoneness: 'warm',
      tl: { total: [120, 240], glazee: true, spritz: 30, rest: 20, on: 'Score and glaze every 30 minutes.', pull: 'Warm through, deep mahogany glaze.' } },
    { id: 'pork_char_siu', category: 'Pork', name: 'Char Siu', glyph: 'pork', hazard: 'pork', thickness: 'thin', pitBand: [300, 375], blurb: 'Cantonese BBQ pork — sticky, red, and lacquered.',
      doneness: [ { id: 'done', label: 'Done (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [60, 120], turn: { elapsedMin: 25, note: 'Baste and turn often.' }, rest: 10, on: 'Marinated overnight, basted with honey.' } },
    { id: 'pork_carnitas', category: 'Pork', name: 'Carnitas', glyph: 'pork', hazard: 'pork', thickness: 'medium', pitBand: [250, 300], blurb: 'Citrus-braised pork shoulder, crisped at the end.',
      doneness: [ { id: 'tender', label: 'Shreddable', targetF: 200 } ], defaultDoneness: 'tender',
      tl: { total: [240, 360], stall: [150, 165, 60, 120], wrap: [165, 'Cover / wrap', 'Braise in citrus and lard until shreddable.'], spritz: null, rest: 20, on: 'In a foil pan with orange and onion.' } },
    { id: 'pork_suckling', category: 'Pork', name: 'Suckling Pig', glyph: 'pork', hazard: 'pork', thickness: 'thick', pitBand: [250, 300], blurb: 'Whole pig — skin crackling is the goal.',
      doneness: [ { id: 'done', label: 'Done (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [300, 480], spritz: 30, turn: { elapsedMin: 120, note: 'Rotate for even skin.' }, rest: 45, on: 'Skin dried, then rubbed with oil and salt.' } },

    // ── Poultry ────────────────────────────────────────────────────────
    { id: 'poultry_whole', category: 'Poultry', name: 'Whole Turkey', glyph: 'wholeBird', hazard: 'poultry', thickness: 'thick', pitBand: [275, 325], blurb: 'Breast to 165°F — the safe minimum, and where it eats best.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [150, 240], turn: { elapsedMin: 60, note: 'Rotate for even colour.' }, rest: 20, on: 'Breast side up, indirect.', pull: 'Carryover is never relied on for poultry.' } },
    { id: 'poultry_turkey_breast', category: 'Poultry', name: 'Turkey Breast', glyph: 'wholeBird', hazard: 'poultry', thickness: 'thick', pitBand: [275, 325], blurb: 'The easy bird — uniform and forgiving-ish.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [90, 150], spritz: null, rest: 15, on: 'Skin on, breast up.' } },
    { id: 'poultry_breast', category: 'Poultry', name: 'Chicken Breast', glyph: 'poultry', hazard: 'poultry', thickness: 'thin', pitBand: [325, 375], blurb: 'Pull at 165°F — juicy and safe.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [30, 50], turn: { elapsedMin: 15, note: 'Flip once.' }, rest: 5, on: 'Indirect to keep it juicy.' } },
    { id: 'poultry_thigh', category: 'Poultry', name: 'Chicken Thighs', glyph: 'poultry', hazard: 'poultry', thickness: 'thin', pitBand: [325, 375], blurb: 'Dark meat is best past the minimum — 175–185°F renders it silky.',
      doneness: [ { id: 'safe', label: 'Safe (165°F)', targetF: 165 }, { id: 'silky', label: 'Silky (180°F)', targetF: 180 } ], defaultDoneness: 'silky',
      tl: { total: [45, 75], turn: { elapsedMin: 20, note: 'Flip once.' }, rest: 5, on: 'Dark meat takes the heat well.' } },
    { id: 'poultry_wings', category: 'Poultry', name: 'Chicken Wings', glyph: 'poultry', hazard: 'poultry', thickness: 'thin', pitBand: [325, 400], blurb: 'High heat for crisp skin.',
      doneness: [ { id: 'done', label: 'Done (175°F)', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [45, 75], turn: { elapsedMin: 20, note: 'Flip once.' }, rest: 5, on: 'Hot and indirect.' } },
    { id: 'poultry_spatchcock', category: 'Poultry', name: 'Spatchcock Chicken', glyph: 'poultry', hazard: 'poultry', thickness: 'medium', pitBand: [350, 400], blurb: 'Butterflied for even, fast cooking.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [45, 70], spritz: null, rest: 10, on: 'Backbone removed, pressed flat, skin up.' } },
    { id: 'poultry_beercan', category: 'Poultry', name: 'Beer-Can Chicken', glyph: 'poultry', hazard: 'poultry', thickness: 'medium', pitBand: [325, 375], blurb: 'Upright over a can — crisp skin, steamy interior.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [60, 90], rest: 10, on: 'Sitting on the can, lid down.' } },
    { id: 'poultry_duck', category: 'Poultry', name: 'Whole Duck', glyph: 'wholeBird', hazard: 'poultry', thickness: 'thick', pitBand: [250, 300], blurb: 'Render the fat, crisp the skin, serve medium.',
      doneness: [ { id: 'classic', label: 'Classic (165°F)', targetF: 165 }, { id: 'rose', label: 'Rosé breast (145°F)', targetF: 145 } ], defaultDoneness: 'classic',
      tl: { total: [120, 180], stall: [130, 140, 20, 40], spritz: null, rest: 15, on: 'Prick the skin, start low.' } },
    { id: 'poultry_cornish', category: 'Poultry', name: 'Cornish Hens', glyph: 'wholeBird', hazard: 'poultry', thickness: 'thin', pitBand: [325, 375], blurb: 'Individual birds — fast and impressive.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [50, 80], rest: 10, on: 'Breast side up.' } },
    { id: 'poultry_legs', category: 'Poultry', name: 'Chicken Quarters', glyph: 'poultry', hazard: 'poultry', thickness: 'medium', pitBand: [325, 375], blurb: 'Leg and thigh — forgiving and juicy.',
      doneness: [ { id: 'done', label: 'Done (175°F)', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [60, 90], turn: { elapsedMin: 30, note: 'Flip once.' }, rest: 5, on: 'Skin side up, indirect.' } },

    // ── Seafood ────────────────────────────────────────────────────────
    { id: 'fish_salmon', category: 'Seafood', name: 'Salmon Fillet', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [225, 275], blurb: 'Flakes at 145°F — the safe minimum for fish.',
      doneness: [ { id: 'done', label: 'Flaky (145°F)', targetF: 145 }, { id: 'moist', label: 'Moist centre (125°F)', targetF: 125 } ], defaultDoneness: 'done',
      tl: { total: [30, 60], rest: 5, on: 'Skin side down on a clean grate.' } },
    { id: 'fish_trout', category: 'Seafood', name: 'Whole Trout', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [225, 275], blurb: 'Cooked whole in a basket.',
      doneness: [ { id: 'done', label: 'Flaky (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [25, 45], rest: 5, on: 'In a fish basket so it does not stick.' } },
    { id: 'fish_shrimp', category: 'Seafood', name: 'Shrimp Skewers', glyph: 'shellfish', hazard: 'fish', thickness: 'thin', pitBand: [325, 375], blurb: 'Opaque and pink — about 145°F.',
      doneness: [ { id: 'done', label: 'Opaque (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [10, 20], turn: { elapsedMin: 5, note: 'Turn once.' }, rest: 0, on: 'Skewered, hot and fast.' } },
    { id: 'fish_tuna', category: 'Seafood', name: 'Tuna Steak', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [225, 275], blurb: 'Sear hard, keep the centre rare.',
      doneness: [ { id: 'rare', label: 'Rare (125°F)', targetF: 125 } ], defaultDoneness: 'rare',
      tl: { total: [8, 16], turn: { elapsedMin: 4, note: 'Flip once.' }, rest: 3, on: 'Very hot, very quick.' } },
    { id: 'fish_cod', category: 'Seafood', name: 'Cod Loin', glyph: 'fish', hazard: 'fish', thickness: 'medium', pitBand: [225, 275], blurb: 'Flaky white fish — gentle heat.',
      doneness: [ { id: 'done', label: 'Flaky (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [25, 40], rest: 5, on: 'Butter and lemon, indirect.' } },
    { id: 'fish_halibut', category: 'Seafood', name: 'Halibut', glyph: 'fish', hazard: 'fish', thickness: 'medium', pitBand: [225, 275], blurb: 'Meaty and lean — easy to dry out.',
      doneness: [ { id: 'done', label: 'Flaky (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [25, 45], rest: 5, on: 'Indirect, brushed with oil.' } },
    { id: 'fish_catfish', category: 'Seafood', name: 'Catfish', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [325, 375], blurb: 'Cornmeal crust, hot and fast.',
      doneness: [ { id: 'done', label: 'Flaky (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [15, 25], turn: { elapsedMin: 7, note: 'Flip once.' }, rest: 3, on: 'On a well-oiled grate.' } },
    { id: 'fish_swordfish', category: 'Seafood', name: 'Swordfish', glyph: 'fish', hazard: 'fish', thickness: 'medium', pitBand: [275, 325], blurb: 'Dense and steak-like.',
      doneness: [ { id: 'done', label: 'Done (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [20, 35], turn: { elapsedMin: 10, note: 'Flip once.' }, rest: 5, on: 'Marinated, hot and fast.' } },
    { id: 'fish_scallops', category: 'Seafood', name: 'Scallops', glyph: 'shellfish', hazard: 'fish', thickness: 'thin', pitBand: [375, 425], blurb: 'Sear screaming hot — translucent inside.',
      doneness: [ { id: 'done', label: 'Done (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [6, 12], turn: { elapsedMin: 3, note: 'Flip once, do not move before.' }, rest: 2, on: 'Bone dry, on a very hot grate.' } },
    { id: 'fish_lobster', category: 'Seafood', name: 'Lobster Tails', glyph: 'shellfish', hazard: 'fish', thickness: 'medium', pitBand: [300, 350], blurb: 'Split, buttered, and pulled at 140°F.',
      doneness: [ { id: 'done', label: 'Done (140°F)', targetF: 140 } ], defaultDoneness: 'done',
      tl: { total: [20, 35], rest: 3, on: 'Split shell, butter and herbs.' } },
    { id: 'fish_crab', category: 'Seafood', name: 'Crab Legs', glyph: 'shellfish', hazard: 'fish', thickness: 'thin', pitBand: [300, 350], blurb: 'Warm through — no need to cook.',
      doneness: [ { id: 'warm', label: 'Warmed (140°F)', targetF: 140 } ], defaultDoneness: 'warm',
      tl: { total: [15, 25], rest: 2, on: 'In a foil pan with butter.' } },
    { id: 'fish_oysters', category: 'Seafood', name: 'Smoked Oysters', glyph: 'shellfish', hazard: 'fish', thickness: 'thin', pitBand: [225, 275], blurb: 'On the half shell until the edges curl.',
      doneness: [ { id: 'done', label: 'Curled (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [30, 60], rest: 5, on: 'On the half shell, liquor kept.' } },

    // ── Lamb ───────────────────────────────────────────────────────────
    { id: 'lamb_chops', category: 'Lamb', name: 'Lamb Chops', glyph: 'game', hazard: 'wholeMuscleRedMeat', thickness: 'thin', pitBand: [225, 275], blurb: 'Hot and fast, pull early.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ], defaultDoneness: 'medrare',
      tl: { total: [15, 25], turn: { elapsedMin: 7, note: 'Flip once.' }, rest: 5, on: 'Hot and fast.' } },
    { id: 'lamb_leg', category: 'Lamb', name: 'Leg of Lamb', glyph: 'game', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [225, 275], blurb: 'Roast low, rest long.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ], defaultDoneness: 'medrare',
      tl: { total: [120, 180], stall: [120, 135, 20, 40], spritz: 45, rest: 20, on: 'Indirect, low.' } },
    { id: 'lamb_shoulder', category: 'Lamb', name: 'Lamb Shoulder', glyph: 'game', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [250, 275], blurb: 'Low and slow to pull-apart.',
      doneness: [ { id: 'tender', label: 'Pull-apart', targetF: 200 } ], defaultDoneness: 'tender',
      tl: { total: [300, 420], stall: [150, 165, 60, 120], wrap: [165, 'Wrap', 'Braise to pull-apart.'], spritz: 60, rest: 30, on: 'Low and slow.' } },
    { id: 'lamb_rack', category: 'Lamb', name: 'Rack of Lamb', glyph: 'game', hazard: 'wholeMuscleRedMeat', thickness: 'medium', pitBand: [250, 300], blurb: 'Frenched and roasted — elegant and quick.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ], defaultDoneness: 'medrare',
      tl: { total: [30, 50], rest: 10, on: 'Sear, then indirect.' } },
    { id: 'lamb_shanks', category: 'Lamb', name: 'Lamb Shanks', glyph: 'game', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [250, 275], blurb: 'Fall-off-the-bone braise.',
      doneness: [ { id: 'tender', label: 'Fall-apart', targetF: 200 } ], defaultDoneness: 'tender',
      tl: { total: [180, 300], stall: [150, 165, 45, 90], wrap: [165, 'Braise covered', 'Until the meat releases the bone.'], spritz: null, rest: 20, on: 'In a covered pan with stock.' } },
    { id: 'lamb_kofta', category: 'Lamb', name: 'Lamb Kofta', glyph: 'ground', hazard: 'ground', thickness: 'thin', pitBand: [300, 350], blurb: 'Ground lamb floor applies — 160°F.',
      doneness: [ { id: 'done', label: 'Done (160°F)', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [15, 25], turn: { elapsedMin: 7, note: 'Turn once.' }, rest: 3, on: 'On skewers over direct heat.' } },

    // ── Game ───────────────────────────────────────────────────────────
    { id: 'game_venison', category: 'Game', name: 'Venison Roast', glyph: 'game', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [225, 275], blurb: 'Lean and gamy — do not overcook.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 } ], defaultDoneness: 'medrare',
      tl: { total: [90, 150], spritz: 30, rest: 20, on: 'Wrapped in bacon to protect the lean meat.' } },
    { id: 'game_boar', category: 'Game', name: 'Wild Boar Shoulder', glyph: 'game', hazard: 'pork', thickness: 'thick', pitBand: [225, 275], blurb: 'Treat like pork shoulder — a little leaner.',
      doneness: [ { id: 'pulled', label: 'Pulled', targetF: 200 } ], defaultDoneness: 'pulled',
      tl: { total: [420, 660], stall: [150, 170, 90, 180], wrap: [165, 'Wrap', 'Foil to finish.'], spritz: 60, rest: 45, on: 'Fat side up.' } },
    { id: 'game_bison', category: 'Game', name: 'Bison Ribeye', glyph: 'steak', hazard: 'wholeMuscleRedMeat', thickness: 'thin', pitBand: [225, 275], blurb: 'Leaner than beef — pull a touch earlier.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 120 }, { id: 'medrare', label: 'Medium rare', targetF: 130 }, { id: 'medium', label: 'Medium', targetF: 140 } ], defaultDoneness: 'medrare',
      tl: { total: [12, 22], turn: { elapsedMin: 6, note: 'Flip once.' }, rest: 5, on: 'Hot and fast.' } },
    { id: 'game_rabbit', category: 'Game', name: 'Smoked Rabbit', glyph: 'game', hazard: 'poultry', thickness: 'thin', pitBand: [225, 275], blurb: 'Lean white meat — keep it moist.',
      doneness: [ { id: 'done', label: 'Done (160°F)', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [60, 90], spritz: 20, rest: 10, on: 'Basted often.' } },

    // ── Veggies ────────────────────────────────────────────────────────
    { id: 'veg_potato', category: 'Veggies', name: 'Baked Potatoes', glyph: 'potato', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400], blurb: 'Fork-tender at ~205°F centre.',
      doneness: [ { id: 'soft', label: 'Fork-tender', targetF: 205 } ], defaultDoneness: 'soft',
      tl: { total: [60, 90], rest: 5, on: 'Direct over medium heat.' } },
    { id: 'veg_corn', category: 'Veggies', name: 'Corn on the Cob', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [350, 400], blurb: 'Sweet and charred.',
      doneness: [ { id: 'done', label: 'Charred', targetF: 180 } ], defaultDoneness: 'done',
      tl: { total: [25, 45], turn: { elapsedMin: 15, note: 'Rotate a quarter turn.' }, rest: 0, on: 'Husked or soaked in the husk.' } },
    { id: 'veg_mushrooms', category: 'Veggies', name: 'Smoked Mushrooms', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [225, 275], blurb: 'Soak up the smoke.',
      doneness: [ { id: 'done', label: 'Softened', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [45, 75], turn: { elapsedMin: 20, note: 'Stir once.' }, rest: 0, on: 'In a foil pan with garlic butter.' } },
    { id: 'veg_skewers', category: 'Veggies', name: 'Veggie Skewers', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [325, 375], blurb: 'Charred edges, still crisp.',
      doneness: [ { id: 'done', label: 'Charred', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [25, 45], turn: { elapsedMin: 12, note: 'Turn once.' }, rest: 0, on: 'Oil and season, direct heat.' } },
    { id: 'veg_peppers', category: 'Veggies', name: 'Stuffed Peppers', glyph: 'veg', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400], blurb: 'Fill, smoke, and melt the cheese.',
      doneness: [ { id: 'done', label: 'Softened', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [45, 75], rest: 5, on: 'Halved, seeded, filled.' } },
    { id: 'veg_asparagus', category: 'Veggies', name: 'Grilled Asparagus', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [375, 425], blurb: 'Char, lemon, done.',
      doneness: [ { id: 'done', label: 'Tender-crisp', targetF: 170 } ], defaultDoneness: 'done',
      tl: { total: [8, 15], turn: { elapsedMin: 4, note: 'Roll once.' }, rest: 0, on: 'Oiled, direct heat.' } },
    { id: 'veg_cauli', category: 'Veggies', name: 'Cauliflower Steaks', glyph: 'veg', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400], blurb: 'Thick slabs, deep colour.',
      doneness: [ { id: 'done', label: 'Tender', targetF: 190 } ], defaultDoneness: 'done',
      tl: { total: [30, 50], turn: { elapsedMin: 15, note: 'Flip once.' }, rest: 0, on: 'Brushed with oil, direct.' } },
    { id: 'veg_broccoli', category: 'Veggies', name: 'Smoked Broccoli', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [300, 350], blurb: 'Smoky florets, crisp stems.',
      doneness: [ { id: 'done', label: 'Tender-crisp', targetF: 170 } ], defaultDoneness: 'done',
      tl: { total: [20, 35], rest: 0, on: 'Tossed in oil and garlic.' } },
    { id: 'veg_zucchini', category: 'Veggies', name: 'Grilled Zucchini', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [350, 400], blurb: 'Char without going mushy.',
      doneness: [ { id: 'done', label: 'Tender', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [10, 20], turn: { elapsedMin: 5, note: 'Flip once.' }, rest: 0, on: 'Slices or spears, direct.' } },
    { id: 'veg_tofu', category: 'Veggies', name: 'Smoked Tofu', glyph: 'veg', hazard: 'unstated', thickness: 'medium', pitBand: [250, 300], blurb: 'Pressed, marinated, and smoked.',
      doneness: [ { id: 'done', label: 'Firm & smoky', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [30, 60], turn: { elapsedMin: 20, note: 'Flip once.' }, rest: 0, on: 'Pressed and marinated first.' } },
    { id: 'veg_halloumi', category: 'Veggies', name: 'Grilled Halloumi', glyph: 'cheese', hazard: 'unstated', thickness: 'thin', pitBand: [375, 425], blurb: 'Squeaky, salty, and it will not melt.',
      doneness: [ { id: 'done', label: 'Golden', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [6, 12], turn: { elapsedMin: 3, note: 'Flip once.' }, rest: 0, on: 'Dry, direct, hot.' } },

    // ── Sides & Sauces ─────────────────────────────────────────────────
    { id: 'side_beans', category: 'Sides', name: 'Smoked Baked Beans', glyph: 'side', hazard: 'unstated', thickness: 'medium', pitBand: [225, 275], blurb: 'Under the brisket, catching the drippings.',
      doneness: [ { id: 'done', label: 'Thickened', targetF: 180 } ], defaultDoneness: 'done',
      tl: { total: [90, 150], turn: { elapsedMin: 45, note: 'Stir once.' }, rest: 0, on: 'Under the meat to catch drippings.' } },
    { id: 'side_mac', category: 'Sides', name: 'Smoked Mac & Cheese', glyph: 'cheese', hazard: 'unstated', thickness: 'medium', pitBand: [225, 275], blurb: 'Smoky, gooey, golden top.',
      doneness: [ { id: 'done', label: 'Set', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [60, 90], rest: 10, on: 'In a cast-iron pan.' } },
    { id: 'side_queso', category: 'Sides', name: 'Smoked Queso', glyph: 'cheese', hazard: 'unstated', thickness: 'thin', pitBand: [225, 275], blurb: 'Stir often, keep it smooth.',
      doneness: [ { id: 'done', label: 'Molten', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [45, 75], turn: { elapsedMin: 20, note: 'Stir to keep it smooth.' }, rest: 0, on: 'In a foil pan, stirred.' } },
    { id: 'side_cheese', category: 'Sides', name: 'Smoked Cheese', glyph: 'cheese', hazard: 'unstated', thickness: 'thin', pitBand: [70, 100], blurb: 'Cold smoke — never let it melt.',
      doneness: [ { id: 'done', label: 'Coloured (90°F)', targetF: 90 } ], defaultDoneness: 'done',
      tl: { total: [60, 120], turn: { elapsedMin: 30, note: 'Rotate for even colour.' }, rest: 0, on: 'Cold smoke, very low heat.' } },
    { id: 'side_pineapple', category: 'Sides', name: 'Smoked Pineapple', glyph: 'fruit', hazard: 'unstated', thickness: 'thin', pitBand: [250, 300], blurb: 'Caramelised and juicy — great with pork.',
      doneness: [ { id: 'done', label: 'Caramelised', targetF: 150 } ], defaultDoneness: 'done',
      tl: { total: [45, 90], turn: { elapsedMin: 30, note: 'Turn once.' }, rest: 0, on: 'Spears or rings, direct.' } },
    { id: 'side_peaches', category: 'Sides', name: 'Smoked Peaches', glyph: 'fruit', hazard: 'unstated', thickness: 'thin', pitBand: [225, 275], blurb: 'Halved, honeyed, unforgettable.',
      doneness: [ { id: 'done', label: 'Soft', targetF: 150 } ], defaultDoneness: 'done',
      tl: { total: [30, 60], rest: 0, on: 'Cut side up, drizzled with honey.' } },
    { id: 'side_nuts', category: 'Sides', name: 'Smoked Nuts', glyph: 'side', hazard: 'unstated', thickness: 'thin', pitBand: [225, 275], blurb: 'Buttered and spiced, stirred often.',
      doneness: [ { id: 'done', label: 'Toasted', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [30, 60], turn: { elapsedMin: 15, note: 'Stir often.' }, rest: 0, on: 'In a foil pan with butter.' } },
    { id: 'side_cornbread', category: 'Sides', name: 'Smoked Cornbread', glyph: 'bread', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400], blurb: 'Golden edges, smoky crumb.',
      doneness: [ { id: 'done', label: 'Set (200°F)', targetF: 200 } ], defaultDoneness: 'done',
      tl: { total: [25, 45], rest: 10, on: 'In a hot cast-iron skillet.' } },
    { id: 'side_salsa', category: 'Sides', name: 'Smoked Salsa', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [225, 275], blurb: 'Tomatoes and peppers, then blitz.',
      doneness: [ { id: 'done', label: 'Softened', targetF: 170 } ], defaultDoneness: 'done',
      tl: { total: [45, 75], turn: { elapsedMin: 25, note: 'Turn the vegetables.' }, rest: 0, on: 'Whole vegetables on the grate.' } },

    // ── Misc ───────────────────────────────────────────────────────────
    { id: 'misc_egg_bake', category: 'Misc', name: 'Quiche / Egg Bake', glyph: 'egg', hazard: 'egg', thickness: 'medium', pitBand: [325, 375], blurb: 'Custard set through at 160°F — USDA minimum for egg dishes.',
      doneness: [ { id: 'set', label: 'Set (160°F)', targetF: 160 } ], defaultDoneness: 'set',
      tl: { total: [45, 75], rest: 10, on: 'Water bath or indirect.' } },
    { id: 'misc_casserole', category: 'Misc', name: 'Breakfast Casserole', glyph: 'egg', hazard: 'egg', thickness: 'thick', pitBand: [300, 350], blurb: 'A deep bake — same 160°F, read at the centre.',
      doneness: [ { id: 'set', label: 'Set (160°F)', targetF: 160 } ], defaultDoneness: 'set',
      tl: { total: [60, 90], rest: 10, on: 'Deep pan, indirect.' } },
    { id: 'misc_pizza', category: 'Misc', name: 'Smoked Pizza', glyph: 'bread', hazard: 'unstated', thickness: 'thin', pitBand: [450, 550], blurb: 'Hot stone, fast bake, smoky crust.',
      doneness: [ { id: 'done', label: 'Crisp (205°F)', targetF: 205 } ], defaultDoneness: 'done',
      tl: { total: [8, 15], turn: { elapsedMin: 5, note: 'Rotate for even char.' }, rest: 2, on: 'On a preheated stone.' } },
    { id: 'misc_pretzel', category: 'Misc', name: 'Smoked Pretzels', glyph: 'bread', hazard: 'unstated', thickness: 'thin', pitBand: [225, 275], blurb: 'Buttered snack mix, smoked low.',
      doneness: [ { id: 'done', label: 'Toasted', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [45, 90], turn: { elapsedMin: 20, note: 'Stir every 20 minutes.' }, rest: 0, on: 'In a foil pan with seasoned butter.' } },
    { id: 'misc_jerky', category: 'Misc', name: 'Beef Jerky', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'thin', pitBand: [160, 180], blurb: 'Thin strips, low temp, dry until leathery.',
      doneness: [ { id: 'done', label: 'Dry (160°F)', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [180, 300], turn: { elapsedMin: 60, note: 'Rotate racks.' }, rest: 0, on: 'Marinated strips on racks.' } },
    { id: 'misc_butter', category: 'Misc', name: 'Smoked Butter', glyph: 'side', hazard: 'unstated', thickness: 'thin', pitBand: [180, 225], blurb: 'Cold smoke a block — instant upgrade.',
      doneness: [ { id: 'done', label: 'Smoky (80°F)', targetF: 80 } ], defaultDoneness: 'done',
      tl: { total: [60, 120], rest: 0, on: 'Cold smoke, keep it from melting.' } },
  ];

  const CATEGORIES = ['Beef', 'Pork', 'Poultry', 'Seafood', 'Lamb', 'Game', 'Veggies', 'Sides', 'Misc'];

  // ── Cook-style packs ──────────────────────────────────────────────────
  // Selecting a cut is not enough: "Pork Shoulder" could be Texas pulled
  // pork or Kālua pork. A style sets pit band, wrap, spritz, target and the
  // expected timeline together. [FLUTTER] maps to a preset+style record.
  const STYLES = {
    beef_brisket: [
      { id: 'central_texas', name: 'Central Texas', tagline: 'Salt & pepper, butcher paper', pitBand: [225, 275], targetF: 201, wrap: [165, 'Wrap in butcher paper', 'Protects the bark through the stall.'], spritz: null, restMin: 60, note: 'The benchmark. Fat side up, no mop, paper at the stall.' },
      { id: 'competition', name: 'Competition', tagline: 'Injected, foil at the stall', pitBand: [250, 275], targetF: 203, wrap: [165, 'Foil (Texas crutch)', 'Speeds the cook and keeps it moist.'], spritz: 30, restMin: 90, note: 'Richer, sweeter, faster. Judges love it.' },
      { id: 'hot_fast', name: 'Hot & Fast', tagline: '300°F, smaller cuts', pitBand: [300, 325], targetF: 200, wrap: [165, 'Foil', 'Essential at this temp.'], spritz: 30, restMin: 45, note: 'For when you started late. Still great, less margin.' },
    ],
    pork_butt: [
      { id: 'texas_pulled', name: 'Texas Pulled Pork', tagline: 'Yellow mustard + rub, 250°F', pitBand: [225, 275], targetF: 201, wrap: [165, 'Wrap in foil (optional)', 'Foil for speed; leave open for bark.'], spritz: null, restMin: 60, note: 'Yellow mustard binder, coarse rub, long rest.' },
      { id: 'kalua', name: 'Kālua Pork', tagline: 'Salt + liquid smoke, covered', pitBand: [250, 300], targetF: 200, wrap: [165, 'Cover with foil (or banana leaf)', 'Traditional: leaves, salt, and ti.'], spritz: null, restMin: 45, note: 'Hawaiian-style: sea salt, liquid smoke, covered, shredded with cabbage.' },
      { id: 'carolina', name: 'Carolina', tagline: 'Vinegar mop + pepper', pitBand: [225, 275], targetF: 200, wrap: null, spritz: 45, restMin: 45, note: 'Mop with vinegar and red pepper; serve with a vinegar sauce.' },
      { id: 'cuban_mojo', name: 'Cuban Mojo', tagline: 'Citrus, garlic, oregano', pitBand: [250, 275], targetF: 200, wrap: [170, 'Wrap in foil', 'Finish in its own juices.'], spritz: 45, restMin: 30, note: 'Mojo marinade, then smoke and finish in foil with sour orange.' },
    ],
    pork_ribs: [
      { id: '321', name: '3-2-1 (Spare)', tagline: '3h smoke · 2h wrapped · 1h saucy', pitBand: [225, 250], targetF: 195, wrap: [165, 'Wrap in foil', 'Second act: 2 hours wrapped with a splash.'], spritz: 45, restMin: 15, note: 'The classic. Reliable, tender, saucy.' },
      { id: 'no_wrap', name: 'No-Wrap', tagline: 'Kiss the bone', pitBand: [225, 275], targetF: 195, wrap: null, spritz: 45, restMin: 10, note: 'Firmer bite, better bark, longer cook.' },
    ],
    pork_babyback: [
      { id: '221', name: '2-2-1', tagline: 'Shorter than spare ribs', pitBand: [225, 250], targetF: 190, wrap: [165, 'Wrap in foil', '2 hours wrapped.'], spritz: 45, restMin: 15, note: 'The baby-back standard.' },
      { id: 'no_wrap', name: 'No-Wrap', tagline: 'Crisp bark, bite-tender', pitBand: [250, 275], targetF: 190, wrap: null, spritz: 30, restMin: 10, note: 'For bark purists.' },
    ],
    beef_ribeye: [
      { id: 'reverse_sear', name: 'Reverse Sear', tagline: 'Low, then screaming hot', pitBand: [225, 275], targetF: 135, wrap: null, spritz: null, restMin: 8, note: 'Even edge-to-edge colour with a hard crust.' },
      { id: 'direct', name: 'Direct', tagline: 'Hot and fast', pitBand: [400, 500], targetF: 135, wrap: null, spritz: null, restMin: 5, note: 'Weeknight. Crust first, quick finish.' },
    ],
    beef_tritip: [
      { id: 'california', name: 'Santa Maria', tagline: 'Rub, smoke, sear', pitBand: [225, 275], targetF: 135, wrap: null, spritz: null, restMin: 10, note: 'The California classic: garlic, salt, pepper, red oak if you have it.' },
    ],
    poultry_whole: [
      { id: 'classic_roast', name: 'Classic Roast', tagline: 'Butter under the skin', pitBand: [275, 325], targetF: 165, wrap: null, spritz: null, restMin: 20, note: 'Rub butter under the breast skin.' },
      { id: 'spatchcock', name: 'Spatchcock', tagline: 'Flat and fast', pitBand: [350, 400], targetF: 165, wrap: null, spritz: null, restMin: 10, note: 'Backbone out, pressed flat — cuts the time nearly in half.' },
    ],
    lamb_leg: [
      { id: 'rosemary_garlic', name: 'Rosemary & Garlic', tagline: 'Studded and roasted', pitBand: [225, 275], targetF: 135, wrap: null, spritz: 45, restMin: 20, note: 'Stud with garlic and rosemary.' },
    ],
    fish_salmon: [
      { id: 'cedar', name: 'Cedar Plank', tagline: 'Soaked plank, low heat', pitBand: [225, 275], targetF: 145, wrap: null, spritz: null, restMin: 5, note: 'Soak the plank, smoke low, gentle finish.' },
      { id: 'hot_fast', name: 'Hot & Fast', tagline: 'Skin down, crisp', pitBand: [325, 375], targetF: 145, wrap: null, spritz: null, restMin: 3, note: 'Crisp the skin, keep the centre moist.' },
    ],
  };

  // ── Timeline normalization ────────────────────────────────────────────
  // Builds the canonical expected-cook record from an item's `tl` seed.
  // Absent cuts get a synthesized expectation from category/thickness/pit so
  // EVERY entry in the catalog has a timeline (brief requirement).
  function normalizeTimeline(it) {
    const seed = it.tl || {}, pit = it.pitBand || [225, 275];
    const low = pit[1] <= 300, thick = it.thickness === 'thick', med = it.thickness === 'medium';
    let total, stall = null, spritz = seed.spritz !== undefined ? seed.spritz : null, turn = seed.turn || null, wrap = null, rest = seed.rest !== undefined ? seed.rest : 5;

    if (seed.total) total = seed.total;
    else if (low) total = thick ? [240, 360] : med ? [120, 210] : [60, 120];
    else total = thick ? [90, 150] : med ? [45, 90] : [20, 45];

    if (seed.stall) stall = { minF: seed.stall[0], maxF: seed.stall[1], durationMin: [seed.stall[2], seed.stall[3]] };
    else if (low && thick && total[0] >= 240) stall = { minF: 150, maxF: 165, durationMin: [45, 90] };

    if (seed.wrap) wrap = { tempF: seed.wrap[0], label: seed.wrap[1], note: seed.wrap[2] };
    if (spritz === null && low && (thick || med) && !stall) spritz = 45;

    const phases = seed.phases || buildPhases(it, seed, { stall: stall, wrap: wrap, turn: turn, rest: rest, total: total });
    return { totalMin: total, stall: stall, wrap: wrap, spritzEveryMin: spritz, turn: turn, restMin: rest, phases: phases };
  }

  function buildPhases(it, seed, o) {
    const p = [{ id: 'on', label: 'On the smoker', note: seed.on || 'Set it and watch the numbers.' }];
    if (o.total[1] <= 30) p.push({ id: 'flip', label: 'Flip / turn', note: 'Even cook on both sides.' });
    if (o.stall) p.push({ id: 'stall', label: 'The stall', note: 'Evaporative plateau — normal.' });
    if (o.wrap) p.push({ id: 'wrap', label: o.wrap.label, note: o.wrap.note });
    p.push({ id: 'pull', label: 'Pull', note: seed.pull || 'At target, rest before serving.' });
    if (o.rest > 0) p.push({ id: 'rest', label: 'Rest', note: 'Let carryover finish it.' });
    return p;
  }

  const TIMELINES = {};
  CATALOG.forEach((it) => { TIMELINES[it.id] = normalizeTimeline(it); });

  // ── Connection helpers ────────────────────────────────────────────────
  // The dual-link model: Bluetooth and Wi-Fi are independent links with their
  // own health. `primary` says which one is carrying data right now.
  function link(over) {
    return Object.assign({ available: true, connected: false, bars: null, rssi: null, lastSyncS: null, warm: false }, over || {});
  }
  function connection(over) {
    return Object.assign({
      phase: 'connected',          // connected | connecting | offline | provisioning | rollback | error
      error: null,
      deviceName: 'SmokeBridge-A4F2',
      batteryPct: 71,
      recording: true,
      primary: 'wifi',             // 'bt' | 'wifi'
      bt: link(),
      wifi: link({ mode: 'sta' }), // 'sta' | 'ap' | 'off'
    }, over || {});
  }

  function nowMs() { return Date.now(); }
  const H = 3600 * 1000, M = 60 * 1000;

  // ── Scenarios ─────────────────────────────────────────────────────────
  // Each scenario is a complete UI situation. `probes` are jack-ordered 1..4.
  // Jack 4 defaults to the grate/pit role; every jack can be re-roled.
  const SCENARIOS = {
    running: {
      key: 'running', label: 'Running — Wi-Fi + BLE warm',
      connection: connection({ primary: 'wifi', batteryPct: 71, bt: link({ connected: true, bars: 3, rssi: -62, lastSyncS: 4, warm: true }), wifi: link({ mode: 'sta', connected: true, ssid: 'HomeNet-5G', ip: '192.168.1.42', bars: 4, rssi: -48, lastSyncS: 4 }) }),
      cook: {
        active: true, paused: false, name: 'Sunday Brisket & Ribs', startedAtMs: nowMs() - (4 * H + 12 * M),
        pitBand: [225, 275], grateTargetF: 250, styleId: 'central_texas',
        items: [
          { id: 'beef_brisket', jack: 1, addedAtMs: nowMs() - (4 * H + 12 * M) },
          { id: 'pork_ribs', jack: 2, addedAtMs: nowMs() - (3 * H + 20 * M) },
          { id: 'pork_sausage', jack: 3, addedAtMs: nowMs() - (55 * M) },
        ],
      },
      probes: [
        { jack: 1, role: 'food', attached: true, freshness: 'live', tempF: 164.2, targetF: 201, pullF: 193, trendFPerHr: 0.4, stalled: true, peakF: 164.2, lowF: 58.0, avgF: 128.4, etaMin: null, etaNote: 'No estimate while it is in a stall.', spark: [70, 96, 118, 134, 146, 152, 157, 160, 162, 163, 164, 164.2] },
        { jack: 2, role: 'food', attached: true, freshness: 'live', tempF: 172.4, targetF: 195, pullF: 195, trendFPerHr: 6.2, stalled: false, peakF: 172.4, lowF: 62.0, avgF: 118.7, etaMin: 38, etaNote: '', spark: [60, 88, 110, 126, 138, 148, 155, 161, 166, 169, 171, 172.4] },
        { jack: 3, role: 'food', attached: true, freshness: 'live', tempF: 141.8, targetF: 160, pullF: 160, trendFPerHr: 18.0, stalled: false, peakF: 141.8, lowF: 71.0, avgF: 96.2, etaMin: 11, etaNote: '', spark: [72, 80, 92, 104, 116, 126, 133, 137, 139, 140, 141, 141.8] },
        { jack: 4, role: 'pit', attached: true, freshness: 'live', tempF: 248.6, targetF: 250, pullF: null, trendFPerHr: -4.1, stalled: false, peakF: 261.0, lowF: 238.0, avgF: 249.3, etaMin: null, etaNote: '', spark: [252, 255, 258, 261, 259, 256, 253, 251, 250, 249, 249, 248.6] },
      ],
      alarms: [
        { id: 'pit_crash', tier: 'device', severity: 'critical', rule: 'Pit temperature falling fast', detail: 'Down 18°F in 12 min. Check fuel and vents.', valueF: 248.6, atMs: nowMs() - 3 * M, acked: false, sessionScoped: true, ruleId: 'pit_crash', trigger: 'Fell 18°F in 12 min', suggestion: 'Open a vent or add a lit chimney.' },
        { id: 'eta_soon', tier: 'app', severity: 'info', rule: 'Sausages almost ready', detail: 'ETA about 11 minutes to 160°F.', valueF: 141.8, atMs: nowMs() - 1 * M, acked: false, sessionScoped: true, ruleId: 'eta_soon', trigger: 'Within 15 min of target', suggestion: 'Get the buns and mustard ready.' },
      ],
      marks: [
        { id: 'm1', atMs: nowMs() - (4 * H + 12 * M), kind: 'phase_change', label: 'Cook started', probe: 0 },
        { id: 'm2', atMs: nowMs() - (3 * H + 20 * M), kind: 'note', label: 'Added ribs', probe: 2 },
        { id: 'm3', atMs: nowMs() - (2 * H + 55 * M), kind: 'wrapped', label: 'Wrapped brisket in butcher paper', probe: 1 },
        { id: 'm4', atMs: nowMs() - (2 * H), kind: 'note', label: 'Spritzed ribs', probe: 2 },
        { id: 'm5', atMs: nowMs() - (55 * M), kind: 'note', label: 'Added sausages', probe: 3 },
      ],
    },

    idle: {
      key: 'idle', label: 'Idle — Wi-Fi only, instrument mode',
      connection: connection({ primary: 'wifi', batteryPct: 88, bt: link({ available: true, connected: false, warm: false }), wifi: link({ mode: 'sta', connected: true, ssid: 'HomeNet-5G', ip: '192.168.1.42', bars: 4, rssi: -48, lastSyncS: 2 }) }),
      cook: { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] },
      probes: [
        { jack: 1, role: 'food', attached: true, freshness: 'live', tempF: 68.1, targetF: null, pullF: null, trendFPerHr: -0.2, stalled: false, peakF: 68.1, lowF: 67.9, avgF: 68.0, etaMin: null, etaNote: '', spark: [68, 68.1, 68.2, 68.1, 68.0, 68.1, 68.1, 68.1, 68.2, 68.1, 68.1, 68.1] },
        { jack: 2, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
        { jack: 3, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
        { jack: 4, role: 'pit', attached: true, freshness: 'live', tempF: 92.4, targetF: null, pullF: null, trendFPerHr: 24.0, stalled: false, peakF: 92.4, lowF: 74.0, avgF: 83.0, etaMin: null, etaNote: '', spark: [74, 76, 79, 82, 85, 88, 90, 91, 92, 92.2, 92.3, 92.4] },
      ],
      alarms: [], marks: [],
    },

    existing: {
      key: 'existing', label: 'Bridge has a session already running (BLE)',
      connection: connection({ primary: 'bt', batteryPct: 64, bt: link({ connected: true, bars: 2, rssi: -74, lastSyncS: 7, warm: false }), wifi: link({ mode: 'off', connected: false }) }),
      cook: { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] },
      probes: [
        { jack: 1, role: 'food', attached: true, freshness: 'live', tempF: 158.0, targetF: null, pullF: null, trendFPerHr: 1.1, stalled: true, peakF: 158.0, lowF: 61.0, avgF: 121.0, etaMin: null, etaNote: '', spark: [61, 92, 118, 138, 149, 154, 156, 157, 157.5, 157.8, 157.9, 158.0] },
        { jack: 2, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
        { jack: 3, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
        { jack: 4, role: 'pit', attached: true, freshness: 'live', tempF: 243.0, targetF: null, pullF: null, trendFPerHr: -2.0, stalled: false, peakF: 258.0, lowF: 231.0, avgF: 246.0, etaMin: null, etaNote: '', spark: [231, 240, 248, 255, 258, 256, 252, 249, 246, 244, 243.5, 243.0] },
      ],
      alarms: [], marks: [],
      pendingSession: { sessionId: 'SMK-4471', startedAtMs: nowMs() - (2 * H + 5 * M), samples: 253, probeCount: 2, attachedJacks: [1, 4] },
    },

    offline: {
      key: 'offline', label: 'Unreachable — stale data',
      connection: connection({ phase: 'offline', primary: null, batteryPct: null, recording: true, bt: link({ connected: false, bars: 0, lastSyncS: 742 }), wifi: link({ mode: 'sta', connected: false, ssid: 'HomeNet-5G', bars: 0, lastSyncS: 742 }) }),
      cook: {
        active: true, paused: false, name: 'Sunday Brisket & Ribs', startedAtMs: nowMs() - (4 * H + 30 * M), pitBand: [225, 275], grateTargetF: 250,
        items: [
          { id: 'beef_brisket', jack: 1, addedAtMs: nowMs() - (4 * H + 30 * M) },
          { id: 'pork_ribs', jack: 2, addedAtMs: nowMs() - (3 * H + 40 * M) },
        ],
      },
      probes: [
        { jack: 1, role: 'food', attached: true, freshness: 'frozen', tempF: 176.3, targetF: 201, pullF: 193, trendFPerHr: null, stalled: false, peakF: 176.3, lowF: 58.0, avgF: 130.0, etaMin: null, etaNote: '', spark: [70, 100, 124, 142, 155, 164, 170, 174, 175, 176, 176.2, 176.3] },
        { jack: 2, role: 'food', attached: true, freshness: 'frozen', tempF: 181.0, targetF: 195, pullF: 195, trendFPerHr: null, stalled: false, peakF: 181.0, lowF: 62.0, avgF: 120.0, etaMin: null, etaNote: '', spark: [62, 90, 112, 130, 145, 158, 168, 175, 178, 180, 180.5, 181.0] },
        { jack: 3, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
        { jack: 4, role: 'pit', attached: true, freshness: 'frozen', tempF: 251.0, targetF: 250, pullF: null, trendFPerHr: null, stalled: false, peakF: 261.0, lowF: 238.0, avgF: 249.0, etaMin: null, etaNote: '', spark: [252, 255, 258, 261, 259, 256, 253, 251, 250, 249, 249, 251] },
      ],
      alarms: [
        { id: 'bridge_unreachable', tier: 'app', severity: 'warning', rule: 'Bridge unreachable', detail: 'No data for 12 minutes. The bridge is still recording — the gap will fill when it reconnects.', valueF: null, atMs: nowMs() - 12 * M, acked: false, sessionScoped: false, ruleId: 'bridge_unreachable', trigger: 'No packet for 12 min', suggestion: 'Move closer, or re-sync when you can.' },
      ],
      marks: [
        { id: 'm1', atMs: nowMs() - (4 * H + 30 * M), kind: 'phase_change', label: 'Cook started', probe: 0 },
        { id: 'm2', atMs: nowMs() - (3 * H + 40 * M), kind: 'note', label: 'Added ribs', probe: 2 },
        { id: 'm3', atMs: nowMs() - (3 * H), kind: 'wrapped', label: 'Wrapped brisket in butcher paper', probe: 1 },
      ],
    },

    // ── Connection-matrix scenarios (fire from the dev panel) ──────────
    bt_only: {
      key: 'bt_only', label: 'Bluetooth only — no Wi-Fi configured',
      connection: connection({ primary: 'bt', batteryPct: 82, bt: link({ connected: true, bars: 3, rssi: -60, lastSyncS: 3, warm: true }), wifi: link({ mode: 'off', connected: false }) }),
      cook: { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] },
      probes: [
        { jack: 1, role: 'food', attached: true, freshness: 'live', tempF: 22.4, targetF: null, pullF: null, trendFPerHr: 0, stalled: false, peakF: 22.4, lowF: 22.0, avgF: 22.2, etaMin: null, etaNote: '', spark: [22, 22, 22.1, 22.2, 22.3, 22.4, 22.4, 22.4, 22.4, 22.4, 22.4, 22.4] },
        { jack: 2, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
        { jack: 3, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
        { jack: 4, role: 'pit', attached: true, freshness: 'live', tempF: 23.0, targetF: null, pullF: null, trendFPerHr: 0, stalled: false, peakF: 23.2, lowF: 22.8, avgF: 23.0, etaMin: null, etaNote: '', spark: [23, 23, 23.1, 23, 22.9, 23, 23, 23.1, 23, 23, 23, 23] },
      ],
      alarms: [], marks: [],
    },

    sta_connecting: {
      key: 'sta_connecting', label: 'Joining home Wi-Fi (connecting…)',
      connection: connection({ phase: 'connecting', primary: null, batteryPct: 82, bt: link({ connected: true, bars: 3, rssi: -60, lastSyncS: 3, warm: true }), wifi: link({ mode: 'sta', connected: false, ssid: 'HomeNet-5G', bars: null, rssi: null, lastSyncS: null }) }),
      cook: { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] },
      probes: freshProbes(), alarms: [], marks: [],
    },
    sta_wrong_password: {
      key: 'sta_wrong_password', label: 'Wi-Fi: wrong password',
      connection: connection({ phase: 'error', error: 'wrong_password', primary: 'bt', batteryPct: 82, bt: link({ connected: true, bars: 3, rssi: -60, lastSyncS: 3, warm: true }), wifi: link({ mode: 'sta', connected: false, ssid: 'HomeNet-5G', bars: null, rssi: null, lastSyncS: null }) }),
      cook: { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] },
      probes: freshProbes(), alarms: [], marks: [],
    },
    sta_router_unreachable: {
      key: 'sta_router_unreachable', label: 'Wi-Fi: router unreachable',
      connection: connection({ phase: 'error', error: 'router_unreachable', primary: 'bt', batteryPct: 82, bt: link({ connected: true, bars: 3, rssi: -60, lastSyncS: 3, warm: true }), wifi: link({ mode: 'sta', connected: false, ssid: 'HomeNet-5G', bars: 0, rssi: -92, lastSyncS: null }) }),
      cook: { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] },
      probes: freshProbes(), alarms: [], marks: [],
    },
    ap_broadcasting: {
      key: 'ap_broadcasting', label: 'Bridge hotspot — waiting for phone',
      connection: connection({ phase: 'provisioning', primary: 'bt', batteryPct: 82, bt: link({ connected: true, bars: 3, rssi: -60, lastSyncS: 3, warm: true }), wifi: link({ mode: 'ap', connected: false, ssid: 'SmokeBridge-A4F2', passkey: 'smoke-4471', bars: null, lastSyncS: null }) }),
      cook: { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] },
      probes: freshProbes(), alarms: [], marks: [],
    },
    ap_joined: {
      key: 'ap_joined', label: 'Bridge hotspot — phone joined',
      connection: connection({ phase: 'connected', primary: 'wifi', batteryPct: 82, bt: link({ connected: true, bars: 3, rssi: -60, lastSyncS: 3, warm: true }), wifi: link({ mode: 'ap', connected: true, ssid: 'SmokeBridge-A4F2', passkey: 'smoke-4471', ip: '192.168.4.1', bars: 4, rssi: -40, lastSyncS: 1 }) }),
      cook: { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] },
      probes: freshProbes(), alarms: [], marks: [],
    },
    switch_rollback: {
      key: 'switch_rollback', label: 'Mode switch failed — rolled back to BLE',
      connection: connection({ phase: 'rollback', primary: 'bt', batteryPct: 82, bt: link({ connected: true, bars: 3, rssi: -60, lastSyncS: 3, warm: true }), wifi: link({ mode: 'off', connected: false }) }),
      cook: { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] },
      probes: freshProbes(), alarms: [], marks: [], notice: 'The bridge could not join that network, so it kept Bluetooth. Nothing was lost.' ,
    },
  };

  // A neutral 4-probe set for connection-matrix scenarios.
  function freshProbes() {
    return [
      { jack: 1, role: 'food', attached: true, freshness: 'live', tempF: 68.0, targetF: null, pullF: null, trendFPerHr: 0, stalled: false, peakF: 68, lowF: 67.8, avgF: 67.9, etaMin: null, etaNote: '', spark: [68, 68, 68.1, 68, 68, 68, 68, 68, 68, 68, 68, 68] },
      { jack: 2, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
      { jack: 3, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
      { jack: 4, role: 'pit', attached: true, freshness: 'live', tempF: 92.0, targetF: null, pullF: null, trendFPerHr: 24, stalled: false, peakF: 92, lowF: 74, avgF: 83, etaMin: null, etaNote: '', spark: [74, 76, 79, 82, 85, 88, 90, 91, 92, 92, 92, 92] },
    ];
  }

  // ── Past cooks (history) ──────────────────────────────────────────────
  const HISTORY = [
    { id: 'c1', name: 'Labor Day Pulled Pork', presetId: 'pork_butt', styleId: 'texas_pulled', glyph: 'pork', jack: 1, startedAtMs: nowMs() - 6 * 24 * H, durationMin: 612, plannedMin: 600, peakF: 203.1, targetF: 201, favourite: true, notes: 'Wrapped at 165°F. Best bark yet.', marks: 5, rating: 5, status: 'done', photos: 2, stalledMin: 155, wrapAtF: 165 },
    { id: 'c2', name: 'Weeknight Ribeyes', presetId: 'beef_ribeye', styleId: 'reverse_sear', glyph: 'steak', jack: 1, startedAtMs: nowMs() - 4 * 24 * H, durationMin: 18, plannedMin: 16, peakF: 137.0, targetF: 135, favourite: false, notes: 'Two minutes a side, then indirect.', marks: 2, rating: 4, status: 'done', photos: 0, stalledMin: 0, wrapAtF: null },
    { id: 'c3', name: 'Whole Turkey Trial', presetId: 'poultry_whole', styleId: 'classic_roast', glyph: 'wholeBird', jack: 1, startedAtMs: nowMs() - 3 * 24 * H, durationMin: 214, plannedMin: 195, peakF: 165.2, targetF: 165, favourite: false, notes: 'Breast hit 165 first; thighs lagged 20 min.', marks: 3, rating: 3, status: 'done', photos: 1, stalledMin: 0, wrapAtF: null },
    { id: 'c4', name: 'Sunday Brisket & Ribs', presetId: 'beef_brisket', styleId: 'central_texas', glyph: 'brisket', jack: 1, startedAtMs: nowMs() - 1 * 24 * H, durationMin: 498, plannedMin: 480, peakF: 202.6, targetF: 201, favourite: true, notes: 'Stalled 2h 40m. Wrapped in paper.', marks: 7, rating: 5, status: 'done', photos: 3, stalledMin: 160, wrapAtF: 165 },
    { id: 'c5', name: 'Salmon on a Plank', presetId: 'fish_salmon', styleId: 'cedar', glyph: 'fish', jack: 2, startedAtMs: nowMs() - 9 * 24 * H, durationMin: 41, plannedMin: 45, peakF: 145.4, targetF: 145, favourite: false, notes: 'Cedar plank, 275°F.', marks: 2, rating: 4, status: 'done', photos: 1, stalledMin: 0, wrapAtF: null },
    { id: 'c6', name: 'Memorial Day Brisket', presetId: 'beef_brisket', styleId: 'competition', glyph: 'brisket', jack: 1, startedAtMs: nowMs() - 40 * 24 * H, durationMin: 731, plannedMin: 720, peakF: 204.0, targetF: 203, favourite: true, notes: 'Overnight cook. Held 4h in a cooler.', marks: 9, rating: 5, status: 'done', photos: 4, stalledMin: 175, wrapAtF: 165 },
    { id: 'c7', name: 'Kālua Pork Night', presetId: 'pork_butt', styleId: 'kalua', glyph: 'pork', jack: 1, startedAtMs: nowMs() - 22 * 24 * H, durationMin: 540, plannedMin: 540, peakF: 201.5, targetF: 200, favourite: false, notes: 'Covered with banana leaf and salt.', marks: 4, rating: 4, status: 'done', photos: 2, stalledMin: 120, wrapAtF: 165 },
  ];

  // ── Device / connection modes ─────────────────────────────────────────
  const MODES = [
    {
      id: 'ble', icon: 'bluetooth', name: 'Bluetooth', tagline: 'Direct to the bridge',
      summary: 'The simplest link. Works anywhere near the bridge, needs no network, and uses the least bridge power.',
      good: ['Works with no Wi-Fi at all', 'Lowest bridge power draw', 'Setup and mode changes always work here'],
      limited: ['No full history download', 'No probe naming or alarm-rule editing', 'Shorter range than Wi-Fi'],
      capability: { live: true, preview: true, fullHistory: false, config: true, rules: false, ota: false },
      requiresWifiCreds: false,
    },
    {
      id: 'ap', icon: 'wifi', name: 'Bridge Wi-Fi (its own hotspot)', tagline: 'The bridge hosts the network',
      summary: 'The bridge broadcasts its own Wi-Fi. Your phone joins it directly. Full features, no home network needed.',
      good: ['Every feature, including full history', 'No router or home network required', 'Strong, dedicated link'],
      limited: ['Your phone leaves your normal Wi-Fi while connected', 'Some phones warn about “no internet”'],
      capability: { live: true, preview: true, fullHistory: true, config: true, rules: true, ota: true },
      requiresWifiCreds: false,
    },
    {
      id: 'sta', icon: 'router', name: 'Your Wi-Fi', tagline: 'The bridge joins your network',
      summary: 'The bridge joins your home Wi-Fi. Your phone stays on its normal network and reaches the bridge from anywhere in range.',
      good: ['Phone keeps internet and other apps', 'Reach the bridge anywhere on your network', 'Lowest power draw over time'],
      limited: ['Needs your Wi-Fi name and password', 'Depends on your router’s range and reliability'],
      capability: { live: true, preview: true, fullHistory: true, config: true, rules: true, ota: true },
      requiresWifiCreds: true,
    },
  ];

  // ── Alarm rules (device tier + app insight tier) ──────────────────────
  const ALARM_RULES = [
    { id: 'target_reached', tier: 'device', name: 'Target reached', desc: 'Food crosses its target going up.', severity: 'critical', enabled: true, scoped: 'per probe', windowS: null },
    { id: 'smoke_x_alarm', tier: 'device', name: 'Base station alarm', desc: 'Mirrors the Smoke X4’s own alarm.', severity: 'critical', enabled: true, scoped: 'per probe', windowS: null },
    { id: 'pit_out_of_band', tier: 'device', name: 'Pit out of band', desc: 'Grate temp leaves your pit band.', severity: 'warning', enabled: true, scoped: 'pit', windowS: 600 },
    { id: 'pit_crash', tier: 'device', name: 'Pit crash', desc: 'Pit falls fast below target.', severity: 'critical', enabled: true, scoped: 'pit', windowS: 600 },
    { id: 'probe_detached', tier: 'device', name: 'Probe detached', desc: 'A probe is unplugged or out of range.', severity: 'warning', enabled: true, scoped: 'per probe', windowS: null },
    { id: 'base_lost', tier: 'device', name: 'Base station lost', desc: 'No packet from the Smoke X4.', severity: 'warning', enabled: true, scoped: 'cook', windowS: 600 },
    { id: 'battery_low', tier: 'device', name: 'Battery low', desc: 'Bridge battery warning then critical.', severity: 'warning', enabled: true, scoped: 'device', windowS: null },
    { id: 'storage_low', tier: 'device', name: 'Storage low', desc: 'Little flash left for recording.', severity: 'warning', enabled: true, scoped: 'device', windowS: null },
    { id: 'system_fault', tier: 'device', name: 'System fault', desc: 'Crash dump or failed update.', severity: 'warning', enabled: true, scoped: 'device', windowS: null },
    { id: 'eta_soon', tier: 'app', name: 'ETA soon', desc: 'Insight: a probe is close to target.', severity: 'info', enabled: true, scoped: 'per probe', windowS: null },
    { id: 'stall', tier: 'app', name: 'Stall detected', desc: 'Insight: the meat has plateaued.', severity: 'info', enabled: true, scoped: 'per probe', windowS: null },
    { id: 'bridge_unreachable', tier: 'app', name: 'Bridge unreachable', desc: 'Insight: the app lost the link.', severity: 'warning', enabled: true, scoped: 'device', windowS: null },
  ];

  // ── Mock event bus catalogue ──────────────────────────────────────────
  // The dev panel fires these on window; app.js listens and mutates a scenario
  // so every connection / alarm state can be exercised without a bridge.
  const EVENTS = [
    { id: 'ble-connected', label: 'BLE connected', hint: 'Phone pairs to the bridge over Bluetooth.' },
    { id: 'ble-dropped', label: 'BLE dropped', hint: 'Bluetooth link lost; Wi-Fi may carry on.' },
    { id: 'wifi-connecting', label: 'Wi-Fi connecting', hint: 'Bridge is joining a home network.' },
    { id: 'wifi-wrong-password', label: 'Wi-Fi wrong password', hint: 'Bridge rejects the credential.' },
    { id: 'wifi-router-unreachable', label: 'Router unreachable', hint: 'Credential right, router not reachable.' },
    { id: 'wifi-connected', label: 'Wi-Fi connected', hint: 'Bridge joins home Wi-Fi; BLE goes warm.' },
    { id: 'ap-broadcasting', label: 'Hotspot broadcasting', hint: 'Bridge starts its own access point.' },
    { id: 'ap-joined', label: 'Phone joined hotspot', hint: 'Phone joins the bridge access point.' },
    { id: 'switch-rollback', label: 'Switch rollback', hint: 'Mode change fails; old link restored.' },
    { id: 'resync-complete', label: 'Re-sync complete', hint: 'High-water mark synced; fresh data.' },
    { id: 'alarm-target', label: 'Alarm: target reached', hint: 'Fire a device target alarm.' },
    { id: 'alarm-pit-crash', label: 'Alarm: pit crash', hint: 'Fire a device pit-crash alarm.' },
  ];

  // ── Exposed model ─────────────────────────────────────────────────────
  window.MOCK = {
    F, TIMELINES, CATALOG, CATEGORIES, STYLES, SCENARIOS, HISTORY, MODES, ALARM_RULES, EVENTS,
    defaultScenario: 'running',
    settings: {
      units: 'F',               // 'F' | 'C'  (display only; data stays °F)
      themeMode: 'system',      // 'system' | 'light' | 'dark'
      displayProfile: 'standard', // 'standard' | 'daylight' (high contrast)
      density: 'compact',       // 'comfortable' | 'compact'
      reducedMotion: false,
      preferManualAlarm: false, // user's own alarm wins over device rules
      quietHours: true,         // 22:00-06:00 silences warning/info, never critical
      monitoring: true,         // background alarm monitoring on/off
      holdBle: true,            // keep BLE warm while on Wi-Fi for fast failover
      autoWrapReminder: true,   // Timeline tab sends wrap/spritz reminders
      customCatalog: [],        // user-defined foods (persisted in Flutter)
    },
  };
})();