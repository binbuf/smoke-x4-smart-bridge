/// The one list of reviewable UI scenarios.
///
/// Two things read it.
///
/// * `tool/ui_screenshots_test.dart` renders every entry with
///   [Scenario.golden] set and compares it with `app/screenshots/<id>.png`.
/// * `ScenarioLabScreen` lists the same entries in debug builds, so the gallery
///   a reviewer taps through and the screenshots CI checks cannot drift apart.
///
/// An entry owns everything that makes its state reproducible: the controller
/// seed, the widget, the theme and any taps or drags needed to reach the state.
/// Nothing about a scenario lives outside this file.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/bridge_controller.dart';
import '../data/ble/ble_client.dart';
import '../data/ble/bridge_codecs.dart';
import '../features/device/device_preview_screen.dart';
import '../features/history/history_full_screen.dart';
import '../features/history/history_screen.dart';
import '../features/settings/bridge_details.dart';
import '../features/settings/settings_details.dart';
import '../features/settings/settings_views.dart';
import '../features/setup/setup_screen.dart';
import '../features/shell/app_shell.dart';
import 'fixtures.dart';

/// One heading in the lab and one ordering unit in the catalogue.
class ScenarioGroup {
  const ScenarioGroup(this.title, this.description);

  final String title;
  final String description;
}

const setupGroup = ScenarioGroup(
  'Setup & permissions',
  'First run, scanning, pairing, and error states',
);
const liveGroup = ScenarioGroup(
  'Live & connection',
  'Freshness, probe, Billows, sync, and link states',
);
const historyGroup = ScenarioGroup(
  'History',
  'Ranges, gaps, empty states, offline cache, and time estimation',
);
const settingsGroup = ScenarioGroup(
  'Settings',
  'Bridge, preferences, Billows, history, and About',
);
const confirmGroup = ScenarioGroup(
  'Confirmations & results',
  'Destructive confirmations and their outcomes',
);
const deviceGroup = ScenarioGroup(
  'Bridge screen (OLED)',
  'The other UI surface: pages, pairing code, power, storage',
);

/// A declarative interaction. The golden test replays these; the lab does not,
/// because a reviewer can scroll and tap the live screen themselves.
sealed class ScenarioAction {
  const ScenarioAction();
}

/// Tap a widget by key, then settle.
final class TapKeyAction extends ScenarioAction {
  const TapKeyAction(this.key);

  final Key key;
}

/// Drag the first [ListView] by [offset], then settle.
final class DragListAction extends ScenarioAction {
  const DragListAction(this.offset);

  final Offset offset;
}

/// A reproducible screen state.
class Scenario {
  const Scenario({
    required this.id,
    required this.title,
    required this.group,
    required this.subtitle,
    required this.icon,
    required this.seed,
    required this.screen,
    this.brightness = Brightness.dark,
    this.actions = const <ScenarioAction>[],
    this.golden = false,
    this.lab = true,
  });

  /// Golden file name without the extension. Stable: the screenshot manifest,
  /// the lab thumbnails and the capture diff are all keyed by it.
  final String id;

  final String title;
  final ScenarioGroup group;
  final String subtitle;
  final IconData icon;

  /// Mutates the controller into the scenario's state. Runs before [screen].
  final void Function(BridgeController controller) seed;

  /// The screen to show, with the controller already seeded.
  final Widget Function(BridgeController controller) screen;

  final Brightness brightness;
  final List<ScenarioAction> actions;

  /// Has a committed `app/screenshots/<id>.png` and a manifest entry.
  final bool golden;

  /// Appears in the Experimental lab.
  final bool lab;
}

List<Scenario> get goldenScenarios =>
    scenarioCatalog.where((scenario) => scenario.golden).toList();

List<Scenario> get labScenarios =>
    scenarioCatalog.where((scenario) => scenario.lab).toList();

Scenario? scenarioById(String id) {
  for (final scenario in scenarioCatalog) {
    if (scenario.id == id) return scenario;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Controller seeds
// ---------------------------------------------------------------------------

void seedLive(
  BridgeController c, {
  ProbeHealth health = ProbeHealth.live,
  ProbePresence presence = ProbePresence.all,
  bool smokeX = true,
  bool storageOk = true,
  ConnectionPhase phase = ConnectionPhase.live,
  SyncState sync = SyncState.idle,
  bool slowLink = false,
  BillowsAttachment billowsAttachment = BillowsAttachment.attached,
  bool smokeXChannel4SetKnown = true,
  bool billowsSeen = true,
  bool offlineCache = true,
  bool historyData = true,
}) {
  c
    ..phase = phase
    ..probeHealth = health
    ..probePresence = presence
    ..smokeXLiveHint = smokeX
    ..smokeXStatus = smokeX ? SmokeXStatus.pairedLive : SmokeXStatus.pairedLost
    ..storageOk = storageOk
    ..syncState = sync
    ..syncProgressPercent = sync == SyncState.backfill
        ? 38
        : (sync == SyncState.error ? 0 : 64)
    ..slowLink = slowLink
    ..billowsAttachment = billowsAttachment
    ..smokeXChannel4SetKnown = smokeXChannel4SetKnown
    ..billowsSeenThisSession = billowsSeen
    ..offlineCache = offlineCache
    ..historyHasData = historyData
    ..phoneRecords = historyData ? 128430 : 0
    ..historyOneProbe = false
    ..historyEstimated = false
    ..historyMissingFromBridge = false
    ..tab = AppTab.live;
}

void seedHistory(
  BridgeController c,
  HistoryRange range, {
  bool hasData = true,
  bool oneProbe = false,
  bool estimated = false,
  bool missing = false,
  bool offline = false,
  bool offlineCache = true,
  DateTimeRange? customRange,
}) {
  c
    ..phase = offline ? ConnectionPhase.offline : ConnectionPhase.live
    ..offlineCache = offlineCache
    ..historyRange = range
    ..historyProbe = null
    ..historyCustomRange = customRange
    ..historySort = HistorySort.probe
    ..historyHasData = hasData
    ..phoneRecords = hasData ? 128430 : 0
    ..historyOneProbe = oneProbe
    ..historyEstimated = estimated
    ..historyMissingFromBridge = missing
    ..syncState = SyncState.complete
    ..tab = AppTab.history;
}

void seedSettings(BridgeController c, {bool offline = false}) {
  c
    ..phase = offline ? ConnectionPhase.offline : ConnectionPhase.live
    ..offlineCache = true
    ..bridgeRecords = 24810
    ..phoneRecords = 128430
    ..savedDataEmpty = false
    ..saveState = SettingsSaveState.idle
    ..tab = AppTab.settings;
}

void seedSetup(
  BridgeController c, {
  BlockReason? blocked,
  bool? hasSavedBridge,
  bool? hasSavedData,
  bool? savedDataEmpty,
  int? phoneRecords,
  SyncState? sync,
  int syncProgressPercent = 64,
}) {
  if (blocked != null) c.setBlocked(blocked);
  if (hasSavedBridge != null) c.hasSavedBridge = hasSavedBridge;
  if (hasSavedData != null) c.hasSavedData = hasSavedData;
  if (savedDataEmpty != null) c.savedDataEmpty = savedDataEmpty;
  if (phoneRecords != null) c.phoneRecords = phoneRecords;
  if (sync != null) {
    c
      ..syncState = sync
      ..syncProgressPercent = syncProgressPercent;
  }
}

void seedDevice(
  BridgeController c, {
  int page = 1,
  DeviceOverlay overlay = DeviceOverlay.none,
  ProbePresence presence = ProbePresence.all,
  BillowsAttachment attachment = BillowsAttachment.attached,
  bool targetKnown = true,
}) {
  c
    ..phase = ConnectionPhase.live
    ..probeHealth = ProbeHealth.live
    ..probePresence = presence
    ..smokeXLiveHint = true
    ..smokeXStatus = SmokeXStatus.pairedLive
    ..billowsAttachment = attachment
    ..smokeXChannel4SetKnown = targetKnown
    ..smokeXChannel4SetF = 225
    ..bridgeRecords = 24810;
}

void seedConfirm(BridgeController c, DestructiveKind kind) {
  if (kind == DestructiveKind.delete30 ||
      kind == DestructiveKind.delete90 ||
      kind == DestructiveKind.deleteAll) {
    c
      ..phoneRecords = 128430
      ..savedDataEmpty = false;
  }
  if (kind == DestructiveKind.clearBridgeHistory) {
    c.bridgeRecords = 24810;
  }
}

/// Custom range covering everything the review fixtures hold.
void seedEntireHistory(BridgeController c) {
  c
    ..tab = AppTab.history
    ..historyRange = HistoryRange.custom
    ..historyEstimated = true;
  c.historyCustomRange = c.entireHistoryRange;
}

// ---------------------------------------------------------------------------
// Screen builders
// ---------------------------------------------------------------------------

Widget liveShell(BridgeController c) => AppShell(controller: c);

Widget historyShell(BridgeController c) => AppShell(controller: c);

Widget settingsShell(BridgeController c) => AppShell(controller: c);

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

final List<Scenario> scenarioCatalog = <Scenario>[
  // --- Setup & permissions -------------------------------------------------
  Scenario(
    id: 'lab.setup.no_bridge',
    title: 'No Bridge yet',
    group: setupGroup,
    subtitle:
        'First launch, no saved Bridge. Find bridge or open history on this '
        'phone.',
    icon: Icons.bluetooth_searching,
    seed: (c) => seedSetup(c, hasSavedBridge: false, hasSavedData: false),
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.noBridge,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.permission_primer',
    title: 'Permission primer',
    group: setupGroup,
    subtitle: 'Explain Nearby devices before the Android prompt.',
    icon: Icons.bluetooth,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.permissionPrimer,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.bluetooth_off',
    title: 'Bluetooth off',
    group: setupGroup,
    subtitle: 'Named blocked state with Open settings and Check again.',
    icon: Icons.bluetooth_disabled,
    seed: (c) => seedSetup(c, blocked: BlockReason.bluetoothOff),
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.bluetoothOff,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.permission_denied',
    title: 'Permission denied',
    group: setupGroup,
    subtitle: 'Grant again or open Android settings.',
    icon: Icons.lock_outline,
    seed: (c) => seedSetup(c, blocked: BlockReason.permissionDenied),
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.permissionDenied,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.permission_blocked',
    title: 'Permission permanently blocked',
    group: setupGroup,
    subtitle: 'The app sends the user to Android app settings.',
    icon: Icons.lock,
    seed: (c) => seedSetup(c, blocked: BlockReason.permissionBlocked),
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.permissionBlocked,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.unsupported_phone',
    title: 'Unsupported phone',
    group: setupGroup,
    subtitle: 'No Bluetooth LE scanning available.',
    icon: Icons.phonelink_erase,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.unsupportedPhone,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.scanning',
    title: 'Scanning',
    group: setupGroup,
    subtitle: 'Live scan spinner with cancel and simulated results.',
    icon: Icons.radar,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.scanning,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.no_results',
    title: 'No results',
    group: setupGroup,
    subtitle: 'Retry, Bluetooth settings, and the asleep-Bridge hint.',
    icon: Icons.search_off,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.noResults,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.results',
    title: 'Scan results',
    group: setupGroup,
    subtitle: 'Last Bridge first, signal words, probe preview, and legacy row.',
    icon: Icons.devices_other,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.results,
      autoAdvance: false,
      previewBridges: previewScannedBridges(),
    ),
  ),
  Scenario(
    id: 'lab.setup.protocol_mismatch',
    title: 'Protocol mismatch',
    group: setupGroup,
    subtitle: '“This Bridge needs a newer app.”',
    icon: Icons.system_update_alt,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.protocolMismatch,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'passkey_dark',
    title: 'Pairing code instruction',
    group: setupGroup,
    subtitle: 'Look at the Bridge screen, then the simulated Android prompt.',
    icon: Icons.pin_outlined,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.passkey,
      autoAdvance: false,
    ),
    golden: true,
  ),
  Scenario(
    id: 'lab.setup.bonding',
    title: 'Pairing in progress',
    group: setupGroup,
    subtitle: 'Connecting, pairing, syncing recent history.',
    icon: Icons.bluetooth_connected,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.bonding,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.bond_wrong_code',
    title: 'Wrong pairing code',
    group: setupGroup,
    subtitle: 'Named retry path after a failed pairing.',
    icon: Icons.error_outline,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.bondWrongCode,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.bond_timeout',
    title: 'Pairing prompt timeout',
    group: setupGroup,
    subtitle: 'Check the notification shade, then retry.',
    icon: Icons.notifications_off_outlined,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.bondTimeout,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.bond_stale',
    title: 'Pairing out of date',
    group: setupGroup,
    subtitle: 'The Bridge was reset; forget the old pairing and re-pair.',
    icon: Icons.link_off,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.bondStale,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.bond_store_full',
    title: 'Phone list full',
    group: setupGroup,
    subtitle: 'Four phones already paired; refuse before the Android prompt.',
    icon: Icons.people_outline,
    seed: seedSetup,
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.bondStoreFull,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.first_sync',
    title: 'First sync',
    group: setupGroup,
    subtitle: 'Recent 24 h first, then background backfill.',
    icon: Icons.cloud_sync_outlined,
    seed: (c) => seedSetup(c, sync: SyncState.recent),
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.firstSync,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'lab.setup.saved_data',
    title: 'History on this phone (after forgetting the Bridge)',
    group: setupGroup,
    subtitle:
        'History on this phone after a forget/reset, with explicit deletion.',
    icon: Icons.folder_open_outlined,
    seed: (c) => seedSetup(
      c,
      hasSavedBridge: false,
      hasSavedData: true,
      savedDataEmpty: false,
      phoneRecords: 128430,
    ),
    screen: (c) => SetupScreen(
      controller: c,
      initialStep: SetupStep.savedData,
      autoAdvance: false,
    ),
  ),
  Scenario(
    id: 'setup_dark',
    title: 'Setup · dark',
    group: setupGroup,
    subtitle: 'First-run “Connect your Bridge”.',
    icon: Icons.bluetooth_searching,
    seed: seedSetup,
    screen: (c) => SetupScreen(controller: c, autoAdvance: false),
    golden: true,
  ),
  Scenario(
    id: 'setup_light',
    title: 'Setup · light',
    group: setupGroup,
    subtitle: 'First-run “Connect your Bridge” in the light theme.',
    icon: Icons.bluetooth_searching,
    seed: seedSetup,
    screen: (c) => SetupScreen(controller: c, autoAdvance: false),
    brightness: Brightness.light,
    golden: true,
  ),

  // --- Live & connection ---------------------------------------------------
  Scenario(
    id: 'live_dark',
    title: 'Live · all probes',
    group: liveGroup,
    subtitle: 'Four connected probes, Billows observed, live banner.',
    icon: Icons.thermostat,
    seed: seedLive,
    screen: liveShell,
    golden: true,
  ),
  Scenario(
    id: 'live_light',
    title: 'Live · light',
    group: liveGroup,
    subtitle: 'The same state in the light theme.',
    icon: Icons.thermostat,
    seed: seedLive,
    screen: liveShell,
    brightness: Brightness.light,
    golden: true,
  ),
  Scenario(
    id: 'lab.live.aging',
    title: 'Live · aging',
    group: liveGroup,
    subtitle: 'Amber freshness; still a reading.',
    icon: Icons.hourglass_bottom,
    seed: (c) => seedLive(c, health: ProbeHealth.aging),
    screen: liveShell,
  ),
  Scenario(
    id: 'live_stale_dark',
    title: 'Live · stale',
    group: liveGroup,
    subtitle: 'Last reading 4m ago; the Bridge still answers.',
    icon: Icons.schedule,
    seed: (c) {
      c
        ..phase = ConnectionPhase.stale
        ..smokeXAgeOverride = const Duration(minutes: 4);
    },
    screen: liveShell,
    golden: true,
  ),
  Scenario(
    id: 'lab.live.frozen',
    title: 'Live · frozen',
    group: liveGroup,
    subtitle: 'No readings for 12 min; no derived values.',
    icon: Icons.timer_off_outlined,
    seed: (c) =>
        seedLive(c, health: ProbeHealth.frozen, phase: ConnectionPhase.stale),
    screen: liveShell,
  ),
  Scenario(
    id: 'lab.live.detached_probe',
    title: 'Live · detached probe 3',
    group: liveGroup,
    subtitle: 'Shows — and Not connected, never 0 °F.',
    icon: Icons.graphic_eq,
    seed: (c) => seedLive(c, presence: ProbePresence.detachedP3),
    screen: liveShell,
  ),
  Scenario(
    id: 'lab.live.no_probes',
    title: 'Live · no probes',
    group: liveGroup,
    subtitle: 'All four probes absent; no invented zeros.',
    icon: Icons.signal_cellular_off,
    seed: (c) => seedLive(c, presence: ProbePresence.none),
    screen: liveShell,
  ),
  Scenario(
    id: 'lab.live.smoke_x_silent',
    title: 'Smoke X4 not sending',
    group: liveGroup,
    subtitle: 'The Bridge answers but has not heard the transmitter.',
    icon: Icons.sensors_off_outlined,
    seed: (c) => seedLive(c, smokeX: false),
    screen: liveShell,
  ),
  Scenario(
    id: 'lab.live.storage_unavailable',
    title: 'Storage unavailable',
    group: liveGroup,
    subtitle: 'Live readings only; this session is not recorded.',
    icon: Icons.sd_card_alert_outlined,
    seed: (c) => seedLive(c, storageOk: false),
    screen: liveShell,
  ),
  Scenario(
    id: 'lab.live.syncing_recent',
    title: 'Syncing recent',
    group: liveGroup,
    subtitle: 'Catch-up banner and progress for the last 24 h.',
    icon: Icons.sync,
    seed: (c) =>
        seedLive(c, phase: ConnectionPhase.syncing, sync: SyncState.recent),
    screen: liveShell,
  ),
  Scenario(
    id: 'lab.live.slow_link',
    title: 'Slow-link backfill',
    group: liveGroup,
    subtitle: 'MTU 23 note; backfill continues in the background.',
    icon: Icons.slow_motion_video,
    seed: (c) => seedLive(
      c,
      phase: ConnectionPhase.syncing,
      sync: SyncState.backfill,
      slowLink: true,
    ),
    screen: liveShell,
  ),
  Scenario(
    id: 'lab.live.reconnecting',
    title: 'Reconnecting',
    group: liveGroup,
    subtitle: 'Bounded retry with the attempt/backoff state.',
    icon: Icons.sync_problem,
    seed: (c) => seedLive(c, phase: ConnectionPhase.reconnecting),
    screen: liveShell,
  ),
  Scenario(
    id: 'lab.live.unreachable',
    title: 'Can’t reach the Bridge',
    group: liveGroup,
    subtitle: 'All retries failed; tap to retry or forget.',
    icon: Icons.link_off,
    seed: (c) => seedLive(c, phase: ConnectionPhase.failed),
    screen: liveShell,
  ),
  Scenario(
    id: 'lab.live.blocked_bluetooth_off',
    title: 'Blocked · Bluetooth off',
    group: liveGroup,
    subtitle: 'Global banner names the reason and opens settings.',
    icon: Icons.bluetooth_disabled,
    seed: (c) => c
      ..phase = ConnectionPhase.blocked
      ..blockReason = BlockReason.bluetoothOff
      ..tab = AppTab.live,
    screen: liveShell,
  ),
  Scenario(
    id: 'live_offline_cache',
    title: 'Offline with cache',
    group: liveGroup,
    subtitle: 'Cached readings, labelled as saved.',
    icon: Icons.cloud_off_outlined,
    seed: (c) =>
        seedLive(c, phase: ConnectionPhase.offline, offlineCache: true),
    screen: liveShell,
    golden: true,
  ),
  Scenario(
    id: 'live_offline_nocache_dark',
    title: 'Offline without cache',
    group: liveGroup,
    subtitle: 'Nothing saved yet; one clear next action.',
    icon: Icons.cloud_off,
    seed: (c) => seedLive(
      c,
      phase: ConnectionPhase.offline,
      offlineCache: false,
      historyData: false,
    ),
    screen: liveShell,
    golden: true,
  ),
  Scenario(
    id: 'lab.live.sync_failed',
    title: 'History sync failed',
    group: liveGroup,
    subtitle: 'Named catch-up failure with retry; live can continue.',
    icon: Icons.error_outline,
    seed: (c) => seedLive(c, sync: SyncState.error),
    screen: liveShell,
  ),
  Scenario(
    id: 'live_billows_detected',
    title: 'Billows · detected',
    group: liveGroup,
    subtitle: 'Billows status; set temp mirrors the Smoke X4.',
    icon: Icons.air,
    seed: (c) => seedLive(c, billowsAttachment: BillowsAttachment.attached),
    screen: liveShell,
    actions: const [DragListAction(Offset(0, -320))],
    golden: true,
  ),
  Scenario(
    id: 'lab.live.billows_never_seen',
    title: 'Billows · not detected',
    group: liveGroup,
    subtitle: 'Never seen this session; Live stays quiet.',
    icon: Icons.air,
    seed: (c) => seedLive(
      c,
      billowsAttachment: BillowsAttachment.unknown,
      billowsSeen: false,
    ),
    screen: liveShell,
  ),
  Scenario(
    id: 'live_billows_lost',
    title: 'Billows · lost this session',
    group: liveGroup,
    subtitle: 'Detected earlier, now missing; Live shows a loss notice.',
    icon: Icons.link_off,
    seed: (c) {
      seedLive(
        c,
        billowsAttachment: BillowsAttachment.detached,
        smokeXChannel4SetKnown: false,
        billowsSeen: false,
      );
      c.billowsSeenThisSession = true;
    },
    screen: liveShell,
    actions: const [DragListAction(Offset(0, -320))],
    golden: true,
  ),
  Scenario(
    id: 'lab.live.billows_lost_mid_session',
    title: 'Billows · lost mid-session',
    group: liveGroup,
    subtitle: 'Detected earlier; the fan link now has an issue.',
    icon: Icons.air,
    seed: (c) => seedLive(
      c,
      billowsAttachment: BillowsAttachment.detached,
      billowsSeen: true,
    ),
    screen: liveShell,
  ),
  Scenario(
    id: 'live_x4_warning_dark',
    title: 'Live · Smoke X4 warning sheet',
    group: liveGroup,
    subtitle: 'The X4 stopped sending; the sheet offers pairing steps.',
    icon: Icons.warning_amber_rounded,
    seed: (c) {
      seedLive(c);
      c.smokeXAgeOverride = const Duration(minutes: 4);
    },
    // The warning only appears once the X4 has gone quiet; keep the seed honest
    // by mirroring what the screenshot has always captured.
    screen: liveShell,
    actions: const [TapKeyAction(Key('live.smokeXWarning'))],
    golden: true,
  ),

  // --- History -------------------------------------------------------------
  Scenario(
    id: 'history_dark',
    title: 'History · 24 hours',
    group: historyGroup,
    subtitle: 'Compact range/probe dropdowns, 24 h chart, gap and controls.',
    icon: Icons.show_chart,
    seed: (c) => c
      ..tab = AppTab.history
      ..historyRange = HistoryRange.twentyFourHours
      ..historyMissingFromBridge = true,
    screen: historyShell,
    golden: true,
  ),
  Scenario(
    id: 'history_light',
    title: 'History · light',
    group: historyGroup,
    subtitle: 'The same range in the light theme.',
    icon: Icons.show_chart,
    seed: (c) => c.tab = AppTab.history,
    screen: historyShell,
    brightness: Brightness.light,
    golden: true,
  ),
  Scenario(
    id: 'lab.history.one_hour',
    title: 'History · 1 hour',
    group: historyGroup,
    subtitle: 'Four series with one visible gap.',
    icon: Icons.show_chart,
    seed: (c) => seedHistory(c, HistoryRange.oneHour),
    screen: historyShell,
  ),
  Scenario(
    id: 'lab.history.six_hours',
    title: 'History · 6 hours',
    group: historyGroup,
    subtitle: 'Range chip and wider history.',
    icon: Icons.show_chart,
    seed: (c) => seedHistory(c, HistoryRange.sixHours),
    screen: historyShell,
  ),
  Scenario(
    id: 'lab.history.24_hours',
    title: 'History · 24 hours (synced)',
    group: historyGroup,
    subtitle: 'Range chip and wider history, with sync complete.',
    icon: Icons.show_chart,
    seed: (c) => seedHistory(c, HistoryRange.twentyFourHours),
    screen: historyShell,
  ),
  Scenario(
    id: 'history_cooks_dark',
    title: 'History · detected cooks',
    group: historyGroup,
    subtitle: 'Summary and detected cooks.',
    icon: Icons.outdoor_grill,
    seed: (c) => c
      ..tab = AppTab.history
      ..historyRange = HistoryRange.twoDays,
    screen: historyShell,
    actions: const [DragListAction(Offset(0, -520))],
    golden: true,
  ),
  Scenario(
    id: 'history_all_dark',
    title: 'History · entire archive',
    group: historyGroup,
    subtitle:
        'All saved history selected through Custom range, estimated time.',
    icon: Icons.show_chart,
    seed: seedEntireHistory,
    screen: historyShell,
    golden: true,
  ),
  Scenario(
    id: 'lab.history.one_probe',
    title: 'History · one probe',
    group: historyGroup,
    subtitle: 'Only P4 has data; no zero lines for absent probes.',
    icon: Icons.linear_scale,
    seed: (c) => seedHistory(c, HistoryRange.twentyFourHours, oneProbe: true),
    screen: historyShell,
  ),
  Scenario(
    id: 'history_empty_dark',
    title: 'History · empty',
    group: historyGroup,
    subtitle: '“No readings yet” with a Bridge-status action.',
    icon: Icons.folder_off_outlined,
    seed: (c) => c
      ..tab = AppTab.history
      ..historyHasData = false
      ..phoneRecords = 0,
    screen: historyShell,
    golden: true,
  ),
  Scenario(
    id: 'lab.history.offline_cache',
    title: 'History · offline cache',
    group: historyGroup,
    subtitle: 'Cached history labelled “Showing saved readings”.',
    icon: Icons.cloud_off_outlined,
    seed: (c) => seedHistory(c, HistoryRange.sixHours, offline: true),
    screen: historyShell,
  ),
  Scenario(
    id: 'lab.history.offline_no_cache',
    title: 'History · offline, no cache',
    group: historyGroup,
    subtitle: 'Nothing saved on this phone; retry is the next step.',
    icon: Icons.cloud_off,
    seed: (c) => seedHistory(
      c,
      HistoryRange.oneHour,
      hasData: false,
      offline: true,
      offlineCache: false,
    ),
    screen: historyShell,
  ),
  Scenario(
    id: 'lab.history.estimated',
    title: 'History · estimated time',
    group: historyGroup,
    subtitle: 'Clock was unknown; axis is labelled estimated.',
    icon: Icons.schedule,
    seed: (c) => seedHistory(c, HistoryRange.twentyFourHours, estimated: true),
    screen: historyShell,
  ),
  Scenario(
    id: 'lab.history.gap',
    title: 'History overwritten before sync',
    group: historyGroup,
    subtitle: 'Permanent gap marker and explanation.',
    icon: Icons.link_off,
    seed: (c) => seedHistory(c, HistoryRange.twoDays, missing: true),
    screen: historyShell,
  ),
  Scenario(
    id: 'history_custom_range_dark',
    title: 'History · custom range sheet',
    group: historyGroup,
    subtitle: 'Custom date-and-time range sheet, starting all saved history.',
    icon: Icons.date_range,
    seed: (c) => c.tab = AppTab.history,
    screen: historyShell,
    actions: const [
      TapKeyAction(Key('history.range.menu')),
      TapKeyAction(Key('history.range.custom')),
    ],
    golden: true,
  ),
  Scenario(
    id: 'history_filter_dark',
    title: 'History · filtered P1, 1 hour',
    group: historyGroup,
    subtitle: 'History filtered P1 and 1 hour.',
    icon: Icons.filter_alt_outlined,
    seed: (c) => c
      ..tab = AppTab.history
      ..historyRange = HistoryRange.oneHour
      ..historyProbe = 1,
    screen: historyShell,
    golden: true,
  ),
  Scenario(
    id: 'history_probe_empty_dark',
    title: 'History · selected probe has no data',
    group: historyGroup,
    subtitle: 'Selected probe has no data in range.',
    icon: Icons.show_chart,
    seed: (c) => c
      ..tab = AppTab.history
      ..historyOneProbe = true
      ..historyProbe = 1
      ..historyRange = HistoryRange.oneHour,
    screen: historyShell,
    golden: true,
  ),
  Scenario(
    id: 'past_cook_dark',
    title: 'Past cook',
    group: historyGroup,
    subtitle: 'Detected cook opened historical view.',
    icon: Icons.outdoor_grill,
    seed: _noSeed,
    screen: (c) =>
        PastCookScreen(controller: c, cook: buildCookSessions().first),
    golden: true,
  ),
  Scenario(
    id: 'past_cook_light',
    title: 'Past cook · light',
    group: historyGroup,
    subtitle: 'Detected cook opened historical view in the light theme.',
    icon: Icons.outdoor_grill,
    seed: _noSeed,
    screen: (c) =>
        PastCookScreen(controller: c, cook: buildCookSessions().first),
    brightness: Brightness.light,
    golden: true,
  ),
  Scenario(
    id: 'history_fullscreen_dark',
    title: 'History · full-screen chart',
    group: historyGroup,
    subtitle: 'Dedicated full-screen chart in portrait.',
    icon: Icons.fullscreen,
    seed: seedEntireHistory,
    screen: (c) => HistoryFullScreenScreen(controller: c),
    golden: true,
  ),

  // --- Settings ------------------------------------------------------------
  Scenario(
    id: 'settings_dark',
    title: 'Settings · connected',
    group: settingsGroup,
    subtitle: 'All sections editable, live values.',
    icon: Icons.tune,
    seed: seedSettings,
    screen: settingsShell,
    golden: true,
  ),
  Scenario(
    id: 'settings_light',
    title: 'Settings · light',
    group: settingsGroup,
    subtitle: 'All sections editable, live values, light theme.',
    icon: Icons.tune,
    seed: seedSettings,
    screen: settingsShell,
    brightness: Brightness.light,
    golden: true,
  ),
  Scenario(
    id: 'lab.settings.offline',
    title: 'Settings · offline',
    group: settingsGroup,
    subtitle: 'Last read values, disabled with a reason.',
    icon: Icons.lock_outline,
    seed: (c) => seedSettings(c, offline: true),
    screen: settingsShell,
  ),
  Scenario(
    id: 'bridge_details_dark',
    title: 'Bridge details',
    group: settingsGroup,
    subtitle: 'Status, sync, technical details and Bridge actions.',
    icon: Icons.bluetooth,
    seed: (c) => c
      ..phase = ConnectionPhase.live
      ..slowLink = false
      ..smokeXStatus = SmokeXStatus.pairedLive
      ..smokeXLiveHint = true,
    screen: (c) => BridgeDetailsScreen(controller: c),
    golden: true,
  ),
  Scenario(
    id: 'bridge_details_light',
    title: 'Bridge details · light',
    group: settingsGroup,
    subtitle:
        'Status, sync, technical details and Bridge actions, light theme.',
    icon: Icons.bluetooth,
    seed: (c) => c
      ..phase = ConnectionPhase.live
      ..slowLink = false
      ..smokeXStatus = SmokeXStatus.pairedLive
      ..smokeXLiveHint = true,
    screen: (c) => BridgeDetailsScreen(controller: c),
    brightness: Brightness.light,
    golden: true,
  ),
  Scenario(
    id: 'lab.settings.bridge_details_slow_link',
    title: 'Bridge details · slow link',
    group: settingsGroup,
    subtitle: 'MTU 23 in technical details; sync still works.',
    icon: Icons.bluetooth,
    seed: (c) => c
      ..phase = ConnectionPhase.live
      ..slowLink = true
      ..smokeXStatus = SmokeXStatus.pairedLive
      ..smokeXLiveHint = true,
    screen: (c) => BridgeDetailsScreen(controller: c),
  ),
  Scenario(
    id: 'billows_settings_dark',
    title: 'Billows settings · status only',
    group: settingsGroup,
    subtitle: 'Set temp mirrored from the Smoke X4.',
    icon: Icons.air,
    seed: (c) => c.phase = ConnectionPhase.live,
    screen: (c) => BillowsSettingsScreen(controller: c),
    golden: true,
  ),
  Scenario(
    id: 'lab.settings.billows_lost',
    title: 'Billows settings · lost',
    group: settingsGroup,
    subtitle: 'Detected earlier; connection log explains the drop.',
    icon: Icons.air,
    seed: (c) => c
      ..phase = ConnectionPhase.live
      ..billowsAttachment = BillowsAttachment.detached
      ..billowsSeenThisSession = true,
    screen: (c) => BillowsSettingsScreen(controller: c),
  ),
  Scenario(
    id: 'history_storage_dark',
    title: 'History & storage',
    group: settingsGroup,
    subtitle: 'History on this phone and the Bridge, with explicit deletion.',
    icon: Icons.sd_storage_outlined,
    seed: (c) => c
      ..phase = ConnectionPhase.live
      ..bridgeRecords = 24810
      ..phoneRecords = 128430
      ..savedDataEmpty = false,
    screen: (c) => HistoryStorageScreen(controller: c),
    golden: true,
  ),
  Scenario(
    id: 'history_storage_light',
    title: 'History & storage · light',
    group: settingsGroup,
    subtitle:
        'History on this phone and the Bridge, with explicit deletion, light '
        'theme.',
    icon: Icons.sd_storage_outlined,
    seed: (c) => c
      ..phase = ConnectionPhase.live
      ..bridgeRecords = 24810
      ..phoneRecords = 128430
      ..savedDataEmpty = false,
    screen: (c) => HistoryStorageScreen(controller: c),
    brightness: Brightness.light,
    golden: true,
  ),
  Scenario(
    id: 'lab.settings.history_storage_offline',
    title: 'History & storage · offline',
    group: settingsGroup,
    subtitle: 'Bridge history unavailable offline; phone deletion still works.',
    icon: Icons.lock_outline,
    seed: (c) => c.phase = ConnectionPhase.offline,
    screen: (c) => HistoryStorageScreen(controller: c),
  ),
  Scenario(
    id: 'appearance_dark',
    title: 'Appearance',
    group: settingsGroup,
    subtitle: 'System / light / dark appearance.',
    icon: Icons.palette_outlined,
    seed: (c) => c.phase = ConnectionPhase.live,
    screen: (c) => AppearanceScreen(controller: c),
    golden: true,
  ),
  Scenario(
    id: 'appearance_light',
    title: 'Appearance · light',
    group: settingsGroup,
    subtitle: 'System / light / dark appearance, light theme.',
    icon: Icons.palette_outlined,
    seed: (c) => c.phase = ConnectionPhase.live,
    screen: (c) => AppearanceScreen(controller: c),
    brightness: Brightness.light,
    golden: true,
  ),
  Scenario(
    id: 'lab.settings.about',
    title: 'About',
    group: settingsGroup,
    subtitle: 'Versions, USB-only update, privacy, attribution.',
    icon: Icons.info_outline,
    seed: (c) => c.phase = ConnectionPhase.live,
    screen: (c) => AboutScreen(controller: c),
  ),
  Scenario(
    id: 're_pair_dark',
    title: 'Re-pair Smoke X4 instructions',
    group: settingsGroup,
    subtitle: 'Physical SYNC gesture; keeps log and phone pairings.',
    icon: Icons.sync_alt,
    seed: (c) => c.phase = ConnectionPhase.live,
    screen: (c) => RePairScreen(controller: c),
    golden: true,
  ),
  Scenario(
    id: 'device_log_dark',
    title: 'History on this phone screen',
    group: settingsGroup,
    subtitle: 'The only path to history after the Bridge is forgotten.',
    icon: Icons.folder_open_outlined,
    seed: (c) => c
      ..hasSavedData = true
      ..savedDataEmpty = false
      ..phoneRecords = 128430,
    screen: (c) => SavedDataScreen(controller: c),
    golden: true,
  ),

  // --- Confirmations & results --------------------------------------------
  Scenario(
    id: 'lab.confirm.forget_phone',
    title: 'Forget this phone',
    group: confirmGroup,
    subtitle:
        'Pairing removed; Bridge keeps recording; history on this phone kept.',
    icon: Icons.link_off,
    seed: (c) => seedConfirm(c, DestructiveKind.forgetPhone),
    screen: (c) => ConfirmationPreviewScreen(
      controller: c,
      kind: DestructiveKind.forgetPhone,
    ),
  ),
  Scenario(
    id: 'lab.confirm.clear_bridge_history',
    title: 'Clear history on the Bridge',
    group: confirmGroup,
    subtitle:
        'Erases the Bridge history; keeps pairing and history on this phone.',
    icon: Icons.sd_card_alert_outlined,
    seed: (c) => seedConfirm(c, DestructiveKind.clearBridgeHistory),
    screen: (c) => ConfirmationPreviewScreen(
      controller: c,
      kind: DestructiveKind.clearBridgeHistory,
    ),
  ),
  Scenario(
    id: 'lab.confirm.delete30',
    title: 'Delete older than 30 days',
    group: confirmGroup,
    subtitle: 'Confirmation names count and date range.',
    icon: Icons.delete_outline,
    seed: (c) => seedConfirm(c, DestructiveKind.delete30),
    screen: (c) => ConfirmationPreviewScreen(
      controller: c,
      kind: DestructiveKind.delete30,
    ),
  ),
  Scenario(
    id: 'lab.confirm.delete90',
    title: 'Delete older than 90 days',
    group: confirmGroup,
    subtitle: 'Confirmation names count and date range.',
    icon: Icons.delete_outline,
    seed: (c) => seedConfirm(c, DestructiveKind.delete90),
    screen: (c) => ConfirmationPreviewScreen(
      controller: c,
      kind: DestructiveKind.delete90,
    ),
  ),
  Scenario(
    id: 'lab.confirm.delete_all',
    title: 'Delete all history on this phone',
    group: confirmGroup,
    subtitle: 'Explicit user action only; never automatic.',
    icon: Icons.delete_forever_outlined,
    seed: (c) => seedConfirm(c, DestructiveKind.deleteAll),
    screen: (c) => ConfirmationPreviewScreen(
      controller: c,
      kind: DestructiveKind.deleteAll,
    ),
  ),
  Scenario(
    id: 'confirm_factory_reset_dark',
    title: 'Factory reset',
    group: confirmGroup,
    subtitle: 'Full loss list; disconnect is success; phone data kept.',
    icon: Icons.restart_alt,
    seed: (c) => seedConfirm(c, DestructiveKind.factoryReset),
    screen: (c) => ConfirmationPreviewScreen(
      controller: c,
      kind: DestructiveKind.factoryReset,
    ),
    golden: true,
  ),
  Scenario(
    id: 'confirm_power_off_light',
    title: 'Power off',
    group: confirmGroup,
    subtitle: 'Confirm, then the wake instruction.',
    icon: Icons.power_settings_new,
    seed: (c) => seedConfirm(c, DestructiveKind.powerOff),
    screen: (c) => ConfirmationPreviewScreen(
      controller: c,
      kind: DestructiveKind.powerOff,
    ),
    brightness: Brightness.light,
    golden: true,
  ),
  Scenario(
    id: 'lab.confirm.bridge_off',
    title: 'Bridge is off / wake',
    group: confirmGroup,
    subtitle: 'Post-power-off state and simulated PRG wake.',
    icon: Icons.battery_alert,
    seed: _noSeed,
    screen: (c) => PowerOffScreen(controller: c),
  ),

  // --- Bridge screen (OLED) ------------------------------------------------
  Scenario(
    id: 'oled_page_dark',
    title: 'Page 1 · probes',
    group: deviceGroup,
    subtitle: 'Four probe lines, detached ---, status strip.',
    icon: Icons.monitor,
    seed: (c) => seedDevice(c, page: 1),
    screen: (c) => DevicePreviewScreen(controller: c),
    golden: true,
  ),
  Scenario(
    id: 'lab.device.detached_probe',
    title: 'Page 1 · detached probe',
    group: deviceGroup,
    subtitle: 'P3 shows ---, never 0.0.',
    icon: Icons.monitor,
    seed: (c) => seedDevice(c, presence: ProbePresence.detachedP3),
    screen: (c) => DevicePreviewScreen(controller: c),
  ),
  Scenario(
    id: 'lab.device.page2',
    title: 'Page 2 · link',
    group: deviceGroup,
    subtitle: 'App connected or ready to pair, and Smoke X4 pairing.',
    icon: Icons.monitor,
    seed: (c) => seedDevice(c, page: 2),
    screen: (c) => DevicePreviewScreen(controller: c, initialPage: 2),
  ),
  Scenario(
    id: 'lab.device.page3',
    title: 'Page 3 · Billows',
    group: deviceGroup,
    subtitle: 'Detected, set temp mirrored, status only.',
    icon: Icons.monitor,
    seed: (c) => seedDevice(c, page: 3),
    screen: (c) => DevicePreviewScreen(controller: c, initialPage: 3),
  ),
  Scenario(
    id: 'lab.device.page3_detached',
    title: 'Page 3 · Billows detached',
    group: deviceGroup,
    subtitle: 'Not attached and unknown target; no invented state.',
    icon: Icons.monitor,
    seed: (c) => seedDevice(
      c,
      page: 3,
      attachment: BillowsAttachment.detached,
      targetKnown: false,
    ),
    screen: (c) => DevicePreviewScreen(controller: c, initialPage: 3),
  ),
  Scenario(
    id: 'lab.device.page4',
    title: 'Page 4 · device',
    group: deviceGroup,
    subtitle: 'Battery, storage, readings, uptime, heap.',
    icon: Icons.monitor,
    seed: (c) => seedDevice(c, page: 4),
    screen: (c) => DevicePreviewScreen(controller: c, initialPage: 4),
  ),
  Scenario(
    id: 'oled_passkey_dark',
    title: 'Pairing code overlay',
    group: deviceGroup,
    subtitle: 'Six digits on the Bridge screen during pairing.',
    icon: Icons.pin_outlined,
    seed: (c) => seedDevice(c, overlay: DeviceOverlay.passkey),
    screen: (c) => DevicePreviewScreen(
      controller: c,
      initialOverlay: DeviceOverlay.passkey,
    ),
    golden: true,
  ),
  Scenario(
    id: 'lab.device.power_countdown',
    title: 'Power-off countdown',
    group: deviceGroup,
    subtitle: 'Keep holding, release to cancel/commit.',
    icon: Icons.timer_outlined,
    seed: (c) => seedDevice(c, overlay: DeviceOverlay.power),
    screen: (c) =>
        DevicePreviewScreen(controller: c, initialOverlay: DeviceOverlay.power),
  ),
  Scenario(
    id: 'lab.device.storage_failure',
    title: 'Storage failure overlay',
    group: deviceGroup,
    subtitle: 'Persistent warning; live readings only.',
    icon: Icons.sd_card_alert_outlined,
    seed: (c) => seedDevice(c, overlay: DeviceOverlay.storage),
    screen: (c) => DevicePreviewScreen(
      controller: c,
      initialOverlay: DeviceOverlay.storage,
    ),
  ),
  Scenario(
    id: 'lab.device.resetting',
    title: 'Factory reset progress',
    group: deviceGroup,
    subtitle: 'RESETTING… then reboot; no on-device confirmation.',
    icon: Icons.restart_alt,
    seed: (c) => seedDevice(c, overlay: DeviceOverlay.resetting),
    screen: (c) => DevicePreviewScreen(
      controller: c,
      initialOverlay: DeviceOverlay.resetting,
    ),
  ),
  Scenario(
    id: 'lab.device.clearing',
    title: 'Clear history progress',
    group: deviceGroup,
    subtitle: 'CLEARING LOG… keeps pairing and settings.',
    icon: Icons.delete_sweep_outlined,
    seed: (c) => seedDevice(c, overlay: DeviceOverlay.clearing),
    screen: (c) => DevicePreviewScreen(
      controller: c,
      initialOverlay: DeviceOverlay.clearing,
    ),
  ),
  Scenario(
    id: 'lab.device.off',
    title: 'Power-off committed',
    group: deviceGroup,
    subtitle: 'OFF, then deep sleep until PRG is held.',
    icon: Icons.power_settings_new,
    seed: (c) => seedDevice(c, overlay: DeviceOverlay.off),
    screen: (c) =>
        DevicePreviewScreen(controller: c, initialOverlay: DeviceOverlay.off),
  ),
  Scenario(
    id: 'lab.device.boot',
    title: 'Boot splash',
    group: deviceGroup,
    subtitle: 'Logo and firmware, at least 300 ms.',
    icon: Icons.power,
    seed: (c) => seedDevice(c, overlay: DeviceOverlay.boot),
    screen: (c) =>
        DevicePreviewScreen(controller: c, initialOverlay: DeviceOverlay.boot),
  ),

];

/// Seeds for screens that do not depend on controller state at all.
void _noSeed(BridgeController c) {}

/// Review-only result rows. The product flow always uses live scan results.
List<ScannedBridge> previewScannedBridges() {
  Uint8List advertisement({required int tempF10, required int battery}) {
    final data = Uint8List(11);
    final view = ByteData.sublistView(data);
    view.setUint16(0, 65535, Endian.little);
    data[2] = 1;
    view.setInt16(4, tempF10, Endian.little);
    data[6] = battery;
    return data;
  }

  BleDevice device({
    required String id,
    required String name,
    required int rssi,
    Uint8List? data,
    bool contract = true,
  }) {
    return BleDevice(
      id: id,
      name: name,
      rssi: rssi,
      manufacturerData: data,
      serviceUuids: contract
          ? const <String>[bleContractServiceUuid]
          : const <String>['7f9a0000-4c5b-4b0f-9a3d-1c2e3f405162'],
    );
  }

  return <ScannedBridge>[
    ScannedBridge(
      device: device(
        id: 'fake-A4F2',
        name: 'SmokeX4-A4F2',
        rssi: -60,
        data: advertisement(tempF10: 2250, battery: 87),
      ),
      requiresNewerApp: false,
    ),
    ScannedBridge(
      device: device(
        id: 'fake-B91C',
        name: 'SmokeX4-B91C',
        rssi: -82,
        data: advertisement(tempF10: 1800, battery: 64),
      ),
      requiresNewerApp: false,
    ),
    ScannedBridge(
      device: device(
        id: 'fake-legacy',
        name: 'SmokeX4-LEGACY',
        rssi: -74,
        contract: false,
      ),
      requiresNewerApp: true,
    ),
  ];
}
