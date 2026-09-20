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
 *   §4  Domain helpers (catalog, timelines, derived values)
 *   §5  Renderers — chrome (appbar / nav / dev panel)
 *   §6  Renderers — views (live / timeline / graph / cooks / device / detail)
 *   §7  Renderers — overlays (onboarding / setup / connect / modes / alarms …)
 *   §8  Actions + event delegation
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
    themeProfile: M.settings.themeProfile,
    settings: Object.assign({}, M.settings),

    overlay: null,
    onboardStep: 0,

    selectedCookId: null,
    chartRange: 'all',
    isolatedProbe: null,

    catalog: { category: 'Beef', selectedId: null, doneness: null, jack: 1 },
    setupMode: 'new',
    pendingAck: {},
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
    minus: '<path d="M5 12h14"/>',
    utensils: '<path d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 002-2V2M7 2v20M21 15V2a5 5 0 00-5 5v6c0 1.1.9 2 2 2h3z"/>',
    wrap: '<path d="M16.5 9.4l-9-5.19M21 16V8a2 2 0 00-1-1.73l-7-4a2 2 0 00-2 0l-7 4A2 2 0 003 8v8a2 2 0 001 1.73l7 4a2 2 0 002 0l7-4A2 2 0 0021 16z"/><path d="M3.27 6.96L12 12.01l8.73-5.05M12 22.08V12"/>',
    droplet: '<path d="M12 2.69l5.66 5.66a8 8 0 11-11.31 0z"/>',
    rotate: '<path d="M23 4v6h-6M1 20v-6h6"/><path d="M20.49 9A9 9 0 005.64 5.64L1 10M23 14l-4.64 4.36A9 9 0 013.51 15"/>',
    calendar: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
    sun: '<circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/>',
    moon: '<path d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z"/>',
    sliders: '<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6"/>',
    more: '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
    activity: '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
    eye: '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>',
    mapPin: '<path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z"/><circle cx="12" cy="10" r="3"/>',
    package: '<path d="M16.5 9.4l-9-5.19M21 16V8a2 2 0 00-1-1.73l-7-4a2 2 0 00-2 0l-7 4A2 2 0 003 8v8a2 2 0 001 1.73l7 4a2 2 0 002 0l7-4A2 2 0 0021 16z"/><path d="M3.27 6.96L12 12.01l8.73-5.05M12 22.08V12"/>',
    wifiOff: '<path d="M1 1l22 22M16.72 11.06A10.94 10.94 0 0119 12.55M5 12.55a10.94 10.94 0 015.17-2.39M10.71 5.05A16 16 0 0122.58 9M1.42 9a15.91 15.91 0 014.7-2.88M8.53 16.11a6 6 0 016.95 0M12 20h.01"/>',
    upload: '<path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M17 8l-5-5-5 5M12 3v12"/>',
    compass: '<circle cx="12" cy="12" r="10"/><path d="M16.24 7.76l-2.12 6.36-6.36 2.12 2.12-6.36 6.36-2.12z"/>',
    key: '<path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 11-7.778 7.778 5.5 5.5 0 017.777-7.777zm0 0L15.5 7.5m0 0l3 3L22 7l-3-3m-3.5 3.5L19 4"/>',
  };
  function icon(name, size) {
    const p = ICON_PATHS[name] || '';
    const s = size || 18;
    return '<svg viewBox="0 0 24 24" width="' + s + '" height="' + s + '" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + p + '</svg>';
  }

  const GLYPH = { brisket: '🥩', beef: '🥩', steak: '🥩', pork: '🍖', ribs: '🍖', poultry: '🍗', wholeBird: '🍗', fish: '🐟', ground: '🍔', egg: '🥚', ambient: '🥔', pit: '🔥', unstated: '🍽️' };
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
      '<circle cx="' + c + '" cy="' + c + '" r="' + r + '" fill="none" stroke="rgba(255,255,255,0.09)" stroke-width="7"/>' + band + arc +
      '</svg><div class="g-center"><div class="g-val">' + esc(o.center) + '</div><div class="g-cap">' + esc(o.caption || '') + '</div></div></div>';
  }

  // [FLUTTER] Maps to the fl_chart cook chart. Rules ported:
  //   runs split at gaps before decimation; area fill <=16%; target lines are
  //   labelled ON the line; crosshair returns the nearest real sample.
  function buildChart(series, opts) {
    opts = opts || {};
    const W = 340, H = 190, padL = 30, padR = 12, padT = 12, padB = 26;
    const xMin = opts.xMin, xMax = opts.xMax;
    let yMin = opts.yMin, yMax = opts.yMax;
    if (yMin === undefined) {
      let lo = Infinity, hi = -Infinity;
      series.forEach((s) => s.points.forEach((p) => { if (p.y < lo) lo = p.y; if (p.y > hi) hi = p.y; }));
      yMin = Math.floor((lo - 8) / 25) * 25; yMax = Math.ceil((hi + 8) / 25) * 25;
    }
    const x = (v) => padL + ((v - xMin) / (xMax - xMin)) * (W - padL - padR);
    const y = (v) => padT + (1 - (v - yMin) / (yMax - yMin)) * (H - padT - padB);
    let svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none">';
    for (let i = 0; i <= 4; i++) {
      const gy = padT + (i / 4) * (H - padT - padB);
      const gv = yMax - (i / 4) * (yMax - yMin);
      svg += '<line x1="' + padL + '" y1="' + gy + '" x2="' + (W - padR) + '" y2="' + gy + '" stroke="rgba(255,255,255,0.07)"/>';
      svg += '<text x="' + (padL - 5) + '" y="' + (gy + 3) + '" fill="#94A3B8" font-size="8.5" text-anchor="end" font-family="JetBrains Mono, monospace">' + Math.round(conv(gv)) + '</text>';
    }
    (opts.targets || []).forEach((t) => {
      if (t.value === null || t.value === undefined) return;
      const ty = y(t.value);
      svg += '<line x1="' + padL + '" y1="' + ty + '" x2="' + (W - padR) + '" y2="' + ty + '" stroke="' + t.color + '" stroke-width="1" stroke-dasharray="4 4" opacity="0.65"/>';
      svg += '<text x="' + (W - padR) + '" y="' + (ty - 3) + '" fill="' + t.color + '" font-size="8.5" text-anchor="end" font-family="JetBrains Mono, monospace">' + esc(t.label) + '</text>';
    });
    series.forEach((s) => {
      if (s.hidden) return;
      const dim = opts.isolated && opts.isolated !== s.probe;
      const col = dim ? 'rgba(255,255,255,0.18)' : s.color;
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
      svg += '<line x1="' + mx.toFixed(1) + '" y1="' + padT + '" x2="' + mx.toFixed(1) + '" y2="' + (H - padB) + '" stroke="#FAB219" stroke-width="1" stroke-dasharray="2 3" opacity="0.45"/>';
    });
    if (opts.now !== undefined && opts.now <= xMax) {
      svg += '<line x1="' + x(opts.now).toFixed(1) + '" y1="' + padT + '" x2="' + x(opts.now).toFixed(1) + '" y2="' + (H - padB) + '" stroke="#F8FAFC" opacity="0.5"/>';
    }
    for (let i = 0; i <= 4; i++) {
      const v = xMin + (i / 4) * (xMax - xMin), px = x(v);
      svg += '<text x="' + px.toFixed(1) + '" y="' + (H - 8) + '" fill="#94A3B8" font-size="8.5" text-anchor="middle" font-family="JetBrains Mono, monospace">' + esc(opts.xLabels ? opts.xLabels(v) : Math.round(v)) + '</text>';
    }
    return svg + '</svg>';
  }

  // ===================================================== §4 DOMAIN HELPERS ====
  function catalogById(id) { return M.CATALOG.find((c) => c.id === id); }
  function catalogInCat(cat) { return M.CATALOG.filter((c) => c.category === cat); }
  function timelineFor(id) { return M.TIMELINES[id] || null; }
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
      if (probe.role === 'pit') {
        v = start + (cur - start) * p + Math.sin(p * 9) * 6 + (r() - 0.5) * 3;
      } else {
        let e = Math.pow(p, 0.55);
        if (probe.stalled && p > 0.55 && p < 0.88) e = Math.pow(0.55, 0.55) + (p - 0.55) * 0.12;
        v = start + (cur - start) * e + (r() - 0.5) * 2.2;
      }
      pts.push({ x: xx, y: Math.max(0, v) });
    }
    pts[n].y = cur;
    return pts;
  }
  function seriesColor(jack) { return ['var(--p1)', 'var(--p2)', '#1FA31F', 'var(--p4)'][jack - 1] || 'var(--p1)'; }

  // ==================================================== §5 RENDER: CHROME ====
  function renderAppbar() { $('#appbar').innerHTML = appbarHtml(); }

  function appbarHtml() {
    const s = scenario(), c = s.connection;
    const online = c.state === 'connected';
    const mode = M.MODES.find((m) => m.id === c.mode) || M.MODES[0];
    const modeIcon = c.mode === 'ble' ? 'bluetooth' : c.mode === 'ap' ? 'wifi' : 'router';
    const alarms = (s.alarms || []).filter((a) => !a.acked && !state.pendingAck[a.id]);
    const badge = alarms.length ? '<span class="dot-badge">' + alarms.length + '</span>' : '';
    const bell = '<button class="icon-btn" data-action="open-alerts" title="Alerts">' + icon('bell') + badge + '</button>';

    if (state.screen === 'cookDetail') {
      return '<button class="icon-btn" data-action="back">' + icon('chevronLeft') + '</button>' +
        '<div><div class="ab-title" style="font-size:17px">Cook detail</div></div><div class="spacer"></div>' + bell;
    }
    if (state.screen === 'cooks') {
      return '<div><div class="ab-title">Cooks</div><div class="ab-sub">History & new cooks</div></div><div class="spacer"></div>' +
        '<button class="icon-btn" data-action="open-setup" title="Start a cook">' + icon('plus') + '</button>' + bell;
    }
    const chip = '<button class="transport' + (online ? '' : ' is-offline') + '" data-action="open-connect">' +
      '<span class="pulse-dot ' + (online ? '' : 'idle') + '"></span>' + icon(modeIcon, 14) +
      '<span class="tp-label">' + (online ? esc(mode.name) : 'Offline') + '</span>' +
      '<span class="tp-detail">· ' + (online ? (c.lastSyncS < 60 ? c.lastSyncS + 's' : Math.round(c.lastSyncS / 60) + 'm') : ago(Date.now() - c.lastSyncS * 1000)) + '</span></button>';
    if (state.screen === 'live') return chip + '<div class="spacer"></div>' + bell;
    const titles = { timeline: ['Timeline', 'Expected & actual'], graph: ['Graph', 'All probes'], device: ['Device', 'Connection & settings'] };
    const t = titles[state.screen] || ['Smoke', ''];
    return '<div><div class="ab-title">' + t[0] + '</div><div class="ab-sub">' + t[1] + '</div></div><div class="spacer"></div>' + bell;
  }

  function renderNav() {
    const items = [
      { id: 'live', label: 'Live', icon: 'activity' },
      { id: 'timeline', label: 'Timeline', icon: 'list' },
      { id: 'graph', label: 'Graph', icon: 'chart' },
      { id: 'cooks', label: 'Cooks', icon: 'history' },
      { id: 'device', label: 'Device', icon: 'cpu' },
    ];
    const alarmCount = (scenario().alarms || []).filter((a) => !a.acked && !state.pendingAck[a.id]).length;
    $('#nav').innerHTML = items.map((it) => {
      const on = state.screen === it.id || (state.screen === 'cookDetail' && it.id === 'cooks');
      const dot = it.id === 'live' && alarmCount ? '<span class="ndot"></span>' : '';
      return '<button class="nav-item' + (on ? ' on' : '') + '" data-action="nav" data-screen="' + it.id + '">' +
        icon(it.icon) + '<span class="nlabel">' + it.label + '</span>' + dot + '</button>';
    }).join('');
  }

  function renderView() {
    const map = { live: viewLive, timeline: viewTimeline, graph: viewGraph, cooks: viewCooks, cookDetail: viewCookDetail, device: viewDevice };
    $('#view').innerHTML = (map[state.screen] || viewLive)();
    if (state.screen === 'graph') wireChart();
  }

  // ====================================================== §6 RENDER: VIEWS ====
  // ---- Live ----------------------------------------------------------------
  function viewLive() {
    const s = scenario(), c = s.connection, cook = s.cook;
    const grate = s.probes.find((p) => p.role === 'pit');
    let html = '';

    // 1. Alarm strip(s) — highest severity first, inline acknowledge.
    html += alarmStrips(s);

    // 2. Adopt banner — the "hook into already-collected data" case.
    if (s.pendingSession && !cook.active) {
      const ps = s.pendingSession;
      html += '<div class="card" style="border-color:rgba(217,89,38,0.4);background:linear-gradient(180deg,rgba(217,89,38,0.10),var(--card) 60%)">' +
        '<div class="card-head">' + icon('history') + '<div class="card-title">A cook is already running</div></div>' +
        '<div class="body small">Your bridge has been recording for <b class="hi">' + fmtDuration(Date.now() - ps.startedAtMs) + '</b> with ' +
        ps.probeCount + ' probes attached (' + ps.samples + ' samples). We can pull that history in and build the cook around it.</div>' +
        '<div class="btn-row mt4"><button class="btn primary" data-action="adopt">' + icon('download') + 'Adopt session</button>' +
        '<button class="btn ghost" data-action="discard-session">Start fresh</button></div></div>';
    }

    // 3. Cook header + stopwatch (or instrument mode).
    if (cook.active) {
      const firstCat = catalogById((cook.items[0] || {}).id);
      html += '<div class="card">' +
        '<div class="cook-head">' + foodAvatar(firstCat ? firstCat.glyph : 'unstated') +
        '<div class="ch-meta"><div class="ch-name">' + esc(cook.name) + '</div>' +
        '<div class="ch-line">' + icon('lock', 12) + 'Recording on the bridge — safe even if this phone drops</div></div>' +
        '<button class="icon-btn" data-action="open-setup" title="Cook settings">' + icon('sliders') + '</button></div>' +
        '<div class="stopwatch mt4' + (cook.paused ? ' paused' : '') + '">' +
        '<div><div class="sw-label">Cook time</div><div class="sw-time" id="swTime">' + fmtStopwatch(Date.now() - cook.startedAtMs) + '</div>' +
        '<div class="sw-started">Started ' + fmtClock(cook.startedAtMs) + (cook.paused ? ' · paused' : '') + '</div></div>' +
        '<div class="spacer"></div><div class="sw-actions">' +
        '<button class="sw-btn" data-action="pause-cook" title="' + (cook.paused ? 'Resume' : 'Pause') + '">' + icon(cook.paused ? 'play' : 'pause') + '</button>' +
        '<button class="sw-btn" data-action="edit-start" title="Adjust start time">' + icon('edit') + '</button>' +
        '</div></div></div>';
    } else {
      html += '<div class="card">' +
        '<div class="card-head">' + icon('thermometer') + '<div class="card-title">Instrument mode</div>' +
        '<span class="spacer"></span><span class="tiny muted">no targets</span></div>' +
        '<div class="body small">Watching live temperatures without a cook. Nothing is lost — the bridge records everything either way. Add a cook whenever you want targets, timers and a timeline.</div>' +
        '<div class="btn-row mt4"><button class="btn primary" data-action="open-setup">' + icon('plus') + 'Start a cook</button>' +
        '<button class="btn ghost" data-action="nav" data-screen="graph">' + icon('chart') + 'View graph</button></div></div>';
    }

    // 4. Hero — the grate/pit temperature. [BIZ] Hero is always ink, never hue.
    if (grate) {
      const tp = tempParts(grate.tempF);
      const band = cook.pitBand;
      const inBand = grate.tempF !== null && grate.tempF >= band[0] && grate.tempF <= band[1];
      html += '<div class="card hero mt3"><div class="hero-info">' +
        '<div class="hero-kicker">' + icon('flame', 13) + 'Grate · Jack ' + grate.jack + '</div>' +
        '<div class="hero-temp"><span>' + tp.num + '</span><span class="dec">' + tp.dec + '</span><span class="unit">' + tp.unit + '</span></div>' +
        '<div class="hero-target">Target <b>' + fmtTemp(grate.targetF, 0) + '</b> · ' + (grate.freshness === 'live' ? 'live' : 'stale') + '</div>' +
        '<div class="hero-band">Pit band ' + band[0] + '–' + band[1] + '° F ' + (inBand ? '<span style="color:var(--positive)">· in band</span>' : '<span style="color:var(--warning)">· out of band</span>') + '</div>' +
        '<div class="row mt2">' + trendChip(grate.trendFPerHr, true) + '</div></div>' +
        '<div class="hero-side">' + gauge({
          value: grate.tempF, min: 0, max: 500, color: 'var(--p1)', center: fmtTemp(grate.tempF, 0).replace(unitLabel(), ''), caption: 'grate',
          bandMin: grate.tempF !== null ? grate.tempF - 30 : undefined, bandMax: grate.tempF !== null ? grate.tempF + 30 : undefined,
        }) + '</div></div>';
    }

    // 5. Timer board — FRONT AND CENTER. 3 meat timers + 1 grate timer.
    html += '<div class="section-label">' + icon('clock', 13) + 'Timers<span class="spacer"></span><span class="muted tiny">tap to manage</span></div>' +
      '<div class="timer-grid">' + s.probes.map((p) => timerTile(p, cook)).join('') + '</div>';

    // 6. Mini live graph.
    const elapsedMin = cook.startedAtMs ? Math.round((Date.now() - cook.startedAtMs) / 60000) : 0;
    html += '<div class="card tap mt3" data-action="nav" data-screen="graph">' +
      '<div class="card-head">' + icon('chart') + '<div class="card-title">Live graph</div><span class="spacer"></span>' +
      '<span class="tiny muted">' + (state.units === 'C' ? '°C' : '°F') + ' · last ' + elapsedMin + 'm</span>' + icon('chevronRight') + '</div>' +
      '<div class="chart">' + miniChart(s) + '</div></div>';

    // 7. Quick actions.
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
    return alarms.slice(0, 3).map((a) => {
      const ic = a.severity === 'critical' ? 'alertCircle' : a.severity === 'warning' ? 'alertTriangle' : 'info';
      const tier = a.tier === 'device' ? '<span class="tier-tag device">Device</span>' : '<span class="tier-tag app">Advisory</span>';
      return '<div class="alarm-bar ' + a.severity + '" data-action="open-alerts">' +
        '<span class="al-icon">' + icon(ic) + '</span><div class="al-text">' +
        '<div class="al-title">' + esc(a.rule) + ' ' + tier + '</div>' +
        '<div class="al-detail">' + esc(a.detail) + (a.valueF ? ' · ' + fmtTemp(a.valueF) : '') + '</div></div>' +
        '<button class="al-ack" data-action="ack-alarm" data-id="' + a.id + '">Ack</button></div>';
    }).join('');
  }

  // [BIZ] Detached probe renders "— / Unplugged", never 0 (I3).
  // [BIZ] Stale removes derived values (ETA/trend) instead of greying (I4).
  function timerTile(p, cook) {
    const item = (cook.items || []).find((it) => it.jack === p.jack);
    const cat = item ? catalogById(item.id) : null;
    const isGrate = p.role === 'pit';
    const attached = p.attached;
    const tp = attached ? tempParts(p.tempF) : { num: '—', dec: '', unit: '' };
    const target = isGrate ? (cook.grateTargetF || p.targetF) : p.targetF;
    const prog = (attached && target && p.tempF !== null) ? Math.max(0, Math.min(1, p.tempF / target)) : 0;
    const canShowDerived = p.freshness === 'live';

    let flags = '';
    if (p.stalled && canShowDerived) flags += '<span class="tt-stall">STALL</span>';
    if (attached && target && p.tempF >= target - 0.001) flags += '<span class="tt-done">DONE</span>';
    if (isGrate) flags += '<span class="tt-grate-tag">Grate</span>';

    let sub = !attached ? '<span style="color:var(--text-muted)">Unplugged</span>'
      : isGrate ? 'Pit band ' + cook.pitBand[0] + '–' + cook.pitBand[1] + '° F'
      : 'Target <b>' + fmtTemp(target, 0) + '</b>';

    let etaBlock = '';
    if (canShowDerived && p.etaMin !== null && p.etaMin !== undefined) {
      etaBlock = '<div class="tt-eta">' + icon('clock', 13) + '<span class="eta-big">' + fmtEta(p.etaMin) + '</span><span class="eta-note">to pull</span></div>';
    } else if (canShowDerived && p.stalled) {
      etaBlock = '<div class="tt-eta"><span class="eta-note">ETA paused during stall</span></div>';
    } else if (!canShowDerived && attached) {
      etaBlock = '<div class="tt-eta"><span class="eta-note">' + (p.freshness === 'frozen' ? 'Stale — estimates hidden' : 'Estimate unavailable') + '</span></div>';
    }
    const phase = phaseOf(p);
    return '<div class="timer-tile p' + p.jack + (isGrate ? ' grate' : '') + '" data-action="open-probe" data-jack="' + p.jack + '">' +
      '<div class="tt-flags">' + flags + '</div>' +
      '<div class="tt-top"><span class="jack-badge ' + (attached ? 'p' + p.jack : 'detached') + '">' + p.jack + '</span>' +
      '<span class="tt-name">' + esc(cat ? cat.name : (isGrate ? 'Grate' : 'Probe ' + p.jack)) + '</span></div>' +
      '<div class="tt-temp' + (attached ? '' : ' detached') + '">' + tp.num + '<span class="u">' + (attached ? tp.dec + tp.unit : '') + '</span></div>' +
      '<div class="tt-sub">' + sub + '</div>' +
      (attached && target ? '<div class="tt-progress"><i style="width:' + (prog * 100).toFixed(0) + '%"></i></div>' : '') +
      etaBlock +
      (phase && attached && !isGrate ? '<div class="tt-sub" style="margin-top:7px">' + phase + '</div>' : '') + '</div>';
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

  // ---- Timeline ------------------------------------------------------------
  // [BIZ] The Timeline is database-driven (MOCK.TIMELINES), not a guess: every
  // cut carries expected total, stall window, wrap point, spritz cadence,
  // turn point and rest. See NOTES.md §Timeline DB.
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
  function viewGraph() {
    const s = scenario(), cook = s.cook;
    const started = cook.startedAtMs || (Date.now() - 60 * 60000);
    const now = Date.now(), elapsed = (now - started) / 60000;
    const ranges = { '15m': 15, '1h': 60, '6h': 360, 'all': elapsed };
    const span = ranges[state.chartRange] || elapsed;
    const xMin = Math.max(0, elapsed - span), xMax = Math.max(span, elapsed);
    const series = s.probes.filter((p) => p.attached && p.spark && p.spark.length).map((p) => {
      const all = buildSeries(p, { startedAtMs: now - elapsed * 60000 });
      return { probe: p.jack, color: seriesColor(p.jack), points: all.filter((q) => q.x >= xMin), width: p.role === 'pit' ? 2.6 : 2, dash: [null, '7 4', '2 4', '9 3 2 3'][p.jack - 1] || null };
    });
    const targets = s.probes.filter((p) => p.attached && p.targetF !== null && p.targetF !== undefined)
      .map((p) => ({ value: p.targetF, color: seriesColor(p.jack), label: fmtTemp(p.targetF, 0) }));
    const marks = (s.marks || []).map((mk) => ({ x: (mk.atMs - started) / 60000 })).filter((m) => m.x >= xMin);
    lastChart = { series: series.map((sr) => ({ name: probeName(s.probes.find((p) => p.jack === sr.probe), cook), points: sr.points })), xMin: xMin, xMax: xMax, started: started };

    let html = '<div class="seg-chips mb3">' + ['15m', '1h', '6h', 'all'].map((r) =>
      '<button class="chip' + (state.chartRange === r ? ' on' : '') + '" data-action="chart-range" data-range="' + r + '">' + r + '</button>').join('') + '</div>';
    html += '<div class="chart-wrap"><div class="chart" id="chartHost">' + buildChart(series, {
      xMin: xMin, xMax: xMax, targets: targets, marks: marks, now: elapsed, isolated: state.isolatedProbe,
      xLabels: (v) => fmtClock(started + v * 60000),
    }) + '<div class="crosshair-tip" id="chartTip"></div></div>';
    html += '<div class="legend">' + s.probes.map((p) => {
      if (!p.attached) return '';
      const dim = state.isolatedProbe && state.isolatedProbe !== p.jack;
      return '<button class="legend-item' + (dim ? ' dim' : '') + '" data-action="isolate" data-jack="' + p.jack + '">' +
        '<span class="legend-swatch" style="' + legendSwatch(p.jack) + '"></span>' +
        '<span class="lg-name">' + esc(probeName(p, cook)) + '</span><span class="lg-val">' + fmtTemp(p.tempF) + '</span></button>';
    }).join('') + '</div></div>';

    html += '<div class="section-label">' + icon('activity', 13) + 'Window statistics</div><div class="card">';
    s.probes.filter((p) => p.attached).forEach((p, idx, arr) => {
      html += '<div class="row between" style="padding:8px 0' + (idx < arr.length - 1 ? ';border-bottom:1px solid var(--hairline)' : '') + '">' +
        '<div class="row" style="gap:8px"><span class="jack-badge p' + p.jack + '">' + p.jack + '</span><span class="hi bold small">' + esc(probeName(p, cook)) + '</span></div>' +
        '<div class="row" style="gap:14px">' + statMini('High', fmtTemp(p.peakF, 0)) + statMini('Avg', fmtTemp(p.avgF, 0)) + statMini('Low', fmtTemp(p.lowF, 0)) + '</div></div>';
    });
    html += '</div>';
    html += '<div class="btn-row mt3"><button class="btn" data-action="open-mark">' + icon('bookmark') + 'Add mark</button>' +
      '<button class="btn ghost" data-action="export">' + icon('download') + 'Export CSV</button></div>';
    return html;
  }
  function statMini(label, val) { return '<div class="center"><div class="tiny muted">' + label + '</div><div class="mono hi small">' + val + '</div></div>'; }

  // [BIZ] Hue is never the only identity channel: each probe also owns a
  // stroke pattern (P1 solid, P2 dashed, P3 dotted, P4 dash-dot) that survives
  // a monochrome export. The legend swatch must show it too.
  function legendSwatch(jack) {
    const c = seriesColor(jack);
    if (jack === 1) return 'background:' + c;
    if (jack === 2) return 'background-image:repeating-linear-gradient(90deg,' + c + ' 0 4px,transparent 4px 7px)';
    if (jack === 3) return 'background-image:repeating-linear-gradient(90deg,' + c + ' 0 2px,transparent 2px 5px)';
    return 'background-image:repeating-linear-gradient(90deg,' + c + ' 0 5px,transparent 5px 6px,' + c + ' 6px 8px,transparent 8px 9px)';
  }

  function probeName(p, cook) {
    if (p.role === 'pit') return 'Grate · jack 4';
    if (p.role === 'unused') return 'Jack ' + p.jack + ' · unused';
    const it = (cook.items || []).find((i) => i.jack === p.jack);
    const cat = it ? catalogById(it.id) : null;
    return cat ? cat.name : 'Probe ' + p.jack;
  }

  // ---- Cooks / history -----------------------------------------------------
  function viewCooks() {
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
          '<div class="cc-sub"><span>' + fmtDay(h.startedAtMs) + '</span><span>' + fmtDuration(h.durationMin * 60000) + '</span><span>' + h.marks + ' marks</span></div></div>' +
          '<div class="cc-right"><div class="cc-peak">' + fmtTemp(h.peakF, 0) + '</div><div class="cc-peak-label">peak</div></div>' + icon('chevronRight') + '</div>').join('') + '</div>';
    });
    return html;
  }

  function viewCookDetail() {
    const h = M.HISTORY.find((x) => x.id === state.selectedCookId) || M.HISTORY[0];
    let html = '<div class="card"><div class="cook-head">' + foodAvatar(h.glyph, 'lg') +
      '<div class="ch-meta"><div class="ch-name">' + esc(h.name) + '</div>' +
      '<div class="ch-line">' + fmtDay(h.startedAtMs) + ' · ' + fmtClock(h.startedAtMs) + ' · ' + fmtDuration(h.durationMin * 60000) + '</div>' +
      '<div class="stars mt1">' + '★'.repeat(h.rating) + '☆'.repeat(5 - h.rating) + '</div></div>' +
      '<button class="icon-btn" data-action="toggle-fav" data-id="' + h.id + '">' + icon('bookmark') + '</button></div></div>';
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
      '<button class="btn ghost" data-action="export">' + icon('download') + 'Export</button></div>';
    html += '<button class="btn danger mt3" data-action="delete-cook">' + icon('trash') + 'Delete cook</button>';
    return html;
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

  // ---- Device --------------------------------------------------------------
  function viewDevice() {
    const s = scenario(), c = s.connection, online = c.state === 'connected';
    const mode = M.MODES.find((m) => m.id === c.mode) || M.MODES[0];
    let html = '<div class="card"><div class="card-head">' + icon('link') + '<div class="card-title">' + esc(c.deviceName) + '</div>' +
      '<span class="spacer"></span><span class="pulse-dot ' + (online ? '' : 'idle') + '"></span></div>' +
      devRow('Mode', esc(mode.name)) + devRow('Phone → bridge', signalBars(c.bleBars !== null ? c.bleBars : c.routerBars)) +
      (c.mode === 'sta' ? devRow('Bridge → router', signalBars(c.routerBars)) : '') +
      devRow('Battery', c.batteryPct === null ? '—' : c.batteryPct + '%') +
      devRow('Recording', c.recording ? 'Yes — on the bridge' : 'No') +
      '<div class="btn-row mt4"><button class="btn" data-action="resync">' + icon('refresh') + 'Re-sync</button>' +
      '<button class="btn ghost" data-action="open-modes">' + icon('sliders') + 'Change mode</button></div>' +
      '<button class="btn ghost mt2" data-action="disconnect">' + icon('unlink') + 'Disconnect</button></div>';
    html += '<div class="section-label">How you are connected</div><div class="cap-notice">' + icon('info') +
      '<div class="cn-text">' + esc(mode.summary) + '</div></div>';
    html += '<div class="section-label">Settings</div><div class="card">' +
      setRow('thermometer', 'Units', 'Temperatures in ' + (state.units === 'C' ? 'Celsius' : 'Fahrenheit'),
        '<button class="chip' + (state.units === 'F' ? ' on' : '') + '" data-action="set-units" data-units="F">°F</button>' +
        '<button class="chip' + (state.units === 'C' ? ' on' : '') + '" data-action="set-units" data-units="C">°C</button>') +
      setRow('sun', 'Display profile', state.themeProfile === 'daylight' ? 'Daylight (high contrast)' : 'Dark (default)',
        '<button class="chip' + (state.themeProfile === 'dark' ? ' on' : '') + '" data-action="set-theme" data-theme="dark">Dark</button>' +
        '<button class="chip' + (state.themeProfile === 'daylight' ? ' on' : '') + '" data-action="set-theme" data-theme="daylight">Sun</button>') +
      setRow('bell', 'Alarms & monitoring', state.settings.monitoring ? 'Watching in the background' : 'Off', icon('chevronRight'), 'open-alerts') +
      setRow('key', 'Prefer my own alarms', 'Manual alarms win over device rules', toggle('preferManualAlarm')) +
      setRow('moon', 'Quiet hours', 'Silences warning & info 10pm–6am. Critical always sounds', toggle('quietHours')) +
      setRow('link', 'Keep Bluetooth warm', 'Faster failover while on Wi-Fi', toggle('holdBle')) +
      setRow('calendar', 'Wrap / spritz reminders', 'Use the expected timeline for nudges', toggle('autoWrapReminder')) + '</div>';
    html += '<div class="section-label">Bridge</div><div class="card">' +
      setRow('cpu', 'Firmware', 'v1.4.2 · up to date', icon('chevronRight')) +
      setRow('upload', 'Update firmware', 'Over Wi-Fi only', icon('chevronRight')) +
      setRow('info', 'About & diagnostics', 'Device id, signal, logs', icon('chevronRight')) + '</div>';
    html += '<div class="card subtle mt3"><div class="tiny muted">A bridge with no clock stores no timestamp — never a made-up one. A detached probe is absent, never 0.</div></div>';
    return html;
  }
  function devRow(k, v) { return '<div class="row between small mt2"><span class="muted">' + k + '</span><span class="hi">' + v + '</span></div>'; }
  function signalBars(n) {
    if (n === null || n === undefined) return '—';
    let s = '';
    for (let i = 1; i <= 4; i++) s += '<span style="display:inline-block;width:4px;height:' + (4 + i * 3) + 'px;margin-left:2px;border-radius:1px;background:' + (i <= n ? 'var(--text-hi)' : 'rgba(255,255,255,0.16)') + '"></span>';
    return '<span style="display:inline-flex;align-items:flex-end">' + s + '</span>';
  }
  function setRow(ic, name, sub, right, action) {
    return '<div class="set-row"' + (action ? ' data-action="' + action + '"' : '') + '><div class="sr-icon">' + icon(ic) + '</div>' +
      '<div class="sr-meta"><div class="sr-name">' + name + '</div><div class="sr-sub">' + sub + '</div></div>' +
      '<div class="sr-right">' + right + '</div></div>';
  }
  function toggle(key, on) {
    const v = state.settings[key] !== undefined ? state.settings[key] : !!on;
    return '<button class="toggle' + (v ? ' on' : '') + '" data-action="toggle-setting" data-key="' + key + '"></button>';
  }
  function emptyState(title, copy, action, actionLabel, ic) {
    return '<div class="state"><div class="st-art">' + icon(ic || 'calendar', 34) + '</div>' +
      '<div class="st-title">' + esc(title) + '</div><div class="st-copy">' + esc(copy) + '</div>' +
      (action ? '<button class="btn primary" style="width:auto" data-action="' + action + '">' + icon('plus') + esc(actionLabel) + '</button>' : '') + '</div>';
  }

  // =================================================== §7 RENDER: OVERLAYS ====
  function renderOverlays() {
    const host = $('#overlays');
    const o = state.overlay;
    if (!o) { host.innerHTML = ''; return; }
    const map = {
      onboarding: overlayOnboarding, setup: overlaySetup, connect: overlayConnect,
      modes: overlayModes, alarms: overlayAlarms, mark: overlayMark,
      probe: overlayProbe, adopt: overlayAdopt, editStart: overlayEditStart,
    };
    host.innerHTML = (map[o.name] || (() => ''))(o.props || {});
    if (o.name === 'graph') { /* no-op */ }
  }
  function openOverlay(name, props) { state.overlay = { name: name, props: props || {} }; renderOverlays(); }
  function closeOverlay() { state.overlay = null; renderOverlays(); }
  function scrim(inner, center) { return '<div class="scrim open' + (center ? ' center' : '') + '" data-action="scrim-click">' + inner + '</div>'; }

  // ---- Onboarding wizard ---------------------------------------------------
  // [BIZ] The passkey is shown ONLY on the device OLED. The app cannot render a
  // real code, so it coaches the user BEFORE Android's own (wrong) dialog,
  // which says "Usually 0000 or 1234".
  function overlayOnboarding() {
    const steps = ['welcome', 'preflight', 'scan', 'passkey', 'sync', 'network', 'name', 'done'];
    const i = state.onboardStep;
    const rail = '<div class="step-rail">' + steps.map((st, idx) =>
      '<span class="step-dot' + (idx === i ? ' on' : idx < i ? ' done' : '') + '"></span>').join('') + '</div>';
    let body = '';
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
        '<div style="flex:1"><div class="hi bold small">SmokeBridge-A4F2</div><div class="tiny muted">Strong signal · ready to pair</div></div>' + icon('chevronRight') + '</div></div>';
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
      body = '<div class="card-title">How should we stay in touch?</div><div class="body small mt2 mb3">You can change this any time from the Device tab.</div>' +
        M.MODES.map((m) => modeCard(m, m.id === 'ble')).join('');
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

  function modeCard(m, active) {
    return '<div class="mode-card' + (active ? ' on' : '') + '" data-action="set-mode" data-mode="' + m.id + '" style="margin-bottom:10px">' +
      '<div class="mode-icon">' + icon(m.icon) + '</div><div class="mode-body">' +
      '<div class="row between"><div class="mode-name">' + esc(m.name) + '</div>' + (active ? '<span class="mode-badge">Active</span>' : '') + '</div>' +
      '<div class="mode-tag">' + esc(m.tagline) + '</div><div class="mode-desc">' + esc(m.summary) + '</div>' +
      '<div class="mode-lists">' + m.good.map((g) => '<div class="mode-li good">' + esc(g) + '</div>').join('') +
      m.limited.map((g) => '<div class="mode-li limit">' + esc(g) + '</div>').join('') + '</div></div></div>';
  }

  // ---- Setup sheet (the catalog) -------------------------------------------
  // Three first-class ways to start (the brief's flexibility requirement):
  //   new      — set up before you light the fire
  //   existing — hook into data the bridge already collected
  //   watch    — no targets, just live numbers
  function overlaySetup() {
    const mode = state.setupMode, cat = state.catalog.category;
    const sel = state.catalog.selectedId ? catalogById(state.catalog.selectedId) : null;
    const don = sel ? donenessFor(sel, state.catalog.doneness) : null;
    const pull = sel ? pullTempFor(sel, don) : null;
    const cook = scenario().cook, assigned = {};
    (cook.items || []).forEach((it) => { assigned[it.jack] = it.id; });

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

    html += '<div class="tiny muted mt4 mb2">' + (mode === 'existing' ? 'WHAT IS ON THE GRILL?' : 'WHAT ARE YOU COOKING?') + '</div>' +
      '<div class="filter-row mb3">' + M.CATEGORIES.map((c) =>
        '<button class="chip' + (c === cat ? ' on' : '') + '" data-action="catalog-cat" data-cat="' + esc(c) + '">' + esc(c) + '</button>').join('') + '</div>' +
      '<div class="catalog-grid">' + catalogInCat(cat).map((item) => {
        const d = donenessFor(item, item.defaultDoneness);
        return '<button class="catalog-item' + (state.catalog.selectedId === item.id ? ' selected' : '') + '" data-action="catalog-pick" data-id="' + item.id + '">' +
          foodAvatar(item.glyph) + '<div class="ci-name">' + esc(item.name) + '</div><div class="ci-meta">' + esc(item.blurb) + '</div>' +
          '<div class="ci-temp">' + icon('target', 11) + ' ' + fmtTemp(d.targetF, 0) + ' · pit ' + item.pitBand[0] + '–' + item.pitBand[1] + '°</div></button>';
      }).join('') + '</div>';

    if (sel) {
      if (sel.doneness.length > 1) {
        html += '<div class="tiny muted mt4 mb2">DONENESS</div><div class="seg-chips">' + sel.doneness.map((d) =>
          '<button class="chip' + (donenessFor(sel, state.catalog.doneness).id === d.id ? ' on' : '') + '" data-action="doneness-pick" data-id="' + d.id + '">' + esc(d.label) + ' · ' + fmtTemp(d.targetF, 0) + '</button>').join('') + '</div>';
      }
      const carry = carryoverFor(sel), tl = timelineFor(sel.id);
      html += '<div class="card subtle mt3"><div class="row between small"><span class="muted">Target (after rest)</span><span class="hi bold">' + fmtTemp(don.targetF, 0) + '</span></div>' +
        (carry > 0 ? '<div class="row between small mt2"><span class="muted">Pull early by carryover</span><span class="hi">' + fmtTemp(pull, 0) + ' (−' + carry + '°)</span></div>' : '') +
        '<div class="row between small mt2"><span class="muted">Expected rest</span><span class="hi">' + restMinutesFor(sel) + ' min</span></div>' +
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
      '<button class="icon-btn" data-action="close-overlay">' + icon('x') + '</button></div>' +
      '<div class="sheet-body">' + inner + '</div></div>');
  }

  // ---- Connect sheet -------------------------------------------------------
  function overlayConnect() {
    const s = scenario(), c = s.connection, online = c.state === 'connected';
    const mode = M.MODES.find((m) => m.id === c.mode) || M.MODES[0];
    let body = '<div class="card"><div class="row">' + icon(online ? 'link' : 'unlink', 20) +
      '<div style="flex:1"><div class="hi bold">' + esc(c.deviceName) + '</div>' +
      '<div class="tiny muted">' + (online ? 'Connected via ' + esc(mode.name) + ' · last reading ' + ago(Date.now() - c.lastSyncS * 1000) : 'Not connected') + '</div></div>' +
      '<span class="pulse-dot ' + (online ? '' : 'idle') + '"></span></div></div>' +
      '<div class="tiny muted mt4 mb2">SWITCH MODE — ALWAYS AVAILABLE OVER BLUETOOTH</div>' +
      M.MODES.map((m) => modeCard(m, m.id === c.mode)).join('') +
      '<div class="cap-notice mt2">' + icon('info') + '<div class="cn-text">Switching to Wi-Fi happens over Bluetooth, so it works even when the bridge is not on a network. If the new mode fails, the bridge keeps its old network and Bluetooth stays as your escape hatch.</div></div>' +
      '<div class="btn primary mt4" data-action="resync">' + icon('refresh') + 'Re-sync now</div>' +
      '<button class="btn ghost mt2" data-action="disconnect">' + icon('unlink') + 'Disconnect</button>';
    return scrim('<div class="sheet"><div class="sheet-grab"></div>' +
      '<div class="sheet-head"><div style="flex:1"><div class="sh-title">Connection</div><div class="sh-sub">' + esc(c.deviceName) + '</div></div>' +
      '<button class="icon-btn" data-action="close-overlay">' + icon('x') + '</button></div><div class="sheet-body">' + body + '</div></div>');
  }

  // ---- Modes sheet ---------------------------------------------------------
  function overlayModes() {
    const c = scenario().connection;
    let html = '<div class="cap-notice">' + icon('compass') + '<div class="cn-text">Three ways to talk to the bridge. They trade range, features and battery differently — pick what fits where you cook.</div></div><div class="mt3"></div>';
    html += M.MODES.map((m) => {
      const cap = m.capability;
      return modeCard(m, m.id === c.mode) +
        '<div class="card subtle" style="margin:-4px 0 12px"><div class="tiny muted mb2">Capabilities in this mode</div>' +
        capRow('Live readings', cap.live) + capRow('2-hour preview', cap.preview) + capRow('Full history download', cap.fullHistory) +
        capRow('Alarm-rule editing', cap.rules) + capRow('Firmware update', cap.ota) + '</div>';
    }).join('');
    return scrim('<div class="sheet"><div class="sheet-grab"></div>' +
      '<div class="sheet-head"><div style="flex:1"><div class="sh-title">Connection modes</div><div class="sh-sub">Switch any time — the app stays reachable</div></div>' +
      '<button class="icon-btn" data-action="close-overlay">' + icon('x') + '</button></div><div class="sheet-body">' + html + '</div></div>');
  }
  function capRow(label, ok) {
    return '<div class="row between small" style="padding:3px 0"><span class="body">' + label + '</span>' +
      (ok ? '<span style="color:var(--positive)">' + icon('check', 15) + '</span>' : '<span class="muted">—</span>') + '</div>';
  }

  // ---- Alarms sheet --------------------------------------------------------
  // [BIZ] Two visibly separate tiers (I2):
  //   DEVICE  — the nine rules on the ESP32, authoritative. The app mirrors.
  //   APP     — advisory only (ETA soon, stall, unreachable). Never re-decides.
  function overlayAlarms() {
    const s = scenario();
    const active = (s.alarms || []).filter((a) => !a.acked && !state.pendingAck[a.id]);
    let html = '';
    if (active.length) {
      html += '<div class="section-label" style="margin-top:0">Active now</div>';
      html += active.map((a) => {
        const ic = a.severity === 'critical' ? 'alertCircle' : a.severity === 'warning' ? 'alertTriangle' : 'info';
        return '<div class="alarm-bar ' + a.severity + '" style="cursor:default">' + '<span class="al-icon">' + icon(ic) + '</span>' +
          '<div class="al-text"><div class="al-title">' + esc(a.rule) + ' ' + (a.tier === 'device' ? '<span class="tier-tag device">Device</span>' : '<span class="tier-tag app">Advisory</span>') + '</div>' +
          '<div class="al-detail">' + esc(a.detail) + '</div></div>' +
          '<button class="al-ack" data-action="ack-alarm" data-id="' + a.id + '">Acknowledge</button></div>';
      }).join('');
    } else {
      html += '<div class="cap-notice">' + icon('check') + '<div class="cn-text">No active alarms. The bridge is watching with or without this app.</div></div>';
    }
    html += '<div class="section-label">Delivery</div>' +
      '<div class="card"><div class="row"><span style="color:var(--positive)">' + icon('bell', 20) + '</span>' +
      '<div style="flex:1"><div class="hi bold small">This phone will wake you</div><div class="tiny muted">Notifications allowed · critical alarms bypass quiet hours</div></div></div>' +
      '<button class="btn ghost sm mt3" data-action="test-alarm">' + icon('zap') + 'Send a test alarm</button></div>';

    html += '<div class="section-label">Device rules <span class="spacer"></span><span class="tiny muted">authoritative</span></div><div class="card">' +
      M.ALARM_RULES.filter((r) => r.tier === 'device').map((r) =>
        '<div class="set-row"><div class="sr-icon">' + icon(r.severity === 'critical' ? 'alertCircle' : 'alertTriangle') + '</div>' +
        '<div class="sr-meta"><div class="sr-name">' + r.name + '</div><div class="sr-sub">' + r.desc + ' · ' + r.scoped + '</div></div>' +
        '<div class="sr-right">' + toggle('__dev_' + r.id, r.enabled) + '</div></div>').join('') + '</div>';

    html += '<div class="section-label">App advisories <span class="spacer"></span><span class="tiny muted">never overrides the device</span></div><div class="card">' +
      M.ALARM_RULES.filter((r) => r.tier === 'app').map((r) =>
        '<div class="set-row"><div class="sr-icon">' + icon('info') + '</div>' +
        '<div class="sr-meta"><div class="sr-name">' + r.name + '</div><div class="sr-sub">' + r.desc + '</div></div>' +
        '<div class="sr-right">' + toggle('__app_' + r.id, r.enabled) + '</div></div>').join('') + '</div>';

    html += '<div class="section-label">Preferences</div><div class="card">' +
      setRow('key', 'Prefer my own alarms', 'Your manual alarms win over the device rules', toggle('preferManualAlarm')) +
      setRow('moon', 'Quiet hours', 'Silence warning & info 10pm–6am · critical always sounds', toggle('quietHours')) +
      setRow('bell', 'Background monitoring', 'Check on the bridge and bubble up alarms', toggle('monitoring')) + '</div>';
    return scrim('<div class="sheet"><div class="sheet-grab"></div>' +
      '<div class="sheet-head"><div style="flex:1"><div class="sh-title">Alarms</div><div class="sh-sub">Device rules and app advisories, kept separate</div></div>' +
      '<button class="icon-btn" data-action="close-overlay">' + icon('x') + '</button></div><div class="sheet-body">' + html + '</div></div>');
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
      '<div class="card inset mt3"><div class="tiny muted mb2">Add a note (optional)</div><div class="body small">Wrapped the brisket in butcher paper…</div></div>' +
      '<div class="btn primary mt4" data-action="close-overlay">' + icon('check') + 'Save mark</div>';
    return scrim('<div class="sheet"><div class="sheet-grab"></div>' +
      '<div class="sheet-head"><div style="flex:1"><div class="sh-title">Add a mark</div><div class="sh-sub">A timestamped event on this cook</div></div>' +
      '<button class="icon-btn" data-action="close-overlay">' + icon('x') + '</button></div><div class="sheet-body">' + html + '</div></div>');
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

    if (!isGrate && p.targetF !== null && p.targetF !== undefined) {
      html += '<div class="card subtle mt3">' + phaseTrack(p) + '</div>';
    }
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
      '<button class="btn ghost mt2" data-action="export">' + icon('share') + 'Export this probe</button>';
    return scrim('<div class="sheet"><div class="sheet-grab"></div>' +
      '<div class="sheet-head"><div style="flex:1"><div class="sh-title">Probe ' + jack + '</div><div class="sh-sub">' + (cat ? esc(cat.name) : 'Jack details') + '</div></div>' +
      '<button class="icon-btn" data-action="close-overlay">' + icon('x') + '</button></div><div class="sheet-body">' + html + '</div></div>');
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

  // =============================================== §8 ACTIONS + DELEGATION ====
  function toast(msg) {
    const t = $('#toast');
    t.textContent = msg; t.classList.add('show');
    clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove('show'), 2200);
  }
  function go(screen) { state.screen = screen; render(); $('#view').scrollTop = 0; }

  function startCook(mode) {
    const s = scenario();
    const sel = catalogById(state.catalog.selectedId);
    if (!sel) { toast('Pick a food first'); return; }
    const don = donenessFor(sel, state.catalog.doneness);
    const start = mode === 'existing' && s.pendingSession ? s.pendingSession.startedAtMs : Date.now();
    s.cook.active = true; s.cook.paused = false;
    s.cook.name = sel.name + (mode === 'existing' ? ' (adopted)' : ' cook');
    s.cook.startedAtMs = start;
    s.cook.grateTargetF = s.cook.grateTargetF || 250;
    s.cook.items = (s.cook.items || []).filter((it) => it.jack !== state.catalog.jack);
    s.cook.items.push({ id: sel.id, jack: state.catalog.jack, addedAtMs: start });
    const p = s.probes.find((pp) => pp.jack === state.catalog.jack);
    if (p) { p.role = 'food'; p.attached = true; p.targetF = don.targetF; p.pullF = pullTempFor(sel, don); p.freshness = 'live'; if (p.tempF === null) p.tempF = 60; }
    const pulled = mode === 'existing' && s.pendingSession ? s.pendingSession.samples : 0;
    s.pendingSession = null;
    closeOverlay();
    go('live');
    toast(mode === 'existing' ? 'Cook adopted · pulled ' + pulled + ' samples' : sel.name + ' cook started');
  }

  document.addEventListener('click', function (e) {
    const el = e.target.closest('[data-action]');
    if (!el) return;
    const a = el.dataset.action;
    const s = scenario();
    switch (a) {
      case 'nav': go(el.dataset.screen); break;
      case 'back': go('cooks'); break;
      case 'dev-screen': go(el.dataset.screen); break;
      case 'scenario': {
        const key = el.dataset.key;
        M.SCENARIOS[key] = JSON.parse(JSON.stringify(SCEN_TEMPLATE[key]));
        state.scenarioKey = key; closeOverlay(); render(); break;
      }
      case 'open-overlay': openOverlay(el.dataset.name); break;
      case 'close-overlay': closeOverlay(); break;
      case 'scrim-click': if (e.target === el) closeOverlay(); break;
      case 'open-connect': openOverlay('connect'); break;
      case 'open-modes': openOverlay('modes'); break;
      case 'open-alerts': openOverlay('alarms'); break;
      case 'open-mark': openOverlay('mark'); break;
      case 'open-setup': state.catalog.selectedId = state.catalog.selectedId || null; openOverlay('setup'); break;
      case 'open-probe': openOverlay('probe', { jack: Number(el.dataset.jack) }); break;
      case 'adopt': openOverlay('adopt'); break;
      case 'adopt-confirm': state.catalog.selectedId = state.catalog.selectedId || 'beef_brisket'; state.catalog.jack = 1; startCook('existing'); break;
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
      case 'catalog-cat': state.catalog.category = el.dataset.cat; state.catalog.selectedId = null; renderOverlays(); break;
      case 'catalog-pick': state.catalog.selectedId = el.dataset.id; state.catalog.doneness = null; renderOverlays(); break;
      case 'doneness-pick': state.catalog.doneness = el.dataset.id; renderOverlays(); break;
      case 'catalog-jack': state.catalog.jack = Number(el.dataset.jack); renderOverlays(); break;
      case 'start-cook': startCook('new'); break;
      case 'start-existing': startCook('existing'); break;
      case 'start-watch': s.cook.active = false; closeOverlay(); go('live'); toast('Watching live — no cook set'); break;
      case 'ack-alarm': state.pendingAck[el.dataset.id] = true; render(); toast('Alarm acknowledged'); break;
      case 'test-alarm': toast('Test alarm sent to your phone'); break;
      case 'set-units': state.units = el.dataset.units; render(); break;
      case 'set-theme': state.themeProfile = el.dataset.theme; render(); break;
      case 'toggle-setting': {
        const k = el.dataset.key;
        if (k.indexOf('__') === 0) { toast('Rule toggled'); break; }
        state.settings[k] = !state.settings[k]; render(); break;
      }
      case 'set-mode': {
        const id = el.dataset.mode, m = M.MODES.find((x) => x.id === id);
        s.connection.mode = id; s.connection.state = 'connected'; s.connection.lastSyncS = 0;
        if (id === 'ble') { s.connection.bleBars = 3; s.connection.routerBars = null; }
        else if (id === 'ap') { s.connection.bleBars = null; s.connection.routerBars = 4; }
        else { s.connection.bleBars = null; s.connection.routerBars = 4; }
        closeOverlay(); render(); toast('Switched to ' + m.name); break;
      }
      case 'resync': s.connection.state = 'connected'; s.connection.lastSyncS = 0; render(); toast('Re-synced · up to date'); break;
      case 'disconnect': s.connection.state = 'offline'; s.connection.lastSyncS = 30; closeOverlay(); render(); toast('Disconnected — the bridge keeps recording'); break;
      case 'chart-range': state.chartRange = el.dataset.range; render(); break;
      case 'isolate': state.isolatedProbe = state.isolatedProbe === Number(el.dataset.jack) ? null : Number(el.dataset.jack); render(); break;
      case 'select-cook': state.selectedCookId = el.dataset.id; go('cookDetail'); break;
      case 'toggle-fav': { const h = M.HISTORY.find((x) => x.id === el.dataset.id); h.favourite = !h.favourite; render(); break; }
      case 'repeat-cook': {
        const h = M.HISTORY.find((x) => x.id === el.dataset.id);
        state.catalog.selectedId = h.presetId; state.catalog.category = catalogById(h.presetId).category; state.catalog.doneness = null; state.catalog.jack = 1;
        state.setupMode = 'new'; openOverlay('setup'); break;
      }
      case 'delete-cook': toast('Deleted (mock)'); go('cooks'); break;
      case 'export': toast('Exporting CSV — works offline'); break;
      case 'mark-kind': { const k = el.dataset.kind; closeOverlay(); toast('Marked: ' + k.replace('_', ' ')); break; }
      case 'mark-pulled': closeOverlay(); toast('Pulled — rest timer started'); break;
      case 'probe-role': { const p = s.probes.find((x) => x.jack === Number(el.dataset.jack)); p.role = el.dataset.role; render(); break; }
      case 'onboard-next': state.onboardStep = Math.min(7, state.onboardStep + 1); renderOverlays(); break;
      case 'onboard-prev': state.onboardStep = Math.max(0, state.onboardStep - 1); renderOverlays(); break;
      case 'finish-onboard': state.onboardStep = 0; closeOverlay(); go('live'); toast('Welcome — you are connected'); break;
      default: break;
    }
  });

  // ---- Chart crosshair -----------------------------------------------------
  let lastChart = null;
  function wireChart() {
    const host = document.getElementById('chartHost');
    const tip = document.getElementById('chartTip');
    if (!host || !tip || !lastChart) return;
    const svg = host.querySelector('svg');
    if (!svg) return;
    host.onmousemove = function (ev) {
      const rect = svg.getBoundingClientRect();
      const vbx = ((ev.clientX - rect.left) / rect.width) * 340;
      const frac = (vbx - 30) / (340 - 30 - 12);
      const t = lastChart.xMin + frac * (lastChart.xMax - lastChart.xMin);
      let rows = '', nearestT = t;
      lastChart.series.forEach((sr) => {
        let best = null, bd = Infinity;
        sr.points.forEach((p) => { const d = Math.abs(p.x - t); if (d < bd) { bd = d; best = p; } });
        if (best) { nearestT = best.x; rows += '<div class="ct-row"><span class="ct-name">' + esc(sr.name) + '</span><span class="ct-val">' + fmtTemp(best.y) + '</span></div>'; }
      });
      tip.innerHTML = '<div class="ct-time">' + fmtClock(lastChart.started + nearestT * 60000) + '</div>' + rows;
      tip.style.display = 'block';
      const tw = 150;
      tip.style.left = Math.min(rect.width - tw, Math.max(0, ev.clientX - rect.left + 10)) + 'px';
      tip.style.top = '8px';
    };
    host.onmouseleave = function () { tip.style.display = 'none'; };
  }

  // ======================================================== §9 BOOT + TICK ====
  const SCEN_TEMPLATE = JSON.parse(JSON.stringify(M.SCENARIOS));

  function renderDev() {
    const scen = Object.keys(M.SCENARIOS).map((k) =>
      '<button class="dp-btn' + (state.scenarioKey === k ? ' on' : '') + '" data-action="scenario" data-key="' + k + '">' + esc(M.SCENARIOS[k].label) + '</button>').join('');
    $('#dpScenarios').innerHTML = scen;
    const screens = ['live', 'timeline', 'graph', 'cooks', 'device'];
    $('#dpScreens').innerHTML = screens.map((sc) =>
      '<button class="dp-btn' + (state.screen === sc ? ' on' : '') + '" data-action="dev-screen" data-screen="' + sc + '">' + sc + '</button>').join('');
    const overlays = [['onboarding', 'Onboarding'], ['setup', 'Cook setup'], ['connect', 'Connection'], ['modes', 'Modes'], ['alarms', 'Alarms'], ['mark', 'Add mark'], ['adopt', 'Adopt session'], ['editStart', 'Edit start']];
    $('#dpOverlays').innerHTML = overlays.map((o) =>
      '<button class="dp-btn" data-action="open-overlay" data-name="' + o[0] + '">' + o[1] + '</button>').join('');
    $('#dpSettings').innerHTML =
      '<button class="dp-btn" data-action="set-units" data-units="' + (state.units === 'F' ? 'C' : 'F') + '">Units: ' + state.units + ' → ' + (state.units === 'F' ? 'C' : 'F') + '</button>' +
      '<button class="dp-btn" data-action="set-theme" data-theme="' + (state.themeProfile === 'dark' ? 'daylight' : 'dark') + '">Profile: ' + state.themeProfile + '</button>' +
      '<button class="dp-btn" data-action="open-connect">Simulate connection sheet</button>';
  }

  function render() {
    document.body.classList.toggle('daylight', state.themeProfile === 'daylight');
    renderAppbar(); renderNav(); renderView(); renderOverlays(); renderDev();
    if (state.screen === 'graph') wireChart();
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
  //   index.html?screen=graph&scenario=idle&overlay=setup&units=C
  try {
    if (typeof location !== 'undefined') {
      const raw = (location.search || '').replace(/^\?/, '') + '&' + (location.hash || '').replace(/^#/, '');
      const q = new URLSearchParams(raw);
      if (q.get('scenario') && M.SCENARIOS[q.get('scenario')]) state.scenarioKey = q.get('scenario');
      if (q.get('screen')) state.screen = q.get('screen');
      if (q.get('units')) state.units = q.get('units');
      if (q.get('overlay')) state.overlay = { name: q.get('overlay'), props: {} };
    }
  } catch (e) { /* deep links are a prototype nicety only */ }

  // First run: open onboarding when the app has never connected.
  render();
  setInterval(tick, 1000);
  tick();

  // Expose a couple of hooks for manual poking in the console.
  window.SMOKE_UI = { state: state, open: openOverlay, close: closeOverlay, render: render };
})();
