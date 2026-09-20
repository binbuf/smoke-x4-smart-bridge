/* ============================================================================
 * mock-data.js — Smoke X4 Smart Bridge (new UI prototype)
 * ----------------------------------------------------------------------------
 * Static mock objects for the whole app. Nothing here talks to a real bridge.
 *
 * BUSINESS LOGIC NOTES FOR THE FLUTTER PORT
 * -----------------------------------------
 * This file is the *shape* of the app's data, not a transport. When this is
 * rebuilt in Flutter:
 *   - `MOCK.presets`      -> the preset library (already exists: domain/plan/presets.dart)
 *   - `MOCK.timelines`    -> NEW. A per-cut expected-cook database. This is the
 *                            one thing the current app does not have and the
 *                            Timeline tab depends on. See NOTES.md §Timeline DB.
 *   - `MOCK.scenario`     -> the four "situations" the UI must handle:
 *                            offline / connected-idle / running / alarming.
 *   - `MOCK.history`      -> past cooks (CookAnnotation windows over samples).
 *
 * INVARIANTS CARRIED FROM THE RESEARCH NOTES (do not break these in Flutter):
 *   I1  The bridge is a listener, never a transmitter (only one LoRa ack ever).
 *   I2  The device is authoritative. The app mirrors device alarms; it does not
 *       re-decide them. App-tier alarms are clearly labelled "advisory".
 *   I3  Absent != zero. A detached probe renders as "— / unplugged", never 0.
 *   I4  Never present stale data as current. Derived values (ETA, trend) are
 *       REMOVED when data is stale, not greyed out.
 *   I5  No dead controls. Disabled controls state their reason on screen.
 *   I12 Food safety is a hard gate (targets below a class floor are refused).
 *   I14 One ember primary action per screen.
 * ========================================================================== */

(function () {
  'use strict';

  // ── Units ──────────────────────────────────────────────────────────────
  // Storage is canonical tenths-of-°F. Everything in this file is °F.
  // Display conversion lives in app.js (toDisplay / formatTemp) so the
  // prototype can toggle °F/°C without touching the data.
  const F = (v) => v; // identity, documented for clarity

  // ── The expected-cook database ────────────────────────────────────────
  // One entry per cut. `phases` is the honest arc the Timeline tab draws
  // BEFORE any data arrives; `stall`/`wrap`/`spritz`/`turn` are the optional
  // interventions the app will remind about.
  //
  //   totalMin      expected cook duration range, minutes (pre-rest)
  //   stall         { minF, maxF, durationMin:[lo,hi] }  evaporative plateau
  //   wrap          { tempF, label, note }               when/if to wrap
  //   spritzEveryMin minutes between spritzes (null = not applicable)
  //   turn          { elapsedMin | tempF, note }         when to rotate/flip
  //   restMin       carryover rest, minutes (matches restSecondsFor in app)
  //   phases        ordered milestones for the timeline rail
  const TIMELINES = {
    // ── Beef ───────────────────────────────────────────────────────────
    beef_brisket: {
      totalMin: [600, 840],
      stall: { minF: 150, maxF: 170, durationMin: [120, 240] },
      wrap: { tempF: 165, label: 'Wrap in butcher paper', note: 'The Texas crutch — speeds the stall and protects the bark.' },
      spritzEveryMin: 45,
      turn: null,
      restMin: 60,
      phases: [
        { id: 'on', label: 'On the smoker', note: 'Fat side up, point toward the fire.' },
        { id: 'stall', label: 'The stall', note: 'Evaporative cooling. Do not panic — this is normal.' },
        { id: 'wrap', label: 'Wrap', note: 'Butcher paper or foil.' },
        { id: 'probe', label: 'Probe-tender', note: 'Butter-smooth in the flat.' },
        { id: 'rest', label: 'Rest', note: 'Hold in a cooler if needed.' },
      ],
    },
    beef_ribeye: {
      totalMin: [12, 20], stall: null,
      wrap: null, spritzEveryMin: null,
      turn: { elapsedMin: 5, note: 'Flip once for even char.' },
      restMin: 5,
      phases: [
        { id: 'on', label: 'Sear', note: 'Hot and fast over direct heat.' },
        { id: 'flip', label: 'Flip', note: 'One turn, then finish indirect.' },
        { id: 'pull', label: 'Pull early', note: 'Carryover finishes it.' },
        { id: 'rest', label: 'Rest', note: '5 minutes, tented.' },
      ],
    },
    beef_prime_rib: {
      totalMin: [180, 300],
      stall: { minF: 110, maxF: 125, durationMin: [30, 60] },
      wrap: null, spritzEveryMin: 60,
      turn: null, restMin: 30,
      phases: [
        { id: 'on', label: 'On', note: 'Low and indirect.' },
        { id: 'stall', label: 'Small stall', note: 'Lower and shorter than a brisket.' },
        { id: 'pull', label: 'Pull early', note: 'Thick roast coasts 5-10°F.' },
        { id: 'rest', label: 'Rest', note: '30 minutes before carving.' },
      ],
    },
    beef_chuck: {
      totalMin: [300, 420],
      stall: { minF: 150, maxF: 165, durationMin: [60, 120] },
      wrap: { tempF: 165, label: 'Wrap', note: 'Foil to braise-tender.' },
      spritzEveryMin: 60, turn: null, restMin: 30,
      phases: [
        { id: 'on', label: 'On', note: 'Treat like a small brisket.' },
        { id: 'stall', label: 'Stall', note: 'Wrap to push through.' },
        { id: 'shred', label: 'Shreddable', note: 'Fork-tender at ~205°F.' },
        { id: 'rest', label: 'Rest', note: '30 minutes.' },
      ],
    },
    beef_burger: {
      totalMin: [8, 14], stall: null, wrap: null, spritzEveryMin: null,
      turn: { elapsedMin: 4, note: 'Flip once.' }, restMin: 3,
      phases: [
        { id: 'on', label: 'On', note: 'Hot and fast.' },
        { id: 'flip', label: 'Flip', note: 'One turn.' },
        { id: 'done', label: '160°F', note: 'Ground beef is a hard floor.' },
      ],
    },
    beef_shortribs: {
      totalMin: [300, 420],
      stall: { minF: 150, maxF: 165, durationMin: [60, 120] },
      wrap: { tempF: 165, label: 'Wrap', note: 'Braise until the collagen gives.' },
      spritzEveryMin: 60, turn: null, restMin: 20,
      phases: [
        { id: 'on', label: 'On', note: 'Low and slow.' },
        { id: 'stall', label: 'Stall', note: 'Expect it around 150-165°F.' },
        { id: 'wrap', label: 'Wrap', note: 'Foil or braise.' },
        { id: 'tender', label: 'Tender', note: '~200°F, probe-tender.' },
      ],
    },
    beef_tritip: {
      totalMin: [45, 90], stall: null, wrap: null,
      spritzEveryMin: null, turn: { elapsedMin: 20, note: 'Flip at the halfway mark.' },
      restMin: 10,
      phases: [
        { id: 'on', label: 'On', note: 'Indirect, then sear.' },
        { id: 'flip', label: 'Flip', note: 'Even cook on both sides.' },
        { id: 'pull', label: 'Pull at 130°F', note: 'Medium rare, then sear.' },
        { id: 'rest', label: 'Rest', note: '10 minutes, then slice across the grain.' },
      ],
    },
    // ── Pork ───────────────────────────────────────────────────────────
    pork_butt: {
      totalMin: [480, 720],
      stall: { minF: 150, maxF: 170, durationMin: [120, 240] },
      wrap: { tempF: 165, label: 'Wrap in foil', note: 'The hot-and-fast trick once the bark is set.' },
      spritzEveryMin: 60, turn: null, restMin: 60,
      phases: [
        { id: 'on', label: 'On the smoker', note: 'Fat cap up.' },
        { id: 'stall', label: 'The stall', note: 'Long stall — wrap to shorten it.' },
        { id: 'wrap', label: 'Wrap', note: 'Foil speeds it; paper keeps bark.' },
        { id: 'pull', label: 'Pulled', note: 'Probe slides in like warm butter at ~201°F.' },
        { id: 'rest', label: 'Rest', note: 'At least an hour, held warm.' },
      ],
    },
    pork_ribs: {
      totalMin: [240, 360],
      stall: null,
      wrap: { tempF: 165, label: 'Wrap (3-2-1)', note: 'Optional: 3h smoke, 2h wrapped, 1h sauced.' },
      spritzEveryMin: 45, turn: null, restMin: 15,
      phases: [
        { id: 'on', label: 'On', note: 'Bone side down.' },
        { id: 'wrap', label: 'Wrap', note: 'Optional, for tenderness.' },
        { id: 'sauce', label: 'Sauce', note: 'Last 30 minutes to set the glaze.' },
        { id: 'bend', label: 'Bend test', note: 'Bark cracks when lifted with tongs.' },
      ],
    },
    pork_babyback: {
      totalMin: [180, 300],
      stall: null,
      wrap: { tempF: 165, label: 'Wrap (2-2-1)', note: 'Shorter cook than spare ribs.' },
      spritzEveryMin: 45, turn: null, restMin: 15,
      phases: [
        { id: 'on', label: 'On', note: 'Bone side down.' },
        { id: 'wrap', label: 'Wrap', note: 'Optional.' },
        { id: 'bend', label: 'Bend test', note: 'Bite-tender at ~195°F.' },
      ],
    },
    pork_loin: {
      totalMin: [60, 120], stall: null, wrap: null,
      spritzEveryMin: 30, turn: { elapsedMin: 30, note: 'Rotate for even colour.' },
      restMin: 10,
      phases: [
        { id: 'on', label: 'On', note: 'Lean cut — do not overcook.' },
        { id: 'pull', label: 'Pull at 145°F', note: 'Juicy with a short rest.' },
        { id: 'rest', label: 'Rest', note: '10 minutes, tented.' },
      ],
    },
    pork_belly: {
      totalMin: [150, 210],
      stall: { minF: 150, maxF: 165, durationMin: [30, 60] },
      wrap: { tempF: 165, label: 'Wrap', note: 'Then cube and sauce for burnt ends.' },
      spritzEveryMin: 45, turn: null, restMin: 15,
      phases: [
        { id: 'on', label: 'On', note: 'Skin side up.' },
        { id: 'wrap', label: 'Wrap', note: 'Until probe-tender.' },
        { id: 'cube', label: 'Cube & sauce', note: 'Back on the heat for burnt ends.' },
      ],
    },
    pork_sausage: {
      totalMin: [45, 90], stall: null, wrap: null,
      spritzEveryMin: null, turn: { elapsedMin: 20, note: 'Roll for even browning.' },
      restMin: 5,
      phases: [
        { id: 'on', label: 'On', note: 'Indirect heat to avoid casing blowout.' },
        { id: 'roll', label: 'Roll', note: 'Even colour all around.' },
        { id: 'done', label: '160°F', note: 'Ground meat floor.' },
      ],
    },
    // ── Poultry ────────────────────────────────────────────────────────
    poultry_whole: {
      totalMin: [150, 240], stall: null, wrap: null,
      spritzEveryMin: null, turn: { elapsedMin: 60, note: 'Rotate for even colour.' },
      restMin: 20,
      phases: [
        { id: 'on', label: 'On', note: 'Breast side up, indirect.' },
        { id: 'rotate', label: 'Rotate', note: 'Even browning.' },
        { id: 'done', label: '165°F breast', note: 'Carryover is never relied on for poultry.' },
        { id: 'rest', label: 'Rest', note: '20 minutes before carving.' },
      ],
    },
    poultry_breast: {
      totalMin: [30, 50], stall: null, wrap: null,
      spritzEveryMin: null, turn: { elapsedMin: 15, note: 'Flip once.' },
      restMin: 5,
      phases: [
        { id: 'on', label: 'On', note: 'Indirect to keep it juicy.' },
        { id: 'flip', label: 'Flip', note: 'Even cook.' },
        { id: 'done', label: '165°F', note: 'Pull immediately.' },
      ],
    },
    poultry_thigh: {
      totalMin: [45, 75], stall: null, wrap: null,
      spritzEveryMin: null, turn: { elapsedMin: 20, note: 'Flip once.' },
      restMin: 5,
      phases: [
        { id: 'on', label: 'On', note: 'Dark meat takes the heat well.' },
        { id: 'flip', label: 'Flip', note: 'Even colour.' },
        { id: 'silky', label: '175-185°F', note: 'Past the minimum — renders the collagen silky.' },
      ],
    },
    poultry_wings: {
      totalMin: [45, 75], stall: null, wrap: null,
      spritzEveryMin: null, turn: { elapsedMin: 20, note: 'Flip once.' },
      restMin: 5,
      phases: [
        { id: 'on', label: 'On', note: 'Hot and indirect.' },
        { id: 'flip', label: 'Flip', note: 'Crisp both sides.' },
        { id: 'done', label: '175°F', note: 'Crisp skin, safe meat.' },
      ],
    },
    // ── Seafood ────────────────────────────────────────────────────────
    fish_salmon: {
      totalMin: [30, 60], stall: null, wrap: null,
      spritzEveryMin: null, turn: null, restMin: 5,
      phases: [
        { id: 'on', label: 'On', note: 'Skin side down on a clean grate.' },
        { id: 'flaky', label: '145°F flaky', note: 'Or pull at 125°F for a moist centre (sashimi-grade only).' },
      ],
    },
    fish_trout: {
      totalMin: [25, 45], stall: null, wrap: null,
      spritzEveryMin: null, turn: null, restMin: 5,
      phases: [
        { id: 'on', label: 'On', note: 'Whole, in a basket.' },
        { id: 'flaky', label: '145°F', note: 'Flakes at the backbone.' },
      ],
    },
    fish_shrimp: {
      totalMin: [10, 20], stall: null, wrap: null,
      spritzEveryMin: null, turn: { elapsedMin: 5, note: 'Turn once.' },
      restMin: 0,
      phases: [
        { id: 'on', label: 'On', note: 'Skewered, hot and fast.' },
        { id: 'pink', label: 'Opaque & pink', note: '145°F, do not overcook.' },
      ],
    },
    fish_tuna: {
      totalMin: [8, 16], stall: null, wrap: null,
      spritzEveryMin: null, turn: { elapsedMin: 4, note: 'Flip once.' },
      restMin: 3,
      phases: [
        { id: 'sear', label: 'Sear', note: 'Very hot, very quick.' },
        { id: 'pull', label: 'Pull at 125°F', note: 'Rare centre.' },
      ],
    },
    // ── Lamb ───────────────────────────────────────────────────────────
    lamb_chops: {
      totalMin: [15, 25], stall: null, wrap: null,
      spritzEveryMin: null, turn: { elapsedMin: 7, note: 'Flip once.' },
      restMin: 5,
      phases: [
        { id: 'sear', label: 'Sear', note: 'Hot and fast.' },
        { id: 'flip', label: 'Flip', note: 'Even crust.' },
        { id: 'pull', label: 'Pull at 130°F', note: 'Medium rare.' },
      ],
    },
    lamb_leg: {
      totalMin: [120, 180],
      stall: { minF: 120, maxF: 135, durationMin: [20, 40] },
      wrap: null, spritzEveryMin: 45,
      turn: null, restMin: 20,
      phases: [
        { id: 'on', label: 'On', note: 'Indirect, low.' },
        { id: 'stall', label: 'Small stall', note: 'Short plateau.' },
        { id: 'pull', label: 'Pull at 135°F', note: 'Medium rare, rests to 140°F.' },
        { id: 'rest', label: 'Rest', note: '20 minutes.' },
      ],
    },
    lamb_shoulder: {
      totalMin: [300, 420],
      stall: { minF: 150, maxF: 165, durationMin: [60, 120] },
      wrap: { tempF: 165, label: 'Wrap', note: 'Braise to pull-apart.' },
      spritzEveryMin: 60, turn: null, restMin: 30,
      phases: [
        { id: 'on', label: 'On', note: 'Low and slow.' },
        { id: 'stall', label: 'Stall', note: 'Wrap to push through.' },
        { id: 'pull', label: 'Pull-apart', note: '~200°F.' },
      ],
    },
    // ── Veggies / Sides ────────────────────────────────────────────────
    veg_potato: {
      totalMin: [60, 90], stall: null, wrap: null, spritzEveryMin: null,
      turn: null, restMin: 5,
      phases: [
        { id: 'on', label: 'On', note: 'Direct over medium heat.' },
        { id: 'soft', label: '205°F centre', note: 'Fork-tender.' },
      ],
    },
    veg_corn: {
      totalMin: [25, 45], stall: null, wrap: null, spritzEveryMin: null,
      turn: { elapsedMin: 15, note: 'Rotate a quarter turn.' }, restMin: 0,
    },
    veg_mushrooms: {
      totalMin: [45, 75], stall: null, wrap: null, spritzEveryMin: null,
      turn: { elapsedMin: 20, note: 'Stir once.' }, restMin: 0,
    },
    veg_skewers: {
      totalMin: [25, 45], stall: null, wrap: null, spritzEveryMin: null,
      turn: { elapsedMin: 12, note: 'Turn once.' }, restMin: 0,
    },
    // ── Eggs ───────────────────────────────────────────────────────────
    egg_bake: {
      totalMin: [45, 75], stall: null, wrap: null, spritzEveryMin: null,
      turn: null, restMin: 10,
      phases: [
        { id: 'on', label: 'On', note: 'Water bath or indirect.' },
        { id: 'set', label: '160°F set', note: 'Custard set through.' },
      ],
    },
    egg_casserole: {
      totalMin: [60, 90], stall: null, wrap: null, spritzEveryMin: null,
      turn: null, restMin: 10,
    },
    // ── Other sides ────────────────────────────────────────────────────
    side_beans: {
      totalMin: [90, 150], stall: null, wrap: null, spritzEveryMin: null,
      turn: { elapsedMin: 45, note: 'Stir once.' }, restMin: 0,
    },
    side_mac: {
      totalMin: [60, 90], stall: null, wrap: null, spritzEveryMin: null,
      turn: null, restMin: 10,
    },
    side_queso: {
      totalMin: [45, 75], stall: null, wrap: null, spritzEveryMin: null,
      turn: { elapsedMin: 20, note: 'Stir to keep it smooth.' }, restMin: 0,
    },
  };

  // ── The catalog ───────────────────────────────────────────────────────
  // `glyph` drives the placeholder avatar (replaced by real images later).
  // `doneness` targets are POST-REST finals; `pullOffsetF` is carryover.
  // Red meat defaults to medium rare per the brief.
  const CATALOG = [
    // ── Beef ───────────────────────────────────────────────────────────
    { id: 'beef_brisket', category: 'Beef', name: 'Texas Brisket', glyph: 'brisket', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [225, 275],
      blurb: 'Low and slow until the collagen gives.',
      doneness: [ { id: 'sliceable', label: 'Sliceable', targetF: 195 }, { id: 'tender', label: 'Tender', targetF: 201 }, { id: 'shred', label: 'Pitmaster shred', targetF: 203 } ],
      defaultDoneness: 'tender' },
    { id: 'beef_ribeye', category: 'Beef', name: 'Ribeye Steak', glyph: 'steak', hazard: 'wholeMuscleRedMeat', thickness: 'thin', pitBand: [200, 250],
      blurb: 'A whole-muscle cut — cook it to the doneness you like.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 }, { id: 'medwell', label: 'Medium well', targetF: 155 }, { id: 'well', label: 'Well done', targetF: 165 } ],
      defaultDoneness: 'medrare' },
    { id: 'beef_prime_rib', category: 'Beef', name: 'Prime Rib Roast', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [225, 275],
      blurb: 'Thick roast — it keeps climbing off the heat.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 }, { id: 'medwell', label: 'Medium well', targetF: 155 }, { id: 'well', label: 'Well done', targetF: 165 } ],
      defaultDoneness: 'medrare' },
    { id: 'beef_chuck', category: 'Beef', name: 'Chuck Roast', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [250, 275],
      blurb: 'Braise-tender — treat it like a small brisket.',
      doneness: [ { id: 'sliceable', label: 'Sliceable', targetF: 195 }, { id: 'shred', label: 'Shreddable', targetF: 205 } ],
      defaultDoneness: 'shred' },
    { id: 'beef_burger', category: 'Beef', name: 'Burgers', glyph: 'ground', hazard: 'ground', thickness: 'thin', pitBand: [325, 375],
      blurb: 'Ground beef finishes at 160°F — grinding mixes bacteria through.',
      doneness: [ { id: 'done', label: 'Done (160°F)', targetF: 160 } ], defaultDoneness: 'done' },
    { id: 'beef_shortribs', category: 'Beef', name: 'Beef Short Ribs', glyph: 'ribs', hazard: 'wholeMuscleRedMeat', thickness: 'medium', pitBand: [250, 275],
      blurb: 'Braise-tender, rich and beefy.',
      doneness: [ { id: 'tender', label: 'Probe-tender', targetF: 200 }, { id: 'shred', label: 'Fall-apart', targetF: 205 } ],
      defaultDoneness: 'tender' },
    { id: 'beef_tritip', category: 'Beef', name: 'Tri-Tip', glyph: 'steak', hazard: 'wholeMuscleRedMeat', thickness: 'medium', pitBand: [225, 275],
      blurb: 'Reverse-sear, then slice across the grain.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ],
      defaultDoneness: 'medrare' },
    // ── Pork ───────────────────────────────────────────────────────────
    { id: 'pork_butt', category: 'Pork', name: 'Pork Shoulder', glyph: 'pork', hazard: 'pork', thickness: 'thick', pitBand: [225, 275],
      blurb: 'Boston butt — pull it apart at 201°F.',
      doneness: [ { id: 'sliceable', label: 'Sliceable', targetF: 185 }, { id: 'pulled', label: 'Pulled', targetF: 201 } ],
      defaultDoneness: 'pulled' },
    { id: 'pork_ribs', category: 'Pork', name: 'Spare Ribs', glyph: 'ribs', hazard: 'pork', thickness: 'thin', pitBand: [225, 275],
      blurb: 'Bend-test tender — bark set, meat pulled back from the bone.',
      doneness: [ { id: 'tender', label: 'Bite-tender', targetF: 195 }, { id: 'falloff', label: 'Fall-off-bone', targetF: 203 } ],
      defaultDoneness: 'tender' },
    { id: 'pork_babyback', category: 'Pork', name: 'Baby Back Ribs', glyph: 'ribs', hazard: 'pork', thickness: 'thin', pitBand: [225, 275],
      blurb: 'Shorter cook, leaner, a touch sweeter.',
      doneness: [ { id: 'tender', label: 'Bite-tender', targetF: 190 }, { id: 'falloff', label: 'Fall-off-bone', targetF: 200 } ],
      defaultDoneness: 'tender' },
    { id: 'pork_loin', category: 'Pork', name: 'Pork Loin', glyph: 'pork', hazard: 'pork', thickness: 'medium', pitBand: [250, 300],
      blurb: 'A lean cut — pull at 145°F and rest for juicy slices.',
      doneness: [ { id: 'juicy', label: 'Juicy (145°F + rest)', targetF: 145 }, { id: 'well', label: 'Well done', targetF: 160 } ],
      defaultDoneness: 'juicy' },
    { id: 'pork_belly', category: 'Pork', name: 'Pork Belly Burnt Ends', glyph: 'pork', hazard: 'pork', thickness: 'medium', pitBand: [250, 275],
      blurb: 'Cubed, sauced, and back on the heat.',
      doneness: [ { id: 'tender', label: 'Probe-tender', targetF: 200 } ], defaultDoneness: 'tender' },
    { id: 'pork_sausage', category: 'Pork', name: 'Sausages & Brats', glyph: 'ground', hazard: 'ground', thickness: 'thin', pitBand: [225, 275],
      blurb: 'Indirect heat so the casings do not blow out.',
      doneness: [ { id: 'done', label: 'Done (160°F)', targetF: 160 } ], defaultDoneness: 'done' },
    // ── Poultry ────────────────────────────────────────────────────────
    { id: 'poultry_whole', category: 'Poultry', name: 'Whole Turkey', glyph: 'wholeBird', hazard: 'poultry', thickness: 'thick', pitBand: [275, 325],
      blurb: 'Breast to 165°F — the safe minimum, and where it eats best.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done' },
    { id: 'poultry_breast', category: 'Poultry', name: 'Chicken Breast', glyph: 'poultry', hazard: 'poultry', thickness: 'thin', pitBand: [325, 375],
      blurb: 'Pull at 165°F — juicy and safe.',
      doneness: [ { id: 'done', label: 'Done (165°F)', targetF: 165 } ], defaultDoneness: 'done' },
    { id: 'poultry_thigh', category: 'Poultry', name: 'Chicken Thighs', glyph: 'poultry', hazard: 'poultry', thickness: 'thin', pitBand: [325, 375],
      blurb: 'Dark meat is best past the minimum — 175–185°F renders it silky.',
      doneness: [ { id: 'safe', label: 'Safe (165°F)', targetF: 165 }, { id: 'silky', label: 'Silky (180°F)', targetF: 180 } ],
      defaultDoneness: 'silky' },
    { id: 'poultry_wings', category: 'Poultry', name: 'Chicken Wings', glyph: 'poultry', hazard: 'poultry', thickness: 'thin', pitBand: [325, 400],
      blurb: 'High heat for crisp skin.',
      doneness: [ { id: 'done', label: 'Done (175°F)', targetF: 175 } ], defaultDoneness: 'done' },
    // ── Seafood ────────────────────────────────────────────────────────
    { id: 'fish_salmon', category: 'Seafood', name: 'Salmon Fillet', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [225, 275],
      blurb: 'Flakes at 145°F — the safe minimum for fish.',
      doneness: [ { id: 'done', label: 'Flaky (145°F)', targetF: 145 } ], defaultDoneness: 'done' },
    { id: 'fish_trout', category: 'Seafood', name: 'Whole Trout', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [225, 275],
      blurb: 'Cooked whole in a basket.',
      doneness: [ { id: 'done', label: 'Flaky (145°F)', targetF: 145 } ], defaultDoneness: 'done' },
    { id: 'fish_shrimp', category: 'Seafood', name: 'Shrimp Skewers', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [325, 375],
      blurb: 'Opaque and pink — about 145°F.',
      doneness: [ { id: 'done', label: 'Opaque (145°F)', targetF: 145 } ], defaultDoneness: 'done' },
    { id: 'fish_tuna', category: 'Seafood', name: 'Tuna Steak', glyph: 'fish', hazard: 'fish', thickness: 'thin', pitBand: [225, 275],
      blurb: 'Sear hard, keep the centre rare.',
      doneness: [ { id: 'rare', label: 'Rare (125°F)', targetF: 125 } ], defaultDoneness: 'rare' },
    // ── Lamb ───────────────────────────────────────────────────────────
    { id: 'lamb_chops', category: 'Lamb', name: 'Lamb Chops', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'thin', pitBand: [225, 275],
      blurb: 'Hot and fast, pull early.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ],
      defaultDoneness: 'medrare' },
    { id: 'lamb_leg', category: 'Lamb', name: 'Leg of Lamb', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [225, 275],
      blurb: 'Roast low, rest long.',
      doneness: [ { id: 'rare', label: 'Rare', targetF: 125 }, { id: 'medrare', label: 'Medium rare', targetF: 135 }, { id: 'medium', label: 'Medium', targetF: 145 } ],
      defaultDoneness: 'medrare' },
    { id: 'lamb_shoulder', category: 'Lamb', name: 'Lamb Shoulder', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'thick', pitBand: [250, 275],
      blurb: 'Low and slow to pull-apart.',
      doneness: [ { id: 'tender', label: 'Pull-apart', targetF: 200 } ], defaultDoneness: 'tender' },
    // ── Veggies & Sides ────────────────────────────────────────────────
    { id: 'veg_potato', category: 'Veggies & Sides', name: 'Baked Potatoes', glyph: 'ambient', hazard: 'unstated', thickness: 'medium', pitBand: [350, 400],
      blurb: 'Fork-tender at ~205°F centre.',
      doneness: [ { id: 'soft', label: 'Fork-tender', targetF: 205 } ], defaultDoneness: 'soft' },
    { id: 'veg_corn', category: 'Veggies & Sides', name: 'Corn on the Cob', glyph: 'ambient', hazard: 'unstated', thickness: 'thin', pitBand: [350, 400],
      blurb: 'Sweet and charred.',
      doneness: [ { id: 'done', label: 'Charred', targetF: 180 } ], defaultDoneness: 'done' },
    { id: 'veg_mushrooms', category: 'Veggies & Sides', name: 'Smoked Mushrooms', glyph: 'ambient', hazard: 'unstated', thickness: 'thin', pitBand: [225, 275],
      blurb: 'Soak up the smoke.',
      doneness: [ { id: 'done', label: 'Softened', targetF: 160 } ], defaultDoneness: 'done' },
    { id: 'veg_skewers', category: 'Veggies & Sides', name: 'Veggie Skewers', glyph: 'ambient', hazard: 'unstated', thickness: 'thin', pitBand: [325, 375],
      blurb: 'Charred edges, still crisp.',
      doneness: [ { id: 'done', label: 'Charred', targetF: 175 } ], defaultDoneness: 'done' },
    { id: 'side_beans', category: 'Veggies & Sides', name: 'Smoked Baked Beans', glyph: 'ambient', hazard: 'unstated', thickness: 'medium', pitBand: [225, 275],
      blurb: 'Under the brisket, catching the drippings.',
      doneness: [ { id: 'done', label: 'Thickened', targetF: 180 } ], defaultDoneness: 'done' },
    { id: 'side_mac', category: 'Veggies & Sides', name: 'Smoked Mac & Cheese', glyph: 'ambient', hazard: 'unstated', thickness: 'medium', pitBand: [225, 275],
      blurb: 'Smoky, gooey, golden top.',
      doneness: [ { id: 'done', label: 'Set', targetF: 165 } ], defaultDoneness: 'done' },
    { id: 'side_queso', category: 'Veggies & Sides', name: 'Smoked Queso', glyph: 'ambient', hazard: 'unstated', thickness: 'thin', pitBand: [225, 275],
      blurb: 'Stir often, keep it smooth.',
      doneness: [ { id: 'done', label: 'Molten', targetF: 160 } ], defaultDoneness: 'done' },
    // ── Eggs ───────────────────────────────────────────────────────────
    { id: 'egg_bake', category: 'Eggs', name: 'Quiche / Egg Bake', glyph: 'egg', hazard: 'egg', thickness: 'medium', pitBand: [325, 375],
      blurb: 'Custard set through at 160°F — USDA’s minimum for egg dishes.',
      doneness: [ { id: 'set', label: 'Set (160°F)', targetF: 160 } ], defaultDoneness: 'set' },
    { id: 'egg_casserole', category: 'Eggs', name: 'Breakfast Casserole', glyph: 'egg', hazard: 'egg', thickness: 'thick', pitBand: [300, 350],
      blurb: 'A deep bake — same 160°F, read at the centre.',
      doneness: [ { id: 'set', label: 'Set (160°F)', targetF: 160 } ], defaultDoneness: 'set' },
  ];

  const CATEGORIES = ['Beef', 'Pork', 'Poultry', 'Seafood', 'Lamb', 'Veggies & Sides', 'Eggs'];

  // ── Active cook scenarios ─────────────────────────────────────────────
  // Each scenario is a complete UI situation. `probes` are jack-ordered 1..4.
  // Jack 4 defaults to the grate/pit role (brief: "assume probe 4 will be
  // grate temp by default but allow users to choose").
  //
  // Every probe carries the fields the reader needs, and nothing derived is
  // pre-baked as truth: `freshness` drives whether ETA/trend are shown at all
  // (invariant I4).

  function nowMs() { return Date.now(); }
  const H = 3600 * 1000, M = 60 * 1000;

  const SCENARIOS = {
    // A full Sunday cook: brisket in the stall, ribs climbing, sausages on.
    running: {
      key: 'running',
      label: 'Running cook (stall + alarms)',
      connection: { state: 'connected', mode: 'ble', deviceName: 'SmokeBridge-A4F2', bleBars: 3, routerBars: null, batteryPct: 71, recording: true, lastSyncS: 4 },
      cook: {
        active: true, paused: false,
        name: 'Sunday Brisket & Ribs',
        startedAtMs: nowMs() - (4 * H + 12 * M),
        pitBand: [225, 275],
        grateTargetF: 250,
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
        { id: 'pit_crash', tier: 'device', severity: 'critical', rule: 'Pit temperature falling fast', detail: 'Down 18°F in 12 min. Check fuel and vents.', valueF: 248.6, atMs: nowMs() - 3 * M, acked: false, sessionScoped: true },
        { id: 'eta_soon', tier: 'app', severity: 'info', rule: 'Sausages almost ready', detail: 'ETA about 11 minutes to 160°F.', valueF: 141.8, atMs: nowMs() - 1 * M, acked: false, sessionScoped: true },
      ],
      marks: [
        { id: 'm1', atMs: nowMs() - (4 * H + 12 * M), kind: 'phase_change', label: 'Cook started', probe: 0 },
        { id: 'm2', atMs: nowMs() - (3 * H + 20 * M), kind: 'note', label: 'Added ribs', probe: 2 },
        { id: 'm3', atMs: nowMs() - (2 * H + 55 * M), kind: 'wrapped', label: 'Wrapped brisket in butcher paper', probe: 1 },
        { id: 'm4', atMs: nowMs() - (2 * H), kind: 'note', label: 'Spritzed ribs', probe: 2 },
        { id: 'm5', atMs: nowMs() - (55 * M), kind: 'note', label: 'Added sausages', probe: 3 },
      ],
    },

    // Connected, no cook: pure instrument mode. Targets are null.
    idle: {
      key: 'idle',
      label: 'Connected — instrument mode (no cook)',
      connection: { state: 'connected', mode: 'sta', deviceName: 'SmokeBridge-A4F2', bleBars: null, routerBars: 4, batteryPct: 88, recording: true, lastSyncS: 2 },
      cook: { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] },
      probes: [
        { jack: 1, role: 'food', attached: true, freshness: 'live', tempF: 68.1, targetF: null, pullF: null, trendFPerHr: -0.2, stalled: false, peakF: 68.1, lowF: 67.9, avgF: 68.0, etaMin: null, etaNote: '', spark: [68, 68.1, 68.2, 68.1, 68.0, 68.1, 68.1, 68.1, 68.2, 68.1, 68.1, 68.1] },
        { jack: 2, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
        { jack: 3, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
        { jack: 4, role: 'pit', attached: true, freshness: 'live', tempF: 92.4, targetF: null, pullF: null, trendFPerHr: 24.0, stalled: false, peakF: 92.4, lowF: 74.0, avgF: 83.0, etaMin: null, etaNote: '', spark: [74, 76, 79, 82, 85, 88, 90, 91, 92, 92.2, 92.3, 92.4] },
      ],
      alarms: [],
      marks: [],
    },

    // A bridge that has been recording with no phone: the "hook into data
    // already collected" case. `pendingSession` is what the adopt sheet reads.
    existing: {
      key: 'existing',
      label: 'Bridge has a session already running',
      connection: { state: 'connected', mode: 'ble', deviceName: 'SmokeBridge-A4F2', bleBars: 2, routerBars: null, batteryPct: 64, recording: true, lastSyncS: 7 },
      cook: { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] },
      probes: [
        { jack: 1, role: 'food', attached: true, freshness: 'live', tempF: 158.0, targetF: null, pullF: null, trendFPerHr: 1.1, stalled: true, peakF: 158.0, lowF: 61.0, avgF: 121.0, etaMin: null, etaNote: '', spark: [61, 92, 118, 138, 149, 154, 156, 157, 157.5, 157.8, 157.9, 158.0] },
        { jack: 2, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
        { jack: 3, role: 'unused', attached: false, freshness: 'unknown', tempF: null, targetF: null, pullF: null, trendFPerHr: null, stalled: false, peakF: null, lowF: null, avgF: null, etaMin: null, etaNote: '', spark: [] },
        { jack: 4, role: 'pit', attached: true, freshness: 'live', tempF: 243.0, targetF: null, pullF: null, trendFPerHr: -2.0, stalled: false, peakF: 258.0, lowF: 231.0, avgF: 246.0, etaMin: null, etaNote: '', spark: [231, 240, 248, 255, 258, 256, 252, 249, 246, 244, 243.5, 243.0] },
      ],
      alarms: [],
      marks: [],
      pendingSession: { sessionId: 'SMK-4471', startedAtMs: nowMs() - (2 * H + 5 * M), samples: 253, probeCount: 2, attachedJacks: [1, 4] },
    },

    // Offline / stale: freshness ladder must remove derived values.
    offline: {
      key: 'offline',
      label: 'Bridge unreachable — stale data',
      connection: { state: 'offline', mode: 'ble', deviceName: 'SmokeBridge-A4F2', bleBars: 0, routerBars: null, batteryPct: null, recording: true, lastSyncS: 742 },
      cook: {
        active: true, paused: false, name: 'Sunday Brisket & Ribs',
        startedAtMs: nowMs() - (4 * H + 30 * M), pitBand: [225, 275], grateTargetF: 250,
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
        { id: 'bridge_unreachable', tier: 'app', severity: 'warning', rule: 'Bridge unreachable', detail: 'No data for 12 minutes. The bridge is still recording — the gap will fill when it reconnects.', valueF: null, atMs: nowMs() - 12 * M, acked: false, sessionScoped: false },
      ],
      marks: [
        { id: 'm1', atMs: nowMs() - (4 * H + 30 * M), kind: 'phase_change', label: 'Cook started', probe: 0 },
        { id: 'm2', atMs: nowMs() - (3 * H + 40 * M), kind: 'note', label: 'Added ribs', probe: 2 },
        { id: 'm3', atMs: nowMs() - (3 * H), kind: 'wrapped', label: 'Wrapped brisket in butcher paper', probe: 1 },
      ],
    },
  };

  // ── Past cooks (history) ──────────────────────────────────────────────
  const HISTORY = [
    { id: 'c1', name: 'Labor Day Pulled Pork', presetId: 'pork_butt', glyph: 'pork', jack: 1, startedAtMs: nowMs() - 6 * 24 * H, durationMin: 612, peakF: 203.1, targetF: 201, favourite: true, notes: 'Wrapped at 165°F. Best bark yet.', marks: 5, rating: 5, status: 'done' },
    { id: 'c2', name: 'Weeknight Ribeyes', presetId: 'beef_ribeye', glyph: 'steak', jack: 1, startedAtMs: nowMs() - 4 * 24 * H, durationMin: 18, peakF: 137.0, targetF: 135, favourite: false, notes: 'Two minutes a side, then indirect.', marks: 2, rating: 4, status: 'done' },
    { id: 'c3', name: 'Whole Turkey Trial', presetId: 'poultry_whole', glyph: 'wholeBird', jack: 1, startedAtMs: nowMs() - 3 * 24 * H, durationMin: 214, peakF: 165.2, targetF: 165, favourite: false, notes: 'Breast hit 165 first; thighs lagged 20 min.', marks: 3, rating: 3, status: 'done' },
    { id: 'c4', name: 'Sunday Brisket & Ribs', presetId: 'beef_brisket', glyph: 'brisket', jack: 1, startedAtMs: nowMs() - 1 * 24 * H, durationMin: 498, peakF: 202.6, targetF: 201, favourite: true, notes: 'Stalled 2h 40m. Wrapped in paper.', marks: 7, rating: 5, status: 'done' },
    { id: 'c5', name: 'Salmon on a Plank', presetId: 'fish_salmon', glyph: 'fish', jack: 2, startedAtMs: nowMs() - 9 * 24 * H, durationMin: 41, peakF: 145.4, targetF: 145, favourite: false, notes: 'Cedar plank, 275°F.', marks: 2, rating: 4, status: 'done' },
    { id: 'c6', name: 'Memorial Day Brisket', presetId: 'beef_brisket', glyph: 'brisket', jack: 1, startedAtMs: nowMs() - 40 * 24 * H, durationMin: 731, peakF: 204.0, targetF: 203, favourite: true, notes: 'Overnight cook. Held 4h in a cooler.', marks: 9, rating: 5, status: 'done' },
  ];

  // ── Device / connection modes ─────────────────────────────────────────
  // The three modes the brief asks for, with honest explainers. In Flutter
  // these map to ConnectionSupervisor's transport preference + app_net modes.
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

  // ── Alarm rules (device tier + app tier) ─────────────────────────────
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
    { id: 'eta_soon', tier: 'app', name: 'ETA soon', desc: 'Advisory: a probe is close to target.', severity: 'info', enabled: true, scoped: 'per probe', windowS: null },
    { id: 'stall', tier: 'app', name: 'Stall detected', desc: 'Advisory: the meat has plateaued.', severity: 'info', enabled: true, scoped: 'per probe', windowS: null },
    { id: 'bridge_unreachable', tier: 'app', name: 'Bridge unreachable', desc: 'Advisory: the app lost the link.', severity: 'warning', enabled: true, scoped: 'device', windowS: null },
  ];

  // ── Exposed model ─────────────────────────────────────────────────────
  window.MOCK = {
    F,
    TIMELINES,
    CATALOG,
    CATEGORIES,
    SCENARIOS,
    HISTORY,
    MODES,
    ALARM_RULES,
    // The default view when the page loads.
    defaultScenario: 'running',
    // App-level settings the prototype can toggle.
    settings: {
      units: 'F',              // 'F' | 'C'  (display only; data stays °F)
      themeProfile: 'dark',    // 'dark' | 'daylight'
      preferManualAlarm: false, // user's own alarm wins over device rules
      quietHours: true,        // 22:00-06:00 silences warning/info, never critical
      monitoring: true,        // background alarm monitoring on/off
      holdBle: true,           // keep BLE warm while on Wi-Fi for fast failover
      preferredTransport: 'auto',
      autoWrapReminder: true,  // Timeline tab sends wrap/spritz reminders
    },
  };
})();
