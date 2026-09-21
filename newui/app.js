/* ============================================================================
 * app.js — Smoke X4 Smart Bridge (new UI prototype)
 * ----------------------------------------------------------------------------
 * A single-file renderer + interaction layer over mock-data.js. It is NOT
 * production code; it exists to make every screen and flow of the proposed
 * UX clickable so it can be perfected before being translated to Flutter.
 *
 *   §1  State + constants
 *   §2  Formatting helpers (temps, time, units)
 *   §3  SVG helpers (icons, sparklines, gauge, chart)
 *   §4  Domain helpers (catalog, styles, timelines, derived values)
 *   §5  Renderers — chrome (appbar / nav / dev panel)
 *   §6  Renderers — views (live / temps / timeline / graph / settings /
 *                   history / cookDetail)
 *   §7  Renderers — overlays
 *   §8  Actions + event delegation + mock event bus
 *   §9  Boot + tick
 *
 * Comments prefixed `[BIZ]` are rules that must survive the port to Dart.
 * Comments prefixed `[FLUTTER]` map UI to an existing engine so the redesign
 * reuses engines rather than reinventing them.
 * ========================================================================== */

(function () {
  'use strict';

  // ============================================================ §1 STATE ====
  const M = window.MOCK;

  const state = {
    scenarioKey: M.defaultScenario,
    screen: 'live',
    units: M.settings.units,
    themeMode: M.settings.themeMode,           // system | light | dark
    displayProfile: M.settings.displayProfile, // standard | daylight
    density: M.settings.density,               // compact | comfortable
    reducedMotion: M.settings.reducedMotion,
    settings: Object.assign({}, M.settings),

    overlay: null,
    onboardStep: 0,
    onboardTroubleshoot: false,

    selectedCookId: null,
    chartRange: 'all',
    isolatedProbe: null,
    graph: { zoom: 1, pan: 0 },
    fullGraph: false,

    catalog: { category: 'Beef', selectedId: null, doneness: null, jack: 1, styleId: null, query: '' },
    setupMode: 'new',
    pendingAck: {},

    confirm: null,     // { title, body, confirmLabel, danger, action, data }
    customForm: null,  // working draft while adding a custom food
    verb: null,        // { kind, title, sub, steps, step, done } for device verbs
  };

  const $ = (sel, root) => (root || document).querySelector(sel);
  const $$ = (sel, root) => Array.prototype.slice.call((root || document).querySelectorAll(sel));
  const scenario = () => M.SCENARIOS[state.scenarioKey];

  // ==================================================== §2 FORMAT HELPERS ====
  // [BIZ] Storage is canonical °F. Conversion happens at the display edge only,
  // so a unit toggle never rewrites a sample (domain/analysis/units.dart).
  function conv(f) { return state.units === 'C' ? (f - 32) * 5 / 9 : f; }
  function unitLabel() { return state.units === 'C' ? '° C' : '° F'; }
  function fmtTemp(f, dec) {
    if (f === null || f === undefined) return '—';
    return conv(f).toFixed(dec === undefined ? 1 : dec) + unitLabel();
  }
  function tempParts(f) {
    if (f === null || f === undefined) return { num: '—', dec: '', unit: '' };
    const s = conv(f).toFixed(1), dot = s.indexOf('.');
    return { num: s.slice(0, dot), dec: s.slice(dot), unit: unitLabel() };
  }
  function fmtClock(ms) {
    if (!ms) return '—';
    return new Date(ms).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  }
  function fmtDay(ms) { return new Date(ms).toLocaleDateString([], { month: 'short', day: 'numeric' }); }
  function fmtDuration(ms) {
    if (ms === null || ms === undefined) return '—';
    const t = Math.max(0, Math.round(ms / 1000));
    const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
    if (h > 0) return h + 'h ' + m + 'm';
    if (m > 0) return m + 'm';
    return s + 's';
  }
  function fmtStopwatch(ms) {
    const t = Math.max(0, Math.round(ms / 1000));
    return [Math.floor(t / 3600), Math.floor((t % 3600) / 60), t % 60]
      .map((n) => String(n).padStart(2, '0')).join(':');
  }
  function fmtEta(min) {
    if (min === null || min === undefined) return null;
    if (min < 1) return '<1 min';
    if (min < 60) return min + ' min';
    return Math.floor(min / 60) + 'h' + (min % 60 ? ' ' + (min % 60) + 'm' : '');
  }
  function ago(ms) {
    const s = Math.round((Date.now() - ms) / 1000);
    if (s < 60) return s + 's ago';
    const m = Math.round(s / 60);
    return m < 60 ? m + 'm ago' : Math.round(m / 60) + 'h ago';
  }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  // ======================================================== §3 SVG HELPERS ====
  const ICON_PATHS = {
    bluetooth: '<path d="M6.5 6.5l11 11L12 23V1l5.5 5.5-11 11"/>',
    wifi: '<path d="M5 12.55a11 11 0 0114.08 0"/><path d="M1.42 9a16 16 0 0121.16 0"/><path d="M8.53 16.11a6 6 0 016.95 0"/><path d="M12 20h.01"/>',
    router: '<rect x="2" y="14" width="20" height="8" rx="2"/><path d="M6.01 18H6M10 18h.01"/><path d="M12 14V10M8 10a6 6 0 018 0M5 6a11 11 0 0114 0"/>',
    thermometer: '<path d="M14 14.76V3.5a2.5 2.5 0 00-5 0v11.26a4.5 4.5 0 105 0z"/>',
    flame: '<path d="M8.5 14.5A2.5 2.5 0 0011 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 11-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 002.5 2.5z"/>',
    clock: '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
    chart: '<path d="M12 20V10M18 20V4M6 20v-4"/>',
    history: '<path d="M3 3v5h5"/><path d="M3.05 13A9 9 0 106 5.3L3 8"/><path d="M12 7v5l4 2"/>',
    cpu: '<rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><path d="M9 1v3M15 1v3M9 20v3M15 20v3M20 9h3M20 14h3M1 9h3M1 14h3"/>',
    bell: '<path d="M18 8A6 6 0 006 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 01-3.46 0"/>',
    chevronRight: '<path d="M9 18l6-6-6-6"/>',
    chevronDown: '<path d="M6 9l6 6 6-6"/>',
    chevronLeft: '<path d="M15 18l-6-6 6-6"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    check: '<path d="M20 6L9 17l-5-5"/>',
    x: '<path d="M18 6L6 18M6 6l12 12"/>',
    play: '<path d="M5 3l14 9-14 9V3z"/>',
    pause: '<path d="M6 4h4v16H6zM14 4h4v16h-4z"/>',
    edit: '<path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/>',
    refresh: '<path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>',
    link: '<path d="M10 13a5 5 0 007.54.54l3-3a5 5 0 00-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 00-7.54-.54l-3 3a5 5 0 007.07 7.07l1.71-1.71"/>',
    unlink: '<path d="M18.84 12.25l1.72-1.71a5 5 0 00-7.07-7.07l-1.72 1.71M5.17 11.75l-1.72 1.71a5 5 0 007.07 7.07l1.71-1.71M8 2v3M2 8h3M16 22v-3M22 16h-3"/>',
    alertTriangle: '<path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><path d="M12 9v4M12 17h.01"/>',
    alertCircle: '<circle cx="12" cy="12" r="10"/><path d="M12 8v4M12 16h.01"/>',
    info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/>',
    question: '<circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 015.83 1c0 2-3 3-3 3M12 17h.01"/>',
    zap: '<path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/>',
    bookmark: '<path d="M19 21l-7-5-7 5V5a2 2 0 012-2h10a2 2 0 012 2z"/>',
    share: '<path d="M4 12v8a2 2 0 002 2h12a2 2 0 002-2v-8"/><path d="M16 6l-4-4-4 4M12 2v13"/>',
    download: '<path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/>',
    trash: '<path d="M3 6h18M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2"/>',
    lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 018 0v4"/>',
    battery: '<rect x="1" y="6" width="18" height="12" rx="2"/><path d="M23 10v4M5 9v6"/>',
    target: '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/>',
    arrowUp: '<path d="M12 19V5M5 12l7-7 7 7"/>',
    arrowDown: '<path d="M12 5v14M19 12l-7 7-7-7"/>',
    arrowRight: '<path d="M5 12h14M12 5l7 7-7 7"/>',
    arrowLeft: '<path d="M19 12H5M12 19l-7-7 7-7"/>',
    minus: '<path d="M5 12h14"/>',
    utensils: '<path d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 002-2V2M7 2v20M21 15V2a5 5 0 00-5 5v6c0 1.1.9 2 2 2h3z"/>',
    wrap: '<path d="M16.5 9.4l-9-5.19M21 16V8a2 2 0 00-1-1.73l-7-4a2 2 0 00-2 0l-7 4A2 2 0 003 8v8a2 2 0 001 1.73l7 4a2 2 0 002 0l7-4A2 2 0 0021 16z"/><path d="M3.27 6.96L12 12.01l8.73-5.05M12 22.08V12"/>',
    droplet: '<path d="M12 2.69l5.66 5.66a8 8 0 11-11.31 0z"/>',
    rotate: '<path d="M23 4v6h-6M1 20v-6h6"/><path d="M20.49 9A9 9 0 005.64 5.64L1 10M23 14l-4.64 4.36A9 9 0 013.51 15"/>',
    calendar: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
    sun: '<circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/>',
    moon: '<path d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z"/>',
    monitor: '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8M12 17v4"/>',
    sliders: '<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6"/>',
    more: '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
    activity: '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
    eye: '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>',
    mapPin: '<path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z"/><circle cx="12" cy="10" r="3"/>',
    package: '<path d="M16.5 9.4l-9-5.19M21 16V8a2 2 0 00-1-1.73l-7-4a2 2 0 00-2 0l-7 4A2 2 0 003 8v8a2 2 0 001 1.73l7 4a2 2 0 002 0l7-4A2 2 0 0021 16z"/><path d="M3.27 6.96L12 12.01l8.73-5.05M12 22.08V12"/>',
    upload: '<path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M17 8l-5-5-5 5M12 3v12"/>',
    compass: '<circle cx="12" cy="12" r="10"/><path d="M16.24 7.76l-2.12 6.36-6.36 2.12 2.12-6.36 6.36-2.12z"/>',
    key: '<path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 11-7.778 7.778 5.5 5.5 0 017.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4"/>',
    search: '<circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/>',
    signal: '<path d="M2 20h.01M7 20v-4M12 20v-8M17 20V8M22 20V4"/>',
    expand: '<path d="M8 3H5a2 2 0 00-2 2v3M16 3h3a2 2 0 012 2v3M8 21H5a2 2 0 01-2-2v-3M16 21h3a2 2 0 002-2v-3"/>',
    compress: '<path d="M8 3v3a2 2 0 01-2 2H3M16 3v3a2 2 0 002 2h3M8 21v-3a2 2 0 00-2-2H3M16 21v-3a2 2 0 012-2h3"/>',
    zoomIn: '<circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35M11 8v6M8 11h6"/>',
    zoomOut: '<circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35M8 11h6"/>',
    qr: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><path d="M14 14h3v3h-3zM20 14h1M14 20h3M20 20h1M17 17h1v1"/>',
    wifiOff: '<path d="M1 1l22 22M16.72 11.06A10.94 10.94 0 0119 12.55M5 12.55a10.94 10.94 0 015.17-2.39M10.71 5.05A16 16 0 0122.58 9M1.42 9a15.91 15.91 0 014.7-2.88M8.53 16.11a6 6 0 016.95 0M12 20h.01"/>',
    camera: '<path d="M23 19a2 2 0 01-2 2H3a2 2 0 01-2-2V8a2 2 0 012-2h4l2-3h6l2 3h4a2 2 0 012 2z"/><circle cx="12" cy="13" r="4"/>',
    star: '<path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>',
  };
  function icon(name, size) {
    const p = ICON_PATHS[name] || '';
    const s = size || 18;
    return '<svg viewBox="0 0 24 24" width="' + s + '" height="' + s + '" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + p + '</svg>';
  }
  function iconBtn(name, action, opts) {
    opts = opts || {};
    return '<button class="icon-btn" data-action="' + action + '"' + (opts.data || '') + ' aria-label="' + esc(opts.label || action) + '" title="' + esc(opts.label || action) + '">' + icon(name) + (opts.badge || '') + '</button>';
  }

  const GLYPH = {
    brisket: '🥩', beef: '🥩', steak: '🥩', pork: '🍖', ribs: '🍖', poultry: '🍗', wholeBird: '🦃',
    fish: '🐟', shellfish: '🦐', game: '🦌', ground: '🍔', egg: '🥚', veg: '🥦', potato: '🥔',
    cheese: '🧀', bread: '🍞', fruit: '🍑', side: '🍲', ambient: '🥔', pit: '🔥', unstated: '🍽️',
  };
  function foodAvatar(glyph, cls) {
    const g = glyph || 'unstated';
    return '<span class="food-avatar fa-' + esc(g) + (cls ? ' ' + cls : '') + '">' + (GLYPH[g] || '🍽️') + '</span>';
  }

  function sparkline(values, color, w, h) {
    w = w || 52; h = h || 22;
    if (!values || values.length < 2) return '<span class="spark" style="width:' + w + 'px"></span>';
    const min = Math.min.apply(null, values), max = Math.max.apply(null, values), span = (max - min) || 1;
    const pts = values.map((v, i) => {
      const x = (i / (values.length - 1)) * (w - 4) + 2;
      const y = h - 3 - ((v - min) / span) * (h - 6);
      return x.toFixed(1) + ',' + y.toFixed(1);
    }).join(' ');
    return '<span class="spark"><svg width="' + w + '" height="' + h + '"><polyline points="' + pts + '" fill="none" stroke="' + color + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>';
  }

  // [BIZ] The gauge ring is a MARK. "Target reached" closes the ring; it never
  // turns green — green is transport health only.
  function gauge(o) {
    const size = 118, r = 50, c = size / 2, circ = 2 * Math.PI * r;
    const frac = Math.max(0, Math.min(1, (o.value - o.min) / (o.max - o.min)));
    const col = o.color || 'var(--pit)';
    let band = '';
    if (o.bandMin !== undefined && o.bandMax !== undefined) {
      const f0 = Math.max(0, Math.min(1, (o.bandMin - o.min) / (o.max - o.min)));
      const f1 = Math.max(0, Math.min(1, (o.bandMax - o.min) / (o.max - o.min)));
      band = '<circle cx="' + c + '" cy="' + c + '" r="' + r + '" fill="none" stroke="' + col + '" stroke-width="9" opacity="0.14" stroke-dasharray="' +
        ((f1 - f0) * circ).toFixed(1) + ' ' + circ.toFixed(1) + '" stroke-dashoffset="' + (-f0 * circ).toFixed(1) + '"/>';
    }
    const arc = '<circle cx="' + c + '" cy="' + c + '" r="' + r + '" fill="none" stroke="' + col + '" stroke-width="7" stroke-linecap="round" stroke-dasharray="' +
      (frac * circ).toFixed(1) + ' ' + circ.toFixed(1) + '"/>';
    return '<div class="gauge"><svg width="' + size + '" height="' + size + '">' +
      '<circle cx="' + c + '" cy="' + c + '" r="' + r + '" fill="none" stroke="var(--hairline-strong)" stroke-width="7"/>' + band + arc +
      '</svg><div class="g-center"><div class="g-val">' + esc(o.center) + '</div><div class="g-cap">' + esc(o.caption || '') + '</div></div></div>';
  }

  // [FLUTTER] Maps to the fl_chart cook chart. Rules ported:
  //   runs split at gaps before decimation; area fill <=16%; target lines are
  //   labelled ON the line; crosshair returns the nearest real sample.
  function buildChart(series, opts) {
    opts = opts || {};
    const W = 340, H = opts.height || 190, padL = 30, padR = 12, padT = 12, padB = 26;
    const xMin = opts.xMin, xMax = opts.xMax;
    let yMin = opts.yMin, yMax = opts.yMax;
    if (yMin === undefined) {
      let lo = Infinity, hi = -Infinity;
      series.forEach((s) => s.points.forEach((p) => { if (p.y < lo) lo = p.y; if (p.y > hi) hi = p.y; }));
      if (lo === Infinity) { lo = 32; hi = 220; }
      yMin = Math.floor((lo - 8) / 25) * 25; yMax = Math.ceil((hi + 8) / 25) * 25;
      if (yMax === yMin) yMax = yMin + 25;
    }
    const x = (v) => padL + ((v - xMin) / (xMax - xMin)) * (W - padL - padR);
    const y = (v) => padT + (1 - (v - yMin) / (yMax - yMin)) * (H - padT - padB);
    let svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none">';
    for (let i = 0; i <= 4; i++) {
      const gy = padT + (i / 4) * (H - padT - padB);
      const gv = yMax - (i / 4) * (yMax - yMin);
      svg += '<line x1="' + padL + '" y1="' + gy + '" x2="' + (W - padR) + '" y2="' + gy + '" stroke="var(--hairline)"/>';
      svg += '<text x="' + (padL - 5) + '" y="' + (gy + 3) + '" fill="var(--text-muted)" font-size="8.5" text-anchor="end" font-family="JetBrains Mono, monospace">' + Math.round(conv(gv)) + '</text>';
    }
    (opts.bands || []).forEach((b) => {
      const y0 = y(b.max), y1 = y(b.min);
      svg += '<rect x="' + padL + '" y="' + y0.toFixed(1) + '" width="' + (W - padL - padR) + '" height="' + Math.max(0, y1 - y0).toFixed(1) + '" fill="' + (b.color || 'var(--warning)') + '" opacity="0.08"/>';
    });
    (opts.targets || []).forEach((t) => {
      if (t.value === null || t.value === undefined) return;
      const ty = y(t.value);
      svg += '<line x1="' + padL + '" y1="' + ty + '" x2="' + (W - padR) + '" y2="' + ty + '" stroke="' + t.color + '" stroke-width="1" stroke-dasharray="4 4" opacity="0.65"/>';
      svg += '<text x="' + (W - padR) + '" y="' + (ty - 3) + '" fill="' + t.color + '" font-size="8.5" text-anchor="end" font-family="JetBrains Mono, monospace">' + esc(t.label) + '</text>';
    });
    series.forEach((s) => {
      if (s.hidden) return;
      const dim = opts.isolated && opts.isolated !== s.probe;
      const col = dim ? 'var(--chrome-dim)' : s.color;
      const d = s.points.map((p, i) => (i ? 'L' : 'M') + x(p.x).toFixed(1) + ' ' + y(p.y).toFixed(1)).join(' ');
      if (!dim && s.points.length > 1) {
        const area = d + ' L' + x(s.points[s.points.length - 1].x).toFixed(1) + ' ' + (H - padB) + ' L' + x(s.points[0].x).toFixed(1) + ' ' + (H - padB) + ' Z';
        svg += '<path d="' + area + '" fill="' + s.color + '" opacity="0.10"/>';
      }
      svg += '<path d="' + d + '" fill="none" stroke="' + col + '" stroke-width="' + (s.width || 2) + '" stroke-linecap="round" stroke-linejoin="round"' + (s.dash ? ' stroke-dasharray="' + s.dash + '"' : '') + '/>';
      if (!dim && s.points.length) {
        const lp = s.points[s.points.length - 1];
        svg += '<circle cx="' + x(lp.x).toFixed(1) + '" cy="' + y(lp.y).toFixed(1) + '" r="3" fill="' + s.color + '"/>';
      }
    });
    (opts.marks || []).forEach((mk) => {
      const mx = x(mk.x);
      if (mx < padL || mx > W - padR) return;
      svg += '<line x1="' + mx.toFixed(1) + '" y1="' + padT + '" x2="' + mx.toFixed(1) + '" y2="' + (H - padB) + '" stroke="var(--warning)" stroke-width="1" stroke-dasharray="2 3" opacity="0.45"/>';
    });
    if (opts.now !== undefined && opts.now <= xMax && opts.now >= xMin) {
      svg += '<line x1="' + x(opts.now).toFixed(1) + '" y1="' + padT + '" x2="' + x(opts.now).toFixed(1) + '" y2="' + (H - padB) + '" stroke="var(--text-hi)" opacity="0.5"/>';
    }
    for (let i = 0; i <= 4; i++) {
      const v = xMin + (i / 4) * (xMax - xMin), px = x(v);
      svg += '<text x="' + px.toFixed(1) + '" y="' + (H - 8) + '" fill="var(--text-muted)" font-size="8.5" text-anchor="middle" font-family="JetBrains Mono, monospace">' + esc(opts.xLabels ? opts.xLabels(v) : Math.round(v)) + '</text>';
    }
    return svg + '</svg>';
  }

  // ===================================================== §4 DOMAIN HELPERS ====
  function allCatalog() { return M.CATALOG.concat(state.settings.customCatalog || []); }
  function catalogById(id) { return allCatalog().find((c) => c.id === id); }
  function catalogInCat(cat) { return allCatalog().filter((c) => c.category === cat); }
  function timelineFor(id) {
    const c = catalogById(id);
    if (c && c.timeline) return c.timeline;
    return M.TIMELINES[id] || null;
  }
  function stylesFor(id) { return M.STYLES[id] || null; }
  function donenessFor(cat, id) {
    if (!cat) return null;
    if (!id) id = cat.defaultDoneness;
    return cat.doneness.find((d) => d.id === id) || cat.doneness[0];
  }

  // [BIZ] carryover / pull temp / rest mirror presets.dart + cook_phase.dart.
  // Poultry carryover is always zero; pull is clamped at the safety floor.
  function carryoverFor(cat) {
    if (!cat) return 0;
    if (cat.hazard === 'poultry') return 0;
    return cat.thickness === 'thick' ? 8 : cat.thickness === 'medium' ? 5 : 2;
  }
  function pullTempFor(cat, d) {
    const target = d ? d.targetF : (cat ? cat.doneness[0].targetF : null);
    return target === null ? null : target - carryoverFor(cat);
  }
  function restMinutesFor(cat) {
    const co = carryoverFor(cat);
    return co <= 0 ? 0 : co <= 2 ? 5 : co <= 5 ? 10 : 20;
  }
  function styleName(id) {
    for (const k in M.STYLES) { const s = M.STYLES[k].find((x) => x.id === id); if (s) return s.name; }
    return null;
  }

  function rng(seed) {
    return function () {
      seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
      let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function buildSeries(probe, cook) {
    const elapsedMin = cook.startedAtMs ? Math.max(20, (Date.now() - cook.startedAtMs) / 60000) : 60;
    const n = 90, r = rng(probe.jack * 7919 + 13);
    const start = probe.lowF !== null && probe.lowF !== undefined ? probe.lowF : (probe.role === 'pit' ? 70 : 58);
    const cur = probe.tempF !== null && probe.tempF !== undefined ? probe.tempF : start;
    const pts = [];
    for (let i = 0; i <= n; i++) {
      const p = i / n, xx = elapsedMin * p;
      let v;
      if (probe.role === 'pit') v = start + (cur - start) * p + Math.sin(p * 9) * 6 + (r() - 0.5) * 3;
      else {
        let e = Math.pow(p, 0.55);
        if (probe.stalled && p > 0.55 && p < 0.88) e = Math.pow(0.55, 0.55) + (p - 0.55) * 0.12;
        v = start + (cur - start) * e + (r() - 0.5) * 2.2;
      }
      pts.push({ x: xx, y: Math.max(0, v) });
    }
    pts[n].y = cur;
    return pts;
  }
  function seriesColor(jack) { return ['var(--p1)', 'var(--p2)', 'var(--p3)', 'var(--p4)'][jack - 1] || 'var(--p1)'; }

  // ==================================================== §5 RENDER: CHROME ====
  function renderAppbar() { $('#appbar').innerHTML = appbarHtml(); }

  function linkInfo() {
    const c = scenario().connection;
    const bt = c.bt || {}, wifi = c.wifi || {};
    let label, iconName, cls = '';
    if (c.phase === 'offline') { label = 'Offline'; iconName = 'wifiOff'; cls = 'is-offline'; }
    else if (c.phase === 'connecting') { label = 'Connecting…'; iconName = 'refresh'; cls = 'is-busy'; }
    else if (c.phase === 'provisioning') { label = 'Hotspot'; iconName = 'wifi'; cls = 'is-busy'; }
    else if (c.phase === 'rollback') { label = 'Bluetooth'; iconName = 'bluetooth'; cls = 'is-busy'; }
    else if (c.primary === 'bt') { label = 'Bluetooth'; iconName = 'bluetooth'; }
    else if (c.primary === 'wifi') { label = wifi.mode === 'ap' ? 'Bridge Wi-Fi' : 'Home Wi-Fi'; iconName = wifi.mode === 'ap' ? 'wifi' : 'router'; }
    else { label = 'Offline'; iconName = 'wifiOff'; cls = 'is-offline'; }
    const btDot = '<span class="lc-radio' + (bt.connected ? ' on' : '') + (c.primary === 'bt' ? ' pri' : '') + '" title="Bluetooth">' + icon('bluetooth', 13) + '</span>';
    const wifiDot = '<span class="lc-radio' + (wifi.connected ? ' on' : '') + (c.primary === 'wifi' ? ' pri' : '') + '" title="Wi-Fi">' + icon(wifi.mode === 'ap' ? 'wifi' : 'router', 13) + '</span>';
    return { label: label, iconName: iconName, cls: cls, btDot: btDot, wifiDot: wifiDot, c: c };
  }

  function appbarHtml() {
    const s = scenario();
    const alarms = (s.alarms || []).filter((a) => !a.acked && !state.pendingAck[a.id]);
    const badge = alarms.length ? '<span class="dot-badge">' + alarms.length + '</span>' : '';
    const bell = iconBtn('bell', 'open-alerts', { label: 'Alerts', badge: badge });

    if (state.screen === 'cookDetail') {
      return '<button class="icon-btn" data-action="back" aria-label="Back">' + icon('chevronLeft') + '</button>' +
        '<div><div class="ab-title" style="font-size:17px">Cook detail</div></div><div class="spacer"></div>' + bell;
    }
    if (state.screen === 'history') {
      return '<button class="icon-btn" data-action="nav" data-screen="settings" aria-label="Back">' + icon('chevronLeft') + '</button>' +
        '<div><div class="ab-title">History</div><div class="ab-sub">Past cooks</div></div><div class="spacer"></div>' +
        iconBtn('plus', 'open-setup', { label: 'Start a cook' }) + bell;
    }
    if (state.screen === 'live') {
      const li = linkInfo();
      const chip = '<button class="link-chip ' + li.cls + '" data-action="open-connect" aria-label="Connection status">' +
        '<span class="pulse-dot ' + (li.c.phase === 'offline' ? 'idle' : li.c.phase === 'connected' ? '' : 'warn') + '"></span>' +
        icon(li.iconName, 14) + '<span class="lc-label">' + esc(li.label) + '</span>' +
        '<span class="lc-sep"></span>' + li.btDot + li.wifiDot + '</button>';
      return chip + '<div class="spacer"></div>' + bell;
    }
    const titles = {
      temps: ['Temperatures', 'Every probe, up close'],
      timeline: ['Timeline', 'Expected & actual'],
      graph: ['Graph', 'All probes'],
      settings: ['Settings', 'Connection & preferences'],
    };
    const t = titles[state.screen] || ['Smoke', ''];
    return '<div><div class="ab-title">' + t[0] + '</div><div class="ab-sub">' + t[1] + '</div></div><div class="spacer"></div>' + bell;
  }

  function renderNav() {
    const items = [
      { id: 'live', label: 'Live', icon: 'activity' },
      { id: 'temps', label: 'Temps', icon: 'thermometer' },
      { id: 'timeline', label: 'Timeline', icon: 'list' },
      { id: 'graph', label: 'Graph', icon: 'chart' },
      { id: 'settings', label: 'Settings', icon: 'sliders' },
    ];
    const alarmCount = (scenario().alarms || []).filter((a) => !a.acked && !state.pendingAck[a.id]).length;
    $('#nav').innerHTML = items.map((it) => {
      const on = state.screen === it.id ||
        (state.screen === 'cookDetail' && it.id === 'settings') ||
        (state.screen === 'history' && it.id === 'settings');
      const dot = it.id === 'live' && alarmCount ? '<span class="ndot"></span>' : '';
      return '<button class="nav-item' + (on ? ' on' : '') + '" data-action="nav" data-screen="' + it.id + '" aria-label="' + it.label + '">' +
        icon(it.icon) + '<span class="nlabel">' + it.label + '</span>' + dot + '</button>';
    }).join('');
  }

  function renderView() {
    const map = {
      live: viewLive, temps: viewTemps, timeline: viewTimeline, graph: viewGraph,
      settings: viewSettings, history: viewHistory, cookDetail: viewCookDetail,
    };
    $('#view').innerHTML = (map[state.screen] || viewLive)();
  }

  // ====================================================== §6 RENDER: VIEWS ====
  // ---- Live (glance) -------------------------------------------------------
  function viewLive() {
    const s = scenario(), cook = s.cook;
    const grate = s.probes.find((p) => p.role === 'pit');
    let html = '';

    html += alarmStrips(s);

    if (s.notice) html += '<div class="cap-notice warn mb3">' + icon('info') + '<div class="cn-text">' + esc(s.notice) + '</div></div>';

    if (s.pendingSession && !cook.active) {
      const ps = s.pendingSession;
      html += '<div class="card" style="border-color:rgba(var(--pit-rgb),0.4);background:linear-gradient(180deg,rgba(var(--pit-rgb),0.10),var(--card) 60%)">' +
        '<div class="card-head">' + icon('history') + '<div class="card-title">A cook is already running</div></div>' +
        '<div class="body small">Your bridge has been recording for <b class="hi">' + fmtDuration(Date.now() - ps.startedAtMs) + '</b> with ' +
        ps.probeCount + ' probes attached (' + ps.samples + ' samples). We can pull that history in and build the cook around it.</div>' +
        '<div class="btn-row mt4"><button class="btn primary" data-action="adopt">' + icon('download') + 'Adopt session</button>' +
        '<button class="btn ghost" data-action="discard-session">Start fresh</button></div></div>';
    }

    if (cook.active) {
      const firstCat = catalogById((cook.items[0] || {}).id);
      html += '<div class="card">' +
        '<div class="cook-head">' + foodAvatar(firstCat ? firstCat.glyph : 'unstated') +
        '<div class="ch-meta"><div class="ch-name">' + esc(cook.name) + '</div>' +
        '<div class="ch-line">' + icon('lock', 12) + 'Recording on the bridge — safe even if this phone drops</div></div>' +
        iconBtn('sliders', 'open-setup', { label: 'Cook settings' }) + '</div>' +
        '<div class="stopwatch mt4' + (cook.paused ? ' paused' : '') + '">' +
        '<div><div class="sw-label">Cook time</div><div class="sw-time" id="swTime">' + fmtStopwatch(Date.now() - cook.startedAtMs) + '</div>' +
        '<div class="sw-started">Started ' + fmtClock(cook.startedAtMs) + (cook.paused ? ' · paused' : '') + '</div></div>' +
        '<div class="spacer"></div><div class="sw-actions">' +
        '<button class="sw-btn" data-action="pause-cook" aria-label="' + (cook.paused ? 'Resume' : 'Pause') + '" title="' + (cook.paused ? 'Resume' : 'Pause') + '">' + icon(cook.paused ? 'play' : 'pause') + '</button>' +
        '<button class="sw-btn" data-action="edit-start" aria-label="Adjust start time" title="Adjust start time">' + icon('edit') + '</button>' +
        '</div></div></div>';
    } else {
      html += '<div class="card">' +
        '<div class="card-head">' + icon('thermometer') + '<div class="card-title">Instrument mode</div>' +
        '<span class="spacer"></span><span class="tiny muted">no targets</span></div>' +
        '<div class="body small">Watching live temperatures without a cook. Nothing is lost — the bridge records everything either way. Add a cook whenever you want targets, timers and a timeline.</div>' +
        '<div class="btn-row mt4"><button class="btn primary" data-action="open-setup">' + icon('plus') + 'Start a cook</button>' +
        '<button class="btn ghost" data-action="nav" data-screen="graph">' + icon('chart') + 'View graph</button></div></div>';
    }

    const attached = s.probes.filter((p) => p.attached && p.role !== 'unused');
    const meats = attached.filter((p) => p.role === 'food');
    const hottest = meats.slice().sort((a, b) => (b.tempF || 0) - (a.tempF || 0))[0];
    const done = meats.filter((p) => p.targetF && p.tempF >= p.targetF).length;
    const toTarget = meats.filter((p) => p.targetF && p.tempF < p.targetF).length;
    html += '<div class="section-label">At a glance</div><div class="summary-strip">' +
      '<div class="ss"><div class="ss-k">Grate</div><div class="ss-v">' + (grate && grate.attached ? fmtTemp(grate.tempF, 0).replace(unitLabel(), '') : '—') + '<span class="tiny muted">' + (grate && grate.attached ? unitLabel() : '') + '</span></div><div class="ss-s">' + (grate && grate.attached ? 'Pit band ' + cook.pitBand[0] + '–' + cook.pitBand[1] + '°' : 'No pit probe') + '</div></div>' +
      '<div class="ss"><div class="ss-k">Hottest food</div><div class="ss-v">' + (hottest ? fmtTemp(hottest.tempF, 0).replace(unitLabel(), '') : '—') + '<span class="tiny muted">' + (hottest ? unitLabel() : '') + '</span></div><div class="ss-s">' + (hottest ? esc(probeName(hottest, cook)) : 'None attached') + '</div></div>' +
      '<div class="ss"><div class="ss-k">To target</div><div class="ss-v">' + toTarget + '</div><div class="ss-s">' + (done ? done + ' ready' : 'none ready yet') + '</div></div></div>';

    html += '<div class="section-label">' + icon('thermometer', 13) + 'Probes<span class="spacer"></span>' +
      '<span class="link" data-action="nav" data-screen="temps">Details</span></div>' +
      '<div class="probe-rail">' + s.probes.map((p) => compactProbe(p, cook)).join('') + '</div>';

    const elapsedMin = cook.startedAtMs ? Math.round((Date.now() - cook.startedAtMs) / 60000) : 0;
    html += '<div class="card tap mt3" data-action="nav" data-screen="graph">' +
      '<div class="card-head">' + icon('chart') + '<div class="card-title">Live graph</div><span class="spacer"></span>' +
      '<span class="tiny muted">' + (state.units === 'C' ? '°C' : '°F') + ' · last ' + elapsedMin + 'm</span>' + icon('chevronRight') + '</div>' +
      '<div class="chart">' + miniChart(s) + '</div></div>';

    html += '<div class="section-label">Quick actions</div><div class="btn-row">' +
      '<button class="btn" data-action="open-mark">' + icon('bookmark') + 'Mark</button>' +
      '<button class="btn" data-action="open-setup">' + icon('plus') + 'Add food</button></div>';
    return html;
  }

  function alarmStrips(s) {
    const alarms = (s.alarms || []).filter((a) => !a.acked && !state.pendingAck[a.id]);
    if (!alarms.length) return '';
    const order = { critical: 0, warning: 1, info: 2 };
    alarms.sort((a, b) => order[a.severity] - order[b.severity]);
    let html = '';
    if (alarms.length > 1) html += '<div class="row between mb2"><span class="tiny muted">' + alarms.length + ' active alerts</span><span class="link" data-action="ack-all">Acknowledge all</span></div>';
    html += alarms.slice(0, 3).map((a) => {
      const ic = a.severity === 'critical' ? 'alertCircle' : a.severity === 'warning' ? 'alertTriangle' : 'info';
      const tier = a.tier === 'device' ? '<span class="tier-tag device">Device</span>' : '<span class="tier-tag app">Insight</span>';
      return '<div class="alarm-bar ' + a.severity + '" data-action="open-alarm-detail" data-id="' + a.id + '">' +
        '<span class="al-icon">' + icon(ic) + '</span><div class="al-text">' +
        '<div class="al-title">' + esc(a.rule) + ' ' + tier + '</div>' +
        '<div class="al-detail">' + esc(a.detail) + (a.valueF ? ' · ' + fmtTemp(a.valueF) : '') + '</div></div>' +
        '<button class="al-ack" data-action="ack-alarm" data-id="' + a.id + '" aria-label="Acknowledge" title="Acknowledge">' + icon('check', 17) + '</button></div>';
    }).join('');
    return html;
  }

  // [BIZ] Detached probe renders "— / Unplugged", never 0 (I3).
  function compactProbe(p, cook) {
    const isGrate = p.role === 'pit';
    const attached = p.attached && p.role !== 'unused';
    const tp = attached ? tempParts(p.tempF) : { num: '—', dec: '', unit: '' };
    const target = isGrate ? (cook.grateTargetF || p.targetF) : p.targetF;
    const prog = (attached && target && p.tempF !== null) ? Math.max(0, Math.min(1, p.tempF / target)) : 0;
    const canShow = p.freshness === 'live';
    let flags = '';
    if (p.stalled && canShow) flags += '<span class="tt-stall">STALL</span>';
    if (attached && target && p.tempF >= target) flags += '<span class="tt-done">DONE</span>';
    const sub = !p.attached ? 'Unplugged' : p.role === 'unused' ? 'Unused' :
      isGrate ? 'Pit band ' + cook.pitBand[0] + '–' + cook.pitBand[1] + '°' :
      (canShow && p.etaMin !== null && p.etaMin !== undefined ? fmtEta(p.etaMin) + ' to pull' : (target ? 'Target ' + fmtTemp(target, 0) : 'No target'));
    return '<div class="compact-probe p' + p.jack + (isGrate ? ' grate' : '') + '" data-action="open-probe" data-jack="' + p.jack + '">' +
      '<div class="tt-flags">' + flags + '</div>' +
      '<div class="cp-top"><span class="jack-badge ' + (p.attached ? 'p' + p.jack : 'detached') + '" style="width:22px;height:22px;font-size:11px">' + p.jack + '</span>' +
      '<span class="cp-name">' + esc(probeName(p, cook)) + '</span></div>' +
      '<div class="cp-temp">' + tp.num + '<span class="u">' + (attached ? tp.dec + tp.unit : '') + '</span></div>' +
      '<div class="cp-sub">' + esc(sub) + '</div>' +
      (attached && target ? '<div class="cp-bar"><i style="width:' + (prog * 100).toFixed(0) + '%"></i></div>' : '') + '</div>';
  }

  function phaseOf(p) {
    if (!p.attached || p.targetF === null || p.targetF === undefined) return '';
    const pull = p.pullF === null || p.pullF === undefined ? p.targetF : p.pullF;
    if (p.tempF >= p.targetF) return '<span style="color:var(--positive)">Ready to serve</span>';
    if (p.tempF >= pull) return '<span style="color:var(--warning)">Pull now — coast to ' + fmtTemp(p.targetF, 0) + '</span>';
    return 'Approaching · pull at ' + fmtTemp(pull, 0);
  }

  function trendChip(rate, perHr) {
    if (rate === null || rate === undefined) return '<span class="trend-chip flat">' + icon('minus', 11) + 'stale</span>';
    const r = perHr ? rate : rate * 60;
    if (Math.abs(r) < 0.6) return '<span class="trend-chip flat">~0° F/hr</span>';
    const up = r > 0;
    return '<span class="trend-chip ' + (up ? 'up' : 'down') + '">' + icon(up ? 'arrowUp' : 'arrowDown', 11) + Math.abs(r).toFixed(1) + '° F/hr</span>';
  }

  function miniChart(s) {
    const cook = s.cook, W = 300, H = 70;
    const elapsed = cook.startedAtMs ? (Date.now() - cook.startedAtMs) / 60000 : 60;
    let svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none">';
    s.probes.filter((p) => p.attached).forEach((p) => {
      const pts = buildSeries(p, cook), vals = pts.map((q) => q.y);
      const lo = Math.min.apply(null, vals), hi = Math.max.apply(null, vals), span = (hi - lo) || 1;
      const d = pts.map((q, i) => {
        const xx = (q.x / elapsed) * W, yy = H - 4 - ((q.y - lo) / span) * (H - 8);
        return (i ? 'L' : 'M') + xx.toFixed(1) + ' ' + yy.toFixed(1);
      }).join(' ');
      svg += '<path d="' + d + '" fill="none" stroke="' + seriesColor(p.jack) + '" stroke-width="' + (p.role === 'pit' ? 2.4 : 1.8) + '" stroke-linecap="round" stroke-linejoin="round"/>';
    });
    return svg + '</svg>';
  }

  // ---- Temps (big widgets) -------------------------------------------------
  function viewTemps() {
    const s = scenario(), cook = s.cook;
    const attached = s.probes.filter((p) => p.attached && p.role !== 'unused');
    if (!attached.length) {
      return emptyState('No probes attached', 'Plug a probe into the Smoke X4 and it will appear here the moment the bridge hears it.', 'nav', 'View graph', 'thermometer');
    }
    let html = '<div class="row between mb3"><span class="tiny muted">' + attached.length + ' attached · updated ' +
      (s.connection.phase === 'connected' ? 'live' : 'stale') + '</span>' +
      '<div class="seg"><button data-action="set-units" data-units="F" class="' + (state.units === 'F' ? 'on' : '') + '">°F</button>' +
      '<button data-action="set-units" data-units="C" class="' + (state.units === 'C' ? 'on' : '') + '">°C</button></div></div>';

    html += '<div class="stack">' + attached.map((p) => tempCard(p, cook)).join('') + '</div>';

    const detached = s.probes.filter((p) => !p.attached || p.role === 'unused');
    if (detached.length) {
      html += '<div class="section-label">Not attached</div><div class="card subtle">' + detached.map((p, i) =>
        '<div class="link-row off" style="cursor:default;' + (i === detached.length - 1 ? 'border-bottom:none' : '') + '">' +
        '<div class="lr-icon">' + icon('thermometer') + '</div><div class="lr-meta"><div class="lr-name">Jack ' + p.jack + '</div>' +
        '<div class="lr-sub">Unplugged — absent, never 0°</div></div>' +
        '<div class="lr-right"><button class="btn ghost sm" data-action="open-probe" data-jack="' + p.jack + '">Set role</button></div></div>').join('') + '</div>';
    }
    html += '<div class="btn-row mt4"><button class="btn" data-action="open-mark">' + icon('bookmark') + 'Add mark</button>' +
      '<button class="btn ghost" data-action="open-setup">' + icon('plus') + 'Add food</button></div>';
    return html;
  }

  function tempCard(p, cook) {
    const isGrate = p.role === 'pit';
    const attached = p.attached;
    const tp = attached ? tempParts(p.tempF) : { num: '—', dec: '', unit: '' };
    const target = isGrate ? (cook.grateTargetF || p.targetF) : p.targetF;
    const canShow = p.freshness === 'live';
    const prog = (attached && target && p.tempF !== null) ? Math.max(0, Math.min(1, p.tempF / target)) : 0;
    const fresh = p.freshness === 'live' ? 'Live' : p.freshness === 'aging' ? 'Aging' : p.freshness === 'frozen' ? 'Stale' : '—';
    let flags = '';
    if (p.stalled && canShow) flags += '<span class="tt-stall">STALL</span>';
    if (attached && target && p.tempF >= target) flags += '<span class="tt-done">DONE</span>';
    if (isGrate) flags += '<span class="tt-grate-tag">Grate</span>';
    return '<div class="temp-card p' + p.jack + (attached ? '' : ' detached') + '" data-action="open-probe" data-jack="' + p.jack + '">' +
      '<div class="tc-head"><span class="jack-badge ' + (attached ? 'p' + p.jack : 'detached') + '">' + p.jack + '</span>' +
      '<span class="tc-name">' + esc(probeName(p, cook)) + '</span><span class="spacer"></span>' + flags + '</div>' +
      '<div class="tc-body"><div class="tc-temp">' + tp.num + '<span class="u">' + (attached ? tp.dec + tp.unit : '') + '</span></div>' +
      '<div class="tc-side">' + (canShow ? trendChip(p.trendFPerHr, true) : '<span class="trend-chip flat">stale</span>') +
      '<span class="tiny muted">' + fresh + '</span></div></div>' +
      (attached && target ? '<div class="tt-progress mt3"><i style="width:' + (prog * 100).toFixed(0) + '%"></i></div>' : '') +
      '<div class="tc-meta">' + tempMeta(p, isGrate, cook) + '</div></div>';
  }
  function tempMeta(p, isGrate, cook) {
    const canShow = p.freshness === 'live';
    const cells = [];
    if (isGrate) {
      const inBand = p.tempF !== null && p.tempF >= cook.pitBand[0] && p.tempF <= cook.pitBand[1];
      cells.push(['Pit band', cook.pitBand[0] + '–' + cook.pitBand[1] + '°'], ['Status', inBand ? 'In band' : 'Out']);
    } else if (p.targetF) {
      cells.push(['Target', fmtTemp(p.targetF, 0)], ['Pull at', p.pullF ? fmtTemp(p.pullF, 0) : '—']);
      cells.push(['ETA', canShow && p.etaMin !== null && p.etaMin !== undefined ? fmtEta(p.etaMin) : (p.stalled && canShow ? 'Stalled' : '—')]);
    }
    cells.push(['High', fmtTemp(p.peakF, 0)], ['Avg', fmtTemp(p.avgF, 0)]);
    return cells.map((c) => '<div class="tc-m"><div class="tc-mk">' + c[0] + '</div><div class="tc-mv">' + c[1] + '</div></div>').join('');
  }

  // ---- Timeline ------------------------------------------------------------
  function viewTimeline() {
    const s = scenario(), cook = s.cook;
    if (!cook.active && !s.pendingSession) {
      return emptyState('No cook to schedule', 'Start a cook and everything you put on the grill appears here with an expected timeline — stall, wrap, rest and all.', 'open-setup', 'Start a cook', 'calendar');
    }
    const started = cook.startedAtMs || (s.pendingSession ? s.pendingSession.startedAtMs : Date.now());
    const now = Date.now();
    const items = cook.items.map((it) => {
      const cat = catalogById(it.id);
      const tl = timelineFor(it.id) || { totalMin: [60, 90], restMin: 10, phases: [] };
      const mid = (tl.totalMin[0] + tl.totalMin[1]) / 2;
      return { it: it, cat: cat, tl: tl, start: it.addedAtMs, end: it.addedAtMs + mid * 60000, expectedMin: mid, rest: tl.restMin };
    });
    const domainEnd = Math.max(now, Math.max.apply(null, items.map((i) => i.end))) + 45 * 60000;
    const x = (t) => ((t - started) / (domainEnd - started)) * 100;
    const lastEnd = Math.max.apply(null, items.map((i) => i.end));

    let html = '<div class="card"><div class="card-head">' + icon('list') + '<div class="card-title">Expected schedule</div></div>' +
      '<div class="row" style="gap:18px">' +
      '<div><div class="tiny muted">Everything off by</div><div class="mono hi bold" style="font-size:18px">' + fmtClock(lastEnd) + '</div></div>' +
      '<div><div class="tiny muted">Served by</div><div class="mono hi bold" style="font-size:18px">' + fmtClock(lastEnd + 30 * 60000) + '</div></div>' +
      '<div><div class="tiny muted">Items</div><div class="mono hi bold" style="font-size:18px">' + items.length + '</div></div></div></div>';

    html += '<div class="gantt mt3">' +
      '<div class="gantt-axis"><span>' + fmtClock(started) + '</span><span>' + fmtClock(started + (domainEnd - started) / 2) + '</span><span>' + fmtClock(domainEnd) + '</span></div>';
    items.forEach((row) => {
      const left = x(row.start), right = x(row.end), w = Math.max(2, right - left);
      const pct = Math.max(0, Math.min(1, (now - row.start) / (row.end - row.start)));
      let marks = '';
      if (row.tl.stall) {
        const sl = x(row.start + row.expectedMin * 0.38 * 60000);
        const sw = x(row.start + row.expectedMin * 0.72 * 60000) - sl;
        marks += '<span class="gantt-milestone stall" style="left:' + sl + '%;width:' + sw + 'px;border-radius:6px" title="Expected stall"></span>';
      }
      if (row.tl.wrap) marks += '<span class="gantt-milestone wrap" style="left:' + x(row.start + row.expectedMin * 0.55 * 60000) + '%" title="' + esc(row.tl.wrap.label) + '"></span>';
      html += '<div class="gantt-row"><div class="gantt-label">' + foodAvatar(row.cat ? row.cat.glyph : 'unstated', 'sm') +
        '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + esc(row.cat ? row.cat.name : 'Item') + '</span></div>' +
        '<div class="gantt-track"><span class="gantt-bar p' + row.it.jack + '" style="left:' + left + '%;width:' + w + '%">' +
        '<span class="gb-fill" style="width:' + (pct * 100).toFixed(0) + '%"></span>' +
        '<span class="gb-text">' + fmtClock(row.end) + '</span></span>' + marks +
        (row.it.jack === 1 ? '<span class="gantt-now" style="left:' + x(now) + '%"></span>' : '') +
        '</div></div>';
    });
    html += '</div>';

    html += '<div class="section-label">' + icon('zap', 13) + 'Upcoming</div>';
    const upcoming = [], seenUp = {};
    items.forEach((row) => {
      const add = (u) => { const key = u.icon + '|' + Math.round(u.at / 60000); if (!seenUp[key]) { seenUp[key] = 1; upcoming.push(u); } };
      if (row.tl.wrap) add({ at: row.start + row.expectedMin * 0.55 * 60000, icon: 'wrap', label: row.tl.wrap.label, note: row.tl.wrap.note });
      if (row.tl.spritzEveryMin) add({ at: now + 20 * 60000, icon: 'droplet', label: 'Spritz', note: 'Every ' + row.tl.spritzEveryMin + ' min to keep the bark moist.' });
      if (row.tl.turn) add({ at: row.start + (row.tl.turn.elapsedMin || 30) * 60000, icon: 'rotate', label: 'Turn / rotate', note: row.tl.turn.note });
    });
    upcoming.sort((a, b) => a.at - b.at);
    html += '<div class="milestone-grid">' + upcoming.slice(0, 4).map((u) =>
      '<div class="milestone"><div class="ms-label">' + icon(u.icon, 12) + esc(u.label) + '</div>' +
      '<div class="ms-val">' + fmtClock(u.at) + '</div><div class="ms-note">' + esc(u.note) + '</div></div>').join('') + '</div>';

    html += '<div class="section-label">' + icon('clock', 13) + 'The cook, in order</div>';
    const events = [];
    (s.marks || []).forEach((mk) => events.push({ at: mk.atMs, actual: true, title: mk.label, note: mk.kind.replace('_', ' ') }));
    items.forEach((row) => {
      (row.tl.phases || []).forEach((p, idx, arr) => {
        const at = row.start + row.expectedMin * (idx / Math.max(1, arr.length - 1)) * 60000;
        if (at > now) events.push({ at: at, actual: false, title: row.cat.name + ' · ' + p.label, note: p.note });
      });
    });
    events.sort((a, b) => a.at - b.at);
    html += '<div class="rail">' + events.map((e, i) => {
      const isNow = !e.actual && e.at > now && (i === 0 || events[i - 1].at <= now);
      const cls = e.actual ? 'done' : (isNow ? 'now' : 'predicted');
      return '<div class="rail-item ' + (e.actual ? '' : 'predicted') + '"><span class="rail-dot ' + cls + '"></span>' +
        '<div class="rail-time">' + fmtClock(e.at) + (e.actual ? '' : ' · expected') + '</div>' +
        '<div class="rail-title">' + esc(e.title) + '</div>' + (e.note ? '<div class="rail-note">' + esc(e.note) + '</div>' : '') + '</div>';
    }).join('') + '</div>';

    html += '<div class="btn-row mt4"><button class="btn" data-action="open-setup">' + icon('plus') + 'Add something</button>' +
      '<button class="btn ghost" data-action="open-mark">' + icon('bookmark') + 'Log event</button></div>';
    return html;
  }

  // ---- Graph ---------------------------------------------------------------
  function graphDomain() {
    const s = scenario(), cook = s.cook;
    const started = cook.startedAtMs || (Date.now() - 60 * 60000);
    const now = Date.now(), elapsed = Math.max(5, (now - started) / 60000);
    const ranges = { '15m': 15, '1h': 60, '6h': 360, all: elapsed };
    const base = ranges[state.chartRange] || elapsed;
    const span = Math.max(2, base / state.graph.zoom);
    const viewEnd = Math.max(span, elapsed - state.graph.pan);
    const xMin = Math.max(0, viewEnd - span), xMax = Math.min(elapsed, xMin + span);
    return { started: started, elapsed: elapsed, xMin: xMin, xMax: xMax, now: elapsed };
  }
  function graphSeries() {
    const s = scenario();
    const d = graphDomain();
    return s.probes.filter((p) => p.attached && p.spark && p.spark.length).map((p) => {
      const all = buildSeries(p, { startedAtMs: Date.now() - d.elapsed * 60000 });
      return { probe: p.jack, color: seriesColor(p.jack), points: all.filter((q) => q.x >= d.xMin), width: p.role === 'pit' ? 2.6 : 2, dash: [null, '7 4', '2 4', '9 3 2 3'][p.jack - 1] || null };
    });
  }
  function viewGraph() {
    const s = scenario(), cook = s.cook, d = graphDomain();
    const series = graphSeries();
    const targets = s.probes.filter((p) => p.attached && p.targetF !== null && p.targetF !== undefined)
      .map((p) => ({ value: p.targetF, color: seriesColor(p.jack), label: fmtTemp(p.targetF, 0) }));
    const marks = (s.marks || []).map((mk) => ({ x: (mk.atMs - d.started) / 60000 })).filter((m) => m.x >= d.xMin);
    lastChart = { series: series.map((sr) => ({ name: probeName(s.probes.find((p) => p.jack === sr.probe), cook), points: sr.points })), xMin: d.xMin, xMax: d.xMax, started: d.started };

    let html = '<div class="row between mb3"><div class="seg-chips">' + ['15m', '1h', '6h', 'all'].map((r) =>
      '<button class="chip' + (state.chartRange === r ? ' on' : '') + '" data-action="graph-range" data-range="' + r + '">' + r + '</button>').join('') + '</div>' +
      '<div class="zoom-bar">' +
      '<button class="zb" data-action="graph-zoom" data-dir="out" aria-label="Zoom out">' + icon('zoomOut') + '</button>' +
      '<button class="zb" data-action="graph-zoom" data-dir="in" aria-label="Zoom in">' + icon('zoomIn') + '</button>' +
      '<button class="zb" data-action="graph-fullscreen" aria-label="Fullscreen">' + icon('expand') + '</button></div></div>';

    html += '<div class="chart-wrap"><div class="chart" id="chartHost">' + buildChart(series, {
      xMin: d.xMin, xMax: d.xMax, targets: targets, marks: marks, now: d.now, isolated: state.isolatedProbe,
      bands: [{ min: cook.pitBand[0], max: cook.pitBand[1], color: 'var(--warning)' }],
      xLabels: (v) => fmtClock(d.started + v * 60000),
    }) + '<div class="crosshair-tip" id="chartTip"></div></div>';
    html += '<div class="legend">' + s.probes.map((p) => {
      if (!p.attached) return '';
      const dim = state.isolatedProbe && state.isolatedProbe !== p.jack;
      return '<button class="legend-item' + (dim ? ' dim' : '') + '" data-action="isolate" data-jack="' + p.jack + '">' +
        '<span class="legend-swatch" style="' + legendSwatch(p.jack) + '"></span>' +
        '<span class="lg-name">' + esc(probeName(p, cook)) + '</span><span class="lg-val">' + fmtTemp(p.tempF) + '</span></button>';
    }).join('') + '</div>' +
      '<div class="row between mt3"><span class="tiny muted">' + (state.graph.zoom > 1 ? (state.graph.zoom.toFixed(1) + '× zoom') : 'Pinch or scroll to zoom · drag to pan') + '</span>' +
      (state.graph.zoom > 1 || state.graph.pan ? '<span class="link" data-action="graph-reset">Reset view</span>' : '') + '</div></div>';

    html += '<div class="section-label">' + icon('activity', 13) + 'Window statistics</div><div class="card">';
    s.probes.filter((p) => p.attached).forEach((p, idx, arr) => {
      html += '<div class="row between" style="padding:8px 0' + (idx < arr.length - 1 ? ';border-bottom:1px solid var(--hairline)' : '') + '">' +
        '<div class="row" style="gap:8px"><span class="jack-badge p' + p.jack + '">' + p.jack + '</span><span class="hi bold small">' + esc(probeName(p, cook)) + '</span></div>' +
        '<div class="row" style="gap:14px">' + statMini('High', fmtTemp(p.peakF, 0)) + statMini('Avg', fmtTemp(p.avgF, 0)) + statMini('Low', fmtTemp(p.lowF, 0)) + '</div></div>';
    });
    html += '</div>';
    html += '<div class="btn-row mt3"><button class="btn" data-action="open-mark">' + icon('bookmark') + 'Add mark</button>' +
      '<button class="btn ghost" data-action="export" data-scope="graph" aria-label="Share graph">' + icon('share') + 'Share</button></div>';
    return html;
  }
  function statMini(label, val) { return '<div class="center"><div class="tiny muted">' + label + '</div><div class="mono hi small">' + val + '</div></div>'; }

  function renderFullGraph() {
    const s = scenario(), cook = s.cook, d = graphDomain();
    const series = graphSeries();
    const targets = s.probes.filter((p) => p.attached && p.targetF).map((p) => ({ value: p.targetF, color: seriesColor(p.jack), label: fmtTemp(p.targetF, 0) }));
    lastChart = { series: series.map((sr) => ({ name: probeName(s.probes.find((p) => p.jack === sr.probe), cook), points: sr.points })), xMin: d.xMin, xMax: d.xMax, started: d.started };
    return '<div class="graph-full" id="graphFull"><div class="gf-head">' +
      '<div><div class="ab-title" style="font-size:17px">Graph</div><div class="ab-sub">' + (state.graph.zoom > 1 ? state.graph.zoom.toFixed(1) + '×' : 'full range') + '</div></div><div class="spacer"></div>' +
      '<div class="zoom-bar">' +
      '<button class="zb" data-action="graph-pan" data-dir="back" aria-label="Pan back">' + icon('arrowLeft') + '</button>' +
      '<button class="zb" data-action="graph-zoom" data-dir="out" aria-label="Zoom out">' + icon('zoomOut') + '</button>' +
      '<button class="zb" data-action="graph-zoom" data-dir="in" aria-label="Zoom in">' + icon('zoomIn') + '</button>' +
      '<button class="zb" data-action="graph-pan" data-dir="fwd" aria-label="Pan forward">' + icon('arrowRight') + '</button>' +
      '<button class="zb" data-action="graph-reset" aria-label="Reset">' + icon('refresh') + '</button>' +
      '<button class="zb" data-action="graph-fullscreen" aria-label="Exit fullscreen">' + icon('compress') + '</button></div></div>' +
      '<div class="gf-body"><div class="gf-chart"><div class="chart" id="chartHostFull">' +
      buildChart(series, { height: 420, xMin: d.xMin, xMax: d.xMax, targets: targets, now: d.now, isolated: state.isolatedProbe,
        bands: [{ min: cook.pitBand[0], max: cook.pitBand[1] }], xLabels: (v) => fmtClock(d.started + v * 60000) }) +
      '<div class="crosshair-tip" id="chartTipFull"></div></div>' +
      '<div class="legend mt3">' + s.probes.filter((p) => p.attached).map((p) =>
        '<button class="legend-item' + (state.isolatedProbe && state.isolatedProbe !== p.jack ? ' dim' : '') + '" data-action="isolate" data-jack="' + p.jack + '">' +
        '<span class="legend-swatch" style="' + legendSwatch(p.jack) + '"></span><span class="lg-name">' + esc(probeName(p, cook)) + '</span>' +
        '<span class="lg-val">' + fmtTemp(p.tempF) + '</span></button>').join('') + '</div></div></div></div>';
  }

  // [BIZ] Hue is never the only identity channel: each probe also owns a
  // stroke pattern (P1 solid, P2 dashed, P3 dotted, P4 dash-dot).
  function legendSwatch(jack) {
    const c = seriesColor(jack);
    if (jack === 1) return 'background:' + c;
    if (jack === 2) return 'background-image:repeating-linear-gradient(90deg,' + c + ' 0 4px,transparent 4px 7px)';
    if (jack === 3) return 'background-image:repeating-linear-gradient(90deg,' + c + ' 0 2px,transparent 2px 5px)';
    return 'background-image:repeating-linear-gradient(90deg,' + c + ' 0 5px,transparent 5px 6px,' + c + ' 6px 8px,transparent 8px 9px)';
  }

  function probeName(p, cook) {
    if (!p) return 'Probe';
    if (p.role === 'pit') return 'Grate · jack ' + p.jack;
    if (p.role === 'unused') return 'Jack ' + p.jack + ' · unused';
    const it = (cook.items || []).find((i) => i.jack === p.jack);
    const cat = it ? catalogById(it.id) : null;
    return cat ? cat.name : 'Probe ' + p.jack;
  }

  // ---- Settings ------------------------------------------------------------
  function viewSettings() {
    const s = scenario(), c = s.connection;
    const bt = c.bt || {}, wifi = c.wifi || {};
    const primaryIsBt = c.primary === 'bt';
    const wifiModeLabel = wifi.mode === 'ap' ? 'Bridge hotspot' : wifi.mode === 'sta' ? (wifi.ssid || 'Home Wi-Fi') : 'Off';

    let html = '<div class="card"><div class="card-head">' + icon('link') + '<div class="card-title">' + esc(c.deviceName) + '</div>' +
      '<span class="spacer"></span><span class="pulse-dot ' + (c.phase === 'offline' ? 'idle' : c.phase === 'connected' ? '' : 'warn') + '"></span></div>';

    html += '<div class="link-row' + (bt.connected ? '' : ' off') + '"><div class="lr-icon">' + icon('bluetooth') + '</div>' +
      '<div class="lr-meta"><div class="lr-name">Bluetooth' + (primaryIsBt && bt.connected ? ' <span class="mode-badge">Carrying data</span>' : (bt.warm ? ' <span class="tier-tag app">Warm</span>' : '')) + '</div>' +
      '<div class="lr-sub">' + (bt.connected ? 'Connected · ' + signalWord(bt.bars) + (bt.rssi ? ' · ' + bt.rssi + ' dBm' : '') + (bt.lastSyncS !== null ? ' · ' + ago(Date.now() - bt.lastSyncS * 1000) : '') : 'Not connected') + '</div></div>' +
      '<div class="lr-right">' + signalBars(bt.bars) + '</div></div>';

    html += '<div class="link-row' + (wifi.connected ? '' : ' off') + '"><div class="lr-icon">' + icon(wifi.mode === 'ap' ? 'wifi' : 'router') + '</div>' +
      '<div class="lr-meta"><div class="lr-name">Wi-Fi' + (c.primary === 'wifi' && wifi.connected ? ' <span class="mode-badge">Carrying data</span>' : '') + '</div>' +
      '<div class="lr-sub">' + (wifi.mode === 'off' ? 'Not set up' : wifi.connected ? wifiModeLabel + (wifi.ip ? ' · ' + wifi.ip : '') + ' · ' + signalWord(wifi.bars) : (c.phase === 'connecting' ? 'Connecting to ' + esc(wifi.ssid || '') + '…' : 'Not connected')) + '</div></div>' +
      '<div class="lr-right">' + signalBars(wifi.bars) + '</div></div>';

    html += '<div class="row between small mt3"><span class="muted">Battery</span><span class="hi">' + (c.batteryPct === null ? '—' : c.batteryPct + '%') + '</span></div>' +
      '<div class="row between small mt2"><span class="muted">Recording</span><span class="hi">' + (c.recording ? 'Yes — on the bridge' : 'No') + '</span></div>';

    html += '<div class="btn-row mt4"><button class="btn" data-action="resync">' + icon('refresh') + 'Re-sync</button>' +
      '<button class="btn ghost" data-action="open-modes">' + icon('sliders') + 'Change mode</button></div>' +
      '<button class="btn ghost mt2" data-action="disconnect">' + icon('unlink') + 'Disconnect</button></div>';

    html += '<div class="section-label">Set up Wi-Fi</div><div class="card">' +
      setRow('wifi', 'Join your home network', 'Keeps your phone on the internet; reach the bridge anywhere', icon('chevronRight'), 'provision-sta') +
      setRow('router', 'Use the bridge hotspot', 'No home network needed — join the bridge directly', icon('chevronRight'), 'provision-ap') +
      (wifi.mode === 'sta' && wifi.connected ? setRow('unlink', 'Forget network', esc(wifi.ssid || ''), '', 'forget-network') : '') + '</div>';

    html += '<div class="section-label">' + icon('history', 13) + 'Cooks</div><div class="card">' +
      setRow('history', 'History', 'Past cooks, notes, ratings and exports', icon('chevronRight'), 'open-history') + '</div>';

    html += '<div class="section-label">Preferences</div><div class="card">' +
      setRow('thermometer', 'Units', 'Temperatures in ' + (state.units === 'C' ? 'Celsius' : 'Fahrenheit'),
        '<div class="seg"><button data-action="set-units" data-units="F" class="' + (state.units === 'F' ? 'on' : '') + '">°F</button>' +
        '<button data-action="set-units" data-units="C" class="' + (state.units === 'C' ? 'on' : '') + '">°C</button></div>') +
      setRow('monitor', 'Appearance', themeLabel(),
        '<div class="seg"><button data-action="set-theme" data-theme="system" class="' + (state.themeMode === 'system' ? 'on' : '') + '">Auto</button>' +
        '<button data-action="set-theme" data-theme="light" class="' + (state.themeMode === 'light' ? 'on' : '') + '">Light</button>' +
        '<button data-action="set-theme" data-theme="dark" class="' + (state.themeMode === 'dark' ? 'on' : '') + '">Dark</button></div>') +
      setRow('sun', 'High-contrast profile', state.displayProfile === 'daylight' ? 'On — for bright sun' : 'Off', toggle('__profile', state.displayProfile === 'daylight')) +
      setRow('sliders', 'Density', state.density === 'compact' ? 'Compact — more at a glance' : 'Comfortable', toggle('__density', state.density === 'comfortable')) +
      setRow('eye', 'Reduce motion', state.reducedMotion ? 'Animations minimised' : 'Full motion', toggle('__motion', state.reducedMotion)) +
      setRow('bell', 'Alarms & monitoring', state.settings.monitoring ? 'Watching in the background' : 'Off', icon('chevronRight'), 'open-alerts') +
      setRow('key', 'Prefer my own alarms', 'Manual alarms win over device rules', toggle('preferManualAlarm')) +
      setRow('moon', 'Quiet hours', 'Silences warning & info 10pm–6am. Critical always sounds', toggle('quietHours')) +
      setRow('link', 'Keep Bluetooth warm', 'Faster failover while on Wi-Fi', toggle('holdBle')) +
      setRow('calendar', 'Wrap / spritz reminders', 'Use the expected timeline for nudges', toggle('autoWrapReminder')) + '</div>';

    html += '<div class="section-label">Bridge</div><div class="card">' +
      setRow('cpu', 'Firmware', esc(M.DEVICE.version) + ' · ' + (M.DEVICE.available ? 'update available' : 'up to date'), icon('chevronRight'), 'open-firmware') +
      setRow('upload', 'Update firmware', M.DEVICE.available ? 'Install ' + esc(M.DEVICE.available) + ' over Wi-Fi' : 'Over Wi-Fi only', icon('chevronRight'), 'open-firmware-update') +
      setRow('info', 'About & diagnostics', esc(M.DEVICE.id) + ' · signal, storage, logs', icon('chevronRight'), 'open-diagnostics') + '</div>';

    html += '<div class="section-label">' + icon('sliders', 13) + 'Device actions</div><div class="card">' +
      setRow('refresh', 'Restart the bridge', 'Recovers a hung bridge · recording pauses ~30 s', icon('chevronRight'), 'ask-restart') +
      setRow('unlink', 'Forget this bridge', 'Remove pairing and Wi-Fi from this app', icon('chevronRight'), 'ask-forget') +
      setRow('alertTriangle', 'Factory reset', 'Erase all settings, Wi-Fi and recorded sessions', icon('chevronRight'), 'ask-factory', 'danger') + '</div>';
    html += '<div class="card subtle mt3"><div class="tiny muted">A bridge with no clock stores no timestamp — never a made-up one. A detached probe is absent, never 0.</div></div>';
    return html;
  }
  function themeLabel() {
    if (state.themeMode === 'system') return 'Follows your phone (' + resolvedTheme() + ')';
    return state.themeMode === 'light' ? 'Light' : 'Dark';
  }
  function signalWord(n) {
    if (n === null || n === undefined) return 'no signal';
    return ['none', 'weak', 'fair', 'good', 'strong'][n] || 'good';
  }
  function signalBars(n) {
    if (n === null || n === undefined) return '<span class="muted">—</span>';
    let s = '';
    for (let i = 1; i <= 4; i++) s += '<span style="display:inline-block;width:4px;height:' + (4 + i * 3) + 'px;margin-left:2px;border-radius:1px;background:' + (i <= n ? 'var(--text-hi)' : 'var(--hairline-strong)') + '"></span>';
    return '<span style="display:inline-flex;align-items:flex-end">' + s + '</span>';
  }
  function setRow(ic, name, sub, right, action, cls) {
    return '<div class="set-row' + (cls ? ' ' + cls : '') + '"' + (action ? ' data-action="' + action + '"' : '') + '><div class="sr-icon">' + icon(ic) + '</div>' +
      '<div class="sr-meta"><div class="sr-name">' + name + '</div><div class="sr-sub">' + sub + '</div></div>' +
      '<div class="sr-right">' + right + '</div></div>';
  }
  function toggle(key, on) {
    const v = state.settings[key] !== undefined ? state.settings[key] : !!on;
    return '<button class="toggle' + (v ? ' on' : '') + '" data-action="toggle-setting" data-key="' + key + '" aria-label="Toggle ' + key + '"></button>';
  }
  function emptyState(title, copy, action, actionLabel, ic) {
    return '<div class="state"><div class="st-art">' + icon(ic || 'calendar', 34) + '</div>' +
      '<div class="st-title">' + esc(title) + '</div><div class="st-copy">' + esc(copy) + '</div>' +
      (action ? '<button class="btn primary" style="width:auto" data-action="' + action + '">' + esc(actionLabel) + '</button>' : '') + '</div>';
  }

  // ---- History (was Cooks) -------------------------------------------------
  function viewHistory() {
    let html = '<button class="btn primary" data-action="open-setup">' + icon('plus') + 'Start a new cook</button>' +
      '<div class="cap-notice mt3">' + icon('info') +
      '<div class="cn-text">Every cook is an annotation over one continuous recording. The bridge records even when this app is closed — <b>you never lose the gap.</b></div></div>';
    const groups = [{ label: 'This week', test: (h) => (Date.now() - h.startedAtMs) < 7 * 24 * 3600 * 1000 }, { label: 'Earlier', test: () => true }];
    const used = {};
    groups.forEach((g) => {
      const rows = M.HISTORY.filter((h) => !used[h.id] && g.test(h));
      rows.forEach((h) => { used[h.id] = true; });
      if (!rows.length) return;
      html += '<div class="section-label">' + g.label + '<span class="spacer"></span><span class="tiny muted">' + rows.length + '</span></div><div class="stack">' +
        rows.map((h) => '<div class="cook-card" data-action="select-cook" data-id="' + h.id + '">' + foodAvatar(h.glyph) +
          '<div class="cc-meta"><div class="cc-name">' + esc(h.name) + (h.favourite ? ' <span class="fav">★</span>' : '') + '</div>' +
          '<div class="cc-sub"><span>' + fmtDay(h.startedAtMs) + '</span><span>' + fmtDuration(h.durationMin * 60000) + '</span><span>' + h.marks + ' marks</span>' + (h.photos ? '<span>' + h.photos + ' photos</span>' : '') + '</div></div>' +
          '<div class="cc-right"><div class="cc-peak">' + fmtTemp(h.peakF, 0) + '</div><div class="cc-peak-label">peak</div></div>' + icon('chevronRight') + '</div>').join('') + '</div>';
    });
    return html;
  }

  function viewCookDetail() {
    const h = M.HISTORY.find((x) => x.id === state.selectedCookId) || M.HISTORY[0];
    let html = '<div class="card"><div class="cook-head">' + foodAvatar(h.glyph, 'lg') +
      '<div class="ch-meta"><div class="ch-name">' + esc(h.name) + '</div>' +
      '<div class="ch-line">' + fmtDay(h.startedAtMs) + ' · ' + fmtClock(h.startedAtMs) + ' · ' + fmtDuration(h.durationMin * 60000) + (styleName(h.styleId) ? ' · ' + esc(styleName(h.styleId)) : '') + '</div>' +
      '<div class="stars mt1">' + '★'.repeat(h.rating) + '☆'.repeat(5 - h.rating) + '</div></div>' +
      iconBtn('bookmark', 'toggle-fav', { data: ' data-id="' + h.id + '"', label: 'Favourite' }) + '</div></div>';

    const diff = h.durationMin - (h.plannedMin || h.durationMin);
    html += '<div class="section-label">Recap</div><div class="card">' +
      recapRow('Cook time', fmtDuration(h.durationMin * 60000), h.plannedMin ? (diff === 0 ? 'On plan' : (diff > 0 ? '+' + diff + ' min vs plan' : diff + ' min vs plan')) : '') +
      recapRow('Peak temp', fmtTemp(h.peakF, 0), h.targetF ? (h.peakF >= h.targetF ? 'Reached target ' + fmtTemp(h.targetF, 0) : 'Target ' + fmtTemp(h.targetF, 0)) : '') +
      (h.stalledMin ? recapRow('Longest stall', h.stalledMin + ' min', 'Evaporative plateau') : '') +
      (h.wrapAtF ? recapRow('Wrapped at', fmtTemp(h.wrapAtF, 0), '') : '') + '</div>';

    html += '<div class="section-label">Result</div><div class="stat-grid">' + stat('Peak', fmtTemp(h.peakF, 0)) + stat('Target', fmtTemp(h.targetF, 0)) + stat('Marks', String(h.marks)) + '</div>';
    html += '<div class="section-label">Chart</div><div class="chart-wrap"><div class="chart">' + buildChart(
      [{ probe: 1, color: seriesColor(1), width: 2, points: histPoints(h) }], {
      yMin: Math.floor((h.peakF - 180) / 25) * 25, yMax: Math.ceil((h.peakF + 20) / 25) * 25,
      targets: [{ value: h.targetF, color: 'var(--p1)', label: fmtTemp(h.targetF, 0) }], xLabels: (v) => Math.round(v) + 'm',
    }) + '</div></div>';
    html += '<div class="section-label">Notes</div><div class="card"><div class="body small">' + esc(h.notes || 'No notes for this cook.') + '</div></div>';
    html += '<div class="section-label">Marks</div><div class="rail">' + [['Cook started', 0], ['Wrapped', 0.5], ['Probe-tender', 0.85], ['Pulled', 1]].map((m) =>
      '<div class="rail-item"><span class="rail-dot done"></span><div class="rail-time">' + fmtClock(h.startedAtMs + m[1] * h.durationMin * 60000) + '</div><div class="rail-title">' + m[0] + '</div></div>').join('') + '</div>';
    html += '<div class="btn-row mt4"><button class="btn" data-action="repeat-cook" data-id="' + h.id + '">' + icon('refresh') + 'Cook again</button>' +
      '<button class="btn ghost" data-action="export" data-scope="cook" aria-label="Share cook">' + icon('share') + 'Share</button></div>';
    html += '<button class="btn danger mt3" data-action="delete-cook">' + icon('trash') + 'Delete cook</button>';
    return html;
  }
  function recapRow(k, v, note) {
    return '<div class="row between small" style="padding:5px 0"><span class="muted">' + k + '</span><span class="hi bold">' + v + (note ? ' <span class="tiny muted" style="font-weight:500">· ' + esc(note) + '</span>' : '') + '</span></div>';
  }
  function histPoints(h) {
    const n = 60, pts = [], r = rng(h.id.length * 31 + 7);
    for (let i = 0; i <= n; i++) {
      const p = i / n;
      let v = 60 + (h.peakF - 60) * Math.pow(p, 0.6);
      if (p > 0.45 && p < 0.7) v = 60 + (h.peakF - 60) * Math.pow(0.45, 0.6) + (p - 0.45) * 20;
      v += (r() - 0.5) * 3;
      pts.push({ x: p * h.durationMin, y: Math.max(40, Math.min(h.peakF, v)) });
    }
    pts[n].y = h.peakF;
    return pts;
  }
  function stat(label, val) { return '<div class="stat"><div class="st-label">' + label + '</div><div class="st-val">' + val + '</div></div>'; }

  // =================================================== §7 RENDER: OVERLAYS ====
  function renderOverlays() {
    const host = $('#overlays');
    const o = state.overlay;
    let html = '';
    if (o) {
      const map = {
        onboarding: overlayOnboarding, setup: overlaySetup, connect: overlayConnect,
        modes: overlayModes, modesRef: overlayModesRef, provisionSta: overlayProvisionSta,
        provisionAp: overlayProvisionAp, alarms: overlayAlarms, alarmDetail: overlayAlarmDetail,
        mark: overlayMark, probe: overlayProbe, adopt: overlayAdopt, editStart: overlayEditStart,
        confirm: overlayConfirm, customFood: overlayCustomFood,
        firmware: overlayFirmware, firmwareUpdate: overlayFirmwareUpdate, diagnostics: overlayDiagnostics, verb: overlayVerb,
      };
      html = (map[o.name] || (() => ''))(o.props || {});
    }
    if (state.fullGraph) html += renderFullGraph();
    host.innerHTML = html;
  }
  function openOverlay(name, props) { state.overlay = { name: name, props: props || {} }; renderOverlays(); }
  function closeOverlay() { state.overlay = null; state.confirm = null; renderOverlays(); }
  function scrim(inner, center) { return '<div class="scrim open' + (center ? ' center' : '') + '" data-action="scrim-click">' + inner + '</div>'; }
  function sheetWrap(title, sub, body) {
    return scrim('<div class="sheet"><div class="sheet-grab"></div>' +
      '<div class="sheet-head"><div style="flex:1"><div class="sh-title">' + title + '</div><div class="sh-sub">' + sub + '</div></div>' +
      '<button class="icon-btn" data-action="close-overlay" aria-label="Close">' + icon('x') + '</button></div>' +
      '<div class="sheet-body">' + body + '</div></div>');
  }

  // ---- Confirm dialog (long-item warning, delete, etc.) --------------------
  function openConfirm(opts) { state.confirm = opts; state.overlay = { name: 'confirm', props: {} }; renderOverlays(); }
  function overlayConfirm() {
    const cf = state.confirm;
    if (!cf) return '';
    return scrim('<div class="modal-card"><div class="sh-title" style="font-family:var(--font-display);font-weight:700;font-size:19px;color:var(--text-hi);margin-bottom:8px">' + esc(cf.title) + '</div>' +
      '<div class="body small">' + cf.body + '</div>' +
      '<div class="btn-row mt4"><button class="btn ' + (cf.danger ? 'danger' : 'primary') + '" data-action="confirm-yes">' + esc(cf.confirmLabel || 'Confirm') + '</button>' +
      '<button class="btn ghost" data-action="confirm-no">Cancel</button></div></div>', true);
  }

  // ---- Onboarding wizard ---------------------------------------------------
  // [BIZ] The passkey is shown ONLY on the device OLED. The app cannot render a
  // real code, so it coaches the user BEFORE Android's own (wrong) dialog.
  function overlayOnboarding() {
    const steps = ['welcome', 'preflight', 'scan', 'passkey', 'sync', 'network', 'name', 'done'];
    const i = state.onboardStep;
    const rail = '<div class="step-rail">' + steps.map((st, idx) =>
      '<span class="step-dot' + (idx === i ? ' on' : idx < i ? ' done' : '') + '"></span>').join('') + '</div>';
    let body = '';
    if (state.onboardTroubleshoot) {
      body = '<div class="card-title center">Let’s find it again</div>' +
        '<div class="body small center mt2 mb3">A few things fix almost every pairing problem.</div>' +
        permRow('cpu', 'Is the bridge powered?', 'Its screen should show a heartbeat', true) +
        permRow('bluetooth', 'Bluetooth on?', 'And the phone is within a few metres', true) +
        permRow('refresh', 'Restart the bridge', 'Hold the button until the screen blinks', false) +
        '<button class="btn mt4" data-action="onboard-prev">' + icon('chevronLeft') + 'Back</button>';
      return scrim('<div class="sheet"><div class="sheet-grab"></div><div class="sheet-head"><div style="flex:1">' + rail + '</div></div>' +
        '<div class="sheet-body">' + body + '</div><div class="sheet-foot"><div class="btn-row">' +
        '<button class="btn ghost" data-action="close-overlay">Close</button>' +
        '<button class="btn primary" data-action="onboard-next">Try again</button></div></div></div>');
    }
    if (i === 0) {
      body = '<div class="bridge-art scanning">' + icon('cpu', 62) + '</div>' +
        '<div class="center"><div class="card-title" style="font-size:22px">Meet your SmokeBridge</div>' +
        '<div class="body small mt2">This little box listens to your Smoke X4 and records every reading — with or without your phone. Let’s connect it.</div></div>';
    } else if (i === 1) {
      body = '<div class="st-title center">A couple of permissions</div>' +
        '<div class="body small center mt2 mb3">Bluetooth to reach the bridge, and notifications so an alarm can find you at 3 a.m.</div>' +
        permRow('bluetooth', 'Bluetooth', 'To find and pair with the bridge', true) +
        permRow('bell', 'Notifications', 'For temperature alarms', true) +
        permRow('mapPin', 'Location', 'Only needed on older Android', false);
    } else if (i === 2) {
      body = '<div class="center"><div class="scan-ring">' + icon('bluetooth', 30) + '</div>' +
        '<div class="card-title mt4">Looking for your bridge</div><div class="body small mt2">Hold your phone near the bridge. Its screen shows a 6-digit code when it is ready.</div></div>' +
        '<div class="card mt4" data-action="onboard-next" style="cursor:pointer"><div class="row">' + icon('cpu', 20) +
        '<div style="flex:1"><div class="hi bold small">SmokeBridge-A4F2</div><div class="tiny muted">Strong signal · ready to pair</div></div>' + icon('chevronRight') + '</div></div>' +
        '<div class="center mt3"><span class="link" data-action="onboard-troubleshoot">Can’t find it?</span></div>';
    } else if (i === 3) {
      body = '<div class="card-title center">Enter the code from the bridge</div>' +
        '<div class="body small center mt2 mb3">The bridge’s own screen shows six digits. Type them here — not the “0000 or 1234” your phone suggests.</div>' +
        '<div class="mono-well">••••••</div><div class="tiny muted center mt2">Shown only on the device. The app never stores it.</div>';
    } else if (i === 4) {
      body = '<div class="center"><div class="scan-ring">' + icon('wifi', 30) + '</div>' +
        '<div class="card-title mt4">Listening for your Smoke X4</div>' +
        '<div class="body small mt2">Put the Smoke X4 into sync mode. The bridge pairs with it silently — it never transmits except for one tiny acknowledgement.</div></div>' +
        '<div class="cap-notice mt4">' + icon('info') + '<div class="cn-text">This keeps the bridge a pure listener. It cannot interfere with your base station.</div></div>';
    } else if (i === 5) {
      body = '<div class="card-title">How should we stay in touch?</div><div class="body small mt2 mb3">You can change this any time from Settings. Switching happens over Bluetooth.</div>' +
        M.MODES.map((m) => modeCardCompact(m, m.id === 'ble')).join('');
    } else if (i === 6) {
      body = '<div class="card-title">Almost there</div><div class="body small mt2 mb3">Name this bridge and pick your units.</div>' +
        '<div class="card inset"><div class="tiny muted mb2">Bridge name</div><div class="hi bold">Backyard Bridge</div></div>' +
        '<div class="card inset mt3"><div class="tiny muted mb2">Units</div><div class="seg-chips"><button class="chip on">° Fahrenheit</button><button class="chip">° Celsius</button></div></div>';
    } else {
      body = '<div class="bridge-art idle">' + icon('check', 56) + '</div>' +
        '<div class="center"><div class="card-title" style="font-size:22px">You’re all set</div>' +
        '<div class="body small mt2">Your bridge is paired, listening, and recording. Start a cook or just watch the numbers.</div></div>';
    }
    const isLast = i === steps.length - 1;
    const label = isLast ? 'Go to Live' : i === 2 ? 'Pair this bridge' : i === 3 ? 'Confirm' : 'Continue';
    return scrim('<div class="sheet"><div class="sheet-grab"></div><div class="sheet-head"><div style="flex:1">' + rail + '</div></div>' +
      '<div class="sheet-body">' + body + '</div><div class="sheet-foot"><div class="btn-row">' +
      (i > 0 ? '<button class="btn ghost" data-action="onboard-prev">Back</button>' : '<button class="btn ghost" data-action="close-overlay">Skip</button>') +
      '<button class="btn primary" data-action="' + (isLast ? 'finish-onboard' : 'onboard-next') + '">' + label + '</button>' +
      '</div></div></div>');
  }
  function permRow(ic, name, sub, granted) {
    return '<div class="set-row"><div class="sr-icon">' + icon(ic) + '</div><div class="sr-meta"><div class="sr-name">' + name + '</div><div class="sr-sub">' + sub + '</div></div>' +
      '<div class="sr-right">' + (granted ? '<span style="color:var(--positive)">' + icon('check') + '</span>' : '<button class="btn sm">Allow</button>') + '</div></div>';
  }

  // Compact mode row: name + one-word state + ? info. No paragraphs.
  function modeCardCompact(m, active) {
    const stateWord = active ? 'Active' : (m.requiresWifiCreds ? 'Needs password' : 'Available');
    return '<div class="mode-card' + (active ? ' on' : '') + '" data-action="set-mode" data-mode="' + m.id + '">' +
      '<div class="mode-icon">' + icon(m.icon) + '</div><div class="mode-body">' +
      '<div class="row between"><div class="mode-name">' + esc(m.name) + '</div>' + (active ? '<span class="mode-badge">Active</span>' : '') + '</div>' +
      '<div class="mode-tag">' + esc(m.tagline) + ' · ' + stateWord + '</div></div>' +
      '<button class="mode-info" data-action="open-modes-ref" data-mode="' + m.id + '" aria-label="About ' + esc(m.name) + '" title="About this mode">' + icon('question') + '</button></div>';
  }

  // ---- Setup sheet (catalog + styles + custom) -----------------------------
  function overlaySetup() {
    const mode = state.setupMode, cat = state.catalog.category;
    const sel = state.catalog.selectedId ? catalogById(state.catalog.selectedId) : null;
    const don = sel ? donenessFor(sel, state.catalog.doneness) : null;
    const pull = sel ? pullTempFor(sel, don) : null;
    const cook = scenario().cook, assigned = {};
    (cook.items || []).forEach((it) => { assigned[it.jack] = it.id; });
    const styles = sel ? stylesFor(sel.id) : null;
    const style = styles && state.catalog.styleId ? styles.find((s) => s.id === state.catalog.styleId) : null;

    let html = '<div class="seg-chips mb3">' +
      '<button class="chip' + (mode === 'new' ? ' on' : '') + '" data-action="setup-mode" data-mode="new">Start a cook</button>' +
      '<button class="chip' + (mode === 'existing' ? ' on' : '') + '" data-action="setup-mode" data-mode="existing">Already started</button>' +
      '<button class="chip' + (mode === 'watch' ? ' on' : '') + '" data-action="setup-mode" data-mode="watch">Just watch</button></div>';

    if (mode === 'watch') {
      html += '<div class="cap-notice">' + icon('info') + '<div class="cn-text">No targets, no timers, no alarms. You will see live numbers and the graph. You can turn a cook on later without losing anything.</div></div>' +
        '<div class="btn primary mt4" data-action="start-watch">' + icon('eye') + 'Watch live temperatures</div>';
      return setupScrim(html, 'Cook setup');
    }
    if (mode === 'existing') {
      const ps = scenario().pendingSession;
      html += '<div class="cap-notice">' + icon('download') + '<div class="cn-text">The bridge has been recording without you. Pick what is on the grill and when it went on — we will <b>pull the readings already collected</b> and build the cook around them.</div></div>';
      if (ps) {
        html += '<div class="card mt3"><div class="row between small"><span class="muted">Session found</span><span class="hi mono">' + ps.sessionId + '</span></div>' +
          '<div class="row between small mt2"><span class="muted">Started</span><span class="hi">' + fmtClock(ps.startedAtMs) + ' (' + fmtDuration(Date.now() - ps.startedAtMs) + ' ago)</span></div>' +
          '<div class="row between small mt2"><span class="muted">Samples</span><span class="hi">' + ps.samples + '</span></div></div>';
      }
      html += '<div class="tiny muted mt4 mb2">WHEN DID IT GO ON?</div><div class="seg-chips">' +
        '<button class="chip on">' + (ps ? 'Bridge session start' : 'Just now') + '</button><button class="chip">I will set a time</button></div>';
    }

    const q = (state.catalog.query || '').trim().toLowerCase();
    const list = q
      ? allCatalog().filter((i) => i.name.toLowerCase().indexOf(q) >= 0 || i.category.toLowerCase().indexOf(q) >= 0 || (i.blurb || '').toLowerCase().indexOf(q) >= 0)
      : catalogInCat(cat);
    html += '<div class="row between mt4 mb2"><span class="tiny muted">' + (mode === 'existing' ? 'WHAT IS ON THE GRILL?' : 'WHAT ARE YOU COOKING?') + '</span>' +
      '<span class="link" data-action="open-custom">' + icon('plus', 12) + 'Custom food</span></div>' +
      '<div class="catalog-search">' + icon('search', 15) + '<input id="catalogSearch" type="search" placeholder="Search all foods — brisket, kalua, jerk, elote…" value="' + esc(state.catalog.query || '') + '" />' +
      (q ? '<button class="cs-clear" data-action="catalog-clear" aria-label="Clear search">' + icon('x', 14) + '</button>' : '') + '</div>' +
      '<div class="filter-row mb2">' + M.CATEGORIES.map((c) =>
        '<button class="chip' + (c === cat && !q ? ' on' : '') + '" data-action="catalog-cat" data-cat="' + esc(c) + '">' + esc(c) + '</button>').join('') + '</div>' +
      '<div class="catalog-count tiny muted mb2">' + list.length + (q ? ' result' + (list.length === 1 ? '' : 's') + ' for “' + esc(state.catalog.query) + '”' : ' foods in ' + esc(cat)) + '</div>' +
      (list.length ? '<div class="catalog-grid">' + list.map((item) => {
        const d = donenessFor(item, item.defaultDoneness);
        const variants = stylesFor(item.id);
        return '<button class="catalog-item' + (state.catalog.selectedId === item.id ? ' selected' : '') + (item.custom ? ' custom' : '') + '" data-action="catalog-pick" data-id="' + item.id + '">' +
          foodAvatar(item.glyph) + '<div class="row between" style="width:100%"><div class="ci-name">' + esc(item.name) + '</div>' + (item.custom ? '<span class="ci-badge">Custom</span>' : '') + '</div>' +
          '<div class="ci-meta">' + esc(item.blurb) + '</div>' +
          '<div class="ci-temp">' + icon('target', 11) + ' ' + fmtTemp(d.targetF, 0) + ' · pit ' + item.pitBand[0] + '–' + item.pitBand[1] + '°' +
          (variants ? ' · <span class="ci-var">' + variants.length + ' styles</span>' : '') + '</div></button>';
      }).join('') + '</div>' : '<div class="state" style="padding:18px 0"><div class="st-copy">No foods match that search.</div></div>');

    if (sel) {
      if (styles) {
        html += '<div class="row between mt4 mb2"><span class="tiny muted">PREPARATION STYLE</span><span class="tiny muted">' + styles.length + ' ways to cook ' + esc(sel.name) + '</span></div>' +
          '<div class="tiny muted mb2" style="margin-top:-4px">Same cut, different dish. Pick the one you are making — it sets the pit band, wrap, target, rest and timeline.</div>' +
          '<div class="style-grid">' + styles.map((st) =>
          '<div class="style-card' + (style && style.id === st.id ? ' on' : '') + '" data-action="style-pick" data-id="' + st.id + '">' +
          '<div class="sc-icon">' + icon('utensils') + '</div><div class="sc-meta"><div class="sc-name">' + esc(st.name) + (st.region ? ' <span class="sc-region">' + esc(st.region) + '</span>' : '') + '</div>' +
          '<div class="sc-tag">' + esc(st.tagline) + '</div><div class="sc-note">' + esc(st.note) + '</div></div></div>').join('') + '</div>';
      }
      if (sel.doneness.length > 1) {
        html += '<div class="tiny muted mt4 mb2">DONENESS</div><div class="seg-chips">' + sel.doneness.map((d) =>
          '<button class="chip' + (donenessFor(sel, state.catalog.doneness).id === d.id ? ' on' : '') + '" data-action="doneness-pick" data-id="' + d.id + '">' + esc(d.label) + ' · ' + fmtTemp(d.targetF, 0) + '</button>').join('') + '</div>';
      }
      const carry = carryoverFor(sel), tl = timelineFor(sel.id);
      const targetF = style ? style.targetF : don.targetF;
      html += '<div class="card subtle mt3"><div class="row between small"><span class="muted">Target (after rest)</span><span class="hi bold">' + fmtTemp(targetF, 0) + '</span></div>' +
        (carry > 0 ? '<div class="row between small mt2"><span class="muted">Pull early by carryover</span><span class="hi">' + fmtTemp(pull, 0) + ' (−' + carry + '°)</span></div>' : '') +
        '<div class="row between small mt2"><span class="muted">Expected rest</span><span class="hi">' + (style ? style.restMin : restMinutesFor(sel)) + ' min</span></div>' +
        '<div class="row between small mt2"><span class="muted">Expected cook</span><span class="hi">' + (tl ? tl.totalMin[0] + '–' + tl.totalMin[1] + ' min' : '—') + '</span></div></div>';
      html += '<div class="tiny muted mt4 mb2">WHICH PROBE?</div><div class="seg-chips">';
      [1, 2, 3, 4].forEach((j) => {
        const busy = assigned[j] && assigned[j] !== sel.id;
        html += '<button class="chip' + (state.catalog.jack === j ? ' on' : '') + (busy ? ' disabled' : '') + '" data-action="catalog-jack" data-jack="' + j + '">' +
          'Jack ' + j + (j === 4 ? ' · grate' : '') + (busy ? ' (in use)' : '') + '</button>';
      });
      html += '</div><div class="cap-notice mt3">' + icon('info') + '<div class="cn-text">Jack 4 is the grate by default. Tap any jack to reassign it.</div></div>';
      html += '<div class="set-row mt2"><div class="sr-icon">' + icon('wrap') + '</div><div class="sr-meta"><div class="sr-name">Wrap & spritz reminders</div><div class="sr-sub">From the expected timeline for ' + esc(sel.name) + '</div></div><div class="sr-right">' + toggle('autoWrapReminder') + '</div></div>';
    }
    const canStart = mode === 'watch' ? true : !!sel;
    html += '<div class="btn primary mt4' + (canStart ? '' : ' disabled') + '" data-action="' + (mode === 'existing' ? 'start-existing' : 'start-cook') + '">' +
      (mode === 'existing' ? icon('download') + 'Start & pull history' : icon('play') + 'Start cook') + '</div>';
    if (!canStart) html += '<div class="tiny muted center mt2">Pick a food above to continue</div>';
    return setupScrim(html, 'New cook');
  }
  function setupScrim(inner, title) {
    const sub = state.setupMode === 'existing' ? 'Build a cook over data already collected'
      : state.setupMode === 'watch' ? 'Live numbers, no plan' : 'Set up before, during, or after you light the fire';
    return scrim('<div class="sheet"><div class="sheet-grab"></div>' +
      '<div class="sheet-head"><div style="flex:1"><div class="sh-title">' + title + '</div><div class="sh-sub">' + sub + '</div></div>' +
      '<button class="icon-btn" data-action="close-overlay" aria-label="Close">' + icon('x') + '</button></div>' +
      '<div class="sheet-body">' + inner + '</div></div>');
  }

  // ---- Custom food form ----------------------------------------------------
  function overlayCustomFood() {
    const f = state.customForm || (state.customForm = {
      name: '', category: 'Beef', glyph: 'beef', hazard: 'wholeMuscleRedMeat', thickness: 'medium',
      pitLo: 225, pitHi: 275, targetF: 145, totalLo: 60, totalHi: 120, restMin: 10, wrapTemp: 0, spritz: 0,
    });
    const glyphs = ['beef', 'steak', 'pork', 'ribs', 'poultry', 'wholeBird', 'fish', 'shellfish', 'game', 'ground', 'egg', 'veg', 'potato', 'cheese', 'bread', 'fruit', 'side'];
    const html = '<div class="cap-notice mb3">' + icon('info') + '<div class="cn-text">Custom foods live alongside the built-in catalog. Give it a target and an expected timeline and the app will plan around it.</div></div>' +
      '<div class="field"><div class="f-label">Name</div><input id="cfName" placeholder="e.g. Smoked Lamb Ribs" value="' + esc(f.name) + '" /></div>' +
      '<div class="field-row"><div class="field"><div class="f-label">Category</div><select id="cfCat">' + M.CATEGORIES.map((c) => '<option' + (c === f.category ? ' selected' : '') + '>' + c + '</option>').join('') + '</select></div>' +
      '<div class="field"><div class="f-label">Icon</div><select id="cfGlyph">' + glyphs.map((g) => '<option' + (g === f.glyph ? ' selected' : '') + '>' + g + '</option>').join('') + '</select></div></div>' +
      '<div class="field-row"><div class="field"><div class="f-label">Hazard class</div><select id="cfHazard">' +
      [['wholeMuscleRedMeat', 'Whole muscle (red meat)'], ['pork', 'Pork'], ['poultry', 'Poultry'], ['ground', 'Ground meat'], ['fish', 'Fish'], ['egg', 'Egg'], ['unstated', 'None / veg']].map((h) => '<option value="' + h[0] + '"' + (h[0] === f.hazard ? ' selected' : '') + '>' + h[1] + '</option>').join('') + '</select></div>' +
      '<div class="field"><div class="f-label">Thickness</div><select id="cfThick">' +
      [['thin', 'Thin'], ['medium', 'Medium'], ['thick', 'Thick']].map((t) => '<option value="' + t[0] + '"' + (t[0] === f.thickness ? ' selected' : '') + '>' + t[1] + '</option>').join('') + '</select></div></div>' +
      '<div class="field-row"><div class="field"><div class="f-label">Pit band low (°F)</div><input id="cfPitLo" type="number" value="' + f.pitLo + '" /></div>' +
      '<div class="field"><div class="f-label">Pit band high (°F)</div><input id="cfPitHi" type="number" value="' + f.pitHi + '" /></div></div>' +
      '<div class="field-row"><div class="field"><div class="f-label">Target final (°F)</div><input id="cfTarget" type="number" value="' + f.targetF + '" /></div>' +
      '<div class="field"><div class="f-label">Rest (min)</div><input id="cfRest" type="number" value="' + f.restMin + '" /></div></div>' +
      '<div class="field-row"><div class="field"><div class="f-label">Cook time low (min)</div><input id="cfTotalLo" type="number" value="' + f.totalLo + '" /></div>' +
      '<div class="field"><div class="f-label">Cook time high (min)</div><input id="cfTotalHi" type="number" value="' + f.totalHi + '" /></div></div>' +
      '<div class="field-row"><div class="field"><div class="f-label">Wrap at (°F, 0 = never)</div><input id="cfWrap" type="number" value="' + f.wrapTemp + '" /></div>' +
      '<div class="field"><div class="f-label">Spritz every (min, 0 = never)</div><input id="cfSpritz" type="number" value="' + f.spritz + '" /></div></div>' +
      '<div class="btn-row mt4"><button class="btn primary" data-action="custom-save">' + icon('check') + 'Add to catalog</button>' +
      '<button class="btn ghost" data-action="close-overlay">Cancel</button></div>';
    return sheetWrap('Custom food', 'Add your own cut to the catalog', html);
  }

  // ---- Connect sheet (dual-link + compact modes) ---------------------------
  function overlayConnect() {
    const s = scenario(), c = s.connection;
    const bt = c.bt || {}, wifi = c.wifi || {};
    const primaryIsBt = c.primary === 'bt';
    let body = '<div class="card"><div class="card-head">' + icon(c.phase === 'offline' ? 'unlink' : 'link') + '<div class="card-title">' + esc(c.deviceName) + '</div>' +
      '<span class="spacer"></span><span class="pulse-dot ' + (c.phase === 'offline' ? 'idle' : c.phase === 'connected' ? '' : 'warn') + '"></span></div>';

    body += '<div class="link-row' + (bt.connected ? '' : ' off') + '"><div class="lr-icon">' + icon('bluetooth') + '</div>' +
      '<div class="lr-meta"><div class="lr-name">Bluetooth' + (primaryIsBt && bt.connected ? ' <span class="mode-badge">Data</span>' : '') + '</div>' +
      '<div class="lr-sub">' + (bt.connected ? signalWord(bt.bars) + ' · ' + (bt.lastSyncS !== null ? ago(Date.now() - bt.lastSyncS * 1000) : '') : 'Not connected') + '</div></div>' +
      '<div class="lr-right">' + signalBars(bt.bars) + '</div></div>';
    body += '<div class="link-row' + (wifi.connected ? '' : ' off') + '"><div class="lr-icon">' + icon(wifi.mode === 'ap' ? 'wifi' : 'router') + '</div>' +
      '<div class="lr-meta"><div class="lr-name">Wi-Fi' + (c.primary === 'wifi' && wifi.connected ? ' <span class="mode-badge">Data</span>' : '') + '</div>' +
      '<div class="lr-sub">' + (wifi.mode === 'off' ? 'Not set up' : wifi.connected ? (wifi.mode === 'ap' ? 'Bridge hotspot' : esc(wifi.ssid || '')) + ' · ' + signalWord(wifi.bars) : 'Not connected') + '</div></div>' +
      '<div class="lr-right">' + signalBars(wifi.bars) + '</div></div>';

    if (c.phase === 'error' || c.phase === 'rollback') {
      const msg = c.error === 'wrong_password' ? 'That Wi-Fi password was rejected. The bridge kept Bluetooth so nothing is lost.'
        : c.error === 'router_unreachable' ? 'The bridge could not reach the router. Check the network name and that the router is on.'
        : s.notice || 'The last change did not stick. The bridge kept its previous link.';
      body += '<div class="cap-notice ' + (c.phase === 'rollback' ? 'warn' : 'crit') + ' mt3">' + icon('alertTriangle') + '<div class="cn-text">' + esc(msg) + '</div></div>' +
        '<div class="btn-row mt3"><button class="btn primary" data-action="provision-sta">' + icon('refresh') + 'Try again</button>' +
        '<button class="btn ghost" data-action="provision-ap">' + icon('wifi') + 'Use hotspot</button></div>';
    }

    body += '<div class="tiny muted mt4 mb2">SWITCH MODE — ALWAYS AVAILABLE OVER BLUETOOTH</div>' +
      M.MODES.map((m) => modeCardCompact(m, m.id === c.mode)).join('') +
      '<div class="cap-notice mt2">' + icon('info') + '<div class="cn-text">Switching to Wi-Fi happens over Bluetooth, so it works even when the bridge is not on a network. If the new mode fails, the bridge keeps its old network and Bluetooth stays as your escape hatch.</div></div>' +
      '<div class="btn primary mt4" data-action="resync">' + icon('refresh') + 'Re-sync now</div>' +
      '<button class="btn ghost mt2" data-action="disconnect">' + icon('unlink') + 'Disconnect</button>';
    return sheetWrap('Connection', esc(c.deviceName), body);
  }

  // ---- Modes sheet (compact, links to reference) ---------------------------
  function overlayModes() {
    const c = scenario().connection;
    let html = '<div class="cap-notice">' + icon('compass') + '<div class="cn-text">Three ways to talk to the bridge. Tap <b>?</b> on any one for the full technical detail.</div></div><div class="mt3"></div>';
    html += M.MODES.map((m) => modeCardCompact(m, m.id === c.mode)).join('');
    return sheetWrap('Connection modes', 'Switch any time — the app stays reachable', html);
  }

  // ---- Technical reference (the old long text lives here) ------------------
  function overlayModesRef(props) {
    const c = scenario().connection;
    const focus = props.mode;
    let html = '<div class="cap-notice">' + icon('info') + '<div class="cn-text">The bridge is a pure listener: it never transmits except for one tiny LoRa acknowledgement. All three modes share that rule.</div></div><div class="mt3"></div>';
    html += M.MODES.map((m) => {
      const cap = m.capability;
      const open = !focus || focus === m.id;
      return '<div class="card' + (m.id === c.mode ? '' : ' subtle') + '" style="margin-bottom:10px">' +
        '<div class="row"><div class="mode-icon">' + icon(m.icon) + '</div><div style="flex:1"><div class="mode-name">' + esc(m.name) + (m.id === c.mode ? ' <span class="mode-badge">Active</span>' : '') + '</div><div class="mode-tag">' + esc(m.tagline) + '</div></div></div>' +
        '<div class="body small mt3">' + esc(m.summary) + '</div>' +
        (open ? '<div class="mt2">' + m.good.map((g) => '<div class="mode-li good">' + esc(g) + '</div>').join('') +
          m.limited.map((g) => '<div class="mode-li limit">' + esc(g) + '</div>').join('') + '</div>' +
          '<div class="divider"></div><div class="tiny muted mb2">CAPABILITIES</div>' +
          capRow('Live readings', cap.live) + capRow('2-hour preview', cap.preview) + capRow('Full history download', cap.fullHistory) +
          capRow('Alarm-rule editing', cap.rules) + capRow('Firmware update', cap.ota) : '') +
        '</div>';
    }).join('');
    return sheetWrap('Connection modes', 'Technical reference', html);
  }
  function capRow(label, ok) {
    return '<div class="cap-row"><span class="body">' + label + '</span>' +
      (ok ? '<span style="color:var(--positive)">' + icon('check', 15) + '</span>' : '<span class="muted">—</span>') + '</div>';
  }

  // ---- Provision: join home Wi-Fi ------------------------------------------
  function overlayProvisionSta() {
    const nets = [{ ssid: 'HomeNet-5G', bars: 4 }, { ssid: 'HomeNet-2.4G', bars: 3 }, { ssid: 'Backyard-AP', bars: 2 }];
    const html = '<div class="cap-notice">' + icon('info') + '<div class="cn-text">The bridge joins your home Wi-Fi so your phone keeps its internet and you can reach the bridge anywhere in range. The password is sent over Bluetooth and is not stored in the app.</div></div>' +
      '<div class="tiny muted mt4 mb2">CHOOSE A NETWORK</div><div class="card subtle">' +
      nets.map((n, i) => '<div class="link-row" style="cursor:pointer' + (i === nets.length - 1 ? ';border-bottom:none' : '') + '" data-action="pick-wifi" data-ssid="' + esc(n.ssid) + '">' +
        '<div class="lr-icon">' + icon('wifi') + '</div><div class="lr-meta"><div class="lr-name">' + esc(n.ssid) + '</div><div class="lr-sub">' + signalWord(n.bars) + '</div></div>' +
        '<div class="lr-right">' + signalBars(n.bars) + icon('chevronRight') + '</div></div>').join('') + '</div>' +
      '<div class="field mt3"><div class="f-label">Password</div><input id="wifiPass" type="password" placeholder="••••••••" /></div>' +
      '<div class="btn primary mt2" data-action="wifi-submit">' + icon('link') + 'Connect bridge</div>' +
      '<button class="btn ghost mt2" data-action="close-overlay">Cancel</button>';
    return sheetWrap('Join home Wi-Fi', 'Sent over Bluetooth', html);
  }

  // ---- Provision: use the bridge hotspot -----------------------------------
  function overlayProvisionAp() {
    const c = scenario().connection, wifi = c.wifi || {};
    const ssid = wifi.ssid || 'SmokeBridge-A4F2';
    const pass = wifi.passkey || 'smoke-4471';
    const html = '<div class="cap-notice">' + icon('info') + '<div class="cn-text">No home network? The bridge can broadcast its own. Your phone joins it directly — some phones will warn there is “no internet”, which is normal.</div></div>' +
      '<div class="card mt3"><div class="row"><div class="lr-icon">' + icon('wifi') + '</div><div style="flex:1"><div class="hi bold small">' + esc(ssid) + '</div><div class="tiny muted">Bridge hotspot</div></div>' +
      '<div class="lr-icon">' + icon('qr') + '</div></div>' +
      '<div class="tiny muted mt3 mb2">Network password</div><div class="mono-well sm">' + esc(pass) + '</div></div>' +
      '<ol class="body small mt3" style="padding-left:18px;line-height:1.8"><li>Open your phone’s Wi-Fi settings.</li><li>Join <b class="hi">' + esc(ssid) + '</b>.</li><li>Come back — the app finds the bridge automatically.</li></ol>' +
      '<button class="btn primary mt4" data-action="open-wifi-settings">' + icon('wifi') + 'Open Wi-Fi settings</button>' +
      '<button class="btn ghost mt2" data-action="fire-event" data-id="ap-joined">' + icon('check') + 'I have joined (simulate)</button>' +
      '<div class="tiny muted center mt2">The bridge stays on Bluetooth until you confirm.</div>';
    return sheetWrap('Use the bridge hotspot', 'Direct link, no router needed', html);
  }

  // ---- Alarms sheet --------------------------------------------------------
  // [BIZ] Two visibly separate tiers (I2):
  //   DEVICE  — the nine rules on the ESP32, authoritative. The app mirrors.
  //   APP     — insights only (ETA soon, stall, unreachable). Never re-decides.
  function overlayAlarms() {
    const s = scenario();
    const active = (s.alarms || []).filter((a) => !a.acked && !state.pendingAck[a.id]);
    let html = '';
    if (active.length) {
      html += '<div class="section-label" style="margin-top:0">Active now</div>';
      html += active.map((a) => {
        const ic = a.severity === 'critical' ? 'alertCircle' : a.severity === 'warning' ? 'alertTriangle' : 'info';
        return '<div class="alarm-bar ' + a.severity + '" data-action="open-alarm-detail" data-id="' + a.id + '">' + '<span class="al-icon">' + icon(ic) + '</span>' +
          '<div class="al-text"><div class="al-title">' + esc(a.rule) + ' ' + (a.tier === 'device' ? '<span class="tier-tag device">Device</span>' : '<span class="tier-tag app">Insight</span>') + '</div>' +
          '<div class="al-detail">' + esc(a.detail) + '</div></div>' +
          '<button class="al-ack" data-action="ack-alarm" data-id="' + a.id + '" aria-label="Acknowledge" title="Acknowledge">' + icon('check', 17) + '</button></div>';
      }).join('');
    } else {
      html += '<div class="cap-notice">' + icon('check') + '<div class="cn-text">No active alarms. The bridge is watching with or without this app.</div></div>';
    }
    html += '<div class="section-label">Delivery</div>' +
      '<div class="card"><div class="row"><span style="color:var(--positive)">' + icon('bell', 20) + '</span>' +
      '<div style="flex:1"><div class="hi bold small">This phone will wake you</div><div class="tiny muted">Notifications allowed · critical alarms bypass quiet hours</div></div></div>' +
      '<button class="btn ghost sm mt3" data-action="test-alarm">' + icon('zap') + 'Send a test alarm</button></div>';

    html += '<div class="section-label">From the bridge <span class="spacer"></span><span class="tiny muted">authoritative</span></div><div class="card">' +
      M.ALARM_RULES.filter((r) => r.tier === 'device').map((r) =>
        '<div class="set-row"><div class="sr-icon">' + icon(r.severity === 'critical' ? 'alertCircle' : 'alertTriangle') + '</div>' +
        '<div class="sr-meta"><div class="sr-name">' + r.name + '</div><div class="sr-sub">' + r.desc + ' · ' + r.scoped + '</div></div>' +
        '<div class="sr-right">' + toggle('__dev_' + r.id, r.enabled) + '</div></div>').join('') + '</div>';

    html += '<div class="section-label">Insights from the app <span class="spacer"></span><span class="tiny muted">never overrides the bridge</span></div><div class="card">' +
      M.ALARM_RULES.filter((r) => r.tier === 'app').map((r) =>
        '<div class="set-row"><div class="sr-icon">' + icon('info') + '</div>' +
        '<div class="sr-meta"><div class="sr-name">' + r.name + '</div><div class="sr-sub">' + r.desc + '</div></div>' +
        '<div class="sr-right">' + toggle('__app_' + r.id, r.enabled) + '</div></div>').join('') + '</div>';

    html += '<div class="section-label">Preferences</div><div class="card">' +
      setRow('key', 'Prefer my own alarms', 'Your manual alarms win over the device rules', toggle('preferManualAlarm')) +
      setRow('moon', 'Quiet hours', 'Silence warning & info 10pm–6am · critical always sounds', toggle('quietHours')) +
      setRow('bell', 'Background monitoring', 'Check on the bridge and bubble up alarms', toggle('monitoring')) + '</div>';
    return sheetWrap('Alerts', 'From the bridge and insights from the app, kept separate', html);
  }

  // ---- Alarm detail --------------------------------------------------------
  function overlayAlarmDetail(props) {
    const s = scenario();
    const a = (s.alarms || []).find((x) => x.id === props.id);
    if (!a) { closeOverlay(); return ''; }
    const ic = a.severity === 'critical' ? 'alertCircle' : a.severity === 'warning' ? 'alertTriangle' : 'info';
    const body = '<div class="card ' + a.severity + '" style="border-color:rgba(var(--' + (a.severity === 'critical' ? 'critical' : a.severity === 'warning' ? 'warning' : 'info') + '-rgb),0.35)">' +
      '<div class="row"><span class="al-icon" style="color:var(--' + (a.severity === 'critical' ? 'critical' : a.severity === 'warning' ? 'warning' : 'info') + ')">' + icon(ic, 22) + '</span>' +
      '<div style="flex:1"><div class="hi bold">' + esc(a.rule) + '</div><div class="tiny muted">' + fmtClock(a.atMs) + ' · ' + ago(a.atMs) + '</div></div>' +
      (a.tier === 'device' ? '<span class="tier-tag device">Device</span>' : '<span class="tier-tag app">Insight</span>') + '</div>' +
      '<div class="body small mt3">' + esc(a.detail) + '</div></div>' +
      '<div class="card subtle mt3"><div class="tiny muted mb2">Why this fired</div>' +
      '<div class="row between small" style="padding:4px 0"><span class="muted">Rule</span><span class="hi">' + esc(a.ruleId || a.id) + '</span></div>' +
      (a.trigger ? '<div class="row between small" style="padding:4px 0"><span class="muted">Trigger</span><span class="hi">' + esc(a.trigger) + '</span></div>' : '') +
      (a.valueF ? '<div class="row between small" style="padding:4px 0"><span class="muted">Reading</span><span class="hi mono">' + fmtTemp(a.valueF) + '</span></div>' : '') +
      (a.suggestion ? '<div class="row between small" style="padding:4px 0"><span class="muted">Suggestion</span><span class="hi">' + esc(a.suggestion) + '</span></div>' : '') + '</div>' +
      '<div class="btn-row mt4"><button class="btn primary" data-action="ack-alarm" data-id="' + a.id + '">' + icon('check') + 'Acknowledge</button>' +
      '<button class="btn ghost" data-action="snooze-alarm" data-id="' + a.id + '">' + icon('clock') + 'Snooze 10m</button></div>' +
      '<button class="btn ghost mt2" data-action="nav" data-screen="graph">' + icon('chart') + 'View on graph</button>';
    return sheetWrap('Alert', a.tier === 'device' ? 'From the bridge' : 'Insight from the app', body);
  }

  // ---- Mark sheet ----------------------------------------------------------
  function overlayMark() {
    const kinds = [
      { k: 'note', icon: 'bookmark', label: 'Note' }, { k: 'wrapped', icon: 'wrap', label: 'Wrapped' },
      { k: 'spritz', icon: 'droplet', label: 'Spritzed' }, { k: 'turn', icon: 'rotate', label: 'Turned' },
      { k: 'lid_open', icon: 'package', label: 'Lid open' }, { k: 'fuel', icon: 'flame', label: 'Added fuel' },
      { k: 'probe_moved', icon: 'thermometer', label: 'Probe moved' }, { k: 'phase_change', icon: 'activity', label: 'Phase change' },
    ];
    const html = '<div class="tiny muted mb2">Log what just happened. Marks appear on the graph and the timeline.</div>' +
      '<div class="catalog-grid">' + kinds.map((x) =>
        '<button class="catalog-item" data-action="mark-kind" data-kind="' + x.k + '" style="align-items:center;text-align:center;gap:6px">' +
        '<span style="color:var(--text-body)">' + icon(x.icon, 22) + '</span><div class="ci-name">' + x.label + '</div></button>').join('') + '</div>' +
      '<div class="field mt3"><div class="f-label">Add a note (optional)</div><textarea id="markNote" rows="2" placeholder="Wrapped the brisket in butcher paper…"></textarea></div>' +
      '<div class="btn primary mt2" data-action="close-overlay">' + icon('check') + 'Save mark</div>';
    return sheetWrap('Add a mark', 'A timestamped event on this cook', html);
  }

  // ---- Probe detail sheet --------------------------------------------------
  function overlayProbe(props) {
    const jack = props.jack || 1;
    const s = scenario(), p = s.probes.find((x) => x.jack === jack);
    const cook = s.cook;
    const item = (cook.items || []).find((it) => it.jack === jack);
    const cat = item ? catalogById(item.id) : null;
    const isGrate = p.role === 'pit';
    const tp = p.attached ? tempParts(p.tempF) : { num: '—', dec: '', unit: '' };
    let html = '<div class="row" style="gap:12px">' +
      '<span class="jack-badge ' + (p.attached ? 'p' + jack : 'detached') + '" style="width:34px;height:34px;font-size:16px">' + jack + '</span>' +
      (cat ? foodAvatar(cat.glyph, 'lg') : '') +
      '<div style="flex:1"><div class="hi bold" style="font-size:17px">' + esc(cat ? cat.name : (isGrate ? 'Grate / pit' : 'Probe ' + jack)) + '</div>' +
      '<div class="tiny muted">' + (p.attached ? 'Live · jack ' + jack : 'Unplugged') + '</div></div></div>';

    html += '<div class="hero mt3" style="padding:0"><div class="hero-info">' +
      '<div class="hero-temp" style="font-size:52px"><span>' + tp.num + '</span><span class="dec" style="font-size:30px">' + tp.dec + '</span><span class="unit" style="font-size:18px">' + tp.unit + '</span></div>' +
      '<div class="row mt2">' + trendChip(p.trendFPerHr, true) + '</div></div>' +
      '<div class="hero-side">' + sparkline(p.spark || [], seriesColor(jack), 96, 54) + '</div></div>';

    if (!isGrate && p.targetF !== null && p.targetF !== undefined) html += '<div class="card subtle mt3">' + phaseTrack(p) + '</div>';
    html += '<div class="stat-grid mt3">' + stat('High', fmtTemp(p.peakF, 0)) + stat('Avg', fmtTemp(p.avgF, 0)) + stat('Low', fmtTemp(p.lowF, 0)) + '</div>';

    html += '<div class="tiny muted mt4 mb2">ROLE</div><div class="seg-chips">' +
      ['food', 'pit', 'unused'].map((r) => '<button class="chip' + (p.role === r ? ' on' : '') + '" data-action="probe-role" data-jack="' + jack + '" data-role="' + r + '">' +
        (r === 'food' ? 'Food' : r === 'pit' ? 'Grate (pit)' : 'Unused') + '</button>').join('') + '</div>';

    if (!isGrate) {
      html += '<div class="tiny muted mt4 mb2">TARGET</div>';
      if (cat) {
        html += '<div class="seg-chips">' + cat.doneness.map((d) =>
          '<button class="chip' + (donenessFor(cat, state.catalog.doneness).id === d.id ? ' on' : '') + '" data-action="doneness-pick" data-id="' + d.id + '">' + esc(d.label) + ' · ' + fmtTemp(d.targetF, 0) + '</button>').join('') + '</div>';
        html += '<div class="cap-notice mt2">' + icon('info') + '<div class="cn-text">Pull at <b>' + fmtTemp(pullTempFor(cat, donenessFor(cat, state.catalog.doneness)), 0) + '</b> — it coasts up to target while it rests.</div></div>';
      } else {
        html += '<button class="btn ghost" data-action="open-setup">' + icon('target') + 'Set a target for this probe</button>';
      }
    }
    html += '<div class="btn-row mt4"><button class="btn" data-action="mark-pulled" data-jack="' + jack + '">' + icon('check') + 'Mark pulled</button>' +
      '<button class="btn ghost" data-action="test-alarm">' + icon('zap') + 'Test alarm</button></div>' +
      '<button class="btn ghost mt2" data-action="export" data-scope="probe" aria-label="Share probe">' + icon('share') + 'Share this probe</button>';
    return sheetWrap('Probe ' + jack, cat ? esc(cat.name) : 'Jack details', html);
  }
  function phaseTrack(p) {
    const pull = p.pullF === null || p.pullF === undefined ? p.targetF : p.pullF;
    const phase = p.tempF >= p.targetF ? 3 : p.tempF >= pull ? 1 : 0;
    const labels = ['Approaching', 'Pull now', 'Resting', 'Ready'];
    return '<div class="row between">' + labels.map((l, i) =>
      '<div class="center" style="flex:1"><div class="mono small" style="color:' + (i <= phase ? 'var(--text-hi)' : 'var(--text-muted)') + '">' + (i <= phase ? '●' : '○') + '</div>' +
      '<div class="tiny" style="color:' + (i === phase ? 'var(--text-hi)' : 'var(--text-muted)') + ';font-weight:' + (i === phase ? '700' : '500') + '">' + l + '</div></div>').join('') + '</div>';
  }

  // ---- Adopt sheet ---------------------------------------------------------
  function overlayAdopt() {
    const ps = scenario().pendingSession;
    if (!ps) { closeOverlay(); return ''; }
    const body = '<div class="state" style="padding:8px 0 4px"><div class="st-art">' + icon('download', 34) + '</div>' +
      '<div class="st-title">Adopt this cook?</div>' +
      '<div class="st-copy">The bridge recorded <b class="hi">' + ps.samples + '</b> samples over <b class="hi">' + fmtDuration(Date.now() - ps.startedAtMs) + '</b> with ' +
      ps.probeCount + ' probes attached. Adopting keeps every one of them and starts the cook at ' + fmtClock(ps.startedAtMs) + '.</div></div>' +
      '<div class="card subtle"><div class="row between small"><span class="muted">Recording continues</span><span class="hi">Yes</span></div>' +
      '<div class="row between small mt2"><span class="muted">Existing samples</span><span class="hi">Kept</span></div>' +
      '<div class="row between small mt2"><span class="muted">Start time</span><span class="hi">' + fmtClock(ps.startedAtMs) + '</span></div></div>';
    return scrim('<div class="modal-card"><div class="sh-title" style="font-family:var(--font-display);font-weight:700;font-size:19px;color:var(--text-hi);margin-bottom:8px">Adopt session</div>' +
      body + '<div class="btn-row mt4"><button class="btn primary" data-action="adopt-confirm">' + icon('download') + 'Adopt</button>' +
      '<button class="btn ghost" data-action="close-overlay">Cancel</button></div></div>', true);
  }

  // ---- Edit start sheet ----------------------------------------------------
  function overlayEditStart() {
    const cook = scenario().cook;
    const opts = [
      { label: 'Just now', mins: 0 }, { label: '30 min ago', mins: 30 }, { label: '1 hour ago', mins: 60 },
      { label: '2 hours ago', mins: 120 }, { label: '4 hours ago', mins: 240 },
    ];
    const body = '<div class="tiny muted mb2">When did the cook actually start?</div>' +
      '<div class="seg-chips">' + opts.map((o) =>
        '<button class="chip" data-action="set-start" data-mins="' + o.mins + '">' + o.label + '</button>').join('') + '</div>' +
      '<div class="card inset mt3"><div class="tiny muted mb2">Current start</div><div class="hi bold">' + fmtClock(cook.startedAtMs) + '</div></div>' +
      '<div class="cap-notice mt3">' + icon('info') + '<div class="cn-text">Changing the start only moves the cook window. The recorded samples are never rewritten.</div></div>';
    return scrim('<div class="modal-card"><div class="sh-title" style="font-family:var(--font-display);font-weight:700;font-size:19px;color:var(--text-hi);margin-bottom:10px">Adjust start time</div>' +
      body + '<div class="btn-row mt4"><button class="btn ghost" data-action="close-overlay">Close</button></div></div>', true);
  }

  // ---- Firmware (installed version + changelog) ----------------------------
  // [FLUTTER] app_ota: OTA is Wi-Fi-only, versioned, and auto-rolls back if the
  // post-boot health gate fails. The UI must state the transport requirement and
  // the session conflict before the user commits (I5, I8, I12-adjacent).
  function overlayFirmware() {
    const d = M.DEVICE;
    const body = '<div class="card"><div class="row"><div class="sr-icon">' + icon('cpu') + '</div>' +
      '<div style="flex:1"><div class="hi bold">' + esc(d.version) + '</div><div class="tiny muted">Installed ' + esc(d.versionDate) + ' · ' + esc(d.channel) + ' channel</div></div>' +
      (d.available ? '<span class="ci-badge" style="color:var(--warning);border-color:rgba(var(--warning-rgb),0.4)">Update</span>' : '<span style="color:var(--positive)">' + icon('check') + '</span>') + '</div>' +
      '<div class="divider"></div>' +
      diagRow('Hardware', d.hardware) + diagRow('Bootloader', d.bootloader) + diagRow('Auto-rollback', 'On') + '</div>' +
      '<div class="section-label">Update channel</div><div class="seg-chips">' +
      [['stable', 'Stable'], ['beta', 'Beta']].map((c) =>
        '<button class="chip' + (state.settings.otaChannel === c[0] ? ' on' : '') + '" data-action="set-ota-channel" data-channel="' + c[0] + '">' + c[1] + '</button>').join('') + '</div>' +
      '<div class="cap-notice mt3">' + icon('info') + '<div class="cn-text">Firmware is delivered <b>over Wi-Fi only</b> — Bluetooth cannot carry an image. ' + esc(M.FIRMWARE.rollback) + '</div></div>' +
      (d.available
        ? '<div class="card subtle mt3"><div class="tiny muted mb2">Available now</div><div class="hi bold">' + esc(d.available) + '</div>' +
          '<div class="btn primary mt3" data-action="open-firmware-update">' + icon('upload') + 'Install ' + esc(d.available) + '</div></div>'
        : '<div class="btn primary mt4" data-action="check-firmware">' + icon('refresh') + 'Check for updates</div>');
    return sheetWrap('Firmware', esc(M.DEVICE.version), body);
  }

  function overlayFirmwareUpdate() {
    const d = M.DEVICE, fw = M.FIRMWARE, s = scenario(), c = s.connection, wifi = c.wifi || {};
    const wifiOk = !!wifi.connected;
    const cook = s.cook;
    const conflict = cook.active && !state.settings.forceOta;
    let body = '';
    if (!d.available) {
      body = '<div class="cap-notice">' + icon('check') + '<div class="cn-text">You are on the latest ' + esc(state.settings.otaChannel) + ' release, <b>' + esc(d.version) + '</b>.</div></div>' +
        '<div class="btn primary mt4" data-action="check-firmware">' + icon('refresh') + 'Check again</div>';
      return sheetWrap('Update firmware', 'Over Wi-Fi only', body);
    }
    body += '<div class="card"><div class="row between"><div><div class="tiny muted">Installed</div><div class="hi bold">' + esc(d.version) + '</div></div>' +
      icon('arrowRight') + '<div style="text-align:right"><div class="tiny muted">Available</div><div class="hi bold" style="color:var(--p1)">' + esc(fw.latest) + '</div></div></div>' +
      '<div class="divider"></div>' + fw.notes.map((n) => '<div class="mode-li good">' + esc(n) + '</div>').join('') +
      '<div class="row between tiny muted mt2"><span>' + esc(fw.latestDate) + '</span><span>' + fw.sizeKb + ' KB</span></div></div>';

    if (!wifiOk) {
      body += '<div class="cap-notice warn mt3">' + icon('alertTriangle') + '<div class="cn-text">This bridge is not on Wi-Fi right now. An image is too big for Bluetooth — <b>join home Wi-Fi or the bridge hotspot</b> before updating.</div></div>' +
        '<div class="btn-row mt3"><button class="btn primary" data-action="provision-sta">' + icon('router') + 'Join Wi-Fi</button>' +
        '<button class="btn ghost" data-action="provision-ap">' + icon('wifi') + 'Use hotspot</button></div>';
    } else {
      body += '<div class="cap-notice mt3">' + icon('info') + '<div class="cn-text">Connected over Wi-Fi. Do not power the bridge off during the update.</div></div>';
    }
    if (cook.active) {
      body += '<div class="cap-notice ' + (state.settings.forceOta ? '' : 'crit') + ' mt3">' + icon('alertTriangle') +
        '<div class="cn-text">A cook is <b>recording right now</b>. Updating pauses recording and normally returns <b>409 session_active</b>. Force it only if you accept losing this window.</div></div>' +
        '<div class="set-row mt2"><div class="sr-icon">' + icon('zap') + '</div><div class="sr-meta"><div class="sr-name">Force update during this cook</div><div class="sr-sub">Overrides the session-active guard</div></div>' +
        '<div class="sr-right">' + toggle('forceOta') + '</div></div>';
    }
    const disabled = !wifiOk || conflict;
    body += '<button class="btn primary mt4' + (disabled ? ' disabled' : '') + '" data-action="' + (disabled ? '' : 'firmware-install') + '">' +
      icon('upload') + 'Install ' + esc(fw.latest) + '</button>';
    if (!wifiOk) body += '<div class="tiny muted center mt2">Wi-Fi required to install</div>';
    else if (conflict) body += '<div class="tiny muted center mt2">Force the update above, or wait until the cook is done</div>';
    return sheetWrap('Update firmware', 'Over Wi-Fi only', body);
  }

  // ---- About & diagnostics -------------------------------------------------
  function overlayDiagnostics() {
    const d = M.DEVICE, s = scenario(), c = s.connection, bt = c.bt || {}, wifi = c.wifi || {};
    let body = '<div class="card"><div class="card-head">' + icon('cpu') + '<div class="card-title">' + esc(c.deviceName) + '</div>' +
      '<span class="spacer"></span><span class="mono tiny muted">' + esc(d.id) + '</span></div>' +
      diagRow('Firmware', d.version + ' · ' + d.channel) + diagRow('Hardware', d.hardware) + diagRow('Bootloader', d.bootloader) +
      diagRow('Uptime', fmtDuration(d.uptimeMin * 60000)) + diagRow('Free heap', d.heapKb + ' KB') +
      diagRow('Battery', c.batteryPct === null ? '—' : c.batteryPct + '%') + diagRow('Recording', c.recording ? 'Yes — on the bridge' : 'No') +
      diagRow('Last crash', d.lastCrash || 'None') + '</div>';

    body += '<div class="section-label">Signal</div><div class="card">' +
      '<div class="link-row' + (bt.connected ? '' : ' off') + '"><div class="lr-icon">' + icon('bluetooth') + '</div>' +
      '<div class="lr-meta"><div class="lr-name">Bluetooth</div><div class="lr-sub">' + (bt.connected ? signalWord(bt.bars) + (bt.rssi ? ' · ' + bt.rssi + ' dBm' : '') : 'Not connected') + '</div></div>' +
      '<div class="lr-right">' + signalBars(bt.bars) + '</div></div>' +
      '<div class="link-row' + (wifi.connected ? '' : ' off') + '"><div class="lr-icon">' + icon('router') + '</div>' +
      '<div class="lr-meta"><div class="lr-name">Wi-Fi</div><div class="lr-sub">' + (wifi.mode === 'off' ? 'Not set up' : wifi.connected ? esc(wifi.ssid || '') + (wifi.ip ? ' · ' + wifi.ip : '') + ' · ' + signalWord(wifi.bars) : 'Not connected') + '</div></div>' +
      '<div class="lr-right">' + signalBars(wifi.bars) + '</div></div></div>';

    const st = d.storage;
    body += '<div class="section-label">Storage</div><div class="card">' +
      diagRow('Sessions kept', st.sessions + ' of 64') +
      diagRow('Flash used', st.usedKb + ' of ' + st.totalKb + ' KB') +
      diagRow('Retention', '~' + st.days + ' days of recording') +
      '<div class="tt-progress mt2"><i style="width:' + Math.round((st.usedKb / st.totalKb) * 100) + '%"></i></div></div>';

    body += '<div class="section-label">Recent logs</div><div class="card mono" style="font-size:11px">' +
      d.logs.map((l) => '<div class="row" style="gap:8px;padding:5px 0;border-bottom:1px solid var(--hairline)">' +
        '<span class="muted">' + esc(l.t) + '</span>' +
        '<span style="color:' + (l.level === 'warn' ? 'var(--warning)' : l.level === 'error' ? 'var(--critical)' : 'var(--text-body)') + '">' + esc(l.level) + '</span>' +
        '<span class="hi" style="flex:1">' + esc(l.text) + '</span></div>').join('') + '</div>';

    body += '<div class="btn-row mt4"><button class="btn" data-action="copy-diagnostics">' + icon('download') + 'Copy diagnostics</button>' +
      '<button class="btn ghost" data-action="field-report">' + icon('share') + 'Field report</button></div>';
    return sheetWrap('About & diagnostics', esc(d.id), body);
  }
  function diagRow(k, v) {
    return '<div class="row between small" style="padding:6px 0;border-bottom:1px solid var(--hairline)"><span class="muted">' + k + '</span><span class="hi mono" style="font-size:12px">' + esc(v) + '</span></div>';
  }

  // ---- Device verbs (restart / forget / factory / OTA progress) ------------
  const VERBS = {
    restart: { title: 'Restarting the bridge', sub: 'Settings and the recording are kept.', steps: ['Stopping recording cleanly', 'Draining the sample buffer', 'Rebooting', 'LoRa re-sync', 'Reconnecting'] },
    forget: { title: 'Forgetting this bridge', sub: 'Pairing and Wi-Fi are removed from this app only.', steps: ['Dropping the Bluetooth bond', 'Clearing saved Wi-Fi from the app', 'Stopping background monitoring'] },
    factory: { title: 'Factory resetting', sub: 'Everything on the bridge is being erased.', steps: ['Stopping recording', 'Erasing recorded sessions', 'Clearing Wi-Fi and alarm rules', 'Restoring defaults', 'Rebooting to setup mode'] },
    ota: { title: 'Installing firmware', sub: 'Do not power off the bridge.', steps: ['Verifying the image', 'Streaming over Wi-Fi', 'Writing the inactive slot', 'Rebooting into the new slot', 'Health check'] },
  };
  function openVerb(kind) {
    const V = VERBS[kind] || VERBS.restart;
    state.verb = { kind: kind, title: V.title, sub: V.sub, steps: V.steps, step: 0, done: false };
    state.overlay = { name: 'verb', props: {} };
    renderOverlays();
    runVerb();
  }
  function runVerb() {
    const v = state.verb;
    if (!v || v.done) return;
    if (v.step >= v.steps.length) { applyVerb(v.kind); v.done = true; renderOverlays(); return; }
    v.step += 1; renderOverlays();
    setTimeout(function () { if (state.verb === v) runVerb(); }, 680);
  }
  function applyVerb(kind) {
    const s = scenario(), c = s.connection;
    if (kind === 'restart') {
      c.phase = 'connecting'; c.error = null;
      setTimeout(function () {
        c.phase = 'connected';
        c.bt = Object.assign({}, c.bt, { connected: true, bars: c.bt.bars || 3, lastSyncS: 0 });
        if (!c.primary) c.primary = 'bt';
        render();
      }, 2200);
      s.notice = 'Bridge restarted — recording resumed.';
    } else if (kind === 'forget') {
      c.phase = 'offline'; c.primary = null;
      c.bt = Object.assign({}, c.bt, { connected: false, bars: 0, warm: false });
      c.wifi = Object.assign({}, c.wifi, { mode: 'off', connected: false, ssid: null, ip: null, bars: null });
      s.notice = 'Bridge forgotten — pair again with its passkey.';
    } else if (kind === 'factory') {
      c.phase = 'offline'; c.primary = null;
      c.bt = Object.assign({}, c.bt, { connected: false, bars: 0, warm: false });
      c.wifi = Object.assign({}, c.wifi, { mode: 'off', connected: false, ssid: null, ip: null, bars: null });
      s.cook = { active: false, paused: false, name: '', startedAtMs: null, pitBand: [225, 275], grateTargetF: null, items: [] };
      s.alarms = []; s.marks = []; s.pendingSession = null;
      M.DEVICE.available = null;
      s.notice = 'Bridge erased and back in setup mode.';
    } else if (kind === 'ota') {
      M.DEVICE.version = M.DEVICE.available || M.DEVICE.version;
      M.DEVICE.available = null;
      M.DEVICE.lastCrash = null;
      s.notice = 'Firmware updated to ' + M.DEVICE.version + '.';
    }
  }
  function overlayVerb() {
    const v = state.verb;
    if (!v) return '';
    const rows = v.steps.map(function (st, i) {
      const done = v.done || i < v.step;
      const active = !v.done && i === v.step;
      return '<div class="verb-step' + (done ? ' done' : active ? ' on' : '') + '">' +
        '<span class="vs-dot">' + (done ? icon('check', 12) : active ? '●' : '') + '</span>' +
        '<span class="vs-label">' + esc(st) + '</span></div>';
    }).join('');
    const body = '<div class="verb-head">' + (v.done ? icon('check', 30) : '<span class="verb-spin">' + icon('refresh', 28) + '</span>') + '</div>' +
      '<div class="center"><div class="card-title" style="font-size:18px">' + (v.done ? 'Done' : esc(v.title)) + '</div>' +
      '<div class="body small mt2">' + esc(v.sub) + '</div></div>' +
      '<div class="card mt3">' + rows + '</div>' +
      (v.done ? '<div class="btn primary mt4" data-action="verb-close">' + icon('check') + 'Close</div>'
        : '<div class="tiny muted center mt3">Keep the app open…</div>');
    return sheetWrap(v.done ? 'Complete' : v.title, v.done ? 'All steps finished' : v.sub, body);
  }

  // =============================================== §8 ACTIONS + DELEGATION ====
  let lastChart = null;
  let dragState = null;
  let pendingSsid = 'HomeNet-5G';

  function toast(msg) {
    const t = $('#toast');
    t.textContent = msg; t.classList.add('show');
    clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove('show'), 2200);
  }
  function go(screen) { state.screen = screen; render(); $('#view').scrollTop = 0; }

  function resolvedTheme() {
    if (state.themeMode === 'light') return 'light';
    if (state.themeMode === 'dark') return 'dark';
    try { return (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light'; } catch (e) { return 'light'; }
  }
  function applyBodyClasses() {
    const cls = ['theme-' + resolvedTheme()];
    if (state.displayProfile === 'daylight') cls.push('profile-daylight');
    cls.push('density-' + (state.density === 'comfortable' ? 'comfortable' : 'compact'));
    if (state.reducedMotion) cls.push('reduced-motion');
    document.body.className = cls.join(' ');
  }

  // ---- Cook lifecycle ------------------------------------------------------
  function addItemToCook(presetId, jack, styleId) {
    const s = scenario(), cook = s.cook, cat = catalogById(presetId);
    if (!cook.active) {
      cook.active = true; cook.paused = false;
      cook.startedAtMs = Date.now();
      cook.name = (cat ? cat.name : 'Cook') + ' cook';
      cook.grateTargetF = cook.grateTargetF || 250;
      cook.items = [];
    }
    const start = Date.now();
    cook.items = (cook.items || []).filter((it) => it.jack !== jack);
    cook.items.push({ id: presetId, jack: jack, addedAtMs: start, styleId: styleId || null });
    const st = styleId ? (stylesFor(presetId) || []).find((x) => x.id === styleId) : null;
    if (st && st.pitBand) cook.pitBand = st.pitBand;
    const p = s.probes.find((pp) => pp.jack === jack);
    if (p) {
      const don = donenessFor(cat, state.catalog.doneness);
      p.role = 'food'; p.attached = true; p.freshness = 'live';
      p.targetF = st ? st.targetF : (don ? don.targetF : null);
      p.pullF = p.targetF !== null ? p.targetF - carryoverFor(cat) : null;
      if (p.tempF === null || p.tempF === undefined) p.tempF = 60;
    }
    closeOverlay(); go('live');
    toast((cat ? cat.name : 'Item') + ' added to the cook');
  }

  function requestAdd(presetId, jack, styleId) {
    const s = scenario(), cook = s.cook, cat = catalogById(presetId);
    const tl = timelineFor(presetId) || { totalMin: [60, 90] };
    const mid = (tl.totalMin[0] + tl.totalMin[1]) / 2;
    if (cook.active && (cook.items || []).length) {
      const existing = Math.max.apply(null, cook.items.map((it) => {
        const t = timelineFor(it.id) || { totalMin: [60, 90] };
        return it.addedAtMs + ((t.totalMin[0] + t.totalMin[1]) / 2) * 60000;
      }));
      const newFinish = Date.now() + mid * 60000;
      if (newFinish > existing + 15 * 60000) {
        const delay = Math.round((newFinish - existing) / 60000);
        openConfirm({
          title: 'This will run long', confirmLabel: 'Add anyway',
          body: '<b class="hi">' + esc(cat ? cat.name : 'This item') + '</b> takes about <b class="hi">' + Math.round(mid) + ' min</b>, so it would finish roughly <b class="hi">' + fmtDuration(delay * 60000) + '</b> after everything else is already off the grill. Add it to this cook?',
          action: 'add-item', data: { presetId: presetId, jack: jack, styleId: styleId },
        });
        return;
      }
    }
    addItemToCook(presetId, jack, styleId);
  }

  function adoptCook() {
    const s = scenario(), cook = s.cook;
    const sel = catalogById(state.catalog.selectedId) || catalogById('beef_brisket');
    const ps = s.pendingSession;
    cook.active = true; cook.paused = false;
    cook.name = (sel ? sel.name : 'Cook') + ' (adopted)';
    cook.startedAtMs = ps ? ps.startedAtMs : Date.now();
    cook.grateTargetF = cook.grateTargetF || 250;
    cook.items = (cook.items || []).filter((it) => it.jack !== 1);
    cook.items.push({ id: sel.id, jack: 1, addedAtMs: cook.startedAtMs });
    const p = s.probes.find((pp) => pp.jack === 1);
    const don = donenessFor(sel, state.catalog.doneness);
    if (p) { p.role = 'food'; p.attached = true; p.targetF = don ? don.targetF : null; p.freshness = 'live'; if (p.tempF === null) p.tempF = 60; }
    const pulled = ps ? ps.samples : 0;
    s.pendingSession = null;
    closeOverlay(); go('live');
    toast('Cook adopted · pulled ' + pulled + ' samples');
  }

  // ---- Mock event bus ------------------------------------------------------
  function fireEvent(id) {
    const s = scenario(), c = s.connection;
    switch (id) {
      case 'ble-connected':
        c.phase = 'connected'; c.error = null;
        c.bt = Object.assign({}, c.bt, { available: true, connected: true, bars: 3, rssi: -60, lastSyncS: 0 });
        if (!c.primary) c.primary = 'bt';
        break;
      case 'ble-dropped':
        c.bt = Object.assign({}, c.bt, { connected: false, bars: 0, lastSyncS: 60, warm: false });
        if (c.primary === 'bt') c.primary = (c.wifi && c.wifi.connected) ? 'wifi' : null;
        if (!c.primary) c.phase = 'offline';
        break;
      case 'wifi-connecting':
        c.phase = 'connecting'; c.error = null; c.primary = 'bt';
        c.bt = Object.assign({}, c.bt, { connected: true, bars: c.bt.bars || 3, lastSyncS: 0 });
        c.wifi = Object.assign({}, c.wifi, { mode: 'sta', connected: false, ssid: pendingSsid, ip: null, bars: null, rssi: null, lastSyncS: null });
        break;
      case 'wifi-wrong-password':
        c.phase = 'error'; c.error = 'wrong_password'; c.primary = 'bt';
        c.bt = Object.assign({}, c.bt, { connected: true, bars: c.bt.bars || 3 });
        c.wifi = Object.assign({}, c.wifi, { mode: 'sta', connected: false, ssid: pendingSsid, bars: null, rssi: null });
        break;
      case 'wifi-router-unreachable':
        c.phase = 'error'; c.error = 'router_unreachable'; c.primary = 'bt';
        c.bt = Object.assign({}, c.bt, { connected: true, bars: c.bt.bars || 3 });
        c.wifi = Object.assign({}, c.wifi, { mode: 'sta', connected: false, ssid: pendingSsid, bars: 0, rssi: -92 });
        break;
      case 'wifi-connected':
        c.phase = 'connected'; c.error = null;
        c.wifi = Object.assign({}, c.wifi, { mode: 'sta', connected: true, ssid: pendingSsid, ip: '192.168.1.42', bars: 4, rssi: -48, lastSyncS: 0 });
        c.bt = Object.assign({}, c.bt, { connected: true, warm: true, bars: c.bt.bars || 3, lastSyncS: 0 });
        c.primary = 'wifi';
        break;
      case 'ap-broadcasting':
        c.phase = 'provisioning'; c.error = null; c.primary = 'bt';
        c.bt = Object.assign({}, c.bt, { connected: true, bars: c.bt.bars || 3 });
        c.wifi = { available: true, connected: false, mode: 'ap', ssid: 'SmokeBridge-A4F2', passkey: 'smoke-4471', bars: null, rssi: null, lastSyncS: null, warm: false };
        break;
      case 'ap-joined':
        c.phase = 'connected'; c.error = null;
        c.wifi = Object.assign({}, c.wifi, { mode: 'ap', connected: true, ssid: 'SmokeBridge-A4F2', passkey: 'smoke-4471', ip: '192.168.4.1', bars: 4, rssi: -40, lastSyncS: 0 });
        c.primary = 'wifi';
        break;
      case 'switch-rollback':
        c.phase = 'rollback'; c.error = 'switch_failed'; c.primary = 'bt';
        c.bt = Object.assign({}, c.bt, { connected: true, bars: c.bt.bars || 3, lastSyncS: 0 });
        c.wifi = Object.assign({}, c.wifi, { connected: false });
        s.notice = 'The bridge could not join that network, so it kept Bluetooth. Nothing was lost.';
        break;
      case 'resync-complete':
        c.phase = 'connected'; c.error = null; s.notice = null;
        if (c.bt) c.bt.lastSyncS = 0;
        if (c.wifi) c.wifi.lastSyncS = 0;
        break;
      case 'alarm-target':
        s.alarms = (s.alarms || []).concat([{ id: 'evt_target_' + Date.now(), tier: 'device', severity: 'critical', rule: 'Target reached', detail: 'A probe crossed its target going up.', valueF: 201, atMs: Date.now(), acked: false, ruleId: 'target_reached', trigger: 'Crossed target upward', suggestion: 'Pull it now and rest.' }]);
        break;
      case 'alarm-pit-crash':
        s.alarms = (s.alarms || []).concat([{ id: 'evt_crash_' + Date.now(), tier: 'device', severity: 'critical', rule: 'Pit temperature falling fast', detail: 'Down 18°F in 12 min. Check fuel and vents.', valueF: 248.6, atMs: Date.now(), acked: false, ruleId: 'pit_crash', trigger: 'Fell 18°F in 12 min', suggestion: 'Open a vent or add a lit chimney.' }]);
        break;
    }
    closeOverlay(); render();
    toast('Event: ' + id);
  }

  document.addEventListener('click', function (e) {
    const el = e.target.closest('[data-action]');
    if (!el) return;
    const a = el.dataset.action;
    const s = scenario();
    switch (a) {
      case 'nav': go(el.dataset.screen); break;
      case 'back': go('history'); break;
      case 'dev-screen': go(el.dataset.screen); break;
      case 'scenario': {
        const key = el.dataset.key;
        M.SCENARIOS[key] = JSON.parse(JSON.stringify(SCEN_TEMPLATE[key]));
        state.scenarioKey = key; state.graph = { zoom: 1, pan: 0 }; closeOverlay(); render(); break;
      }
      case 'fire-event': fireEvent(el.dataset.id); break;
      case 'open-overlay': openOverlay(el.dataset.name); break;
      case 'close-overlay': closeOverlay(); break;
      case 'scrim-click': if (e.target === el) { closeOverlay(); if (state.fullGraph) { state.fullGraph = false; renderOverlays(); } } break;
      case 'open-connect': openOverlay('connect'); break;
      case 'open-modes': openOverlay('modes'); break;
      case 'open-modes-ref': openOverlay('modesRef', { mode: el.dataset.mode }); break;
      case 'provision-sta': openOverlay('provisionSta'); break;
      case 'provision-ap': openOverlay('provisionAp'); break;
      case 'open-alerts': openOverlay('alarms'); break;
      case 'open-mark': openOverlay('mark'); break;
      case 'open-setup': openOverlay('setup'); break;
      case 'open-custom': state.customForm = null; openOverlay('customFood'); break;
      case 'open-probe': openOverlay('probe', { jack: Number(el.dataset.jack) }); break;
      case 'open-history': go('history'); break;
      case 'open-alarm-detail': openOverlay('alarmDetail', { id: el.dataset.id }); break;
      case 'open-firmware': openOverlay('firmware'); break;
      case 'open-firmware-update': openOverlay('firmwareUpdate'); break;
      case 'open-diagnostics': openOverlay('diagnostics'); break;
      case 'set-ota-channel': state.settings.otaChannel = el.dataset.channel; renderOverlays(); break;
      case 'check-firmware':
        M.DEVICE.available = M.FIRMWARE.latest;
        renderOverlays(); toast('Update available: ' + M.FIRMWARE.latest); break;
      case 'firmware-install': openVerb('ota'); break;
      case 'verb-close': closeOverlay(); render(); toast('All set'); break;
      case 'copy-diagnostics': toast('Diagnostics copied to clipboard'); break;
      case 'field-report':
        openConfirm({ title: 'Send a field report?', confirmLabel: 'Send report',
          body: 'Bundles recent logs, device facts and the last ' + M.DEVICE.storage.days + ' days of session headers. No cook data leaves the phone without you seeing it first.' }); break;
      case 'ask-restart':
        openConfirm({ title: 'Restart the bridge?', confirmLabel: 'Restart', action: 'restart-device',
          body: 'Recording pauses for about <b class="hi">30 seconds</b>. The bridge keeps its settings and the current cook is <b class="hi">not</b> lost.' }); break;
      case 'ask-forget':
        openConfirm({ title: 'Forget this bridge?', confirmLabel: 'Forget', danger: true, action: 'forget-device',
          body: 'Removes the pairing and saved Wi-Fi from <b class="hi">this app</b>. The bridge keeps recording and keeps its own data. You will need its passkey to pair again.' }); break;
      case 'ask-factory':
        openConfirm({ title: 'Factory reset the bridge?', confirmLabel: 'Factory reset', danger: true, action: 'factory-reset',
          body: '<b class="hi">Everything on the bridge is erased</b> — Wi-Fi, alarm rules and all recorded cook sessions. This cannot be undone. The bridge reboots into setup mode.' }); break;
      case 'open-wifi-settings': toast('Opening your phone’s Wi-Fi settings…'); break;
      case 'adopt': openOverlay('adopt'); break;
      case 'adopt-confirm': state.catalog.selectedId = state.catalog.selectedId || 'beef_brisket'; state.catalog.jack = 1; adoptCook(); break;
      case 'discard-session': s.pendingSession = null; toast('Started fresh — old recording kept on the bridge'); render(); break;
      case 'edit-start': openOverlay('editStart'); break;
      case 'set-start': {
        const mins = Number(el.dataset.mins);
        s.cook.startedAtMs = Date.now() - mins * 60000;
        s.cook.items.forEach((it) => { it.addedAtMs = s.cook.startedAtMs; });
        closeOverlay(); render(); toast('Start time updated'); break;
      }
      case 'pause-cook': s.cook.paused = !s.cook.paused; render(); toast(s.cook.paused ? 'Cook paused' : 'Cook resumed'); break;
      case 'setup-mode': state.setupMode = el.dataset.mode; renderOverlays(); break;
      case 'catalog-cat': state.catalog.category = el.dataset.cat; state.catalog.selectedId = null; state.catalog.styleId = null; state.catalog.query = ''; renderOverlays(); break;
      case 'catalog-clear': state.catalog.query = ''; renderOverlays(); break;
      case 'catalog-pick': state.catalog.selectedId = el.dataset.id; state.catalog.doneness = null; state.catalog.styleId = null; renderOverlays(); break;
      case 'style-pick': state.catalog.styleId = el.dataset.id; renderOverlays(); break;
      case 'doneness-pick': {
        state.catalog.doneness = el.dataset.id;
        const o = state.overlay;
        if (o && o.name === 'probe') {
          const jack = o.props.jack, p = s.probes.find((x) => x.jack === jack);
          const it = (s.cook.items || []).find((x) => x.jack === jack);
          const cat = it ? catalogById(it.id) : null;
          const don = cat ? donenessFor(cat, el.dataset.id) : null;
          if (p && don) { p.targetF = don.targetF; p.pullF = pullTempFor(cat, don); }
        }
        render(); break;
      }
      case 'catalog-jack': state.catalog.jack = Number(el.dataset.jack); renderOverlays(); break;
      case 'start-cook': {
        const sel = catalogById(state.catalog.selectedId);
        if (!sel) { toast('Pick a food first'); break; }
        if (s.cook.active) requestAdd(sel.id, state.catalog.jack, state.catalog.styleId);
        else addItemToCook(sel.id, state.catalog.jack, state.catalog.styleId);
        break;
      }
      case 'start-existing': {
        const sel = catalogById(state.catalog.selectedId);
        if (!sel) { toast('Pick a food first'); break; }
        state.catalog.jack = state.catalog.jack || 1;
        adoptCook(); break;
      }
      case 'start-watch': s.cook.active = false; closeOverlay(); go('live'); toast('Watching live — no cook set'); break;
      case 'add-item': if (state.confirm && state.confirm.data) { const d = state.confirm.data; closeOverlay(); addItemToCook(d.presetId, d.jack, d.styleId); } break;
      case 'confirm-yes': {
        const cf = state.confirm; state.confirm = null;
        if (cf && cf.action === 'add-item') { closeOverlay(); addItemToCook(cf.data.presetId, cf.data.jack, cf.data.styleId); }
        else if (cf && cf.action === 'delete-cook') { closeOverlay(); toast('Deleted (mock)'); go('history'); }
        else if (cf && cf.action === 'restart-device') { openVerb('restart'); }
        else if (cf && cf.action === 'forget-device') { openVerb('forget'); }
        else if (cf && cf.action === 'factory-reset') { openVerb('factory'); }
        else { closeOverlay(); renderOverlays(); }
        break;
      }
      case 'confirm-no': state.confirm = null; closeOverlay(); break;
      case 'ack-alarm': state.pendingAck[el.dataset.id] = true; closeOverlay(); render(); toast('Alarm acknowledged'); break;
      case 'ack-all': (s.alarms || []).forEach((al) => { state.pendingAck[al.id] = true; }); render(); toast('All alerts acknowledged'); break;
      case 'snooze-alarm': closeOverlay(); toast('Snoozed for 10 minutes'); break;
      case 'test-alarm': toast('Test alarm sent to your phone'); break;
      case 'set-units': state.units = el.dataset.units; render(); break;
      case 'set-theme': state.themeMode = el.dataset.theme; render(); break;
      case 'cycle-theme': {
        const order = ['system', 'light', 'dark'];
        state.themeMode = order[(order.indexOf(state.themeMode) + 1) % order.length];
        render(); break;
      }
      case 'toggle-profile': state.displayProfile = state.displayProfile === 'daylight' ? 'standard' : 'daylight'; render(); break;
      case 'toggle-setting': {
        const k = el.dataset.key;
        if (k === '__profile') state.displayProfile = state.displayProfile === 'daylight' ? 'standard' : 'daylight';
        else if (k === '__density') state.density = state.density === 'compact' ? 'comfortable' : 'compact';
        else if (k === '__motion') state.reducedMotion = !state.reducedMotion;
        else if (k.indexOf('__') === 0) { toast('Rule toggled'); break; }
        else state.settings[k] = !state.settings[k];
        render(); break;
      }
      case 'set-mode': {
        const id = el.dataset.mode;
        if (id === 'ble') {
          const c = s.connection;
          c.phase = 'connected'; c.error = null; c.primary = 'bt';
          c.bt = Object.assign({}, c.bt, { available: true, connected: true, bars: c.bt.bars || 3, lastSyncS: 0, warm: true });
          closeOverlay(); render(); toast('Switched to Bluetooth');
        } else if (id === 'ap') openOverlay('provisionAp');
        else openOverlay('provisionSta');
        break;
      }
      case 'pick-wifi': pendingSsid = el.dataset.ssid; toast(pendingSsid + ' selected'); break;
      case 'wifi-submit': {
        const inp = document.getElementById('wifiPass');
        if (inp && !inp.value) { toast('Enter the Wi-Fi password'); break; }
        closeOverlay(); fireEvent('wifi-connected'); break;
      }
      case 'forget-network': {
        s.connection.wifi = Object.assign({}, s.connection.wifi, { mode: 'off', connected: false, ssid: null, ip: null, bars: null });
        if (s.connection.primary === 'wifi') s.connection.primary = s.connection.bt && s.connection.bt.connected ? 'bt' : null;
        render(); toast('Network forgotten'); break;
      }
      case 'resync': s.connection.phase = 'connected'; s.connection.error = null; s.connection.lastSyncS = 0; if (s.connection.bt) s.connection.bt.lastSyncS = 0; if (s.connection.wifi) s.connection.wifi.lastSyncS = 0; render(); toast('Re-synced · up to date'); break;
      case 'disconnect':
        s.connection.phase = 'offline'; s.connection.primary = null;
        s.connection.bt = Object.assign({}, s.connection.bt, { connected: false, bars: 0 });
        s.connection.wifi = Object.assign({}, s.connection.wifi, { connected: false, bars: 0 });
        closeOverlay(); render(); toast('Disconnected — the bridge keeps recording'); break;
      case 'graph-range': state.chartRange = el.dataset.range; state.graph = { zoom: 1, pan: 0 }; render(); break;
      case 'graph-zoom': {
        const dir = el.dataset.dir;
        state.graph.zoom = dir === 'in' ? Math.min(40, state.graph.zoom * 1.5) : Math.max(1, state.graph.zoom / 1.5);
        if (state.graph.zoom === 1) state.graph.pan = 0;
        render(); break;
      }
      case 'graph-pan': {
        const d = graphDomain(), span = d.xMax - d.xMin;
        const step = span * 0.4;
        state.graph.pan = el.dataset.dir === 'back' ? Math.max(0, state.graph.pan + step) : Math.max(0, state.graph.pan - step);
        render(); break;
      }
      case 'graph-reset': state.graph = { zoom: 1, pan: 0 }; render(); break;
      case 'graph-fullscreen': state.fullGraph = !state.fullGraph; renderOverlays(); if (state.fullGraph) wireGraph(); break;
      case 'isolate': state.isolatedProbe = state.isolatedProbe === Number(el.dataset.jack) ? null : Number(el.dataset.jack); render(); break;
      case 'select-cook': state.selectedCookId = el.dataset.id; go('cookDetail'); break;
      case 'toggle-fav': { const h = M.HISTORY.find((x) => x.id === el.dataset.id); h.favourite = !h.favourite; render(); break; }
      case 'repeat-cook': {
        const h = M.HISTORY.find((x) => x.id === el.dataset.id);
        state.catalog.selectedId = h.presetId; state.catalog.category = catalogById(h.presetId).category; state.catalog.doneness = null; state.catalog.styleId = h.styleId || null; state.catalog.jack = 1;
        state.setupMode = 'new'; openOverlay('setup'); break;
      }
      case 'delete-cook':
        openConfirm({ title: 'Delete this cook?', body: 'This removes the annotation and its marks. The underlying bridge recording is kept.', confirmLabel: 'Delete', danger: true, action: 'delete-cook' });
        break;
      case 'export': toast('Opening share sheet — ' + (el.dataset.scope || 'data')); break;
      case 'mark-kind': { const k = el.dataset.kind; closeOverlay(); toast('Marked: ' + k.replace('_', ' ')); break; }
      case 'mark-pulled': closeOverlay(); toast('Pulled — rest timer started'); break;
      case 'probe-role': { const p = s.probes.find((x) => x.jack === Number(el.dataset.jack)); p.role = el.dataset.role; render(); break; }
      case 'custom-save': {
        const g = (id) => { const el2 = document.getElementById(id); return el2 ? el2.value : ''; };
        const name = g('cfName').trim();
        if (!name) { toast('Give it a name'); break; }
        const item = {
          id: 'custom_' + Date.now(), category: g('cfCat'), name: name, glyph: g('cfGlyph'), hazard: g('cfHazard'), thickness: g('cfThick'),
          pitBand: [Number(g('cfPitLo')) || 225, Number(g('cfPitHi')) || 275], blurb: 'Custom food', custom: true,
          doneness: [{ id: 'custom', label: 'Target', targetF: Number(g('cfTarget')) || 160 }], defaultDoneness: 'custom',
          timeline: {
            totalMin: [Number(g('cfTotalLo')) || 60, Number(g('cfTotalHi')) || 120], stall: null,
            wrap: Number(g('cfWrap')) > 0 ? { tempF: Number(g('cfWrap')), label: 'Wrap', note: 'Wrap at the set temperature.' } : null,
            spritzEveryMin: Number(g('cfSpritz')) > 0 ? Number(g('cfSpritz')) : null, turn: null, restMin: Number(g('cfRest')) || 0,
            phases: [{ id: 'on', label: 'On the smoker', note: 'Custom timeline.' }, { id: 'pull', label: 'Pull', note: 'At target, rest before serving.' }],
          },
        };
        state.settings.customCatalog.push(item);
        state.catalog.category = item.category; state.catalog.selectedId = item.id; state.catalog.doneness = null; state.catalog.styleId = null;
        state.customForm = null; closeOverlay(); render(); toast('Added ' + name + ' to the catalog');
        break;
      }
      case 'onboard-troubleshoot': state.onboardTroubleshoot = true; renderOverlays(); break;
      case 'onboard-next':
        if (state.onboardTroubleshoot) { state.onboardTroubleshoot = false; renderOverlays(); break; }
        state.onboardStep = Math.min(7, state.onboardStep + 1); renderOverlays(); break;
      case 'onboard-prev':
        if (state.onboardTroubleshoot) { state.onboardTroubleshoot = false; renderOverlays(); break; }
        state.onboardStep = Math.max(0, state.onboardStep - 1); renderOverlays(); break;
      case 'finish-onboard': state.onboardStep = 0; closeOverlay(); go('live'); toast('Welcome — you are connected'); break;
      default: break;
    }
  });

  // Live catalog search. The overlay is re-rendered on each keystroke, so we
  // restore focus and caret position after the rebuild.
  document.addEventListener('input', function (e) {
    if (e.target && e.target.id === 'catalogSearch') {
      state.catalog.query = e.target.value;
      const pos = e.target.selectionStart;
      renderOverlays();
      const el = document.getElementById('catalogSearch');
      if (el) { el.focus(); try { el.setSelectionRange(pos, pos); } catch (err) { /* search is a nicety */ } }
    }
  });

  // ---- Chart crosshair + gestures ------------------------------------------
  function wireGraph() {
    ['chartHost', 'chartHostFull'].forEach(function (id) {
      const host = document.getElementById(id);
      if (!host) return;
      const tip = host.querySelector('.crosshair-tip');
      const svg = host.querySelector('svg');
      if (!svg) return;

      host.addEventListener('mousemove', function (ev) {
        if (dragState) return;
        if (!lastChart) return;
        const rect = svg.getBoundingClientRect();
        const vbx = ((ev.clientX - rect.left) / rect.width) * 340;
        const frac = (vbx - 30) / (340 - 30 - 12);
        const t = lastChart.xMin + frac * (lastChart.xMax - lastChart.xMin);
        let rows = '', nearestT = t;
        lastChart.series.forEach(function (sr) {
          let best = null, bd = Infinity;
          sr.points.forEach(function (p) { const d = Math.abs(p.x - t); if (d < bd) { bd = d; best = p; } });
          if (best) { nearestT = best.x; rows += '<div class="ct-row"><span class="ct-name">' + esc(sr.name) + '</span><span class="ct-val">' + fmtTemp(best.y) + '</span></div>'; }
        });
        if (tip) {
          tip.innerHTML = '<div class="ct-time">' + fmtClock(lastChart.started + nearestT * 60000) + '</div>' + rows;
          tip.style.display = 'block';
          tip.style.left = Math.min(rect.width - 160, Math.max(0, ev.clientX - rect.left + 10)) + 'px';
          tip.style.top = '8px';
        }
      });
      host.addEventListener('mouseleave', function () { if (tip) tip.style.display = 'none'; });
      host.addEventListener('wheel', function (ev) {
        ev.preventDefault();
        state.graph.zoom = ev.deltaY < 0 ? Math.min(40, state.graph.zoom * 1.2) : Math.max(1, state.graph.zoom / 1.2);
        if (state.graph.zoom === 1) state.graph.pan = 0;
        render();
      }, { passive: false });
      host.addEventListener('pointerdown', function (ev) { dragState = { x: ev.clientX }; host.style.cursor = 'grabbing'; });
      host.addEventListener('pointermove', function (ev) {
        if (!dragState) return;
        const rect = host.getBoundingClientRect();
        const d = graphDomain(), span = d.xMax - d.xMin;
        state.graph.pan = Math.max(0, state.graph.pan - ((ev.clientX - dragState.x) / rect.width) * span);
        dragState.x = ev.clientX;
        render();
      });
      host.addEventListener('pointerup', function () { dragState = null; host.style.cursor = ''; });
      host.addEventListener('pointerleave', function () { dragState = null; });
    });
  }

  // ======================================================== §9 BOOT + TICK ====
  const SCEN_TEMPLATE = JSON.parse(JSON.stringify(M.SCENARIOS));

  function renderDev() {
    $('#dpScenarios').innerHTML = Object.keys(M.SCENARIOS).map((k) =>
      '<button class="dp-btn' + (state.scenarioKey === k ? ' on' : '') + '" data-action="scenario" data-key="' + k + '">' + esc(M.SCENARIOS[k].label) + '</button>').join('');
    const screens = ['live', 'temps', 'timeline', 'graph', 'settings', 'history'];
    $('#dpScreens').innerHTML = screens.map((sc) =>
      '<button class="dp-btn' + (state.screen === sc ? ' on' : '') + '" data-action="dev-screen" data-screen="' + sc + '">' + sc + '</button>').join('');
    const overlays = [['onboarding', 'Onboarding'], ['setup', 'Cook setup'], ['connect', 'Connection'], ['modes', 'Modes'], ['modesRef', 'Modes reference'], ['provisionSta', 'Join Wi-Fi'], ['provisionAp', 'Hotspot'], ['alarms', 'Alerts'], ['mark', 'Add mark'], ['adopt', 'Adopt'], ['editStart', 'Edit start'], ['customFood', 'Custom food'], ['firmware', 'Firmware'], ['firmwareUpdate', 'Update firmware'], ['diagnostics', 'Diagnostics']];
    $('#dpOverlays').innerHTML = overlays.map((o) =>
      '<button class="dp-btn" data-action="open-overlay" data-name="' + o[0] + '">' + o[1] + '</button>').join('');
    $('#dpEvents').innerHTML = M.EVENTS.map((e) =>
      '<button class="dp-btn dp-event" data-action="fire-event" data-id="' + e.id + '" title="' + esc(e.hint) + '">' + esc(e.label) + '</button>').join('');
    $('#dpSettings').innerHTML =
      '<button class="dp-btn" data-action="set-units" data-units="' + (state.units === 'F' ? 'C' : 'F') + '">Units: ' + state.units + ' → ' + (state.units === 'F' ? 'C' : 'F') + '</button>' +
      '<button class="dp-btn" data-action="cycle-theme">Theme: ' + state.themeMode + '</button>' +
      '<button class="dp-btn" data-action="toggle-profile">Profile: ' + state.displayProfile + '</button>' +
      '<button class="dp-btn" data-action="open-connect">Simulate connection sheet</button>';
  }

  function render() {
    applyBodyClasses();
    renderAppbar(); renderNav(); renderView(); renderOverlays(); renderDev();
    if (state.screen === 'graph' || state.fullGraph) wireGraph();
  }

  function tick() {
    const clock = $('#clock');
    if (clock) clock.textContent = new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    const s = scenario();
    if (s.cook.active && !s.cook.paused) {
      const sw = $('#swTime');
      if (sw) sw.textContent = fmtStopwatch(Date.now() - s.cook.startedAtMs);
    }
  }

  // Optional deep links so any view can be opened directly, e.g.
  //   index.html?screen=graph&scenario=idle&overlay=setup&units=C&theme=light
  try {
    if (typeof location !== 'undefined') {
      const raw = (location.search || '').replace(/^\?/, '') + '&' + (location.hash || '').replace(/^#/, '');
      const q = new URLSearchParams(raw);
      if (q.get('scenario') && M.SCENARIOS[q.get('scenario')]) state.scenarioKey = q.get('scenario');
      if (q.get('screen')) state.screen = q.get('screen');
      if (q.get('units')) state.units = q.get('units');
      if (q.get('theme')) state.themeMode = q.get('theme');
      if (q.get('overlay')) state.overlay = { name: q.get('overlay'), props: {} };
    }
  } catch (e) { /* deep links are a prototype nicety only */ }

  render();
  setInterval(tick, 1000);
  tick();

  // Expose a few hooks for manual poking in the console.
  window.SMOKE_UI = { state: state, open: openOverlay, close: closeOverlay, render: render, fire: fireEvent };
})();
