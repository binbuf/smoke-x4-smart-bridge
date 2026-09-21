// gen_mock_content.mjs — turn newui/mock-data.js into typed Dart content.
//
// The prototype is the reviewer-owned source of truth for the catalog, the
// cook-style packs and the small fixtures. Transcribing ~139 cuts and ~318
// styles by hand invites silent drift, so the tables are generated here and
// committed. Run from the repo root:
//
//   node app/tool/gen_mock_content.mjs
//
// Output (all committed):
//   app/lib/data/content/catalog_data.dart
//   app/lib/data/content/styles_data.dart
//   app/lib/data/content/fixtures_data.dart
//
// Hand-written Dart (not generated): the models, `normalizeTimeline`, the
// scenario builders and the repository. Regenerate whenever newui/mock-data.js
// changes; `make app.gen` is not involved (that is build_runner only).

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url)); // app/tool
const repoRoot = join(here, '..', '..');
const srcPath = join(repoRoot, 'newui', 'mock-data.js');
const outDir = join(here, '..', 'lib', 'data', 'content');

const source = readFileSync(srcPath, 'utf8');
const sandbox = { window: {} };
vm.createContext(sandbox);
vm.runInContext(source, sandbox, { filename: 'mock-data.js' });
const M = sandbox.window.MOCK;

// ── Dart emission helpers ────────────────────────────────────────────────

/** A single-quoted Dart string literal (null-safe). */
function s(v) {
  if (v === null || v === undefined) return 'null';
  return (
    "'" +
    String(v)
      .replace(/\\/g, '\\\\')
      .replace(/'/g, "\\'")
      .replace(/\$/g, '\\$')
      .replace(/\r/g, '')
      .replace(/\n/g, '\\n') +
    "'"
  );
}

const header = (note) =>
  `// GENERATED FILE — do not edit by hand.\n` +
  `//\n` +
  `// Produced by \`node app/tool/gen_mock_content.mjs\` from\n` +
  `// \`newui/mock-data.js\` (the reviewer-owned prototype data). ${note}\n` +
  `// ignore_for_file: lines_longer_than_80_chars\n\n`;

const hazardName = (h) => `HazardClass.${h}`;
const thicknessName = (t) => `CutThickness.${t}`;

function donenessList(list) {
  return (
    '[' +
    list
      .map(
        (d) =>
          `Doneness(id: ${s(d.id)}, label: ${s(d.label)}, targetF10: ${
            d.targetF * 10
          })`,
      )
      .join(', ') +
    ']'
  );
}

function seed(it) {
  if (!it.tl) return 'null';
  const tl = it.tl;
  const parts = [];
  if (tl.total) {
    parts.push(`totalMin: MinuteRange(${tl.total[0]}, ${tl.total[1]})`);
  }
  if (tl.stall) {
    parts.push(
      `stall: StallSeed(minF10: ${tl.stall[0] * 10}, maxF10: ${
        tl.stall[1] * 10
      }, durMinLo: ${tl.stall[2]}, durMinHi: ${tl.stall[3]})`,
    );
  }
  if (tl.wrap) {
    parts.push(
      `wrap: WrapStep(tempF10: ${tl.wrap[0] * 10}, label: ${s(
        tl.wrap[1],
      )}, note: ${s(tl.wrap[2])})`,
    );
  }
  const spritzSpecified = Object.prototype.hasOwnProperty.call(tl, 'spritz');
  if (spritzSpecified) {
    if (tl.spritz !== null) {
      parts.push(`spritzEveryMin: ${tl.spritz}`);
    }
    parts.push('spritzSpecified: true');
  }
  if (tl.turn) {
    parts.push(
      `turn: TurnStep(elapsedMin: ${tl.turn.elapsedMin}, note: ${s(
        tl.turn.note,
      )})`,
    );
  }
  if (tl.rest !== undefined) {
    parts.push(`restMin: ${tl.rest}`);
  }
  if (tl.on) parts.push(`onNote: ${s(tl.on)}`);
  if (tl.pull) parts.push(`pullNote: ${s(tl.pull)}`);
  return `TimelineSeed(${parts.join(', ')})`;
}

function catalogFile() {
  const rows = M.CATALOG.map((it) => {
    const pit = it.pitBand || [225, 275];
    return (
      `  CatalogEntry(\n` +
      `    id: ${s(it.id)},\n` +
      `    category: ${s(it.category)},\n` +
      `    name: ${s(it.name)},\n` +
      `    glyph: ${s(it.glyph)},\n` +
      `    hazard: ${hazardName(it.hazard)},\n` +
      `    thickness: ${thicknessName(it.thickness)},\n` +
      `    pitBandMinF10: ${pit[0] * 10},\n` +
      `    pitBandMaxF10: ${pit[1] * 10},\n` +
      `    blurb: ${s(it.blurb)},\n` +
      `    doneness: ${donenessList(it.doneness)},\n` +
      `    defaultDonenessId: ${s(it.defaultDoneness)},\n` +
      `    tl: ${seed(it)},\n` +
      `  ),`
    );
  });
  return (
    header('Catalog + categories.') +
    `import '../../domain/domain.dart';\n` +
    `import '../model/catalog_entry.dart';\n\n` +
    `/// The 10 categories, in picker order.\n` +
    `const List<String> kCategories = [${M.CATEGORIES.map(s).join(', ')}];\n\n` +
    `/// The catalog, reviewer-owned. Every cut carries a doneness ladder; some\n` +
    `/// have no \`tl\` seed and are synthesised by \`normalizeTimeline\`.\n` +
    `const List<CatalogEntry> kCatalog = [\n${rows.join('\n')}\n];\n\n` +
    `/// The named reviewer for the catalog table (NOTES §4; same class of data\n` +
    `/// as \`presets.dart\`).\n` +
    `const String kCatalogReviewer = ${s(
      'Smoke X4 product review — catalog recipes, 2026-09',
    )};\n`
  );
}

function stylesFile() {
  const keys = Object.keys(M.STYLES);
  const blocks = keys.map((presetId) => {
    const styles = M.STYLES[presetId].map((st) => {
      const parts = [
        `id: ${s(st.id)}`,
        `name: ${s(st.name)}`,
        `region: ${s(st.region)}`,
      ];
      if (st.tagline) parts.push(`tagline: ${s(st.tagline)}`);
      parts.push(`pitBandMinF10: ${st.pitBand[0] * 10}`);
      parts.push(`pitBandMaxF10: ${st.pitBand[1] * 10}`);
      parts.push(`targetF10: ${st.targetF * 10}`);
      if (st.wrap) {
        parts.push(
          `wrap: WrapStep(tempF10: ${st.wrap[0] * 10}, label: ${s(
            st.wrap[1],
          )}, note: ${s(st.wrap[2])})`,
        );
      }
      if (st.spritz !== null) parts.push(`spritzEveryMin: ${st.spritz}`);
      if (st.restMin !== 0) parts.push(`restMin: ${st.restMin}`);
      if (st.note) parts.push(`note: ${s(st.note)}`);
      return `    CookStyle(${parts.join(', ')}),`;
    });
    return `  ${s(presetId)}: [\n${styles.join('\n')}\n  ],`;
  });
  return (
    header('Cook-style packs, keyed by preset id.') +
    `import '../../domain/domain.dart';\n\n` +
    `/// Every named style, keyed by the catalog id it prepares.\n` +
    `const Map<String, List<CookStyle>> kStylesByPreset = {\n` +
    `${blocks.join('\n')}\n};\n\n` +
    `/// The named reviewer for the style table.\n` +
    `const String kStylesReviewer = ${s(
      'Smoke X4 product review — regional style packs, 2026-09',
    )};\n`
  );
}

function stringList(items) {
  return `[${items.map(s).join(', ')}]`;
}

function fixturesFile() {
  const history = M.HISTORY.map((h) => {
    const parts = [
      `id: ${s(h.id)}`,
      `name: ${s(h.name)}`,
      `presetId: ${s(h.presetId)}`,
      `styleId: ${s(h.styleId)}`,
      `glyph: ${s(h.glyph)}`,
      `jack: ${h.jack}`,
      `startedAgoMin: ${Math.round((Date.now() - h.startedAtMs) / 60000)}`,
      `durationMin: ${h.durationMin}`,
      `plannedMin: ${h.plannedMin}`,
      `peakF10: ${Math.round(h.peakF * 10)}`,
      `targetF10: ${h.targetF * 10}`,
    ];
    if (h.favourite) parts.push(`favourite: true`);
    if (h.notes) parts.push(`notes: ${s(h.notes)}`);
    if (h.marks !== 0) parts.push(`marks: ${h.marks}`);
    if (h.rating !== 0) parts.push(`rating: ${h.rating}`);
    if (h.status !== 'done') parts.push(`status: ${s(h.status)}`);
    if (h.photos !== 0) parts.push(`photos: ${h.photos}`);
    if (h.stalledMin !== 0) parts.push(`stalledMin: ${h.stalledMin}`);
    if (h.wrapAtF !== null) parts.push(`wrapAtF10: ${h.wrapAtF * 10}`);
    return `  HistorySeed(${parts.join(', ')}),`;
  });

  const modes = M.MODES.map((m) => {
    const c = m.capability;
    return (
      `  ConnectionMode(\n` +
      `    id: ${s(m.id)}, icon: ${s(m.icon)}, name: ${s(m.name)},\n` +
      `    tagline: ${s(m.tagline)}, summary: ${s(m.summary)},\n` +
      `    good: ${stringList(m.good)}, limited: ${stringList(m.limited)},\n` +
      `    capability: ModeCapability(live: ${c.live}, preview: ${c.preview}, ` +
      `fullHistory: ${c.fullHistory}, config: ${c.config}, rules: ${c.rules}, ` +
      `ota: ${c.ota}),\n` +
      `    requiresWifiCreds: ${m.requiresWifiCreds},\n` +
      `  ),`
    );
  });

  const rules = M.ALARM_RULES.map((r) => {
    const parts = [
      `id: ${s(r.id)}`,
      `tier: AlarmTier.${r.tier}`,
      `name: ${s(r.name)}`,
      `desc: ${s(r.desc)}`,
      `severity: AlarmSeverity.${r.severity}`,
    ];
    if (!r.enabled) parts.push(`enabled: false`);
    parts.push(
      `scope: AlarmScope.${r.scoped.replace(/\s+/g, '').replace('perprobe', 'perProbe')}`,
    );
    if (r.windowS !== null) parts.push(`windowS: ${r.windowS}`);
    return `  AlarmRule(${parts.join(', ')}),`;
  });

  const events = M.EVENTS.map(
    (e) =>
      `  MockEventSpec(id: ${s(e.id)}, label: ${s(e.label)}, hint: ${s(e.hint)}),`,
  );

  const dev = M.DEVICE;
  const storage = dev.storage;
  const logs = dev.logs
    .map(
      (l) =>
        `    DeviceLog(t: ${s(l.t)}, level: ${s(l.level)}, text: ${s(l.text)}),`,
    )
    .join('\n');

  return (
    header('Small fixtures: history, modes, alarm rules, device, firmware.') +
    `import '../model/alarm.dart';\n` +
    `import '../model/alarm_rule.dart';\n` +
    `import '../model/connection_mode.dart';\n` +
    `import '../model/device_info.dart';\n` +
    `import '../model/history_entry.dart';\n` +
    `import '../model/mock_event.dart';\n\n` +
    `/// Past cooks, relative to "now" when the repository is built.\n` +
    `const List<HistorySeed> kHistorySeeds = [\n${history.join('\n')}\n];\n\n` +
    `/// The three connection modes and their capability flags.\n` +
    `const List<ConnectionMode> kConnectionModes = [\n${modes.join('\n')}\n];\n\n` +
    `/// Nine device rules + three app insights.\n` +
    `const List<AlarmRule> kAlarmRules = [\n${rules.join('\n')}\n];\n\n` +
    `/// The mock event-bus catalogue the dev panel fires.\n` +
    `const List<MockEventSpec> kMockEvents = [\n${events.join('\n')}\n];\n\n` +
    `/// Device identity and diagnostics fixture.\n` +
    `const DeviceInfo kDevice = DeviceInfo(\n` +
    `  id: ${s(dev.id)}, hardware: ${s(dev.hardware)}, version: ${s(
      dev.version,
    )},\n` +
    `  versionDate: ${s(dev.versionDate)}, bootloader: ${s(dev.bootloader)},\n` +
    `  channel: DeviceChannel.${dev.channel}, uptimeMin: ${dev.uptimeMin}, ` +
    `heapKb: ${dev.heapKb},\n` +
    `  storage: DeviceStorage(usedKb: ${storage.usedKb}, totalKb: ${
      storage.totalKb
    }, sessions: ${storage.sessions}, days: ${storage.days}),\n` +
    (dev.lastCrash === null ? '' : `  lastCrash: ${s(dev.lastCrash)},\n`) +
    `  logs: [\n${logs}\n  ],\n` +
    `);\n\n` +
    `/// Firmware fixture — the OTA rules are real and must survive the port.\n` +
    `const FirmwareInfo kFirmware = FirmwareInfo(\n` +
    `  latest: ${s(M.FIRMWARE.latest)}, latestDate: ${s(M.FIRMWARE.latestDate)},\n` +
    `  sizeKb: ${M.FIRMWARE.sizeKb}, notes: ${stringList(M.FIRMWARE.notes)},\n` +
    `  rollback: ${s(M.FIRMWARE.rollback)},\n` +
    `);\n`
  );
}

mkdirSync(outDir, { recursive: true });
const outputs = {
  'catalog_data.dart': catalogFile(),
  'styles_data.dart': stylesFile(),
  'fixtures_data.dart': fixturesFile(),
};
for (const [name, body] of Object.entries(outputs)) {
  writeFileSync(join(outDir, name), body, 'utf8');
}
console.log(
  `generated ${M.CATALOG.length} catalog cuts, ` +
    `${Object.keys(M.STYLES).length} styled cuts, ` +
    `${Object.values(M.STYLES).reduce((n, a) => n + a.length, 0)} styles`,
);