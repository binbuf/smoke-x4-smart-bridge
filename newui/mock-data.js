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

    // ── Beef (offal & braising cuts) ───────────────────────────────────
    { id: 'beef_cheeks', category: 'Beef', name: 'Beef Cheeks', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'medium', pitBand: [250, 300], blurb: 'Marrow-rich and gelatinous — built for a long braise.',
      doneness: [ { id: 'tender', label: 'Shreddable', targetF: 205 } ], defaultDoneness: 'tender',
      tl: { total: [240, 360], stall: [150, 165, 60, 120], wrap: [165, 'Braise covered', 'Chile adobo or red wine.'], spritz: null, rest: 20, on: 'Low and covered.' } },
    { id: 'beef_oxtail', category: 'Beef', name: 'Beef Oxtail', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'medium', pitBand: [250, 300], blurb: 'Sticky, rich and falling off the bone.',
      doneness: [ { id: 'tender', label: 'Fall-apart', targetF: 205 } ], defaultDoneness: 'tender',
      tl: { total: [240, 360], stall: [150, 165, 60, 120], wrap: [165, 'Braise covered', 'Braise until it releases the bone.'], spritz: null, rest: 20, on: 'Brown hard, then braise.' } },
    { id: 'beef_tongue', category: 'Beef', name: 'Beef Tongue', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'medium', pitBand: [250, 300], blurb: 'Braise, peel, then slice or chop.',
      doneness: [ { id: 'tender', label: 'Peelable', targetF: 205 } ], defaultDoneness: 'tender',
      tl: { total: [180, 300], wrap: [165, 'Braise covered', 'Braise until the skin peels cleanly.'], spritz: null, rest: 20, on: 'Cured or plain, then braised.' } },
    { id: 'beef_shank', category: 'Beef', name: 'Beef Shank', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [250, 300], blurb: 'Cross-cut and braised until it gives.',
      doneness: [ { id: 'tender', label: 'Fork-tender', targetF: 205 } ], defaultDoneness: 'tender',
      tl: { total: [240, 360], stall: [150, 165, 60, 120], wrap: [165, 'Braise covered', 'With wine, tomato and soffritto.'], spritz: null, rest: 20, on: 'Brown, then braise low.' } },

    // ── Pork (head, hock) ──────────────────────────────────────────────
    { id: 'pork_head', category: 'Pork', name: 'Pork Head (Whole Hog)', glyph: 'pork', hazard: 'pork', thickness: 'thick', pitBand: [250, 275], blurb: 'A pit roast for a crowd — juicy and smoky.',
      doneness: [ { id: 'tender', label: 'Pullable', targetF: 190 } ], defaultDoneness: 'tender',
      tl: { total: [480, 720], stall: [150, 170, 120, 240], wrap: [165, 'Cover', 'Wrap or cover to keep it moist.'], spritz: 45, rest: 45, on: 'Low and slow, skin up.' } },
    { id: 'pork_hock', category: 'Pork', name: 'Ham Hock', glyph: 'pork', hazard: 'pork', thickness: 'medium', pitBand: [250, 300], blurb: 'The seasoning bone — smoke it for beans and greens.',
      doneness: [ { id: 'tender', label: 'Tender', targetF: 200 } ], defaultDoneness: 'tender',
      tl: { total: [180, 300], wrap: [165, 'Wrap', 'Finish covered with a little liquid.'], spritz: 45, rest: 20, on: 'Split and smoked hard.' } },

    // ── Poultry (breasts, legs, game birds, offal) ─────────────────────
    { id: 'poultry_duck_breast', category: 'Poultry', name: 'Duck Breast', glyph: 'poultry', hazard: 'poultry', thickness: 'medium', pitBand: [300, 350], blurb: 'Score the fat and serve it pink.',
      doneness: [ { id: 'rose', label: 'Rosé (135°F)', targetF: 135 }, { id: 'classic', label: 'Classic (150°F)', targetF: 150 } ], defaultDoneness: 'rose',
      tl: { total: [20, 35], turn: { elapsedMin: 10, note: 'Render fat skin-side down.' }, rest: 8, on: 'Score the fat, start skin-side down.' } },
    { id: 'poultry_turkey_legs', category: 'Poultry', name: 'Smoked Turkey Legs', glyph: 'poultry', hazard: 'poultry', thickness: 'thick', pitBand: [275, 325], blurb: 'Fairground-style — cook past the minimum to 175°F.',
      doneness: [ { id: 'done', label: 'Done (175°F)', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [120, 180], spritz: 30, rest: 15, on: 'Cured or brined, then smoked.' } },
    { id: 'poultry_quail', category: 'Poultry', name: 'Quail', glyph: 'poultry', hazard: 'poultry', thickness: 'thin', pitBand: [375, 425], blurb: 'Tiny birds — hot and fast.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [20, 30], turn: { elapsedMin: 10, note: 'Turn once.' }, rest: 5, on: 'Hot and fast, oiled.' } },
    { id: 'poultry_pheasant', category: 'Poultry', name: 'Pheasant', glyph: 'wholeBird', hazard: 'poultry', thickness: 'medium', pitBand: [325, 375], blurb: 'Lean game bird — keep it moist.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [45, 75], spritz: 30, rest: 10, on: 'Bacon or butter to protect the lean meat.' } },
    { id: 'poultry_liver', category: 'Poultry', name: 'Chicken Livers', glyph: 'poultry', hazard: 'poultry', thickness: 'thin', pitBand: [350, 400], blurb: 'Rumaki or a coarse country pâté.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [15, 30], turn: { elapsedMin: 8, note: 'Turn once.' }, rest: 5, on: 'Bacon-wrapped, or into a pâté.' } },

    // ── Seafood (more fish & shellfish) ────────────────────────────────
    { id: 'fish_mackerel', category: 'Seafood', name: 'Mackerel', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [325, 375], blurb: 'Oily, rich and great with a glaze.',
      doneness: [ { id: 'done', label: 'Flaky (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [15, 25], turn: { elapsedMin: 7, note: 'Flip once.' }, rest: 3, on: 'Skin side down on a clean grate.' } },
    { id: 'fish_sardines', category: 'Seafood', name: 'Sardines', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [400, 500], blurb: 'Whole, oiled and grilled fast.',
      doneness: [ { id: 'done', label: 'Done (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [6, 12], turn: { elapsedMin: 3, note: 'Turn once, gently.' }, rest: 2, on: 'Very hot, oiled grate.' } },
    { id: 'fish_mussels', category: 'Seafood', name: 'Mussels', glyph: 'shellfish', hazard: 'fish', thickness: 'thin', pitBand: [375, 425], blurb: 'Open them in wine, garlic and butter.',
      doneness: [ { id: 'done', label: 'Opened (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [10, 20], rest: 2, on: 'In a covered pan or foil pack.' } },
    { id: 'fish_clams', category: 'Seafood', name: 'Clams', glyph: 'shellfish', hazard: 'fish', thickness: 'thin', pitBand: [375, 425], blurb: 'Littlenecks in garlic butter, or into a chowder.',
      doneness: [ { id: 'done', label: 'Opened (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [10, 20], rest: 2, on: 'In a covered pan so they steam open.' } },
    { id: 'fish_squid', category: 'Seafood', name: 'Squid / Calamari', glyph: 'shellfish', hazard: 'fish', thickness: 'thin', pitBand: [400, 500], blurb: 'Hot and fast, or it turns to rubber.',
      doneness: [ { id: 'done', label: 'Done (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [4, 8], turn: { elapsedMin: 2, note: 'Flip once.' }, rest: 1, on: 'Screaming hot and quick.' } },
    { id: 'fish_octopus', category: 'Seafood', name: 'Octopus', glyph: 'shellfish', hazard: 'fish', thickness: 'medium', pitBand: [225, 275], blurb: 'Braise to tender, then char.',
      doneness: [ { id: 'done', label: 'Tender (175°F)', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [60, 120], wrap: [165, 'Braise covered', 'Braise until a knife slides in easily.'], spritz: null, rest: 10, on: 'Braise first, char at the very end.' } },
    { id: 'fish_alligator', category: 'Seafood', name: 'Alligator', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [375, 425], blurb: 'Firm, mild and lean — blackened or fried.',
      doneness: [ { id: 'done', label: 'Done (160°F)', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [12, 20], turn: { elapsedMin: 6, note: 'Flip once.' }, rest: 3, on: 'Hot and fast, do not overcook.' } },
    { id: 'fish_frog_legs', category: 'Seafood', name: 'Frog Legs', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [375, 425], blurb: 'Delicate, mild and best blackened.',
      doneness: [ { id: 'done', label: 'Done (160°F)', targetF: 160 } ], defaultDoneness: 'done',
      tl: { total: [10, 18], turn: { elapsedMin: 5, note: 'Flip once.' }, rest: 3, on: 'Hot and fast over clean heat.' } },
    { id: 'fish_crawfish', category: 'Seafood', name: 'Crawfish', glyph: 'shellfish', hazard: 'fish', thickness: 'thin', pitBand: [350, 400], blurb: 'A boil favourite, or smoked tails.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [10, 20], rest: 2, on: 'Boiled with seasoning, or smoked in butter.' } },
    { id: 'fish_whole_bass', category: 'Seafood', name: 'Whole Sea Bass', glyph: 'fish', hazard: 'fish', thickness: 'medium', pitBand: [375, 425], blurb: 'Whole fish stuffed with lemon and herbs.',
      doneness: [ { id: 'done', label: 'Flaky (145°F)', targetF: 145 } ], defaultDoneness: 'done',
      tl: { total: [20, 35], turn: { elapsedMin: 10, note: 'Turn once in a basket.' }, rest: 5, on: 'In a fish basket so it does not stick.' } },

    // ── Lamb (ribs) ────────────────────────────────────────────────────
    { id: 'lamb_ribs', category: 'Lamb', name: 'Lamb Ribs', glyph: 'ribs', hazard: 'wholeMuscleRedMeat', thickness: 'thin', pitBand: [250, 275], blurb: 'Rich, sweet and quicker than pork ribs.',
      doneness: [ { id: 'tender', label: 'Bite-tender', targetF: 200 } ], defaultDoneness: 'tender',
      tl: { total: [150, 240], wrap: [165, 'Wrap', 'Butter, honey and sauce in the wrap.'], spritz: 45, rest: 15, on: 'Bone side down.' } },

    // ── Game (more wild game) ──────────────────────────────────────────
    { id: 'game_elk', category: 'Game', name: 'Elk Roast', glyph: 'game', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [225, 275], blurb: 'Leaner and sweeter than beef.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 } ], defaultDoneness: 'medrare',
      tl: { total: [90, 150], spritz: 30, rest: 20, on: 'Wrapped in bacon to protect the lean meat.' } },
    { id: 'game_antelope', category: 'Game', name: 'Antelope Roast', glyph: 'game', hazard: 'wholeMuscleRedMeat', thickness: 'medium', pitBand: [225, 275], blurb: 'Very lean — fast cook, long rest.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 } ], defaultDoneness: 'medrare',
      tl: { total: [45, 90], spritz: 20, rest: 15, on: 'Oil and herb rub, then a gentle smoke.' } },
    { id: 'game_squirrel', category: 'Game', name: 'Squirrel', glyph: 'game', hazard: 'poultry', thickness: 'thin', pitBand: [250, 300], blurb: 'Small and lean — best smothered in gravy.',
      doneness: [ { id: 'done', label: 'Tender (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [60, 120], wrap: [165, 'Braise covered', 'Smother in onion gravy.'], spritz: null, rest: 10, on: 'Brown, then braise.' } },
    { id: 'game_wild_turkey', category: 'Game', name: 'Wild Turkey', glyph: 'wholeBird', hazard: 'poultry', thickness: 'thick', pitBand: [275, 325], blurb: 'Leaner and drier than farmed — inject it.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [150, 240], turn: { elapsedMin: 60, note: 'Rotate for even colour.' }, rest: 20, on: 'Breast side up, injected and indirect.' } },

    // ── Veggies (more) ─────────────────────────────────────────────────
    { id: 'veg_artichoke', category: 'Veggies', name: 'Grilled Artichokes', glyph: 'veg', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400], blurb: 'Steamed first, then charred with lemon butter.',
      doneness: [ { id: 'done', label: 'Tender', targetF: 190 } ], defaultDoneness: 'done',
      tl: { total: [30, 50], turn: { elapsedMin: 15, note: 'Flip once.' }, rest: 0, on: 'Steam, halve, oil and grill.' } },
    { id: 'veg_cabbage', category: 'Veggies', name: 'Grilled Cabbage', glyph: 'veg', hazard: 'unstated', thickness: 'medium', pitBand: [375, 425], blurb: 'Thick wedges, deep char, sweet centre.',
      doneness: [ { id: 'done', label: 'Tender', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [20, 40], turn: { elapsedMin: 10, note: 'Flip once.' }, rest: 0, on: 'Wedges, oiled, cut side down.' } },
    { id: 'veg_brussels', category: 'Veggies', name: 'Brussels Sprouts', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [350, 400], blurb: 'Charred leaves, crisp outside and tender inside.',
      doneness: [ { id: 'done', label: 'Charred', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [20, 35], turn: { elapsedMin: 12, note: 'Stir once.' }, rest: 0, on: 'Oiled, on a basket or foil pan.' } },
    { id: 'veg_okra', category: 'Veggies', name: 'Grilled Okra', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [350, 400], blurb: 'Dry, hot and charred so it does not go slimy.',
      doneness: [ { id: 'done', label: 'Charred', targetF: 170 } ], defaultDoneness: 'done',
      tl: { total: [12, 20], turn: { elapsedMin: 6, note: 'Turn once.' }, rest: 0, on: 'Dry pods, hot grate.' } },
    { id: 'veg_eggplant', category: 'Veggies', name: 'Smoked Eggplant', glyph: 'veg', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400], blurb: 'Whole for baba ganoush, or halved and glazed.',
      doneness: [ { id: 'done', label: 'Collapsed', targetF: 190 } ], defaultDoneness: 'done',
      tl: { total: [30, 60], turn: { elapsedMin: 20, note: 'Turn for even char.' }, rest: 0, on: 'Whole over direct heat.' } },
    { id: 'veg_sweet_potato', category: 'Veggies', name: 'Sweet Potatoes', glyph: 'potato', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400], blurb: 'Fork-tender, caramelised edges.',
      doneness: [ { id: 'done', label: 'Fork-tender', targetF: 205 } ], defaultDoneness: 'done',
      tl: { total: [50, 80], rest: 5, on: 'Whole or halved, indirect.' } },
    { id: 'veg_plantain', category: 'Veggies', name: 'Plantains', glyph: 'fruit', hazard: 'unstated', thickness: 'thin', pitBand: [350, 400], blurb: 'Sweet maduros or salty tostones.',
      doneness: [ { id: 'done', label: 'Caramelised', targetF: 180 } ], defaultDoneness: 'done',
      tl: { total: [15, 25], turn: { elapsedMin: 8, note: 'Turn once.' }, rest: 0, on: 'Ripe for sweet, green for crisp.' } },
    { id: 'veg_onion', category: 'Veggies', name: 'Smoked Onions', glyph: 'veg', hazard: 'unstated', thickness: 'medium', pitBand: [300, 350], blurb: 'Sweet, jammy and smoky.',
      doneness: [ { id: 'done', label: 'Jammy', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [45, 75], turn: { elapsedMin: 25, note: 'Turn once.' }, rest: 0, on: 'Halved and oiled, cut side down.' } },
    { id: 'veg_garlic', category: 'Veggies', name: 'Smoked Garlic', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [300, 350], blurb: 'Whole bulbs turn soft, sweet and spreadable.',
      doneness: [ { id: 'done', label: 'Soft', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [45, 75], rest: 0, on: 'Whole bulbs, tops cut, oiled and foiled.' } },
    { id: 'veg_tomato', category: 'Veggies', name: 'Smoked Tomatoes', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [225, 275], blurb: 'Concentrated and sweet — great for sauce.',
      doneness: [ { id: 'done', label: 'Softened', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [45, 90], turn: { elapsedMin: 30, note: 'Turn once.' }, rest: 0, on: 'Halved, cut side up, low.' } },
    { id: 'veg_romaine', category: 'Veggies', name: 'Grilled Romaine', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [375, 425], blurb: 'Charred hearts — a grilled Caesar waiting to happen.',
      doneness: [ { id: 'done', label: 'Charred', targetF: 170 } ], defaultDoneness: 'done',
      tl: { total: [6, 12], turn: { elapsedMin: 3, note: 'Turn once.' }, rest: 0, on: 'Halved, cut side down, hot.' } },
    { id: 'veg_avocado', category: 'Veggies', name: 'Grilled Avocado', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [375, 425], blurb: 'Warm, smoky and creamy.',
      doneness: [ { id: 'done', label: 'Warm', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [6, 12], turn: { elapsedMin: 4, note: 'Do not move until it releases.' }, rest: 0, on: 'Halved, cut side down, hot.' } },

    // ── Sides (more) ───────────────────────────────────────────────────
    { id: 'side_stuffing', category: 'Sides', name: 'Smoked Stuffing', glyph: 'bread', hazard: 'unstated', thickness: 'medium', pitBand: [300, 350], blurb: 'Sage, sausage and a golden top.',
      doneness: [ { id: 'done', label: 'Set (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [45, 75], rest: 10, on: 'In a buttered dish, uncovered for a crust.' } },
    { id: 'side_scallop_potatoes', category: 'Sides', name: 'Scalloped Potatoes', glyph: 'potato', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400], blurb: 'Thin slices, cream, bubbling cheese.',
      doneness: [ { id: 'done', label: 'Tender (175°F)', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [60, 90], rest: 10, on: 'In a cream-filled dish, indirect.' } },
    { id: 'side_green_bean', category: 'Sides', name: 'Green Bean Casserole', glyph: 'veg', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400], blurb: 'Cream of mushroom and crispy onions.',
      doneness: [ { id: 'done', label: 'Bubbling', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [40, 60], rest: 10, on: 'In a dish, topped with fried onion.' } },
    { id: 'side_collards', category: 'Sides', name: 'Collard Greens', glyph: 'veg', hazard: 'unstated', thickness: 'medium', pitBand: [250, 300], blurb: 'Ham hock, vinegar, pepper — Southern gold.',
      doneness: [ { id: 'done', label: 'Silky', targetF: 180 } ], defaultDoneness: 'done',
      tl: { total: [90, 150], wrap: [165, 'Cover', 'Braise with ham hock until silky.'], spritz: null, rest: 0, on: 'In a covered pan with ham hock.' } },
    { id: 'side_coleslaw', category: 'Sides', name: 'Coleslaw', glyph: 'veg', hazard: 'unstated', thickness: 'thin', pitBand: [35, 40], blurb: 'No cook — the pulled-pork partner. Chill and dress.',
      doneness: [ { id: 'done', label: 'Chilled (38°F)', targetF: 38 } ], defaultDoneness: 'done',
      tl: { total: [5, 10], rest: 0, on: 'Shred, dress and hold cold.' } },
    { id: 'side_potato_salad', category: 'Sides', name: 'Potato Salad', glyph: 'potato', hazard: 'unstated', thickness: 'medium', pitBand: [35, 40], blurb: 'Boil, dress, chill — mustard or German style.',
      doneness: [ { id: 'done', label: 'Chilled (38°F)', targetF: 38 } ], defaultDoneness: 'done',
      tl: { total: [20, 30], rest: 0, on: 'Boil, dress and hold cold.' } },
    { id: 'side_corn_pudding', category: 'Sides', name: 'Corn Pudding', glyph: 'side', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400], blurb: 'Creamy, sweet and golden-topped.',
      doneness: [ { id: 'done', label: 'Set (175°F)', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [45, 75], rest: 10, on: 'In a buttered dish, water bath optional.' } },
    { id: 'side_hushpuppies', category: 'Sides', name: 'Hushpuppies', glyph: 'bread', hazard: 'unstated', thickness: 'thin', pitBand: [375, 425], blurb: 'Crisp cornmeal bites, fried or grilled.',
      doneness: [ { id: 'done', label: 'Golden (175°F)', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [10, 20], turn: { elapsedMin: 5, note: 'Turn once.' }, rest: 0, on: 'Fried, or grilled on a basket.' } },

    // ── Desserts ───────────────────────────────────────────────────────
    { id: 'dessert_apple_crisp', category: 'Desserts', name: 'Apple Crisp', glyph: 'fruit', hazard: 'unstated', thickness: 'medium', pitBand: [325, 375], blurb: 'Smoked until the oat topping bubbles.',
      doneness: [ { id: 'done', label: 'Bubbling (180°F)', targetF: 180 } ], defaultDoneness: 'done',
      tl: { total: [40, 60], rest: 15, on: 'In a cast-iron skillet, indirect.' } },
    { id: 'dessert_banana_pudding', category: 'Desserts', name: 'Banana Pudding', glyph: 'fruit', hazard: 'unstated', thickness: 'medium', pitBand: [70, 100], blurb: 'Cold-smoke the bananas, then layer and chill.',
      doneness: [ { id: 'done', label: 'Chilled (40°F)', targetF: 40 } ], defaultDoneness: 'done',
      tl: { total: [20, 40], rest: 180, on: 'Cold smoke, then assemble and chill.' } },
    { id: 'dessert_cobbler', category: 'Desserts', name: 'Fruit Cobbler', glyph: 'fruit', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400], blurb: 'Biscuit-topped and golden.',
      doneness: [ { id: 'done', label: 'Golden (190°F)', targetF: 190 } ], defaultDoneness: 'done',
      tl: { total: [45, 75], rest: 15, on: 'In a skillet or dish, indirect.' } },
    { id: 'dessert_smores', category: 'Desserts', name: 'Skillet S’mores', glyph: 'side', hazard: 'unstated', thickness: 'thin', pitBand: [325, 375], blurb: 'Chocolate, marshmallow and graham — melted together.',
      doneness: [ { id: 'done', label: 'Molten (170°F)', targetF: 170 } ], defaultDoneness: 'done',
      tl: { total: [10, 20], rest: 5, on: 'In a cast-iron skillet.' } },
    { id: 'dessert_brownies', category: 'Desserts', name: 'Smoked Brownies', glyph: 'side', hazard: 'unstated', thickness: 'medium', pitBand: [325, 375], blurb: 'Fudgy, with a whisper of smoke.',
      doneness: [ { id: 'done', label: 'Set (175°F)', targetF: 175 } ], defaultDoneness: 'done',
      tl: { total: [30, 45], rest: 20, on: 'In a buttered pan, indirect.' } },
    { id: 'dessert_cheesecake', category: 'Desserts', name: 'Smoked Cheesecake', glyph: 'cheese', hazard: 'unstated', thickness: 'thick', pitBand: [250, 300], blurb: 'Gently smoked, then chilled overnight.',
      doneness: [ { id: 'done', label: 'Set (165°F)', targetF: 165 } ], defaultDoneness: 'done',
      tl: { total: [60, 90], rest: 240, on: 'Indirect, low — then chill completely.' } },
    { id: 'dessert_cinnamon_rolls', category: 'Desserts', name: 'Smoked Cinnamon Rolls', glyph: 'bread', hazard: 'unstated', thickness: 'medium', pitBand: [300, 350], blurb: 'Smoked, then frosted while warm.',
      doneness: [ { id: 'done', label: 'Golden (190°F)', targetF: 190 } ], defaultDoneness: 'done',
      tl: { total: [30, 50], rest: 20, on: 'In a buttered pan, indirect.' } },
    { id: 'dessert_grilled_fruit', category: 'Desserts', name: 'Grilled Stone Fruit', glyph: 'fruit', hazard: 'unstated', thickness: 'thin', pitBand: [375, 425], blurb: 'Peaches, plums and nectarines, charred and honeyed.',
      doneness: [ { id: 'done', label: 'Charred', targetF: 150 } ], defaultDoneness: 'done',
      tl: { total: [8, 15], turn: { elapsedMin: 4, note: 'Turn once.' }, rest: 0, on: 'Halved, cut side down, hot.' } },
  ];

  const CATEGORIES = ['Beef', 'Pork', 'Poultry', 'Seafood', 'Lamb', 'Game', 'Veggies', 'Sides', 'Misc', 'Desserts'];

  // ── Cook-style packs (the cook-variant database) ───────────────────────
  // Selecting a cut is not enough: "Pork Shoulder" could be Texas pulled pork,
  // Kālua pork, Carolina, Cuban mojo, pernil or cochinita pibil — and the same
  // logic repeats for every meat, bird and fish. A style is a *named regional
  // preparation* that sets pit band, wrap, spritz, target, rest and the whole
  // expected timeline together. This table is a headline feature: it is why one
  // cut can become a dozen recognisable dishes. [FLUTTER] maps to a
  // preset+style record keyed by the same preset id.
  //
  // `region` is shown as a badge so the app teaches the taxonomy: Texas,
  // Carolina, Memphis, Kansas City, Alabama, Hawaii, Yucatán, Korea, Japan,
  // Tandoor, Provence, Churrasco, Cajun, Cantonese … It is content, not chrome.
  //
  // wrap: [tempF, label, note] | null.  spritz: minutes between spritzes | null.
  function S(id, name, region, tagline, pit, target, wrap, spritz, rest, note) {
    return { id: id, name: name, region: region, tagline: tagline, pitBand: pit, targetF: target, wrap: wrap, spritz: spritz, restMin: rest, note: note };
  }

  const STYLES = {
    // ── Beef ──────────────────────────────────────────────────────────
    beef_brisket: [
      S('central_texas', 'Central Texas', 'Texas', 'Salt & pepper, butcher paper', [225, 275], 201, [165, 'Wrap in butcher paper', 'Protects the bark through the stall.'], null, 60, 'The benchmark. Fat side up, no mop, paper at the stall.'),
      S('competition', 'Competition', 'KCBS', 'Injected, foil at the stall', [250, 275], 203, [165, 'Foil (Texas crutch)', 'Speeds the cook and keeps it moist.'], 30, 90, 'Richer, sweeter, faster. Judges love it.'),
      S('hot_fast', 'Hot & Fast', 'Modern', '300°F, smaller cuts', [300, 325], 200, [165, 'Foil', 'Essential at this temp.'], 30, 45, 'For when you started late. Still great, less margin.'),
      S('southside', 'Southside Market', 'Texas', 'Elgin hot sausage town favourite', [225, 275], 201, [160, 'Wrap in paper', 'Set the bark, then paper.'], 45, 45, 'The Elgin, Texas style — heavy black pepper, quick paper wrap.'),
      S('montreal_smoked', 'Montreal Smoked Meat', 'Quebec', 'Cured, peppery, steamed to finish', [225, 250], 203, [170, 'Steam to finish', 'Steam is what makes it deli-soft.'], null, 60, 'Cured flat, rubbed in coarse pepper, smoked then steamed.'),
    ],
    beef_ribeye: [
      S('reverse_sear', 'Reverse Sear', 'Modern', 'Low, then screaming hot', [225, 275], 135, null, null, 8, 'Even edge-to-edge colour with a hard crust.'),
      S('direct', 'Direct', 'Weeknight', 'Hot and fast', [400, 500], 135, null, null, 5, 'Crust first, quick finish over the coals.'),
      S('cowboy', 'Cowboy Cut', 'Texas', 'Bone-in, coarse salt', [225, 275], 135, null, null, 10, 'Thick bone-in ribeye, salt only, finished over flame.'),
      S('blackened', 'Blackened', 'Cajun', 'Cast-iron spice crust', [400, 500], 130, null, null, 6, 'Heavy Cajun seasoning seared hard in a ripping pan.'),
    ],
    beef_prime_rib: [
      S('reverse_sear', 'Reverse Sear', 'Classic', 'Low roast, then blast the crust', [225, 275], 135, null, null, 30, 'Gentle roast, then a 500°F finish for the crust.'),
      S('salt_crusted', 'Salt Crusted', 'Classic', 'Rock salt shell', [225, 275], 130, null, null, 30, 'Packed in rock salt — seasons and insulates at once.'),
      S('au_jus', 'Au Jus', 'French', 'Horseradish and jus', [250, 300], 135, [130, 'Rest in jus', 'Hold it warm in the jus before slicing.'], 45, 30, 'Roast to rare, serve with a strong jus and horseradish.'),
    ],
    beef_chuck: [
      S('pepper_stout', 'Pepper Stout Beef', 'Modern', 'Stout, peppers, shredded', [250, 300], 205, [165, 'Braise in stout', 'Beer, peppers and onions in a foil pan.'], null, 30, 'Chicago-style shredded chuck braised in stout with peppers.'),
      S('barbacoa', 'Barbacoa', 'Mexican', 'Chiles, cumin, tender shred', [250, 300], 200, [165, 'Wrap with chile adobo', 'Banana leaf or foil, chile coating.'], null, 30, 'Slow-braised with guajillo and cumin, shredded for tacos.'),
      S('italian_beef', 'Italian Beef', 'Chicago', 'Pepperoncini, dipped', [250, 300], 200, [165, 'Braise with giardiniera', 'Finish in its own seasoned jus.'], null, 30, 'Thin-sliced roast with giardiniera, served wet.'),
    ],
    beef_burger: [
      S('smash', 'Smash', 'Diner', 'Thin, crusty, hot grid', [400, 500], 160, null, null, 3, 'Smash thin on a screaming grate for maximum crust.'),
      S('smoked', 'Smoked', 'BBQ', 'Low smoke, then sauce', [225, 275], 160, null, null, 3, 'Smoke low to finish, glaze in the last ten minutes.'),
      S('tallow', 'Tallow Griddled', 'Modern', 'Seared in beef fat', [400, 500], 155, null, null, 3, 'Griddled in tallow for a deep, beefy crust.'),
    ],
    beef_shortribs: [
      S('galbi', 'Galbi (Korean)', 'Korea', 'Soy, pear, sesame marinade', [250, 300], 200, null, 45, 15, 'Marinated in soy, Asian pear and sesame, grilled hot.'),
      S('braised', 'Braised', 'Classic', 'Red wine, mirepoix, rich', [250, 300], 205, [165, 'Braise covered', 'Low and covered until the collagen gives.'], null, 20, 'A rich red-wine braise — fork-tender and glossy.'),
      S('dino', 'Dino Ribs', 'Texas', 'Salt & pepper, paper wrapped', [250, 275], 203, [165, 'Wrap in paper', 'Protect the bark through the stall.'], 60, 30, 'Big plate ribs smoked to a clean, buttery pull.'),
    ],
    beef_tritip: [
      S('california', 'Santa Maria', 'California', 'Rub, smoke, sear', [225, 275], 135, null, null, 10, 'Garlic, salt, pepper, red oak if you have it.'),
      S('grilled_direct', 'Grilled Direct', 'Weeknight', 'Hot, fast, rested', [375, 425], 135, null, null, 8, 'Direct over coals, turned often, rested before slicing.'),
    ],
    beef_flank: [
      S('carne_asada', 'Carne Asada', 'Mexican', 'Citrus, garlic, char', [400, 500], 135, null, null, 8, 'Lime, garlic and chile marinade, then a hard char.'),
      S('chimichurri', 'Chimichurri', 'Argentina', 'Parsley, vinegar, garlic', [400, 500], 130, null, null, 8, 'Grilled hot and blanketed in herb chimichurri.'),
    ],
    beef_skirt: [
      S('fajita', 'Fajita', 'Tex-Mex', 'Marinated, charred, sliced', [450, 550], 135, null, null, 5, 'The fajita classic — marinated, screamed on the grate.'),
      S('arrachera', 'Arrachera', 'Mexico', 'Lime, beer, soy marinade', [400, 500], 135, null, null, 5, 'Mexican arrachera with a citrus-beer marinade.'),
    ],
    beef_picanha: [
      S('churrasco', 'Churrasco', 'Brazil', 'Skewered, fat cap, coarse salt', [375, 425], 135, null, null, 10, 'Rock salt on the fat cap, rotated over coals.'),
      S('brazilian_roast', 'Brazilian Roast', 'Brazil', 'Fat cap up, indirect', [225, 275], 135, null, 45, 10, 'Roasted fat-side-up, rested and sliced like steak.'),
    ],
    beef_denver: [
      S('seared', 'Hard Seared', 'Modern', 'Salt, high heat, fast', [400, 500], 135, null, null, 5, 'Well-marbled and forgiving — hard sear, quick rest.'),
      S('teriyaki', 'Teriyaki', 'Japan', 'Glazed sweet soy', [375, 425], 140, null, null, 5, 'Glazed with sweet soy and grilled to a shine.'),
    ],
    beef_backribs: [
      S('kansas_city', 'Kansas City', 'Missouri', 'Sweet rub, BBQ glaze', [250, 275], 200, [165, 'Wrap with sauce', 'Braise with apple juice and a splash of sauce.'], 45, 20, 'Sticky, sweet and smoky — sauce at the end.'),
      S('memphis_dry', 'Memphis Dry', 'Tennessee', 'Dry rub, no sauce', [250, 275], 200, null, 45, 20, 'A dry-rub finish — no sauce ever touches the plate.'),
    ],
    beef_pastrami: [
      S('deli', 'Deli Style', 'New York', 'Rye pepper, steamed', [225, 275], 203, [165, 'Wrap & steam', 'Foil with a splash of stock to finish.'], null, 60, 'Deli-style: cured, smoked, then steamed until it slices like butter.'),
      S('montreal', 'Montreal', 'Quebec', 'Heavier pepper, more smoke', [225, 250], 203, [170, 'Steam to finish', 'Steam is what makes it deli-soft.'], null, 60, 'Heavier pepper and smoke than the New York version.'),
    ],
    beef_meatloaf: [
      S('bacon_wrapped', 'Bacon Wrapped', 'Classic', 'Bacon lattice, ketchup glaze', [250, 300], 160, null, null, 10, 'Wrapped in a bacon lattice, glazed at the end.'),
      S('glazed', 'BBQ Glazed', 'Modern', 'Smoked, sauced, caramelised', [250, 300], 160, null, null, 10, 'Smoked then brushed with BBQ glaze until sticky.'),
    ],
    beef_tenderloin: [
      S('chateaubriand', 'Chateaubriand', 'French', 'Whole roast, red wine jus', [225, 275], 135, null, null, 20, 'Roasted whole and rested long. Never overshoot.'),
      S('bacon_wrapped', 'Bacon Wrapped', 'Classic', 'Lean meat, bacon shield', [275, 325], 135, null, null, 15, 'Bacon protects the lean meat as it roasts.'),
    ],
    beef_cheeks: [
      S('barbacoa', 'Barbacoa', 'Mexican', 'Chile braise, shred', [250, 300], 205, [165, 'Braise covered', 'Guajillo, cumin and onion until it shreds.'], null, 20, 'The classic barbacoa cut — marrow-rich and shreddable.'),
      S('bourguignon', 'Bourguignon', 'French', 'Red wine, lardons, pearl onion', [250, 300], 205, [165, 'Braise in wine', 'A rich Burgundy braise.'], null, 20, 'Beef cheeks braised in red wine with lardons.'),
    ],
    beef_oxtail: [
      S('braised', 'Braised', 'Classic', 'Deep, sticky, gelatinous', [250, 300], 205, [165, 'Braise covered', 'Falls off the bone after a long braise.'], null, 20, 'Slow braise — the richest, stickiest cut on the animal.'),
      S('jamaican', 'Jamaican Brown Stew', 'Jamaica', 'Browning sauce, allspice', [250, 300], 205, [165, 'Braise with browning', 'Allspice, scallion, scotch bonnet.'], null, 20, 'Brown-stewed with allspice and scotch bonnet.'),
    ],
    beef_tongue: [
      S('lengua', 'Lengua', 'Mexican', 'Tacos, salsa verde', [250, 300], 205, [165, 'Braise until peelable', 'The skin peels away after a long braise.'], null, 20, 'Braised, peeled, and chopped for tacos de lengua.'),
      S('pastrami', 'Tongue Pastrami', 'Deli', 'Cured, smoked, thin sliced', [225, 275], 203, [165, 'Steam to finish', 'Steam, then slice thin.'], null, 45, 'Cured and smoked like pastrami, sliced paper-thin.'),
    ],
    beef_shank: [
      S('osso_buco', 'Osso Buco', 'Italy', 'Milanese, gremolata', [250, 300], 205, [165, 'Braise covered', 'Wine, tomato and soffritto until it releases.'], null, 20, 'Braised cross-cut shank with gremolata.'),
      S('braised', 'Braised Shank', 'Classic', 'Fork-tender, rich jus', [250, 300], 205, [165, 'Braise covered', 'Low and covered with stock and aromatics.'], null, 20, 'A long, slow braise that turns the shank silky.'),
    ],

    // ── Pork ──────────────────────────────────────────────────────────
    pork_butt: [
      S('texas_pulled', 'Texas Pulled Pork', 'Texas', 'Yellow mustard + rub, 250°F', [225, 275], 201, [165, 'Wrap in foil (optional)', 'Foil for speed; leave open for bark.'], null, 60, 'Yellow mustard binder, coarse rub, long rest.'),
      S('kalua', 'Kālua Pork', 'Hawaii', 'Salt + liquid smoke, covered', [250, 300], 200, [165, 'Cover with foil (or banana leaf)', 'Traditional: leaves, salt, and ti.'], null, 45, 'Hawaiian: sea salt, liquid smoke, covered, shredded with cabbage.'),
      S('carolina', 'Carolina', 'South Carolina', 'Vinegar mop + pepper', [225, 275], 200, null, 45, 45, 'Mop with vinegar and red pepper; serve with a vinegar sauce.'),
      S('cuban_mojo', 'Cuban Mojo', 'Cuba', 'Citrus, garlic, oregano', [250, 275], 200, [170, 'Wrap in foil', 'Finish in its own juices.'], 45, 30, 'Mojo marinade, then smoke and finish in foil with sour orange.'),
      S('memphis', 'Memphis Pulled', 'Tennessee', 'Dry rub, tomato or vinegar', [225, 275], 200, null, 45, 45, 'Dry-rubbed, pulled, and dressed with a thin sauce.'),
      S('alabama_white', 'Alabama White', 'Alabama', 'White sauce, horseradish', [225, 275], 200, null, 45, 45, 'Finished with tangy white sauce — mayo, vinegar, horseradish.'),
      S('pernil', 'Pernil', 'Puerto Rico', 'Garlic, oregano, adobo', [275, 325], 200, [165, 'Cover and finish', 'Crisp the skin at the very end.'], 45, 30, 'Garlic-and-oregano roasted pork shoulder with crackling skin.'),
      S('cochinita_pibil', 'Cochinita Pibil', 'Yucatán', 'Achiote, sour orange, banana leaf', [250, 300], 200, [165, 'Wrap in banana leaf', 'Achiote and sour orange, wrapped tight.'], null, 30, 'Yucatecan achiote pork, slow-cooked in banana leaf.'),
    ],
    pork_ribs: [
      S('321', '3-2-1 (Spare)', 'KCBS', '3h smoke · 2h wrapped · 1h saucy', [225, 250], 195, [165, 'Wrap in foil', 'Second act: 2 hours wrapped with a splash.'], 45, 15, 'The classic. Reliable, tender, saucy.'),
      S('no_wrap', 'No-Wrap', 'Modern', 'Kiss the bone', [225, 275], 195, null, 45, 10, 'Firmer bite, better bark, longer cook.'),
      S('memphis_dry', 'Memphis Dry', 'Tennessee', 'Dry rub, no sauce', [225, 275], 195, null, 45, 10, 'Rubbed all over, never sauced, served with slaw.'),
      S('kansas_city', 'Kansas City', 'Missouri', 'Sweet, sticky, sauced', [225, 275], 195, [165, 'Wrap with brown sugar', 'Butter, brown sugar, honey and sauce.'], 45, 15, 'The thick, sweet KC style — sauce at every stage.'),
      S('st_louis', 'St. Louis Cut', 'Missouri', 'Squared, trimmed, rubbed', [225, 275], 195, null, 45, 10, 'Trimmed to a neat rectangle for even cooking.'),
      S('alabama_white', 'Alabama White', 'Alabama', 'White sauce finish', [250, 275], 195, null, 30, 10, 'Pulled off the heat and dunked in white sauce.'),
      S('jerk', 'Jerk', 'Jamaica', 'Scotch bonnet, allspice, pimento', [275, 325], 200, null, 30, 10, 'Jerk-rubbed over pimento wood — fiery and aromatic.'),
    ],
    pork_babyback: [
      S('221', '2-2-1', 'KCBS', 'Shorter than spare ribs', [225, 250], 190, [165, 'Wrap in foil', '2 hours wrapped.'], 45, 15, 'The baby-back standard.'),
      S('no_wrap', 'No-Wrap', 'Modern', 'Crisp bark, bite-tender', [250, 275], 190, null, 30, 10, 'For bark purists.'),
      S('kansas_city', 'Kansas City', 'Missouri', 'Sweet glaze, fall-apart', [225, 275], 190, [165, 'Wrap with honey butter', 'Honey, butter and sauce in the wrap.'], 45, 15, 'Sticky and sweet, the crowd-pleaser.'),
      S('honey_glazed', 'Honey Glazed', 'Modern', 'Honey-soy lacquer', [225, 275], 190, null, 30, 10, 'Brushed with a honey-soy lacquer until glossy.'),
      S('memphis_dry', 'Memphis Dry', 'Tennessee', 'Dry rub finish', [225, 275], 190, null, 45, 10, 'A dusting of dry rub right before serving.'),
    ],
    pork_loin: [
      S('porchetta', 'Porchetta', 'Italy', 'Rolled, herbed, crackling', [250, 300], 145, [140, 'Hold at temp', 'Pull at 145°F and rest — it dries fast.'], 30, 15, 'Rolled with fennel, garlic and rosemary, skin crisped.'),
      S('crown_roast', 'Crown Roast', 'Classic', 'Frenched rack, roasted', [275, 325], 145, null, 30, 15, 'French-trimmed and roasted into a crown.'),
      S('maple_glazed', 'Maple Glazed', 'Vermont', 'Maple and mustard', [275, 325], 145, null, 30, 10, 'Maple and grainy mustard glaze, basted near the end.'),
    ],
    pork_belly: [
      S('burnt_ends', 'Burnt Ends', 'KCBS', 'Cubed, sauced, back on', [250, 275], 200, [165, 'Wrap', 'Then cube and sauce for burnt ends.'], 45, 15, 'Cubed, sauced and returned to the heat until sticky.'),
      S('chicharron', 'Chicharrón', 'Spain', 'Crisped skin, crackling', [300, 350], 205, null, null, 10, 'Skin-side down until it puffs into glassy crackling.'),
      S('sichuan', 'Sichuan Twice-Cooked', 'China', 'Chilli, doubanjiang, peppercorn', [300, 350], 195, null, null, 10, 'Braised then wok-fired with chilli bean paste.'),
    ],
    pork_sausage: [
      S('texas_hot_guts', 'Texas Hot Guts', 'Texas', 'Elgin-style, coarse, peppery', [225, 275], 160, null, null, 5, 'The Elgin hot link — coarse, peppery, snap casing.'),
      S('italian', 'Italian', 'Italy', 'Fennel, garlic, sweet', [225, 275], 160, null, null, 5, 'Sweet fennel sausage, grilled with peppers and onion.'),
      S('cheddar_jalapeno', 'Cheddar Jalapeño', 'Modern', 'Melty cheese, chilli bite', [225, 275], 160, null, null, 5, 'Cheddar and jalapeño — watch the casing at high heat.'),
    ],
    pork_chops: [
      S('tomahawk', 'Tomahawk', 'Modern', 'Long bone, reverse sear', [225, 275], 145, null, null, 8, 'Long-bone chop, reverse-seared for an even blush.'),
      S('brined_apple', 'Brined & Apple', 'Classic', 'Brine, apple, sage', [275, 325], 145, null, null, 8, 'Brined for a day, served with apple and sage.'),
      S('jerk', 'Jerk', 'Jamaica', 'Scotch bonnet rub', [300, 350], 150, null, null, 5, 'Jerk-rubbed and grilled hot.'),
    ],
    pork_tenderloin: [
      S('bacon_wrapped', 'Bacon Wrapped', 'Classic', 'Lean meat, bacon shield', [275, 325], 145, null, null, 8, 'Bacon keeps the lean tenderloin from drying.'),
      S('teriyaki', 'Teriyaki', 'Japan', 'Sweet soy glaze', [325, 375], 145, null, null, 5, 'Glazed with sweet soy, sesame and scallion.'),
    ],
    pork_ham: [
      S('honey_baked', 'Honey Baked', 'Classic', 'Honey, clove, pineapple', [225, 275], 140, null, 30, 20, 'Scored, studded with clove, then honey-glazed.'),
      S('double_smoked', 'Double Smoked', 'Modern', 'Re-smoked, deep bark', [225, 275], 145, null, 30, 20, 'Fully cooked ham re-smoked for a deeper bark.'),
      S('dr_pepper', 'Dr Pepper Glaze', 'Texas', 'Soda-spiked sweet glaze', [225, 275], 140, null, 30, 20, 'Basted in a Dr Pepper and brown sugar reduction.'),
    ],
    pork_char_siu: [
      S('cantonese', 'Cantonese', 'China', 'Maltose, char, red lacquer', [300, 375], 145, null, null, 10, 'The Cantonese original — maltose, soy and red fermented bean curd.'),
      S('honey_char', 'Honey Char', 'Modern', 'Honey-soy lacquer', [300, 375], 145, null, null, 10, 'A honey-forward lacquer for extra stickiness.'),
    ],
    pork_carnitas: [
      S('citrus', 'Citrus Braise', 'Mexico', 'Orange, lime, garlic', [250, 300], 200, [165, 'Cover / wrap', 'Braise in citrus and lard until shreddable.'], null, 20, 'Orange, lime and garlic braise, crisped at the end.'),
      S('confit', 'Confit', 'France', 'Slow in its own fat', [225, 275], 200, [165, 'Cover in fat', 'Cook gently in lard, then crisp.'], null, 20, 'Pork shoulder confit in lard — impossibly tender.'),
    ],
    pork_suckling: [
      S('lechon', 'Lechón', 'Philippines', 'Whole pig, crisp skin', [250, 300], 145, null, 30, 45, 'Whole roasted pig with shatteringly crisp skin.'),
      S('cuban', 'Cuban Lechón', 'Cuba', 'Mojo, garlic, sour orange', [250, 300], 145, null, 30, 45, 'Mojo-marinated then roasted low until the skin cracks.'),
      S('crackling', 'Crackling Focus', 'Classic', 'Dry skin, oil, salt', [275, 325], 145, null, 30, 45, 'Skin dried overnight for maximum crackle.'),
    ],
    pork_head: [
      S('cochon_de_lait', 'Cochon de Lait', 'Louisiana', 'Slow pit, juicy, smoky', [250, 275], 190, null, 45, 45, 'Cajun whole-hog pit roast, pulled and dressed.'),
      S('porchetta_di_testa', 'Porchetta di Testa', 'Italy', 'Rolled head cheese', [225, 275], 160, [150, 'Press overnight', 'Pressed into a terrine and chilled.'], null, 60, 'Boneless rolled head, poached, pressed and sliced.'),
    ],
    pork_hock: [
      S('braised', 'Braised', 'Classic', 'Collard-rich, gelatinous', [250, 300], 200, [165, 'Braise covered', 'With collards, beans or sauerkraut.'], null, 20, 'The seasoning bone — braised for gelatin and depth.'),
      S('smoked', 'Smoked', 'Southern', 'Split, smoky, intense', [225, 275], 200, [165, 'Wrap', 'Split it so the smoke gets in.'], 45, 20, 'Split and smoked hard for a strong ham hock.'),
    ],

    // ── Poultry ───────────────────────────────────────────────────────
    poultry_whole: [
      S('classic_roast', 'Classic Roast', 'Classic', 'Butter under the skin', [275, 325], 165, null, null, 20, 'Rub butter under the breast skin.'),
      S('spatchcock', 'Spatchcock', 'Modern', 'Flat and fast', [350, 400], 165, null, null, 10, 'Backbone out, pressed flat — cuts the time nearly in half.'),
      S('cajun_injected', 'Cajun Injected', 'Louisiana', 'Butter-garlic injection', [300, 350], 165, null, null, 20, 'Injected with Cajun butter, rubbed inside and out.'),
      S('maple_brined', 'Maple Brined', 'Vermont', 'Maple, salt, rosemary', [275, 325], 165, null, null, 20, 'Maple brine keeps the breast juicy under high heat.'),
      S('jerk', 'Jerk', 'Jamaica', 'Scotch bonnet, allspice', [325, 375], 165, null, 30, 20, 'Spatchcocked and slathered in jerk paste.'),
    ],
    poultry_turkey_breast: [
      S('cajun', 'Cajun', 'Louisiana', 'Creole butter injection', [275, 325], 165, null, null, 15, 'Injected with Creole butter, rubbed in Cajun spice.'),
      S('brined', 'Brined', 'Classic', 'Wet brine, herbs', [275, 325], 165, null, null, 15, 'Overnight brine, then herb butter under the skin.'),
      S('herb', 'Herb Butter', 'Classic', 'Rosemary, thyme, sage', [275, 325], 165, null, null, 15, 'Herb butter stuffed under the skin.'),
    ],
    poultry_breast: [
      S('blackened', 'Blackened', 'Cajun', 'Spice crust, hot pan', [375, 425], 165, null, null, 5, 'Cajun spice seared hard for a black crust.'),
      S('teriyaki', 'Teriyaki', 'Japan', 'Sweet soy, sesame', [350, 400], 165, null, null, 5, 'Glazed with sweet soy and sesame.'),
      S('souvlaki', 'Souvlaki', 'Greece', 'Lemon, oregano, yogurt', [375, 425], 165, null, null, 5, 'Lemon-oregano marinade, grilled on skewers.'),
    ],
    poultry_thigh: [
      S('yakitori', 'Yakitori', 'Japan', 'Tare glaze, binchotan', [375, 425], 180, null, null, 5, 'Skewered and basted with tare over hot coals.'),
      S('jerk', 'Jerk', 'Jamaica', 'Scotch bonnet, pimento', [325, 375], 180, null, 20, 5, 'Dark meat takes jerk beautifully — smoky and fiery.'),
      S('tandoori', 'Tandoori', 'India', 'Yogurt, garam masala', [375, 425], 180, null, null, 5, 'Yogurt-and-spice marinade, charred hot.'),
      S('cajun', 'Cajun', 'Louisiana', 'Blackening spice', [375, 425], 180, null, null, 5, 'Bold blackening spice on juicy dark meat.'),
    ],
    poultry_wings: [
      S('buffalo', 'Buffalo', 'New York', 'Butter, cayenne, vinegar', [375, 425], 175, null, null, 5, 'Crisp them first, then toss in classic buffalo sauce.'),
      S('korean_gochujang', 'Korean Gochujang', 'Korea', 'Sweet-spicy chilli glaze', [375, 425], 175, null, null, 5, 'Gochujang, honey and sesame — sticky and fiery.'),
      S('jerk', 'Jerk', 'Jamaica', 'Scotch bonnet rub', [375, 425], 175, null, null, 5, 'Jerk-rubbed and grilled until charred at the edges.'),
      S('lemon_pepper', 'Lemon Pepper', 'Modern', 'Buttery lemon, cracked pepper', [375, 425], 175, null, null, 5, 'Tossed in lemon-pepper butter the moment they come off.'),
    ],
    poultry_spatchcock: [
      S('tandoori', 'Tandoori', 'India', 'Yogurt, garam masala', [375, 425], 165, null, null, 10, 'Flat bird, tandoori marinade, hard char.'),
      S('jerk', 'Jerk', 'Jamaica', 'Pimento, scotch bonnet', [350, 400], 165, null, 20, 10, 'Jerk paste under and over the skin.'),
      S('lemon_herb', 'Lemon & Herb', 'Provence', 'Herbes de Provence, lemon', [350, 400], 165, null, null, 10, 'Herbes de Provence and lemon halves under the bird.'),
    ],
    poultry_beercan: [
      S('stout', 'Stout Can', 'Modern', 'Coffee stout steam', [325, 375], 165, null, null, 10, 'A stout in the can steams and darkens the meat.'),
      S('cajun', 'Cajun Can', 'Louisiana', 'Creole butter, beer', [325, 375], 165, null, null, 10, 'Creole-spiced, sat on a can of lager.'),
    ],
    poultry_duck: [
      S('peking', 'Peking', 'China', 'Crisp skin, scallion, pancake', [250, 300], 165, null, null, 15, 'Air-dried skin, roasted crisp, served with pancakes.'),
      S('tea_smoked', 'Tea Smoked', 'China', 'Lapsang, rice, brown sugar', [200, 250], 155, null, null, 15, 'Smoked over tea leaves and rice, then roasted.'),
      S('orange', 'Orange Glazed', 'France', 'Orange, honey, star anise', [300, 350], 160, null, null, 15, 'Glazed with orange, honey and star anise.'),
    ],
    poultry_cornish: [
      S('bacon_wrapped', 'Bacon Wrapped', 'Classic', 'Bacon, herbs, lemon', [325, 375], 165, null, null, 10, 'A bacon blanket keeps these little birds moist.'),
      S('herb', 'Herb Roasted', 'Provence', 'Thyme, rosemary, garlic', [325, 375], 165, null, null, 10, 'Stuffed with herbs and roasted until golden.'),
    ],
    poultry_legs: [
      S('jerk', 'Jerk', 'Jamaica', 'Scotch bonnet, allspice', [325, 375], 175, null, 20, 5, 'Jerk marinade, grilled slow then hard at the end.'),
      S('tandoori', 'Tandoori', 'India', 'Yogurt, garam masala', [375, 425], 175, null, null, 5, 'Yogurt marinade, charred and finished with lime.'),
      S('adobo', 'Adobo', 'Philippines', 'Soy, vinegar, bay, garlic', [325, 375], 175, null, null, 5, 'Soy-vinegar adobo, braised then finished on the grill.'),
    ],
    poultry_duck_breast: [
      S('pan_roast', 'Pan Roast', 'France', 'Score the fat, render', [300, 350], 135, null, null, 8, 'Score and render the fat, finish skin-side down.'),
      S('honey_soy', 'Honey Soy', 'Asia', 'Honey, soy, five-spice', [350, 400], 135, null, null, 5, 'Glazed with honey, soy and five-spice.'),
    ],
    poultry_turkey_legs: [
      S('cajun', 'Cajun', 'Louisiana', 'Creole butter injected', [300, 350], 175, null, null, 15, 'Legs take longer than the breast — cook to 175°F.'),
      S('smoked', 'Cherry Smoked', 'Modern', 'Fruitwood, brown sugar', [275, 325], 175, null, 30, 15, 'Cherry wood and a brown-sugar rub.'),
    ],
    poultry_quail: [
      S('bacon_wrapped', 'Bacon Wrapped', 'Southern', 'Bacon, jalapeño, cream cheese', [375, 425], 165, null, null, 5, 'Stuffed with jalapeño cream cheese and wrapped in bacon.'),
      S('marinated', 'Citrus Marinated', 'Mediterranean', 'Lemon, oregano, olive oil', [375, 425], 165, null, null, 5, 'A quick citrus-herb marinade, grilled fast.'),
    ],
    poultry_pheasant: [
      S('bacon_wrapped', 'Bacon Wrapped', 'Classic', 'Lean bird, bacon shield', [325, 375], 165, null, 30, 10, 'Bacon and a butter baste keep this lean bird moist.'),
      S('cider_brined', 'Cider Brined', 'Modern', 'Apple cider brine', [325, 375], 165, null, null, 10, 'Apple-cider brine, roasted with apples and onion.'),
    ],
    poultry_liver: [
      S('rumaki', 'Rumaki', 'Tiki', 'Bacon, water chestnut, teriyaki', [375, 425], 165, null, null, 5, 'Bacon-wrapped chicken liver with a teriyaki glaze.'),
      S('pâté', 'Country Pâté', 'France', 'Brandy, herbs, coarse', [275, 325], 165, [160, 'Bath and chill', 'Bake in a water bath, then press and chill.'], null, 120, 'A coarse country pâté with brandy and thyme.'),
    ],

    // ── Seafood ───────────────────────────────────────────────────────
    fish_salmon: [
      S('cedar', 'Cedar Plank', 'Pacific NW', 'Soaked plank, low heat', [225, 275], 145, null, null, 5, 'Soak the plank, smoke low, gentle finish.'),
      S('hot_fast', 'Hot & Fast', 'Modern', 'Skin down, crisp', [325, 375], 145, null, null, 3, 'Crisp the skin, keep the centre moist.'),
      S('teriyaki', 'Teriyaki', 'Japan', 'Sweet soy, sesame', [325, 375], 145, null, null, 3, 'Glazed with sweet soy and finished with sesame.'),
      S('hot_smoked', 'Hot Smoked', 'Scandinavia', 'Cured, smoked, flaky', [200, 250], 145, null, null, 5, 'Light cure then a long, cool smoke for flaky hot-smoked salmon.'),
      S('dijon_plank', 'Dijon & Dill', 'Scandinavia', 'Mustard, dill, lemon', [225, 275], 145, null, null, 5, 'Dijon-dill butter under a lemon slice.'),
    ],
    fish_trout: [
      S('lemon_butter', 'Lemon Butter', 'Classic', 'Lemon, capers, butter', [225, 275], 145, null, null, 5, 'Stuffed with lemon and dill, basted in butter.'),
      S('bacon_wrapped', 'Bacon Wrapped', 'Campfire', 'Bacon, herbs, whole fish', [275, 325], 145, null, null, 5, 'Whole trout wrapped in bacon and grilled in a basket.'),
      S('almondine', 'Almondine', 'France', 'Brown butter, almonds', [225, 275], 145, null, null, 5, 'Finished with brown butter and toasted almonds.'),
    ],
    fish_shrimp: [
      S('cajun', 'Cajun', 'Louisiana', 'Butter, garlic, cayenne', [325, 375], 145, null, null, 2, 'The shrimp boil flavours — butter, garlic and cayenne.'),
      S('scampi', 'Scampi', 'Italy', 'Garlic, white wine, butter', [325, 375], 145, null, null, 2, 'Garlic, white wine and lemon butter.'),
      S('garlic_butter', 'Garlic Butter', 'Classic', 'Garlic, parsley, lemon', [325, 375], 145, null, null, 2, 'Simple garlic-parsley butter, grilled on skewers.'),
    ],
    fish_tuna: [
      S('sesame_seared', 'Sesame Seared', 'Japan', 'Sesame crust, rare centre', [450, 550], 125, null, null, 3, 'Sesame crust, seared hard, raw in the middle.'),
      S('teriyaki', 'Teriyaki', 'Japan', 'Tare glazed, quick sear', [400, 500], 125, null, null, 3, 'Tare-glazed and seared just long enough to mark.'),
    ],
    fish_cod: [
      S('fish_taco', 'Fish Taco', 'Baja', 'Battered, cabbage, crema', [375, 425], 145, null, null, 3, 'Baja-style — flaky, bright, in a warm tortilla.'),
      S('lemon_butter', 'Lemon Butter', 'Classic', 'Lemon, parsley, butter', [225, 275], 145, null, null, 5, 'Gentle heat, lemon-parsley butter.'),
      S('miso', 'Miso Glazed', 'Japan', 'White miso, mirin, ginger', [325, 375], 145, null, null, 3, 'Sweet white-miso glaze that caramelises beautifully.'),
    ],
    fish_halibut: [
      S('miso_glazed', 'Miso Glazed', 'Japan', 'White miso, mirin', [325, 375], 145, null, null, 3, 'Miso-mirin glaze, broiled to a shine.'),
      S('blackened', 'Blackened', 'Cajun', 'Spice crust, cast iron', [400, 500], 145, null, null, 3, 'Hard Cajun crust on a meaty, lean fillet.'),
    ],
    fish_catfish: [
      S('cajun', 'Cajun', 'Louisiana', 'Cornmeal, cayenne, hot oil', [350, 400], 145, null, null, 3, 'The Louisiana classic — cornmeal and cayenne.'),
      S('cornmeal', 'Cornmeal Crusted', 'Southern', 'Buttermilk, cornmeal', [350, 400], 145, null, null, 3, 'Buttermilk dip, cornmeal crust, hot and fast.'),
    ],
    fish_swordfish: [
      S('salsa_verde', 'Salsa Verde', 'Italy', 'Parsley, capers, lemon', [375, 425], 145, null, null, 5, 'Grilled hard, served with a sharp salsa verde.'),
      S('lemon', 'Lemon & Olive Oil', 'Mediterranean', 'Lemon, oregano, olive oil', [325, 375], 145, null, null, 5, 'Simple lemon-oregano marinade, grilled over coals.'),
    ],
    fish_scallops: [
      S('bacon_wrapped', 'Bacon Wrapped', 'Classic', 'Bacon, maple, sear', [400, 500], 145, null, null, 2, 'Maple-glazed bacon wrapped around a dry scallop.'),
      S('cajun', 'Cajun', 'Louisiana', 'Blackening spice', [450, 550], 145, null, null, 2, 'Blackening spice and a screaming-hot sear.'),
    ],
    fish_lobster: [
      S('garlic_butter', 'Garlic Butter', 'Classic', 'Butter, garlic, lemon', [300, 350], 140, null, null, 3, 'Split, brushed with garlic butter, grilled shell-down.'),
      S('cajun', 'Cajun Butter', 'Louisiana', 'Creole butter, cayenne', [300, 350], 140, null, null, 3, 'Creole butter with a cayenne kick.'),
    ],
    fish_crab: [
      S('garlic_butter', 'Garlic Butter', 'Classic', 'Butter, garlic, parsley', [300, 350], 140, null, null, 2, 'Warmed through in a foil pan of garlic butter.'),
      S('cajun', 'Cajun', 'Louisiana', 'Old Bay, butter, lemon', [300, 350], 140, null, null, 2, 'Old Bay, butter and lemon — the porch pick.'),
    ],
    fish_oysters: [
      S('charbroiled', 'Charbroiled', 'Gulf', 'Butter, garlic, parmesan', [400, 500], 145, null, null, 5, 'On the half shell over a hot fire with garlic-parmesan butter.'),
      S('rockefeller', 'Rockefeller', 'New Orleans', 'Spinach, absinthe, parmesan', [375, 425], 145, null, null, 5, 'The New Orleans classic — spinach, herbs and parmesan.'),
    ],
    fish_mackerel: [
      S('teriyaki', 'Teriyaki', 'Japan', 'Sweet soy, sesame', [325, 375], 145, null, null, 3, 'Oily and rich — brilliant with a sweet-soy glaze.'),
      S('salt_grill', 'Salt Grilled', 'Japan', 'Coarse salt, crisp skin', [400, 500], 145, null, null, 3, 'Salted and grilled skin-side down until crisp.'),
    ],
    fish_sardines: [
      S('grilled', 'Simple Grilled', 'Mediterranean', 'Olive oil, lemon, parsley', [400, 500], 145, null, null, 2, 'Whole sardines, oiled and grilled fast over coals.'),
      S('escabeche', 'Escabeche', 'Spain', 'Vinegar, onion, bay', [350, 400], 145, null, null, 2, 'Fried then marinated in a vinegar-escabeche.'),
    ],
    fish_mussels: [
      S('wine_garlic', 'White Wine & Garlic', 'France', 'Wine, shallot, parsley', [375, 425], 145, null, null, 2, 'Steamed open in white wine, shallot and parsley.'),
      S('smoked', 'Smoked', 'Modern', 'Smoke, then steam', [225, 275], 145, null, null, 2, 'Smoked briefly then finished in a covered pan.'),
    ],
    fish_clams: [
      S('garlic_butter', 'Garlic Butter', 'Classic', 'Garlic, butter, parsley', [375, 425], 145, null, null, 2, 'Littlenecks opened in garlic butter.'),
      S('chowder', 'Smoked Chowder', 'New England', 'Cream, bacon, potato', [250, 300], 165, null, null, 5, 'Smoked clams folded into a creamy chowder.'),
    ],
    fish_squid: [
      S('calamari', 'Grilled Calamari', 'Mediterranean', 'Lemon, olive oil, chilli', [400, 500], 145, null, null, 2, 'Hot and fast — squid turns rubbery if overcooked.'),
      S('salt_pepper', 'Salt & Pepper', 'Cantonese', 'Five-spice, chilli, scallion', [450, 550], 145, null, null, 2, 'The Cantonese salt-and-pepper treatment.'),
    ],
    fish_octopus: [
      S('galician', 'Galician', 'Spain', 'Boiled, paprika, olive oil', [225, 275], 175, null, null, 10, 'Boiled tender then grilled and dressed in paprika oil.'),
      S('charred', 'Charred', 'Mediterranean', 'Lemon, oregano', [375, 425], 175, null, null, 10, 'Braised first, then charred over the fire.'),
    ],
    fish_alligator: [
      S('cajun', 'Cajun', 'Louisiana', 'Blackened, cayenne', [375, 425], 160, null, null, 3, 'Firm, mild and lean — blackened hard and fast.'),
      S('fried', 'Southern Fried', 'Southern', 'Buttermilk, cornmeal', [375, 425], 160, null, null, 3, 'Buttermilk and cornmeal, fried golden.'),
    ],
    fish_frog_legs: [
      S('cajun', 'Cajun', 'Louisiana', 'Blackened, garlic butter', [375, 425], 160, null, null, 3, 'The Cajun classic — blackened and finished in garlic butter.'),
      S('lemon_butter', 'Lemon Butter', 'Classic', 'Lemon, parsley, butter', [375, 425], 160, null, null, 3, 'Delicate and mild — basted in lemon butter.'),
    ],
    fish_crawfish: [
      S('boil', 'Cajun Boil', 'Louisiana', 'Zatarain’s, corn, potato', [350, 400], 165, null, null, 2, 'The crawfish boil — heavily seasoned, with corn and potato.'),
      S('smoked', 'Smoked Tails', 'Modern', 'Butter, garlic, smoke', [250, 300], 165, null, null, 2, 'Tails smoked gently then tossed in garlic butter.'),
    ],
    fish_whole_bass: [
      S('salt_grill', 'Salt Grilled', 'Mediterranean', 'Whole, lemon, herbs', [375, 425], 145, null, null, 5, 'Whole fish stuffed with lemon and herbs, grilled in a basket.'),
      S('banana_leaf', 'Banana Leaf', 'Asia', 'Ginger, scallion, lime', [325, 375], 145, null, null, 5, 'Wrapped in banana leaf with ginger and scallion.'),
    ],

    // ── Lamb ──────────────────────────────────────────────────────────
    lamb_chops: [
      S('tandoori', 'Tandoori', 'India', 'Yogurt, garam masala', [400, 500], 135, null, null, 5, 'Yogurt marinade, charred hard on the outside.'),
      S('rosemary_garlic', 'Rosemary & Garlic', 'Provence', 'Garlic, rosemary, olive oil', [375, 425], 135, null, null, 5, 'Rub with garlic and rosemary, grill fast.'),
      S('harissa', 'Harissa', 'North Africa', 'Chilli paste, cumin, coriander', [400, 500], 135, null, null, 5, 'Harissa-rubbed and grilled until blistered.'),
    ],
    lamb_leg: [
      S('rosemary_garlic', 'Rosemary & Garlic', 'Provence', 'Studded and roasted', [225, 275], 135, null, 45, 20, 'Stud with garlic and rosemary.'),
      S('moroccan', 'Moroccan', 'Morocco', 'Ras el hanout, apricot', [250, 300], 145, null, 45, 20, 'Ras el hanout and apricots — sweet, spiced and tender.'),
      S('greek', 'Greek', 'Greece', 'Lemon, oregano, potato', [250, 300], 140, null, 45, 20, 'Lemon, oregano and potatoes roasted in the pan.'),
      S('tandoori', 'Tandoori', 'India', 'Yogurt, garam masala', [325, 375], 145, null, null, 15, 'Yogurt marinated and roasted hard, no wrap.'),
    ],
    lamb_shoulder: [
      S('moroccan', 'Moroccan', 'Morocco', 'Ras el hanout, apricot, almond', [250, 275], 200, [165, 'Cover', 'Braise with spices, apricots and almonds.'], 60, 30, 'Slow-braised Moroccan lamb with dried fruit.'),
      S('harissa', 'Harissa Pulled', 'North Africa', 'Chilli, cumin, coriander', [250, 275], 200, [165, 'Wrap', 'Chilli paste and aromatics in the wrap.'], 60, 30, 'Harissa-rubbed and pulled for wraps and flatbread.'),
      S('pulled', 'Smoked Pulled', 'Modern', 'Rub, smoke, pull', [250, 275], 200, [165, 'Wrap', 'Foil to finish and rest.'], 60, 30, 'Dry-rubbed, smoked low and pulled like pork.'),
    ],
    lamb_rack: [
      S('pistachio_crusted', 'Pistachio Crusted', 'Modern', 'Pistachio, dijon, breadcrumb', [250, 300], 135, null, null, 10, 'Dijon-herb coat with crushed pistachio.'),
      S('dijon', 'Dijon & Herb', 'French', 'Dijon, thyme, garlic', [250, 300], 135, null, null, 10, 'The French classic — dijon, thyme and garlic.'),
      S('tandoori', 'Tandoori', 'India', 'Yogurt, garam masala', [300, 350], 135, null, null, 8, 'Yogurt marinade, roasted to a charred blush.'),
    ],
    lamb_shanks: [
      S('osso_buco', 'Osso Buco', 'Italy', 'Milanese, gremolata, saffron', [250, 275], 200, [165, 'Braise covered', 'Wine, tomato and gremolata.'], null, 20, 'A lamb version of the Milanese classic.'),
      S('moroccan', 'Moroccan', 'Morocco', 'Ras el hanout, chickpea', [250, 275], 200, [165, 'Braise covered', 'With chickpeas, apricots and spice.'], null, 20, 'Spiced, fruity braise until it falls off the bone.'),
    ],
    lamb_kofta: [
      S('tandoori', 'Tandoori', 'India', 'Yogurt, garam masala', [325, 375], 160, null, null, 3, 'Skewered, spiced and grilled over coals.'),
      S('merguez', 'Merguez', 'North Africa', 'Harissa, cumin, coriander', [325, 375], 160, null, null, 3, 'The North African sausage — smoky, spicy and lamby.'),
      S('mint_yogurt', 'Mint Yogurt', 'Mediterranean', 'Mint, sumac, yogurt', [325, 375], 160, null, null, 3, 'Served with mint-yogurt and sumac onion.'),
    ],
    lamb_ribs: [
      S('kansas_city', 'Kansas City', 'Missouri', 'Sweet rub, sauce glaze', [250, 275], 200, [165, 'Wrap', 'Butter, honey and sauce in the wrap.'], 45, 15, 'Ribs from the lamb breast — rich and sweet.'),
      S('harissa', 'Harissa', 'North Africa', 'Chilli, honey, lemon', [250, 275], 200, [165, 'Wrap', 'Chilli-honey baste.'], 45, 15, 'Fiery harissa and honey basted lamb ribs.'),
    ],

    // ── Game ──────────────────────────────────────────────────────────
    game_venison: [
      S('juniper', 'Juniper & Gin', 'Nordic', 'Juniper, rosemary, cream', [225, 275], 135, null, 30, 20, 'Juniper berries and rosemary keep the lean, gamy meat elegant.'),
      S('bacon_wrapped', 'Bacon Wrapped', 'Campfire', 'Bacon, thyme, pepper', [250, 300], 135, null, 30, 20, 'Bacon-and-herb wrap protects the lean roast.'),
    ],
    game_boar: [
      S('italian_ragu', 'Italian Ragù', 'Italy', 'Chianti, tomato, rosemary', [250, 275], 200, [165, 'Braise covered', 'Slow braise in Chianti and tomato.'], 60, 45, 'Wild boar ragù — richer and gamer than pork.'),
      S('pulled', 'Pulled', 'Modern', 'Rub, smoke, pull', [225, 275], 200, [165, 'Wrap', 'Foil to finish.'], 60, 45, 'Smoked and pulled like pork shoulder, a touch leaner.'),
    ],
    game_bison: [
      S('blackened', 'Blackened', 'Cajun', 'Spice crust, hot sear', [400, 500], 130, null, null, 5, 'Leaner than beef — hard sear, pull early.'),
      S('reverse_sear', 'Reverse Sear', 'Modern', 'Low, then blast', [225, 275], 130, null, null, 6, 'Even blush with a dark crust.'),
    ],
    game_rabbit: [
      S('hunter', 'Hunter Style', 'Italy', 'Tomato, olive, wine, herbs', [250, 300], 160, [160, 'Braise covered', 'With tomato, olives and white wine.'], 20, 10, 'Coniglio alla cacciatora — braised with olives and wine.'),
      S('bacon_wrapped', 'Bacon Wrapped', 'Campfire', 'Bacon, herbs, butter', [225, 275], 160, null, 20, 10, 'Basted with butter and wrapped in bacon.'),
    ],
    game_elk: [
      S('juniper', 'Juniper Rubbed', 'Nordic', 'Juniper, pepper, smoke', [225, 275], 130, null, 30, 20, 'Lean and herbaceous — smoke gently and never overshoot.'),
      S('coffee_cocoa', 'Coffee & Cocoa', 'Modern', 'Coffee, cocoa, chilli', [250, 300], 135, null, 30, 20, 'A coffee-cocoa crust for a gamy, lean roast.'),
    ],
    game_antelope: [
      S('herb_crusted', 'Herb Crusted', 'Modern', 'Thyme, pepper, mustard', [225, 275], 130, null, 30, 20, 'Very lean — cook fast and rest well.'),
    ],
    game_squirrel: [
      S('smothered', 'Smothered', 'Southern', 'Gravy, onion, bay', [250, 300], 165, [165, 'Braise covered', 'Smother in onion gravy until tender.'], 20, 10, 'Classic Southern smothered squirrel and gravy.'),
    ],
    game_wild_turkey: [
      S('cajun', 'Cajun Injected', 'Louisiana', 'Creole butter injection', [300, 350], 165, null, null, 20, 'Leaner and drier than farmed — inject generously.'),
      S('herb', 'Herb Roasted', 'Classic', 'Sage, thyme, butter', [275, 325], 165, null, null, 20, 'Herb butter under the skin, roasted low.'),
    ],

    // ── Veggies ───────────────────────────────────────────────────────
    veg_potato: [
      S('loaded', 'Loaded', 'Diner', 'Cheddar, bacon, sour cream', [350, 400], 205, null, null, 5, 'Split and loaded with cheddar, bacon and scallion.'),
      S('rosemary', 'Rosemary Salt', 'Provence', 'Rosemary, sea salt, oil', [350, 400], 205, null, null, 5, 'Rubbed in oil, rosemary and flaky salt.'),
    ],
    veg_corn: [
      S('elote', 'Elote', 'Mexico', 'Mayo, cotija, chilli, lime', [350, 400], 180, null, null, 0, 'Charred, then rolled in crema, cotija and chilli.'),
      S('honey_butter', 'Honey Butter', 'Classic', 'Honey, butter, pepper', [350, 400], 180, null, null, 0, 'Basted in honey butter and turned often.'),
    ],
    veg_mushrooms: [
      S('garlic_butter', 'Garlic Butter', 'Classic', 'Garlic, butter, parsley', [225, 275], 160, null, null, 0, 'In a foil pan with garlic butter and thyme.'),
      S('soy_sesame', 'Soy Sesame', 'Asia', 'Soy, sesame, ginger', [225, 275], 160, null, null, 0, 'Soy, sesame and ginger — great with any smoke.'),
    ],
    veg_skewers: [
      S('balsamic', 'Balsamic', 'Mediterranean', 'Balsamic, garlic, herbs', [325, 375], 175, null, null, 0, 'Balsamic-garlic marinade, charred at the edges.'),
      S('tandoori', 'Tandoori', 'India', 'Yogurt, garam masala', [350, 400], 175, null, null, 0, 'Yogurt-marinated and charred hot.'),
    ],
    veg_peppers: [
      S('mexican', 'Mexican', 'Mexico', 'Black bean, corn, queso', [350, 400], 175, null, null, 5, 'Stuffed with black beans, corn and queso fresco.'),
      S('italian', 'Italian', 'Italy', 'Sausage, rice, parmesan', [350, 400], 175, null, null, 5, 'Stuffed with sausage, rice and parmesan.'),
    ],
    veg_asparagus: [
      S('lemon_parm', 'Lemon Parmesan', 'Mediterranean', 'Lemon, parmesan, oil', [375, 425], 170, null, null, 0, 'Oiled, grilled, then lemon and shaved parmesan.'),
      S('balsamic', 'Balsamic', 'Mediterranean', 'Balsamic glaze, garlic', [375, 425], 170, null, null, 0, 'Finished with a balsamic glaze reduction.'),
    ],
    veg_cauli: [
      S('buffalo', 'Buffalo', 'Modern', 'Hot sauce, butter, blue cheese', [375, 425], 190, null, null, 0, 'Charred then tossed in buffalo sauce.'),
      S('tahini', 'Tahini & Herb', 'Middle East', 'Tahini, lemon, za’atar', [350, 400], 190, null, null, 0, 'Drizzled with tahini-lemon and za’atar.'),
    ],
    veg_broccoli: [
      S('soy_sesame', 'Soy Sesame', 'Asia', 'Soy, sesame, garlic', [300, 350], 170, null, null, 0, 'Tossed in soy, sesame and garlic.'),
      S('cheesy', 'Cheesy', 'Classic', 'Cheddar, cream', [350, 400], 175, null, null, 0, 'Smoked then smothered in a cheddar cream.'),
    ],
    veg_zucchini: [
      S('italian', 'Italian', 'Italy', 'Olive oil, parmesan, basil', [350, 400], 175, null, null, 0, 'Grilled planks with olive oil, parmesan and basil.'),
      S('miso', 'Miso Glazed', 'Japan', 'Miso, mirin, sesame', [350, 400], 175, null, null, 0, 'Miso-mirin glaze that caramelises on the grate.'),
    ],
    veg_tofu: [
      S('szechuan', 'Szechuan', 'China', 'Chilli bean paste, peppercorn', [250, 300], 165, null, null, 0, 'Pressed, smoked, then tossed in chilli bean paste.'),
      S('teriyaki', 'Teriyaki', 'Japan', 'Sweet soy, sesame', [250, 300], 165, null, null, 0, 'Teriyaki-glazed smoked tofu.'),
    ],
    veg_halloumi: [
      S('honey_chili', 'Honey Chilli', 'Modern', 'Honey, chilli, lime', [375, 425], 165, null, null, 0, 'Golden then drizzled with honey and chilli.'),
      S('herb', 'Herb Oil', 'Mediterranean', 'Oregano, olive oil, lemon', [375, 425], 165, null, null, 0, 'Brushed with oregano oil and lemon.'),
    ],
    veg_artichoke: [
      S('lemon_butter', 'Lemon Butter', 'Classic', 'Lemon, butter, garlic', [350, 400], 190, null, null, 5, 'Halved, oiled and grilled, served with lemon butter.'),
      S('romesco', 'Romesco', 'Spain', 'Romesco sauce, almond', [350, 400], 190, null, null, 5, 'Charred and served with romesco.'),
    ],
    veg_cabbage: [
      S('charred_wedge', 'Charred Wedge', 'Modern', 'Olive oil, lemon, parmesan', [375, 425], 175, null, null, 0, 'Thick wedges, charred hard, dressed with lemon.'),
      S('bacon_braised', 'Bacon Braised', 'Southern', 'Bacon, cider, bay', [250, 300], 175, [165, 'Cover', 'Braise with bacon and cider.'], null, 5, 'Smoked then braised with bacon and cider vinegar.'),
    ],
    veg_brussels: [
      S('bacon_maple', 'Bacon Maple', 'Modern', 'Bacon, maple, balsamic', [350, 400], 175, null, null, 0, 'Charred sprouts with bacon and a maple drizzle.'),
      S('balsamic', 'Balsamic', 'Mediterranean', 'Balsamic, garlic', [350, 400], 175, null, null, 0, 'Tossed in balsamic and garlic.'),
    ],
    veg_okra: [
      S('cajun', 'Cajun', 'Louisiana', 'Cajun spice, oil', [350, 400], 170, null, null, 0, 'Whole pods, Cajun-rubbed and grilled dry.'),
      S('smothered', 'Smothered', 'Southern', 'Tomato, onion, pepper', [300, 350], 175, null, null, 5, 'Smothered with tomato, onion and bell pepper.'),
    ],
    veg_eggplant: [
      S('baba_ganoush', 'Baba Ganoush', 'Middle East', 'Tahini, garlic, lemon', [350, 400], 190, null, null, 0, 'Smoked whole until collapsed, then blended with tahini.'),
      S('miso', 'Miso Glazed', 'Japan', 'Miso, mirin, sesame', [350, 400], 185, null, null, 0, 'Miso-glazed halves, roasted until glossy.'),
    ],
    veg_sweet_potato: [
      S('cinnamon_butter', 'Cinnamon Butter', 'Classic', 'Cinnamon, butter, brown sugar', [350, 400], 205, null, null, 5, 'Roasted and split with cinnamon butter.'),
      S('chipotle', 'Chipotle', 'Mexico', 'Chipotle, honey, lime', [350, 400], 205, null, null, 5, 'Chipotle-honey butter and lime.'),
    ],
    veg_plantain: [
      S('maduros', 'Maduros', 'Caribbean', 'Sweet, caramelised', [350, 400], 180, null, null, 0, 'Ripe plantains grilled until caramelised.'),
      S('tostones', 'Tostones', 'Caribbean', 'Twice-fried, salty', [375, 425], 175, null, null, 0, 'Green plantains smashed and grilled crisp.'),
    ],
    veg_onion: [
      S('blooming', 'Blooming', 'Fairground', 'Battered, spiced, fried', [350, 400], 175, null, null, 5, 'Cut, battered and grilled into a bloom.'),
      S('smoked_rings', 'Smoked Rings', 'Modern', 'Sweet onion, smoke', [300, 350], 175, null, null, 5, 'Thick sweet-onion rings, slow-smoked.'),
    ],
    veg_garlic: [
      S('roasted_bulb', 'Roasted Bulb', 'Classic', 'Olive oil, salt, foil', [300, 350], 175, null, null, 0, 'Whole bulbs, oiled and smoked until soft and sweet.'),
      S('smoked_confit', 'Smoked Confit', 'Modern', 'Oil-poached, thyme', [250, 300], 175, null, null, 0, 'Confit in oil with thyme until spreadable.'),
    ],
    veg_tomato: [
      S('smoked', 'Smoked Slices', 'Southern', 'Smoke, salt, olive oil', [225, 275], 175, null, null, 0, 'Thick slices, smoked low, salt and oil.'),
      S('blistered', 'Blistered', 'Mediterranean', 'High heat, oregano', [400, 500], 175, null, null, 0, 'Blistered on a ripping grate with oregano.'),
    ],
    veg_romaine: [
      S('grilled_caesar', 'Grilled Caesar', 'Modern', 'Caesar, parmesan, lemon', [375, 425], 170, null, null, 0, 'Halved, grilled cut-side down, dressed as Caesar.'),
      S('charred', 'Charred & Anchovy', 'Mediterranean', 'Anchovy, lemon, oil', [375, 425], 170, null, null, 0, 'Charred and drizzled with anchovy-lemon dressing.'),
    ],
    veg_avocado: [
      S('grilled', 'Grilled', 'Modern', 'Lime, chilli, oil', [375, 425], 165, null, null, 0, 'Halved, grilled cut-side down, finished with lime.'),
      S('smoked_guac', 'Smoked Guacamole', 'Mexico', 'Smoke, lime, onion', [225, 275], 165, null, null, 0, 'Smoked then mashed into a smoky guacamole.'),
    ],

    // ── Sides ─────────────────────────────────────────────────────────
    side_beans: [
      S('pit', 'Under-the-Pit', 'Texas', 'Catch the brisket drippings', [225, 275], 180, null, null, 0, 'Smoked under the brisket so every drip lands in the pan.'),
      S('bbq_bourbon', 'BBQ Bourbon', 'Modern', 'Bourbon, molasses, bacon', [225, 275], 180, null, null, 0, 'Bourbon, molasses and bacon — thick and boozy.'),
      S('pinto_texas', 'Texas Pintos', 'Texas', 'Pinto, chilli, cumin', [225, 275], 180, null, null, 0, 'Pintos with chilli, cumin and a ham hock.'),
    ],
    side_mac: [
      S('smoked_gouda', 'Smoked Gouda', 'Modern', 'Gouda, gruyère, crumb', [225, 275], 165, null, null, 10, 'Smoked gouda and gruyère under a buttery crumb.'),
      S('jalapeno', 'Jalapeño', 'Southwest', 'Jalapeño, cheddar, bacon', [225, 275], 165, null, null, 10, 'Jalapeño, cheddar and bacon folded through.'),
    ],
    side_queso: [
      S('chorizo', 'Chorizo', 'Tex-Mex', 'Chorizo, pepper, tomato', [225, 275], 160, null, null, 0, 'Chorizo and roasted pepper in a smooth cheese dip.'),
      S('salsa', 'Salsa Fuego', 'Mexico', 'Chile, tomato, onion', [225, 275], 160, null, null, 0, 'Smoked chile-tomato salsa blended into queso.'),
    ],
    side_cheese: [
      S('cheddar', 'Cold Smoked Cheddar', 'Wisconsin', 'Sharp cheddar, cold smoke', [70, 100], 90, null, null, 120, 'Never let it melt — cold smoke then rest and seal.'),
      S('gouda', 'Cold Smoked Gouda', 'Netherlands', 'Gouda, gentle smoke', [70, 100], 90, null, null, 120, 'A gentle cold smoke that turns gouda nutty and rich.'),
    ],
    side_pineapple: [
      S('brown_sugar', 'Brown Sugar', 'Modern', 'Brown sugar, butter, rum', [250, 300], 150, null, null, 0, 'Brown sugar, butter and a splash of rum.'),
      S('chili_lime', 'Chili Lime', 'Mexico', 'Chilli, lime, salt', [250, 300], 150, null, null, 0, 'Chilli-lime and flaky salt.'),
    ],
    side_peaches: [
      S('bourbon', 'Bourbon', 'Southern', 'Bourbon, brown sugar, butter', [225, 275], 150, null, null, 0, 'Halved, drizzled with bourbon and brown sugar.'),
      S('honey_ricotta', 'Honey Ricotta', 'Modern', 'Honey, ricotta, basil', [225, 275], 150, null, null, 0, 'Honeyed and served over whipped ricotta.'),
    ],
    side_nuts: [
      S('sweet_spicy', 'Sweet & Spicy', 'Modern', 'Sugar, cayenne, rosemary', [225, 275], 160, null, null, 0, 'Sugar, cayenne and rosemary, stirred often.'),
      S('rosemary', 'Rosemary Butter', 'Classic', 'Butter, rosemary, salt', [225, 275], 160, null, null, 0, 'Butter and rosemary, smoked low.'),
    ],
    side_cornbread: [
      S('jalapeno_cheddar', 'Jalapeño Cheddar', 'Southern', 'Jalapeño, cheddar, honey', [350, 400], 200, null, null, 10, 'Jalapeño and cheddar with a honey-butter top.'),
      S('honey', 'Honey Skillet', 'Southern', 'Honey, butter, cast iron', [350, 400], 200, null, null, 10, 'Baked in a hot skillet and brushed with honey butter.'),
    ],
    side_salsa: [
      S('charred', 'Charred Tomatillo', 'Mexico', 'Tomatillo, chile, lime', [225, 275], 170, null, null, 0, 'Charred tomatillos, chile and lime, then blitzed.'),
      S('mango_habanero', 'Mango Habañero', 'Mexico', 'Mango, habañero, lime', [225, 275], 170, null, null, 0, 'Sweet mango with a habañero bite.'),
    ],
    side_stuffing: [
      S('sausage_herb', 'Sausage & Herb', 'Classic', 'Sage, sausage, celery', [300, 350], 165, null, null, 10, 'Sage sausage stuffing smoked in a buttered dish.'),
      S('cornbread', 'Cornbread', 'Southern', 'Cornbread, pecan, herb', [300, 350], 165, null, null, 10, 'Cornbread, pecan and herb stuffing.'),
    ],
    side_scallop_potatoes: [
      S('cheddar', 'Cheddar', 'Classic', 'Cheddar, cream, onion', [350, 400], 175, null, null, 10, 'Thin-sliced potatoes in a cheddar cream.'),
      S('gruyere', 'Gruyère', 'French', 'Gruyère, thyme, cream', [350, 400], 175, null, null, 10, 'Gruyère and thyme gratin.'),
    ],
    side_green_bean: [
      S('classic', 'Classic Casserole', 'Classic', 'Mushroom, fried onion', [350, 400], 165, null, null, 10, 'Cream of mushroom and crispy fried onions.'),
      S('bacon', 'Bacon & Almond', 'Modern', 'Bacon, almond, garlic', [350, 400], 165, null, null, 10, 'Bacon, toasted almond and garlic green beans.'),
    ],
    side_collards: [
      S('ham_hock', 'Ham Hock', 'Southern', 'Ham hock, vinegar, pepper', [250, 300], 180, [165, 'Cover', 'Braise with ham hock until silky.'], null, 0, 'Slow-braised collards with ham hock and a splash of vinegar.'),
      S('smoked', 'Smoked', 'Southern', 'Smoke, onion, chilli', [225, 275], 180, null, null, 0, 'Smoked with onion and chilli, finished with vinegar.'),
    ],
    side_coleslaw: [
      S('vinegar', 'Vinegar', 'Carolina', 'Vinegar, sugar, celery seed', [225, 275], 0, null, null, 0, 'The Carolina pulled-pork partner — sharp and crunchy.'),
      S('creamy', 'Creamy', 'Classic', 'Mayo, buttermilk, dill', [225, 275], 0, null, null, 0, 'Creamy buttermilk slaw, good under anything.'),
    ],
    side_potato_salad: [
      S('mustard', 'Mustard', 'Southern', 'Mustard, egg, relish', [225, 275], 0, null, null, 0, 'Yellow-mustard potato salad with egg and relish.'),
      S('german', 'German', 'Germany', 'Bacon, vinegar, onion', [225, 275], 0, null, null, 0, 'Warm German potato salad with bacon and vinegar.'),
    ],
    side_corn_pudding: [
      S('creamed', 'Creamed', 'Southern', 'Cream, butter, corn', [350, 400], 175, null, null, 10, 'Creamy corn pudding with a golden top.'),
      S('jalapeno', 'Jalapeño', 'Southwest', 'Jalapeño, cheddar', [350, 400], 175, null, null, 10, 'Jalapeño-cheddar corn pudding.'),
    ],
    side_hushpuppies: [
      S('cajun', 'Cajun', 'Louisiana', 'Cornmeal, onion, cayenne', [375, 425], 175, null, null, 0, 'Cornmeal and onion, fried golden — Cajun spice.'),
      S('jalapeno', 'Jalapeño', 'Southwest', 'Jalapeño, cheddar, corn', [375, 425], 175, null, null, 0, 'Jalapeño-cheddar hushpuppies.'),
    ],

    // ── Desserts ──────────────────────────────────────────────────────
    dessert_apple_crisp: [
      S('oat_cinnamon', 'Oat Cinnamon', 'Classic', 'Oats, brown sugar, butter', [325, 375], 180, null, null, 15, 'Smoked until the oat topping is crisp and bubbling.'),
      S('bourbon_pecan', 'Bourbon Pecan', 'Southern', 'Bourbon, pecan, caramel', [325, 375], 180, null, null, 15, 'Bourbon caramel and toasted pecan crumble.'),
    ],
    dessert_banana_pudding: [
      S('classic', 'Classic', 'Southern', 'Vanilla wafer, cream', [70, 100], 80, null, null, 180, 'Cold-smoked bananas, then layered classic-Nilla pudding.'),
      S('bourbon', 'Bourbon', 'Southern', 'Bourbon, caramel, cream', [70, 100], 80, null, null, 180, 'A splash of bourbon in the custard.'),
    ],
    dessert_cobbler: [
      S('peach', 'Peach', 'Southern', 'Peach, butter, biscuit', [350, 400], 190, null, null, 15, 'The Southern peach cobbler, smoked until golden.'),
      S('berry', 'Berry', 'Classic', 'Mixed berry, sugar, biscuit', [350, 400], 190, null, null, 15, 'Mixed-berry cobbler with a buttermilk biscuit top.'),
    ],
    dessert_smores: [
      S('skillet', 'Skillet', 'Campfire', 'Chocolate, marshmallow, graham', [325, 375], 170, null, null, 5, 'A cast-iron skillet of chocolate, marshmallow and graham.'),
      S('bacon', 'Bacon', 'Modern', 'Bacon, chocolate, caramel', [325, 375], 170, null, null, 5, 'Bacon adds smoke and salt to the classic.'),
    ],
    dessert_brownies: [
      S('sea_salt', 'Sea Salt', 'Modern', 'Dark chocolate, flaky salt', [325, 375], 175, null, null, 20, 'Fudgy brownies finished with flaky sea salt.'),
      S('smoked_chocolate', 'Smoked Chocolate', 'Modern', 'Dark chocolate, smoke', [300, 350], 175, null, null, 20, 'The smoke deepens dark chocolate beautifully.'),
    ],
    dessert_cheesecake: [
      S('smoked', 'Smoked', 'Modern', 'Cream cheese, smoke, graham', [250, 300], 165, null, null, 240, 'Smoked gently, then chilled overnight.'),
      S('basque', 'Basque', 'Spain', 'Burnt top, custardy centre', [400, 500], 165, null, null, 240, 'A deliberately burnt top over a custardy centre.'),
    ],
    dessert_cinnamon_rolls: [
      S('cream_cheese', 'Cream Cheese', 'Classic', 'Cinnamon, cream cheese icing', [300, 350], 190, null, null, 20, 'Smoked, then frosted with cream cheese icing.'),
      S('maple_bacon', 'Maple Bacon', 'Modern', 'Maple, bacon, pecan', [300, 350], 190, null, null, 20, 'Maple-bacon icing and toasted pecan.'),
    ],
    dessert_grilled_fruit: [
      S('honey_yogurt', 'Honey Yogurt', 'Mediterranean', 'Honey, yogurt, pistachio', [375, 425], 150, null, null, 0, 'Stone fruit grilled hard, served with honey-yogurt.'),
      S('balsamic', 'Balsamic', 'Mediterranean', 'Balsamic, mint, sugar', [375, 425], 150, null, null, 0, 'Balsamic-mint glaze on charred fruit.'),
    ],

    // ── Misc ──────────────────────────────────────────────────────────
    misc_egg_bake: [
      S('bacon_cheddar', 'Bacon Cheddar', 'Classic', 'Bacon, cheddar, scallion', [325, 375], 160, null, null, 10, 'The diner standard — custard set through at 160°F.'),
      S('spinach_feta', 'Spinach Feta', 'Mediterranean', 'Spinach, feta, dill', [325, 375], 160, null, null, 10, 'Spinach and feta with dill, baked until just set.'),
    ],
    misc_casserole: [
      S('chorizo', 'Chorizo', 'Tex-Mex', 'Chorizo, pepper, potato', [300, 350], 160, null, null, 10, 'Chorizo, roasted pepper and potato, read at the centre.'),
      S('sausage_gravy', 'Sausage Gravy', 'Southern', 'Sausage, gravy, biscuit', [300, 350], 160, null, null, 10, 'Breakfast sausage and gravy baked under a biscuit top.'),
    ],
    misc_pizza: [
      S('margherita', 'Margherita', 'Italy', 'Tomato, mozzarella, basil', [450, 550], 205, null, null, 2, 'Hot stone, fast bake, smoky crust.'),
      S('bbq_chicken', 'BBQ Chicken', 'Modern', 'Smoked chicken, red onion, cilantro', [450, 550], 205, null, null, 2, 'Smoked chicken, BBQ sauce and red onion on a hot stone.'),
    ],
    misc_pretzel: [
      S('mustard', 'Mustard', 'Classic', 'Butter, mustard powder, salt', [225, 275], 160, null, null, 0, 'Seasoned butter and mustard powder, smoked low.'),
      S('cinnamon_sugar', 'Cinnamon Sugar', 'Sweet', 'Butter, cinnamon, sugar', [225, 275], 160, null, null, 0, 'A sweet smoked snack — cinnamon, sugar and butter.'),
    ],
    misc_jerky: [
      S('teriyaki', 'Teriyaki', 'Japan', 'Soy, ginger, mirin', [160, 180], 160, null, null, 0, 'Thin strips, low temp, dry until leathery.'),
      S('pepper', 'Cracked Pepper', 'Classic', 'Coarse pepper, soy, Worcestershire', [160, 180], 160, null, null, 0, 'The original: coarse pepper and a savoury marinade.'),
      S('cajun', 'Cajun', 'Louisiana', 'Cayenne, garlic, paprika', [160, 180], 160, null, null, 0, 'A hot Cajun marinade for a spicy jerky.'),
    ],
    misc_butter: [
      S('garlic_herb', 'Garlic & Herb', 'Classic', 'Garlic, parsley, sea salt', [180, 225], 80, null, null, 0, 'Cold-smoke a block with garlic and herbs folded in.'),
      S('maple', 'Maple', 'Vermont', 'Maple, flaky salt', [180, 225], 80, null, null, 0, 'Maple and flaky salt — unreal on cornbread.'),
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

  // ── Device identity, firmware and diagnostics ─────────────────────────
  // [FLUTTER] DEVICE maps to the `app_config` identity + `device_facts.dart`;
  // FIRMWARE maps to `app_ota`. The OTA rules are real and must survive:
  //   - upload is Wi-Fi only (AP or STA); Bluetooth cannot carry an image
  //   - an active recording session returns 409 `session_active` unless forced
  //   - a failed health gate within 120 s of boot auto-rolls back to the old slot
  const DEVICE = {
    id: 'A4F2-9C71',
    hardware: 'rev C · ESP32-S3',
    version: 'v1.4.2',
    versionDate: '2026-07-18',
    bootloader: '2.1.0',
    channel: 'stable',        // 'stable' | 'beta'
    available: null,          // populated by "Check for updates" (mock)
    uptimeMin: 4387,
    heapKb: 128,
    storage: { usedKb: 36, totalKb: 512, sessions: 12, days: 54 },
    lastCrash: null,
    logs: [
      { t: '09:12:04', level: 'info', text: 'LoRa sync acquired — base station paired' },
      { t: '09:12:09', level: 'info', text: 'Session SMK-4482 opened, 4 probes attached' },
      { t: '09:41:22', level: 'warn', text: 'Probe 3 detached briefly — reconnect 4 s' },
      { t: '09:58:01', level: 'info', text: 'Wi-Fi STA connected — 192.168.1.42' },
      { t: '10:02:47', level: 'info', text: 'Alarm rule pit_crash fired (device tier)' },
    ],
  };
  const FIRMWARE = {
    latest: 'v1.5.0',
    latestDate: '2026-09-02',
    sizeKb: 1024,
    notes: [
      'Faster BLE history streaming on long sessions',
      'Pit-crash rule: less sensitive to lid openings',
      'Fixes a rare AP fallback race after router loss',
    ],
    rollback: 'A failed health check within 120 s of boot auto-rolls back to the previous slot. Nothing is lost.',
  };

  // ── Exposed model ─────────────────────────────────────────────────────
  window.MOCK = {
    F, TIMELINES, CATALOG, CATEGORIES, STYLES, SCENARIOS, HISTORY, MODES, ALARM_RULES, EVENTS, DEVICE, FIRMWARE,
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
      otaChannel: 'stable',     // 'stable' | 'beta'
      forceOta: false,          // allow an OTA while a session is recording (409 override)
      customCatalog: [],        // user-defined foods (persisted in Flutter)
    },
  };
})();