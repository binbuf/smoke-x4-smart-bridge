import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/debug/fixtures.dart';
import 'package:smoke_bridge/features/history/history_full_screen.dart';
import 'package:smoke_bridge/features/history/history_screen.dart';
import 'package:smoke_bridge/features/settings/bridge_details.dart';
import 'package:smoke_bridge/features/settings/settings_details.dart';
import 'package:smoke_bridge/features/settings/settings_views.dart';
import 'package:smoke_bridge/features/setup/setup_screen.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/theme/app_theme.dart';
import 'package:smoke_bridge/widgets/probe_chart.dart';
import 'package:smoke_bridge/widgets/prototype_widgets.dart';

/// T54 state matrix.
///
/// CI runs this file explicitly. Every state below is reachable without
/// hardware; each one renders at 320 dp and 390 dp in both themes with no
/// overflow, and keeps its state marker and stable test keys.
void main() {
  final states = <_StateCase>[
    // Live — 13 §13.4 and the post-T36 states.
    _StateCase(
      'live healthy',
      (controller) => AppShell(controller: controller),
      'P1',
    ),
    _StateCase(
      'live aging',
      (controller) => AppShell(controller: controller),
      'Updated 62s ago',
      configure: (controller) => controller.probeHealth = ProbeHealth.aging,
    ),
    _StateCase(
      'live stale X4',
      (controller) => AppShell(controller: controller),
      'No readings',
      configure: (controller) => controller
        ..phase = ConnectionPhase.stale
        ..smokeXAgeOverride = const Duration(minutes: 4),
    ),
    _StateCase(
      'live lost X4',
      (controller) => AppShell(controller: controller),
      'Signal lost',
      configure: (controller) => controller
        ..smokeXStatus = SmokeXStatus.pairedLost
        ..smokeXAgeOverride = const Duration(minutes: 12),
    ),
    _StateCase(
      'live syncing recent',
      (controller) => AppShell(controller: controller),
      'Syncing saved readings',
      configure: (controller) => controller
        ..syncState = SyncState.recent
        ..syncProgressPercent = 42,
    ),
    _StateCase(
      'live backfill',
      (controller) => AppShell(controller: controller),
      'Loading saved readings',
      configure: (controller) => controller
        ..syncState = SyncState.backfill
        ..slowLink = true,
    ),
    _StateCase(
      'live sync failed',
      (controller) => AppShell(controller: controller),
      'History sync failed',
      configure: (controller) => controller.syncState = SyncState.error,
    ),
    _StateCase(
      'live reconnecting',
      (controller) => AppShell(controller: controller),
      'Reconnecting',
      configure: (controller) => controller
        ..phase = ConnectionPhase.reconnecting
        ..offlineCache = true,
    ),
    _StateCase(
      'live failed without cache',
      (controller) => AppShell(controller: controller),
      'Can’t reach the Bridge',
      configure: (controller) => controller
        ..phase = ConnectionPhase.failed
        ..offlineCache = false,
    ),
    _StateCase(
      'live blocked bluetooth',
      (controller) => AppShell(controller: controller),
      'Bluetooth is off',
      configure: (controller) => controller
        ..phase = ConnectionPhase.blocked
        ..blockReason = BlockReason.bluetoothOff,
    ),
    _StateCase(
      'live offline with cache',
      (controller) => AppShell(controller: controller),
      'These are saved readings, not live values. Retry when the Bridge is back in range.',
      configure: (controller) => controller
        ..phase = ConnectionPhase.offline
        ..offlineCache = true,
    ),
    _StateCase(
      'live offline without cache',
      (controller) => AppShell(controller: controller),
      'Bridge disconnected · nothing saved yet',
      configure: (controller) => controller
        ..phase = ConnectionPhase.offline
        ..offlineCache = false,
    ),
    _StateCase(
      'live no probes',
      (controller) => AppShell(controller: controller),
      'No probes connected',
      configure: (controller) => controller.probePresence = ProbePresence.none,
    ),
    _StateCase(
      'live detached probe',
      (controller) => AppShell(controller: controller),
      'Not connected',
      configure: (controller) =>
          controller.probePresence = ProbePresence.detachedP3,
    ),
    _StateCase(
      'live no sparkline history',
      (controller) => AppShell(controller: controller),
      'No history yet',
      configure: (controller) => controller.historyHasData = false,
    ),
    _StateCase(
      'live storage failure',
      (controller) => AppShell(controller: controller),
      'Not recording',
      configure: (controller) => controller.storageOk = false,
    ),
    _StateCase(
      'live billows detected',
      (controller) => AppShell(controller: controller),
      'Billows',
    ),
    _StateCase(
      'live billows lost',
      (controller) => AppShell(controller: controller),
      'Billows not detected',
      configure: (controller) => controller
        ..billowsAttachment = BillowsAttachment.detached
        ..billowsSeenThisSession = true,
    ),
    _StateCase(
      'live billows never detected',
      (controller) => AppShell(controller: controller),
      'Probes',
      configure: (controller) => controller
        ..billowsAttachment = BillowsAttachment.unknown
        ..billowsSeenThisSession = false,
    ),
    _StateCase(
      'live X4 warning dialog',
      (controller) => AppShell(controller: controller),
      'No data from Smoke X4',
      configure: (controller) => controller
        ..smokeXStatus = SmokeXStatus.pairedLive
        ..smokeXAgeOverride = const Duration(minutes: 4),
      interact: (tester) async {
        await tester.tap(find.byKey(const Key('live.smokeXWarning')));
        await tester.pumpAndSettle();
      },
    ),

    // Setup — every step in 13 §13.4.
    for (final entry in _setupSteps.entries)
      _StateCase(
        'setup ${entry.key.name}',
        (controller) => SetupScreen(
          controller: controller,
          initialStep: entry.key,
          autoAdvance: false,
        ),
        entry.value,
        settle: !_animatedSetupSteps.contains(entry.key),
      ),

    // History.
    _StateCase(
      'history default',
      (controller) => AppShell(controller: controller),
      'Summary',
      configure: (controller) => controller.tab = AppTab.history,
    ),
    _StateCase(
      'history custom range sheet',
      (controller) => AppShell(controller: controller),
      'Custom range',
      configure: (controller) => controller.tab = AppTab.history,
      interact: (tester) async {
        await tester.tap(find.byKey(const Key('history.range.menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('history.range.custom')));
        await tester.pumpAndSettle();
      },
    ),
    _StateCase(
      'history probe filter',
      (controller) => AppShell(controller: controller),
      'P1',
      configure: (controller) => controller
        ..tab = AppTab.history
        ..historyRange = HistoryRange.oneHour
        ..historyProbe = 1,
    ),
    _StateCase(
      'history chart help',
      (controller) => AppShell(controller: controller),
      'Reading the chart',
      configure: (controller) => controller.tab = AppTab.history,
      interact: (tester) async {
        await tester.tap(find.byKey(const Key('history.chart.help')));
        await tester.pumpAndSettle();
      },
    ),
    _StateCase(
      'history cooks',
      (controller) => AppShell(controller: controller),
      'Cooks',
      configure: (controller) => controller.tab = AppTab.history,
    ),
    _StateCase(
      'history empty',
      (controller) => AppShell(controller: controller),
      'No readings yet',
      configure: (controller) => controller
        ..tab = AppTab.history
        ..historyHasData = false
        ..phoneRecords = 0,
    ),
    _StateCase(
      'history all saved',
      (controller) => AppShell(controller: controller),
      'Summary',
      configure: (controller) {
        controller
          ..tab = AppTab.history
          ..historyRange = HistoryRange.custom
          ..historyEstimated = true
          ..historyMissingFromBridge = true;
        controller.historyCustomRange = controller.entireHistoryRange;
      },
    ),
    _StateCase(
      'history offline with cache',
      (controller) => AppShell(controller: controller),
      'Showing saved readings',
      configure: (controller) => controller
        ..tab = AppTab.history
        ..phase = ConnectionPhase.offline
        ..offlineCache = true,
    ),
    _StateCase(
      'cook view',
      (controller) => PastCookScreen(
        controller: controller,
        cook: buildCookSessions().first,
      ),
      'Recorded history',
    ),
    _StateCase(
      'full-screen chart',
      (controller) => HistoryFullScreenScreen(controller: controller),
      'P1',
    ),

    // Settings, Bridge details and confirmations.
    _StateCase(
      'settings connected',
      (controller) => AppShell(controller: controller),
      'Preferences',
      configure: (controller) => controller.tab = AppTab.settings,
    ),
    _StateCase(
      'settings offline',
      (controller) => AppShell(controller: controller),
      'Offline',
      configure: (controller) => controller
        ..tab = AppTab.settings
        ..phase = ConnectionPhase.offline
        ..offlineCache = true,
    ),
    _StateCase(
      'settings celsius',
      (controller) => AppShell(controller: controller),
      'Preferences',
      configure: (controller) => controller
        ..tab = AppTab.settings
        ..units = Units.celsius
        ..tempChangeWindowMinutes = 30,
    ),
    _StateCase(
      'bridge details',
      (controller) => BridgeDetailsScreen(controller: controller),
      'Re-pair Smoke X4',
    ),
    _StateCase(
      'bridge details offline',
      (controller) => BridgeDetailsScreen(controller: controller),
      'Re-pair Smoke X4',
      configure: (controller) => controller
        ..phase = ConnectionPhase.offline
        ..offlineCache = true,
    ),
    _StateCase(
      'history storage',
      (controller) => HistoryStorageScreen(controller: controller),
      'History on this phone',
    ),
    _StateCase(
      'appearance',
      (controller) => AppearanceScreen(controller: controller),
      'Appearance',
    ),
    _StateCase(
      'about',
      (controller) => AboutScreen(controller: controller),
      'About',
    ),
    _StateCase(
      'billows settings',
      (controller) => BillowsSettingsScreen(controller: controller),
      'Billows',
    ),
    _StateCase(
      're-pair',
      (controller) => RePairScreen(controller: controller),
      'Re-pair Smoke X4',
    ),
    _StateCase(
      'saved history on phone',
      (controller) => SavedDataScreen(controller: controller),
      'History on this phone',
    ),
    _StateCase(
      'bridge off',
      (controller) => PowerOffScreen(controller: controller),
      'Bridge is off',
    ),
    _StateCase(
      'confirmation power off',
      (controller) => ConfirmationPreviewScreen(
        controller: controller,
        kind: DestructiveKind.powerOff,
      ),
      'Power off the Bridge?',
    ),
    _StateCase(
      'confirmation factory reset',
      (controller) => ConfirmationPreviewScreen(
        controller: controller,
        kind: DestructiveKind.factoryReset,
      ),
      'Factory reset this Bridge?',
    ),
    _StateCase(
      'confirmation forget phone',
      (controller) => ConfirmationPreviewScreen(
        controller: controller,
        kind: DestructiveKind.forgetPhone,
      ),
      'Forget this phone?',
    ),
    _StateCase(
      'confirmation delete history',
      (controller) => ConfirmationPreviewScreen(
        controller: controller,
        kind: DestructiveKind.deleteAll,
      ),
      'Delete all history from this phone?',
    ),
  ];

  for (final state in states) {
    testWidgets('${state.name} fits 320 and 390 dp in both themes', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 3.0;

      for (final width in [320.0, 390.0]) {
        for (final brightness in [Brightness.dark, Brightness.light]) {
          final controller = demoBridgeController();
          addTearDown(controller.dispose);
          state.configure?.call(controller);
          tester.view.physicalSize = Size(width * 3.0, 844.0 * 3.0);

          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey('${state.name}-$width-$brightness'),
              debugShowCheckedModeBanner: false,
              theme: brightness == Brightness.dark
                  ? AppTheme.dark()
                  : AppTheme.light(),
              home: state.build(controller),
            ),
          );
          if (state.settle) {
            await tester.pumpAndSettle();
          } else {
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          }
          if (state.interact != null) await state.interact!(tester);

          expect(
            find.text(state.marker),
            findsWidgets,
            reason:
                '${state.name} at ${width.toInt()} dp in $brightness should '
                'render its state marker',
          );
          expect(
            tester.takeException(),
            isNull,
            reason:
                '${state.name} at ${width.toInt()} dp in $brightness overflowed',
          );
          if (state.name.startsWith('live')) {
            expect(
              find.byKey(const Key('status.connection')),
              findsOneWidget,
              reason: '${state.name} keeps the connection card',
            );
            expect(
              find.byType(SignalBars),
              findsNWidgets(2),
              reason: '${state.name} keeps separate BLE and LoRa meters',
            );
          }
          if (state.name.startsWith('history') &&
              state.name != 'history storage' &&
              state.name != 'history cooks') {
            expect(
              find.byKey(const Key('history.chart')),
              findsWidgets,
              reason: '${state.name} keeps the chart surface',
            );
            if (state.name == 'history default') {
              expect(
                find.byType(HistoryChart),
                findsOneWidget,
                reason: 'the Summary stays the accessible table equivalent',
              );
            }
          }
        }
      }
    });
  }

  testWidgets('stable test keys from 13 §13.8 are present', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: AppShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    for (final key in const [
      'status.connection',
      'status.appBridgeLink',
      'status.x4Link',
      'live.probe.1',
      'live.probe.2',
      'live.probe.3',
      'live.probe.4',
      'live.billows',
    ]) {
      expect(find.byKey(Key(key)), findsWidgets, reason: key);
    }

    controller.setTab(AppTab.history);
    await tester.pumpAndSettle();

    for (final key in const [
      'history.filters',
      'history.range.menu',
      'history.filter.menu',
      'history.chart',
      'history.summary',
      'history.cooks',
      'history.zoom.out',
      'history.zoom.in',
      'history.zoom.fit',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }

    controller.setTab(AppTab.settings);
    await tester.pumpAndSettle();
    for (final key in const [
      'settings.bridge.status',
      'settings.history.logs',
      'settings.units',
      'settings.tempChangeWindow',
      'settings.appearance',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });
}

const _animatedSetupSteps = <SetupStep>{
  SetupStep.scanning,
  SetupStep.bonding,
  SetupStep.firstSync,
};

const _setupSteps = <SetupStep, String>{
  SetupStep.noBridge: 'Connect your Bridge',
  SetupStep.permissionPrimer: 'Allow Bluetooth to find your Bridge',
  SetupStep.bluetoothOff: 'Bluetooth is off',
  SetupStep.permissionDenied: 'Bluetooth permission needed',
  SetupStep.permissionBlocked: 'Bluetooth permission is blocked',
  SetupStep.unsupportedPhone: 'This phone doesn’t support Bluetooth LE',
  SetupStep.scanning: 'SCANNING',
  SetupStep.noResults: 'No Bridge found',
  SetupStep.connectionFailed: 'Couldn’t connect to the Bridge',
  SetupStep.results: 'Nearby bridges',
  SetupStep.protocolMismatch: 'Update the app to use this Bridge',
  SetupStep.passkey: 'Pair with the Bridge',
  SetupStep.bonding: 'Pairing…',
  SetupStep.bondWrongCode: 'The code didn’t match',
  SetupStep.bondTimeout: 'No prompt appeared',
  SetupStep.bondStale: 'This phone’s pairing is out of date',
  SetupStep.bondStoreFull: 'This Bridge already has 4 phones paired',
  SetupStep.firstSync: 'Loading history',
  SetupStep.savedData: 'History on this phone',
};

class _StateCase {
  const _StateCase(
    this.name,
    this.build,
    this.marker, {
    this.configure,
    this.interact,
    this.settle = true,
  });

  final String name;
  final Widget Function(BridgeController controller) build;
  final String marker;
  final void Function(BridgeController controller)? configure;
  final Future<void> Function(WidgetTester tester)? interact;
  final bool settle;
}
