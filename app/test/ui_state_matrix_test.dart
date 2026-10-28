import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/features/settings/bridge_details.dart';
import 'package:smoke_bridge/features/setup/setup_screen.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/theme/app_theme.dart';

/// CI job 4 runs this file explicitly: every stable view state is rendered at
/// the two supported widths, in both themes, with no overflow.
///
/// T54 expands this into the full UI state matrix and copy gate; the cases here
/// are the states that exist after T06/T07.
void main() {
  final states = <_StateCase>[
    _StateCase('live', (controller) => AppShell(controller: controller), 'P1'),
    _StateCase(
      'live offline with cache',
      (controller) => AppShell(controller: controller),
      'P1',
      configure: (controller) => controller
        ..phase = ConnectionPhase.offline
        ..offlineCache = true,
    ),
    _StateCase(
      'history',
      (controller) => AppShell(controller: controller),
      'Summary',
      configure: (controller) => controller.tab = AppTab.history,
    ),
    _StateCase(
      'history empty',
      (controller) => AppShell(controller: controller),
      'Summary',
      configure: (controller) => controller
        ..tab = AppTab.history
        ..historyHasData = false
        ..phoneRecords = 0,
    ),
    _StateCase(
      'settings',
      (controller) => AppShell(controller: controller),
      'Preferences',
      configure: (controller) => controller.tab = AppTab.settings,
    ),
    _StateCase(
      'settings offline',
      (controller) => AppShell(controller: controller),
      'Preferences',
      configure: (controller) => controller
        ..tab = AppTab.settings
        ..phase = ConnectionPhase.offline
        ..offlineCache = true,
    ),
    _StateCase(
      'setup',
      (controller) => SetupScreen(controller: controller, autoAdvance: false),
      'Connect your Bridge',
    ),
    _StateCase(
      'bridge details',
      (controller) => BridgeDetailsScreen(controller: controller),
      'Re-pair Smoke X4',
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
              debugShowCheckedModeBanner: false,
              theme: brightness == Brightness.dark
                  ? AppTheme.dark()
                  : AppTheme.light(),
              home: state.build(controller),
            ),
          );
          await tester.pumpAndSettle();

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
        }
      }
    });
  }
}

class _StateCase {
  const _StateCase(this.name, this.build, this.marker, {this.configure});

  final String name;
  final Widget Function(BridgeController controller) build;
  final String marker;
  final void Function(BridgeController controller)? configure;
}
