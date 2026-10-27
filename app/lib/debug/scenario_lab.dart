import 'package:flutter/material.dart';

import '../app/bridge_controller.dart';
import '../features/device/device_preview_screen.dart';
import '../features/settings/bridge_details.dart';
import '../features/settings/settings_details.dart';
import '../features/settings/settings_views.dart';
import '../features/setup/setup_screen.dart';
import '../features/shell/app_shell.dart';
import '../widgets/prototype_app_bar.dart';
import '../widgets/prototype_widgets.dart';

class ScenarioLabScreen extends StatefulWidget {
  const ScenarioLabScreen({super.key, required this.controller});

  final BridgeController controller;

  @override
  State<ScenarioLabScreen> createState() => _ScenarioLabScreenState();
}

class _ScenarioLabScreenState extends State<ScenarioLabScreen> {
  final _search = TextEditingController();
  String _query = '';

  BridgeController get controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final groups = _groups(context);
        final query = _query.trim().toLowerCase();
        final filtered = groups
            .map(
              (group) => _LabGroup(
                title: group.title,
                description: group.description,
                entries: group.entries
                    .where(
                      (entry) =>
                          query.isEmpty ||
                          entry.title.toLowerCase().contains(query) ||
                          entry.subtitle.toLowerCase().contains(query) ||
                          group.title.toLowerCase().contains(query),
                    )
                    .toList(),
              ),
            )
            .where((group) => group.entries.isNotEmpty)
            .toList();
        final scenarioCount = filtered.fold<int>(
          0,
          (sum, group) => sum + group.entries.length,
        );

        return Scaffold(
          appBar: prototypeAppBar(context, controller, 'Experimental lab'),
          body: ListView(
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(
                                  Icons.science_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'No devices required',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    Text(
                                      'Every screen and state is simulated. Pick a flow to open it directly.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Theme',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          PrototypeThemeToggle(controller: controller),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  controller.reset();
                                  Navigator.of(context)
                                      .popUntil((route) => route.isFirst);
                                },
                                icon: const Icon(Icons.restart_alt, size: 18),
                                label: const Text('Reset lab state'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  _openSetup(context, SetupStep.noBridge);
                                },
                                icon: const Icon(Icons.play_arrow, size: 18),
                                label: const Text('Start first-run flow'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search screens and states',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$scenarioCount ${scenarioCount == 1 ? 'scenario' : 'scenarios'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (filtered.isEmpty) ...[
                      const SizedBox(height: 12),
                      SectionCard(
                        child: Column(
                          children: [
                            const Icon(Icons.search_off, size: 28),
                            const SizedBox(height: 8),
                            Text(
                              _query.trim().isEmpty
                                  ? 'No scenarios available'
                                  : 'No scenarios match “${_query.trim()}”',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              child: const Text('Clear search'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    for (final group in filtered) _GroupCard(group: group),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Prototype only. Bluetooth, storage, sync, and permissions are simulated',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_LabGroup> _groups(BuildContext context) {
    return [
      _LabGroup(
        title: 'Setup & permissions',
        description: 'First run, scanning, pairing, and error states',
        entries: [
          _entry(
            context,
            icon: Icons.bluetooth_searching,
            title: 'No Bridge yet',
            subtitle: 'First launch, no saved Bridge. Find bridge or open history on this phone.',
            onTap: () {
              controller.hasSavedBridge = false;
              controller.hasSavedData = false;
              _openSetup(context, SetupStep.noBridge);
            },
          ),
          _entry(
            context,
            icon: Icons.bluetooth,
            title: 'Permission primer',
            subtitle: 'Explain Nearby devices before the Android prompt.',
            onTap: () => _openSetup(context, SetupStep.permissionPrimer),
          ),
          _entry(
            context,
            icon: Icons.bluetooth_disabled,
            title: 'Bluetooth off',
            subtitle: 'Named blocked state with Open settings and Check again.',
            onTap: () {
              controller.setBlocked(BlockReason.bluetoothOff);
              _openSetup(context, SetupStep.bluetoothOff);
            },
          ),
          _entry(
            context,
            icon: Icons.lock_outline,
            title: 'Permission denied',
            subtitle: 'Grant again or open Android settings.',
            onTap: () {
              controller.setBlocked(BlockReason.permissionDenied);
              _openSetup(context, SetupStep.permissionDenied);
            },
          ),
          _entry(
            context,
            icon: Icons.lock,
            title: 'Permission permanently blocked',
            subtitle: 'The app sends the user to Android app settings.',
            onTap: () {
              controller.setBlocked(BlockReason.permissionBlocked);
              _openSetup(context, SetupStep.permissionBlocked);
            },
          ),
          _entry(
            context,
            icon: Icons.phonelink_erase,
            title: 'Unsupported phone',
            subtitle: 'No Bluetooth LE scanning available.',
            onTap: () => _openSetup(context, SetupStep.unsupportedPhone),
          ),
          _entry(
            context,
            icon: Icons.radar,
            title: 'Scanning',
            subtitle: 'Live scan spinner with cancel and simulated results.',
            onTap: () => _openSetup(context, SetupStep.scanning),
          ),
          _entry(
            context,
            icon: Icons.search_off,
            title: 'No results',
            subtitle: 'Retry, Bluetooth settings, and the asleep-Bridge hint.',
            onTap: () => _openSetup(context, SetupStep.noResults),
          ),
          _entry(
            context,
            icon: Icons.devices_other,
            title: 'Scan results',
            subtitle: 'Last Bridge first, signal words, probe preview, and legacy row.',
            onTap: () => _openSetup(context, SetupStep.results),
          ),
          _entry(
            context,
            icon: Icons.system_update_alt,
            title: 'Protocol mismatch',
            subtitle: '“This Bridge needs a newer app.”',
            onTap: () => _openSetup(context, SetupStep.protocolMismatch),
          ),
          _entry(
            context,
            icon: Icons.pin_outlined,
            title: 'Pairing code instruction',
            subtitle:
                'Look at the Bridge screen, then the simulated Android prompt.',
            onTap: () => _openSetup(context, SetupStep.passkey),
          ),
          _entry(
            context,
            icon: Icons.bluetooth_connected,
            title: 'Pairing in progress',
            subtitle: 'Connecting, pairing, syncing recent history.',
            onTap: () => _openSetup(context, SetupStep.bonding),
          ),
          _entry(
            context,
            icon: Icons.error_outline,
            title: 'Wrong pairing code',
            subtitle: 'Named retry path after a failed pairing.',
            onTap: () => _openSetup(context, SetupStep.bondWrongCode),
          ),
          _entry(
            context,
            icon: Icons.notifications_off_outlined,
            title: 'Pairing prompt timeout',
            subtitle: 'Check the notification shade, then retry.',
            onTap: () => _openSetup(context, SetupStep.bondTimeout),
          ),
          _entry(
            context,
            icon: Icons.link_off,
            title: 'Pairing out of date',
            subtitle:
                'The Bridge was reset; forget the old pairing and re-pair.',
            onTap: () => _openSetup(context, SetupStep.bondStale),
          ),
          _entry(
            context,
            icon: Icons.people_outline,
            title: 'Phone list full',
            subtitle:
                'Four phones already paired; refuse before the Android prompt.',
            onTap: () => _openSetup(context, SetupStep.bondStoreFull),
          ),
          _entry(
            context,
            icon: Icons.cloud_sync_outlined,
            title: 'First sync',
            subtitle: 'Recent 24 h first, then background backfill.',
            onTap: () {
              controller.syncState = SyncState.recent;
              controller.syncProgressPercent = 64;
              _openSetup(context, SetupStep.firstSync);
            },
          ),
          _entry(
            context,
            icon: Icons.folder_open_outlined,
            title: 'History on this phone (after forgetting the Bridge)',
            subtitle: 'History on this phone after a forget/reset, with explicit deletion.',
            onTap: () {
              controller
                ..hasSavedBridge = false
                ..hasSavedData = true
                ..savedDataEmpty = false
                ..phoneRecords = 128430;
              _openSetup(context, SetupStep.savedData);
            },
          ),
        ],
      ),
      _LabGroup(
        title: 'Live & connection',
        description: 'Freshness, probe, Billows, sync, and link states',
        entries: [
          _entry(
            context,
            icon: Icons.thermostat,
            title: 'Live · all probes',
            subtitle: 'Four connected probes, Billows observed, live banner.',
            onTap: () => _openLive(context),
          ),
          _entry(
            context,
            icon: Icons.hourglass_bottom,
            title: 'Live · aging',
            subtitle: 'Amber freshness; still a reading.',
            onTap: () => _openLive(context, health: ProbeHealth.aging),
          ),
          _entry(
            context,
            icon: Icons.schedule,
            title: 'Live · stale',
            subtitle: 'Last reading 4m ago; the Bridge still answers.',
            onTap: () => _openLive(
              context,
              health: ProbeHealth.stale,
              phase: ConnectionPhase.stale,
            ),
          ),
          _entry(
            context,
            icon: Icons.timer_off_outlined,
            title: 'Live · frozen',
            subtitle: 'No readings for 12 min; no derived values.',
            onTap: () => _openLive(
              context,
              health: ProbeHealth.frozen,
              phase: ConnectionPhase.stale,
            ),
          ),
          _entry(
            context,
            icon: Icons.graphic_eq,
            title: 'Live · detached probe 3',
            subtitle: 'Shows — and Not connected, never 0 °F.',
            onTap: () => _openLive(context, presence: ProbePresence.detachedP3),
          ),
          _entry(
            context,
            icon: Icons.signal_cellular_off,
            title: 'Live · no probes',
            subtitle: 'All four probes absent; no invented zeros.',
            onTap: () => _openLive(context, presence: ProbePresence.none),
          ),
          _entry(
            context,
            icon: Icons.sensors_off_outlined,
            title: 'Smoke X4 not sending',
            subtitle: 'The Bridge answers but has not heard the transmitter.',
            onTap: () => _openLive(context, smokeX: false),
          ),
          _entry(
            context,
            icon: Icons.sd_card_alert_outlined,
            title: 'Storage unavailable',
            subtitle: 'Live readings only; this session is not recorded.',
            onTap: () => _openLive(context, storageOk: false),
          ),
          _entry(
            context,
            icon: Icons.sync,
            title: 'Syncing recent',
            subtitle: 'Catch-up banner and progress for the last 24 h.',
            onTap: () => _openLive(
              context,
              phase: ConnectionPhase.syncing,
              sync: SyncState.recent,
            ),
          ),
          _entry(
            context,
            icon: Icons.slow_motion_video,
            title: 'Slow-link backfill',
            subtitle: 'MTU 23 note; backfill continues in the background.',
            onTap: () => _openLive(
              context,
              phase: ConnectionPhase.syncing,
              sync: SyncState.backfill,
              slowLink: true,
            ),
          ),
          _entry(
            context,
            icon: Icons.sync_problem,
            title: 'Reconnecting',
            subtitle: 'Bounded retry with the attempt/backoff state.',
            onTap: () =>
                _openLive(context, phase: ConnectionPhase.reconnecting),
          ),
          _entry(
            context,
            icon: Icons.link_off,
            title: 'Can’t reach the Bridge',
            subtitle: 'All retries failed; tap to retry or forget.',
            onTap: () => _openLive(context, phase: ConnectionPhase.failed),
          ),
          _entry(
            context,
            icon: Icons.bluetooth_disabled,
            title: 'Blocked · Bluetooth off',
            subtitle: 'Global banner names the reason and opens settings.',
            onTap: () {
              controller
                ..phase = ConnectionPhase.blocked
                ..blockReason = BlockReason.bluetoothOff
                ..tab = AppTab.live;
              _openShell(context);
            },
          ),
          _entry(
            context,
            icon: Icons.cloud_off_outlined,
            title: 'Offline with cache',
            subtitle: 'Cached readings, labelled as saved.',
            onTap: () => _openLive(
              context,
              phase: ConnectionPhase.offline,
              offlineCache: true,
            ),
          ),
          _entry(
            context,
            icon: Icons.cloud_off,
            title: 'Offline without cache',
            subtitle: 'Nothing saved yet; one clear next action.',
            onTap: () => _openLive(
              context,
              phase: ConnectionPhase.offline,
              offlineCache: false,
              historyData: false,
            ),
          ),
          _entry(
            context,
            icon: Icons.error_outline,
            title: 'History sync failed',
            subtitle: 'Named catch-up failure with retry; live can continue.',
            onTap: () => _openLive(
              context,
              phase: ConnectionPhase.live,
              sync: SyncState.error,
            ),
          ),
          _entry(
            context,
            icon: Icons.air,
            title: 'Billows · detected',
            subtitle: 'Billows status; set temp mirrors the Smoke X4.',
            onTap: () => _openLive(
              context,
              billowsAttachment: BillowsAttachment.attached,
            ),
          ),
          _entry(
            context,
            icon: Icons.link_off,
            title: 'Billows · lost this session',
            subtitle:
                'Detected earlier, now missing; Live shows a loss notice.',
            onTap: () => _openLive(
              context,
              billowsAttachment: BillowsAttachment.detached,
              smokeXChannel4SetKnown: false,
            ),
          ),
          _entry(
            context,
            icon: Icons.air,
            title: 'Billows · not detected',
            subtitle: 'Never seen this session; Live stays quiet.',
            onTap: () => _openLive(
              context,
              billowsAttachment: BillowsAttachment.unknown,
              billowsSeen: false,
            ),
          ),
          _entry(
            context,
            icon: Icons.air,
            title: 'Billows · lost mid-session',
            subtitle: 'Detected earlier; the fan link now has an issue.',
            onTap: () => _openLive(
              context,
              billowsAttachment: BillowsAttachment.detached,
              billowsSeen: true,
            ),
          ),
        ],
      ),
      _LabGroup(
        title: 'History',
        description:
            'Ranges, gaps, empty states, offline cache, and time estimation',
        entries: [
          _entry(
            context,
            icon: Icons.show_chart,
            title: 'History · 1 hour',
            subtitle: 'Four series with one visible gap.',
            onTap: () => _openHistory(context, HistoryRange.oneHour),
          ),
          _entry(
            context,
            icon: Icons.show_chart,
            title: 'History · 6 hours',
            subtitle: 'Range chip and wider history.',
            onTap: () => _openHistory(context, HistoryRange.sixHours),
          ),
          _entry(
            context,
            icon: Icons.show_chart,
            title: 'History · 24 hours',
            subtitle: 'Range chip and wider history.',
            onTap: () => _openHistory(context, HistoryRange.twentyFourHours),
          ),
          _entry(
            context,
            icon: Icons.show_chart,
            title: 'History · 2 days',
            subtitle: 'Larger range uses bucketed points.',
            onTap: () => _openHistory(context, HistoryRange.twoDays),
          ),
          _entry(
            context,
            icon: Icons.show_chart,
            title: 'History · entire archive',
            subtitle: 'Custom range covering everything in memory.',
            onTap: () => _openHistory(
              context,
              HistoryRange.custom,
              customRange: controller.entireHistoryRange,
            ),
          ),
          _entry(
            context,
            icon: Icons.linear_scale,
            title: 'History · one probe',
            subtitle: 'Only P4 has data; no zero lines for absent probes.',
            onTap: () => _openHistory(
              context,
              HistoryRange.twentyFourHours,
              oneProbe: true,
            ),
          ),
          _entry(
            context,
            icon: Icons.folder_off_outlined,
            title: 'History · empty',
            subtitle: '“No readings yet” with a Bridge-status action.',
            onTap: () =>
                _openHistory(context, HistoryRange.oneHour, hasData: false),
          ),
          _entry(
            context,
            icon: Icons.cloud_off_outlined,
            title: 'History · offline cache',
            subtitle: 'Cached history labelled “Showing saved readings”.',
            onTap: () =>
                _openHistory(context, HistoryRange.sixHours, offline: true),
          ),
          _entry(
            context,
            icon: Icons.cloud_off,
            title: 'History · offline, no cache',
            subtitle: 'Nothing saved on this phone; retry is the next step.',
            onTap: () => _openHistory(
              context,
              HistoryRange.oneHour,
              hasData: false,
              offline: true,
              offlineCache: false,
            ),
          ),
          _entry(
            context,
            icon: Icons.schedule,
            title: 'History · estimated time',
            subtitle: 'Clock was unknown; axis is labelled estimated.',
            onTap: () => _openHistory(
              context,
              HistoryRange.twentyFourHours,
              estimated: true,
            ),
          ),
          _entry(
            context,
            icon: Icons.link_off,
            title: 'History overwritten before sync',
            subtitle: 'Permanent gap marker and explanation.',
            onTap: () =>
                _openHistory(context, HistoryRange.twoDays, missing: true),
          ),
        ],
      ),
      _LabGroup(
        title: 'Settings',
        description: 'Bridge, preferences, Billows, history, and About',
        entries: [
          _entry(
            context,
            icon: Icons.tune,
            title: 'Settings · connected',
            subtitle: 'All sections editable, live values.',
            onTap: () => _openSettings(context),
          ),
          _entry(
            context,
            icon: Icons.lock_outline,
            title: 'Settings · offline',
            subtitle: 'Last read values, disabled with a reason.',
            onTap: () => _openSettings(context, offline: true),
          ),
          _entry(
            context,
            icon: Icons.bluetooth,
            title: 'Bridge details',
            subtitle: 'Status, sync, technical details and Bridge actions.',
            onTap: () {
              controller
                ..phase = ConnectionPhase.live
                ..slowLink = false
                ..smokeXStatus = SmokeXStatus.pairedLive
                ..smokeXLiveHint = true;
              _push(context, BridgeDetailsScreen(controller: controller));
            },
          ),
          _entry(
            context,
            icon: Icons.bluetooth_searching,
            title: 'Bridge details · slow link',
            subtitle: 'MTU 23 in technical details; sync still works.',
            onTap: () {
              controller
                ..phase = ConnectionPhase.live
                ..slowLink = true
                ..smokeXStatus = SmokeXStatus.pairedLive
                ..smokeXLiveHint = true;
              _push(context, BridgeDetailsScreen(controller: controller));
            },
          ),
          _entry(
            context,
            icon: Icons.air,
            title: 'Billows settings · status only',
            subtitle: 'Set temp mirrored from the Smoke X4.',
            onTap: () {
              controller.phase = ConnectionPhase.live;
              _push(context, BillowsSettingsScreen(controller: controller));
            },
          ),
          _entry(
            context,
            icon: Icons.air,
            title: 'Billows settings · lost',
            subtitle: 'Detected earlier; connection log explains the drop.',
            onTap: () {
              controller
                ..phase = ConnectionPhase.live
                ..billowsAttachment = BillowsAttachment.detached
                ..billowsSeenThisSession = true;
              _push(context, BillowsSettingsScreen(controller: controller));
            },
          ),
          _entry(
            context,
            icon: Icons.sd_storage_outlined,
            title: 'History & storage',
            subtitle:
                'History on this phone and the Bridge, with explicit deletion.',
            onTap: () {
              controller
                ..phase = ConnectionPhase.live
                ..bridgeRecords = 24810
                ..phoneRecords = 128430
                ..savedDataEmpty = false;
              _push(context, HistoryStorageScreen(controller: controller));
            },
          ),
          _entry(
            context,
            icon: Icons.lock_outline,
            title: 'History & storage · offline',
            subtitle: 'Bridge history unavailable offline; phone deletion still works.',
            onTap: () {
              controller.phase = ConnectionPhase.offline;
              _push(context, HistoryStorageScreen(controller: controller));
            },
          ),
          _entry(
            context,
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'System, light and dark palettes.',
            onTap: () {
              controller.phase = ConnectionPhase.live;
              _push(context, AppearanceScreen(controller: controller));
            },
          ),
          _entry(
            context,
            icon: Icons.info_outline,
            title: 'About',
            subtitle: 'Versions, USB-only update, privacy, attribution.',
            onTap: () {
              controller.phase = ConnectionPhase.live;
              _push(context, AboutScreen(controller: controller));
            },
          ),
          _entry(
            context,
            icon: Icons.sync_alt,
            title: 'Re-pair Smoke X4 instructions',
            subtitle: 'Physical SYNC gesture; keeps log and phone pairings.',
            onTap: () {
              controller.phase = ConnectionPhase.live;
              _push(context, RePairScreen(controller: controller));
            },
          ),
          _entry(
            context,
            icon: Icons.folder_open_outlined,
            title: 'History on this phone screen',
            subtitle: 'The only path to history after the Bridge is forgotten.',
            onTap: () {
              controller.hasSavedData = true;
              controller.savedDataEmpty = false;
              controller.phoneRecords = 128430;
              _push(context, SavedDataScreen(controller: controller));
            },
          ),
        ],
      ),
      _LabGroup(
        title: 'Confirmations & results',
        description: 'Destructive confirmations and their outcomes',
        entries: [
          _entry(
            context,
            icon: Icons.link_off,
            title: 'Forget this phone',
            subtitle: 'Pairing removed; Bridge keeps recording; history on this phone kept.',
            onTap: () => _openConfirm(context, DestructiveKind.forgetPhone),
          ),
          _entry(
            context,
            icon: Icons.sd_card_alert_outlined,
            title: 'Clear history on the Bridge',
            subtitle: 'Erases the Bridge history; keeps pairing and history on this phone.',
            onTap: () =>
                _openConfirm(context, DestructiveKind.clearBridgeHistory),
          ),
          _entry(
            context,
            icon: Icons.delete_outline,
            title: 'Delete older than 30 days',
            subtitle: 'Confirmation names count and date range.',
            onTap: () => _openConfirm(context, DestructiveKind.delete30),
          ),
          _entry(
            context,
            icon: Icons.delete_outline,
            title: 'Delete older than 90 days',
            subtitle: 'Confirmation names count and date range.',
            onTap: () => _openConfirm(context, DestructiveKind.delete90),
          ),
          _entry(
            context,
            icon: Icons.delete_forever_outlined,
            title: 'Delete all history on this phone',
            subtitle: 'Explicit user action only; never automatic.',
            onTap: () => _openConfirm(context, DestructiveKind.deleteAll),
          ),
          _entry(
            context,
            icon: Icons.restart_alt,
            title: 'Factory reset',
            subtitle: 'Full loss list; disconnect is success; phone data kept.',
            onTap: () => _openConfirm(context, DestructiveKind.factoryReset),
          ),
          _entry(
            context,
            icon: Icons.power_settings_new,
            title: 'Power off',
            subtitle: 'Confirm, then the wake instruction.',
            onTap: () => _openConfirm(context, DestructiveKind.powerOff),
          ),
          _entry(
            context,
            icon: Icons.battery_alert,
            title: 'Bridge is off / wake',
            subtitle: 'Post-power-off state and simulated PRG wake.',
            onTap: () => _push(context, PowerOffScreen(controller: controller)),
          ),
        ],
      ),
      _LabGroup(
        title: 'Bridge screen (OLED)',
        description:
            'The other UI surface: pages, pairing code, power, storage',
        entries: [
          _entry(
            context,
            icon: Icons.monitor,
            title: 'Page 1 · probes',
            subtitle: 'Four probe lines, detached ---, status strip.',
            onTap: () => _openDevice(context, page: 1),
          ),
          _entry(
            context,
            icon: Icons.monitor,
            title: 'Page 1 · detached probe',
            subtitle: 'P3 shows ---, never 0.0.',
            onTap: () => _openDevice(
              context,
              page: 1,
              presence: ProbePresence.detachedP3,
            ),
          ),
          _entry(
            context,
            icon: Icons.monitor,
            title: 'Page 2 · link',
            subtitle: 'App connected or ready to pair, and Smoke X4 pairing.',
            onTap: () => _openDevice(context, page: 2),
          ),
          _entry(
            context,
            icon: Icons.monitor,
            title: 'Page 3 · Billows',
            subtitle: 'Detected, set temp mirrored, status only.',
            onTap: () => _openDevice(context, page: 3),
          ),
          _entry(
            context,
            icon: Icons.monitor,
            title: 'Page 3 · Billows detached',
            subtitle: 'Not attached and unknown target; no invented state.',
            onTap: () => _openDevice(
              context,
              page: 3,
              attachment: BillowsAttachment.detached,
              targetKnown: false,
            ),
          ),
          _entry(
            context,
            icon: Icons.monitor,
            title: 'Page 4 · device',
            subtitle: 'Battery, storage, readings, uptime, heap.',
            onTap: () => _openDevice(context, page: 4),
          ),
          _entry(
            context,
            icon: Icons.pin_outlined,
            title: 'Pairing code overlay',
            subtitle: 'Six digits on the Bridge screen during pairing.',
            onTap: () =>
                _openDevice(context, page: 1, overlay: DeviceOverlay.passkey),
          ),
          _entry(
            context,
            icon: Icons.timer_outlined,
            title: 'Power-off countdown',
            subtitle: 'Keep holding, release to cancel/commit.',
            onTap: () =>
                _openDevice(context, page: 1, overlay: DeviceOverlay.power),
          ),
          _entry(
            context,
            icon: Icons.sd_card_alert_outlined,
            title: 'Storage failure overlay',
            subtitle: 'Persistent warning; live readings only.',
            onTap: () =>
                _openDevice(context, page: 1, overlay: DeviceOverlay.storage),
          ),
          _entry(
            context,
            icon: Icons.restart_alt,
            title: 'Factory reset progress',
            subtitle: 'RESETTING… then reboot; no on-device confirmation.',
            onTap: () =>
                _openDevice(context, page: 1, overlay: DeviceOverlay.resetting),
          ),
          _entry(
            context,
            icon: Icons.delete_sweep_outlined,
            title: 'Clear history progress',
            subtitle: 'CLEARING LOG… keeps pairing and settings.',
            onTap: () =>
                _openDevice(context, page: 1, overlay: DeviceOverlay.clearing),
          ),
          _entry(
            context,
            icon: Icons.power_settings_new,
            title: 'Power-off committed',
            subtitle: 'OFF, then deep sleep until PRG is held.',
            onTap: () =>
                _openDevice(context, page: 1, overlay: DeviceOverlay.off),
          ),
          _entry(
            context,
            icon: Icons.power,
            title: 'Boot splash',
            subtitle: 'Logo and firmware, at least 300 ms.',
            onTap: () =>
                _openDevice(context, page: 1, overlay: DeviceOverlay.boot),
          ),
        ],
      ),
    ];
  }

  _LabEntry _entry(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return _LabEntry(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  void _openSetup(BuildContext context, SetupStep step) {
    _push(
      context,
      SetupScreen(
        controller: controller,
        initialStep: step,
        autoAdvance: false,
      ),
    );
  }

  void _openLive(
    BuildContext context, {
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
    controller
      ..phase = phase
      ..probeHealth = health
      ..probePresence = presence
      ..smokeXLiveHint = smokeX
      ..smokeXStatus = smokeX
          ? SmokeXStatus.pairedLive
          : SmokeXStatus.pairedLost
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
    _openShell(context);
  }

  void _openHistory(
    BuildContext context,
    HistoryRange range, {
    bool hasData = true,
    bool oneProbe = false,
    bool estimated = false,
    bool missing = false,
    bool offline = false,
    bool offlineCache = true,
    DateTimeRange? customRange,
  }) {
    controller
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
    _openShell(context);
  }

  void _openSettings(BuildContext context, {bool offline = false}) {
    controller
      ..phase = offline ? ConnectionPhase.offline : ConnectionPhase.live
      ..offlineCache = true
      ..bridgeRecords = 24810
      ..phoneRecords = 128430
      ..savedDataEmpty = false
      ..saveState = SettingsSaveState.idle
      ..tab = AppTab.settings;
    _openShell(context);
  }

  void _openConfirm(BuildContext context, DestructiveKind kind) {
    if (kind == DestructiveKind.delete30 ||
        kind == DestructiveKind.delete90 ||
        kind == DestructiveKind.deleteAll) {
      controller
        ..phoneRecords = 128430
        ..savedDataEmpty = false;
    }
    if (kind == DestructiveKind.clearBridgeHistory) {
      controller.bridgeRecords = 24810;
    }
    _push(
      context,
      ConfirmationPreviewScreen(controller: controller, kind: kind),
    );
  }

  void _openDevice(
    BuildContext context, {
    required int page,
    DeviceOverlay overlay = DeviceOverlay.none,
    ProbePresence presence = ProbePresence.all,
    BillowsAttachment attachment = BillowsAttachment.attached,
    bool targetKnown = true,
  }) {
    controller
      ..phase = ConnectionPhase.live
      ..probeHealth = ProbeHealth.live
      ..probePresence = presence
      ..smokeXLiveHint = true
      ..smokeXStatus = SmokeXStatus.pairedLive
      ..billowsAttachment = attachment
      ..smokeXChannel4SetKnown = targetKnown
      ..smokeXChannel4SetF = 225
      ..bridgeRecords = 24810;
    _push(
      context,
      DevicePreviewScreen(
        controller: controller,
        initialPage: page,
        initialOverlay: overlay,
      ),
    );
  }

  void _openShell(BuildContext context) {
    _push(context, AppShell(controller: controller));
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _LabGroup {
  const _LabGroup({
    required this.title,
    required this.description,
    required this.entries,
  });

  final String title;
  final String description;
  final List<_LabEntry> entries;
}

class _LabEntry {
  const _LabEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final _LabGroup group;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              group.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              group.description,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < group.entries.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        group.entries[i].icon,
                        size: 19,
                        color: scheme.primary,
                      ),
                    ),
                    title: Text(
                      group.entries[i].title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      group.entries[i].subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: group.entries[i].onTap,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
