// GENERATED FILE — do not edit by hand.
//
// Produced by `node app/tool/gen_mock_content.mjs` from
// `newui/mock-data.js` (the reviewer-owned prototype data). Small fixtures: history, modes, alarm rules, device, firmware.
// ignore_for_file: lines_longer_than_80_chars

import '../model/alarm.dart';
import '../model/alarm_rule.dart';
import '../model/connection_mode.dart';
import '../model/device_info.dart';
import '../model/history_entry.dart';
import '../model/mock_event.dart';

/// Past cooks, relative to "now" when the repository is built.
const List<HistorySeed> kHistorySeeds = [
  HistorySeed(
    id: 'c1',
    name: 'Labor Day Pulled Pork',
    presetId: 'pork_butt',
    styleId: 'texas_pulled',
    glyph: 'pork',
    jack: 1,
    startedAgoMin: 8640,
    durationMin: 612,
    plannedMin: 600,
    peakF10: 2031,
    targetF10: 2010,
    favourite: true,
    notes: 'Wrapped at 165°F. Best bark yet.',
    marks: 5,
    rating: 5,
    photos: 2,
    stalledMin: 155,
    wrapAtF10: 1650,
  ),
  HistorySeed(
    id: 'c2',
    name: 'Weeknight Ribeyes',
    presetId: 'beef_ribeye',
    styleId: 'reverse_sear',
    glyph: 'steak',
    jack: 1,
    startedAgoMin: 5760,
    durationMin: 18,
    plannedMin: 16,
    peakF10: 1370,
    targetF10: 1350,
    notes: 'Two minutes a side, then indirect.',
    marks: 2,
    rating: 4,
  ),
  HistorySeed(
    id: 'c3',
    name: 'Whole Turkey Trial',
    presetId: 'poultry_whole',
    styleId: 'classic_roast',
    glyph: 'wholeBird',
    jack: 1,
    startedAgoMin: 4320,
    durationMin: 214,
    plannedMin: 195,
    peakF10: 1652,
    targetF10: 1650,
    notes: 'Breast hit 165 first; thighs lagged 20 min.',
    marks: 3,
    rating: 3,
    photos: 1,
  ),
  HistorySeed(
    id: 'c4',
    name: 'Sunday Brisket & Ribs',
    presetId: 'beef_brisket',
    styleId: 'central_texas',
    glyph: 'brisket',
    jack: 1,
    startedAgoMin: 1440,
    durationMin: 498,
    plannedMin: 480,
    peakF10: 2026,
    targetF10: 2010,
    favourite: true,
    notes: 'Stalled 2h 40m. Wrapped in paper.',
    marks: 7,
    rating: 5,
    photos: 3,
    stalledMin: 160,
    wrapAtF10: 1650,
  ),
  HistorySeed(
    id: 'c5',
    name: 'Salmon on a Plank',
    presetId: 'fish_salmon',
    styleId: 'cedar',
    glyph: 'fish',
    jack: 2,
    startedAgoMin: 12960,
    durationMin: 41,
    plannedMin: 45,
    peakF10: 1454,
    targetF10: 1450,
    notes: 'Cedar plank, 275°F.',
    marks: 2,
    rating: 4,
    photos: 1,
  ),
  HistorySeed(
    id: 'c6',
    name: 'Memorial Day Brisket',
    presetId: 'beef_brisket',
    styleId: 'competition',
    glyph: 'brisket',
    jack: 1,
    startedAgoMin: 57600,
    durationMin: 731,
    plannedMin: 720,
    peakF10: 2040,
    targetF10: 2030,
    favourite: true,
    notes: 'Overnight cook. Held 4h in a cooler.',
    marks: 9,
    rating: 5,
    photos: 4,
    stalledMin: 175,
    wrapAtF10: 1650,
  ),
  HistorySeed(
    id: 'c7',
    name: 'Kālua Pork Night',
    presetId: 'pork_butt',
    styleId: 'kalua',
    glyph: 'pork',
    jack: 1,
    startedAgoMin: 31680,
    durationMin: 540,
    plannedMin: 540,
    peakF10: 2015,
    targetF10: 2000,
    notes: 'Covered with banana leaf and salt.',
    marks: 4,
    rating: 4,
    photos: 2,
    stalledMin: 120,
    wrapAtF10: 1650,
  ),
];

/// The three connection modes and their capability flags.
const List<ConnectionMode> kConnectionModes = [
  ConnectionMode(
    id: 'ble',
    icon: 'bluetooth',
    name: 'Bluetooth',
    tagline: 'Direct to the bridge',
    summary:
        'The simplest link. Works anywhere near the bridge, needs no network, and uses the least bridge power.',
    good: [
      'Works with no Wi-Fi at all',
      'Lowest bridge power draw',
      'Setup and mode changes always work here',
    ],
    limited: [
      'No full history download',
      'No probe naming or alarm-rule editing',
      'Shorter range than Wi-Fi',
    ],
    capability: ModeCapability(
      live: true,
      preview: true,
      fullHistory: false,
      config: true,
      rules: false,
      ota: false,
    ),
    requiresWifiCreds: false,
  ),
  ConnectionMode(
    id: 'ap',
    icon: 'wifi',
    name: 'Bridge Wi-Fi (its own hotspot)',
    tagline: 'The bridge hosts the network',
    summary:
        'The bridge broadcasts its own Wi-Fi. Your phone joins it directly. Full features, no home network needed.',
    good: [
      'Every feature, including full history',
      'No router or home network required',
      'Strong, dedicated link',
    ],
    limited: [
      'Your phone leaves your normal Wi-Fi while connected',
      'Some phones warn about “no internet”',
    ],
    capability: ModeCapability(
      live: true,
      preview: true,
      fullHistory: true,
      config: true,
      rules: true,
      ota: true,
    ),
    requiresWifiCreds: false,
  ),
  ConnectionMode(
    id: 'sta',
    icon: 'router',
    name: 'Your Wi-Fi',
    tagline: 'The bridge joins your network',
    summary:
        'The bridge joins your home Wi-Fi. Your phone stays on its normal network and reaches the bridge from anywhere in range.',
    good: [
      'Phone keeps internet and other apps',
      'Reach the bridge anywhere on your network',
      'Lowest power draw over time',
    ],
    limited: [
      'Needs your Wi-Fi name and password',
      'Depends on your router’s range and reliability',
    ],
    capability: ModeCapability(
      live: true,
      preview: true,
      fullHistory: true,
      config: true,
      rules: true,
      ota: true,
    ),
    requiresWifiCreds: true,
  ),
];

/// Nine device rules + three app insights.
const List<AlarmRule> kAlarmRules = [
  AlarmRule(
    id: 'target_reached',
    tier: AlarmTier.device,
    name: 'Target reached',
    desc: 'Food crosses its target going up.',
    severity: AlarmSeverity.critical,
    scope: AlarmScope.perProbe,
  ),
  AlarmRule(
    id: 'smoke_x_alarm',
    tier: AlarmTier.device,
    name: 'Base station alarm',
    desc: 'Mirrors the Smoke X4’s own alarm.',
    severity: AlarmSeverity.critical,
    scope: AlarmScope.perProbe,
  ),
  AlarmRule(
    id: 'pit_out_of_band',
    tier: AlarmTier.device,
    name: 'Pit out of band',
    desc: 'Grate temp leaves your pit band.',
    severity: AlarmSeverity.warning,
    scope: AlarmScope.pit,
    windowS: 600,
  ),
  AlarmRule(
    id: 'pit_crash',
    tier: AlarmTier.device,
    name: 'Pit crash',
    desc: 'Pit falls fast below target.',
    severity: AlarmSeverity.critical,
    scope: AlarmScope.pit,
    windowS: 600,
  ),
  AlarmRule(
    id: 'probe_detached',
    tier: AlarmTier.device,
    name: 'Probe detached',
    desc: 'A probe is unplugged or out of range.',
    severity: AlarmSeverity.warning,
    scope: AlarmScope.perProbe,
  ),
  AlarmRule(
    id: 'base_lost',
    tier: AlarmTier.device,
    name: 'Base station lost',
    desc: 'No packet from the Smoke X4.',
    severity: AlarmSeverity.warning,
    scope: AlarmScope.cook,
    windowS: 600,
  ),
  AlarmRule(
    id: 'battery_low',
    tier: AlarmTier.device,
    name: 'Battery low',
    desc: 'Bridge battery warning then critical.',
    severity: AlarmSeverity.warning,
    scope: AlarmScope.device,
  ),
  AlarmRule(
    id: 'storage_low',
    tier: AlarmTier.device,
    name: 'Storage low',
    desc: 'Little flash left for recording.',
    severity: AlarmSeverity.warning,
    scope: AlarmScope.device,
  ),
  AlarmRule(
    id: 'system_fault',
    tier: AlarmTier.device,
    name: 'System fault',
    desc: 'Crash dump or failed update.',
    severity: AlarmSeverity.warning,
    scope: AlarmScope.device,
  ),
  AlarmRule(
    id: 'eta_soon',
    tier: AlarmTier.app,
    name: 'ETA soon',
    desc: 'Insight: a probe is close to target.',
    severity: AlarmSeverity.info,
    scope: AlarmScope.perProbe,
  ),
  AlarmRule(
    id: 'stall',
    tier: AlarmTier.app,
    name: 'Stall detected',
    desc: 'Insight: the meat has plateaued.',
    severity: AlarmSeverity.info,
    scope: AlarmScope.perProbe,
  ),
  AlarmRule(
    id: 'bridge_unreachable',
    tier: AlarmTier.app,
    name: 'Bridge unreachable',
    desc: 'Insight: the app lost the link.',
    severity: AlarmSeverity.warning,
    scope: AlarmScope.device,
  ),
];

/// The mock event-bus catalogue the dev panel fires.
const List<MockEventSpec> kMockEvents = [
  MockEventSpec(
    id: 'ble-connected',
    label: 'BLE connected',
    hint: 'Phone pairs to the bridge over Bluetooth.',
  ),
  MockEventSpec(
    id: 'ble-dropped',
    label: 'BLE dropped',
    hint: 'Bluetooth link lost; Wi-Fi may carry on.',
  ),
  MockEventSpec(
    id: 'wifi-connecting',
    label: 'Wi-Fi connecting',
    hint: 'Bridge is joining a home network.',
  ),
  MockEventSpec(
    id: 'wifi-wrong-password',
    label: 'Wi-Fi wrong password',
    hint: 'Bridge rejects the credential.',
  ),
  MockEventSpec(
    id: 'wifi-router-unreachable',
    label: 'Router unreachable',
    hint: 'Credential right, router not reachable.',
  ),
  MockEventSpec(
    id: 'wifi-connected',
    label: 'Wi-Fi connected',
    hint: 'Bridge joins home Wi-Fi; BLE goes warm.',
  ),
  MockEventSpec(
    id: 'ap-broadcasting',
    label: 'Hotspot broadcasting',
    hint: 'Bridge starts its own access point.',
  ),
  MockEventSpec(
    id: 'ap-joined',
    label: 'Phone joined hotspot',
    hint: 'Phone joins the bridge access point.',
  ),
  MockEventSpec(
    id: 'switch-rollback',
    label: 'Switch rollback',
    hint: 'Mode change fails; old link restored.',
  ),
  MockEventSpec(
    id: 'resync-complete',
    label: 'Re-sync complete',
    hint: 'High-water mark synced; fresh data.',
  ),
  MockEventSpec(
    id: 'alarm-target',
    label: 'Alarm: target reached',
    hint: 'Fire a device target alarm.',
  ),
  MockEventSpec(
    id: 'alarm-pit-crash',
    label: 'Alarm: pit crash',
    hint: 'Fire a device pit-crash alarm.',
  ),
];

/// Device identity and diagnostics fixture.
const DeviceInfo kDevice = DeviceInfo(
  id: 'A4F2-9C71',
  hardware: 'rev C · ESP32-S3',
  version: 'v1.4.2',
  versionDate: '2026-07-18',
  bootloader: '2.1.0',
  channel: DeviceChannel.stable,
  uptimeMin: 4387,
  heapKb: 128,
  storage: DeviceStorage(usedKb: 36, totalKb: 512, sessions: 12, days: 54),
  logs: [
    DeviceLog(
      t: '09:12:04',
      level: 'info',
      text: 'LoRa sync acquired — base station paired',
    ),
    DeviceLog(
      t: '09:12:09',
      level: 'info',
      text: 'Session SMK-4482 opened, 4 probes attached',
    ),
    DeviceLog(
      t: '09:41:22',
      level: 'warn',
      text: 'Probe 3 detached briefly — reconnect 4 s',
    ),
    DeviceLog(
      t: '09:58:01',
      level: 'info',
      text: 'Wi-Fi STA connected — 192.168.1.42',
    ),
    DeviceLog(
      t: '10:02:47',
      level: 'info',
      text: 'Alarm rule pit_crash fired (device tier)',
    ),
  ],
);

/// Firmware fixture — the OTA rules are real and must survive the port.
const FirmwareInfo kFirmware = FirmwareInfo(
  latest: 'v1.5.0',
  latestDate: '2026-09-02',
  sizeKb: 1024,
  notes: [
    'Faster BLE history streaming on long sessions',
    'Pit-crash rule: less sensitive to lid openings',
    'Fixes a rare AP fallback race after router loss',
  ],
  rollback:
      'A failed health check within 120 s of boot auto-rolls back to the previous slot. Nothing is lost.',
);
