import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/features/live/live_screen.dart';
import 'package:smoke_bridge/features/settings/settings_details.dart';
import 'package:smoke_bridge/theme/app_theme.dart';

import 'support/fake_bridge_session.dart';

/// T57: the observation-only Billows surfaces.
///
/// The target is the Smoke X4 set temp validated by T56 (probe 4 max). `0` is
/// unknown and must render `—`, never a guessed 225 °F. There is no target
/// editor, mode switch or fan claim in this build.
void main() {
  Future<FakeBridgeSession> pumpLive(
    WidgetTester tester, {
    required void Function(FakeBridgeSession session) drive,
  }) async {
    final session = FakeBridgeSession();
    addTearDown(session.dispose);
    drive(session);

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: LiveScreen(controller: session.controller)),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  void healthy(FakeBridgeSession session) {
    session.driveLiveState(
      phase: ConnectionPhase.live,
      probeTemps: const <double?>[225.0, 165.2, null, 80.0],
      smokeXAge: const Duration(seconds: 12),
      smokeXStatus: SmokeXStatus.pairedLive,
      probeHealth: ProbeHealth.live,
      billowsAttachment: BillowsAttachment.attached,
      billowsSeenThisSession: true,
      offlineCache: true,
    );
  }

  testWidgets('known target renders the Smoke X4 set temp and source line', (
    tester,
  ) async {
    final session = await pumpLive(
      tester,
      drive: (session) {
        healthy(session);
        session.driveLiveState(
          billowsTargetKnown: true,
          billowsTargetF: 250,
          billowsLastDetectedAt: session.controller.content.now.subtract(
            const Duration(seconds: 12),
          ),
        );
      },
    );

    final card = find.byKey(const Key('live.billows'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('250.0°F')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('12s ago')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Set on the Smoke X.')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Connected')),
      findsNothing,
    );
    expect(find.textContaining('Read-only'), findsNothing);
    expect(find.text('Set target'), findsNothing);

    // The controller exposes the same value, not a build-time fixture.
    expect(session.controller.liveView.billows!.setTempText, '250.0°F');
  });

  testWidgets('unknown target renders — and never guesses 225 °F', (
    tester,
  ) async {
    await pumpLive(
      tester,
      drive: (session) {
        healthy(session);
        session.driveLiveState(
          billowsTargetKnown: false,
          billowsTargetF: 225,
          billowsLastDetectedAt: session.controller.content.now.subtract(
            const Duration(seconds: 30),
          ),
        );
      },
    );

    final card = find.byKey(const Key('live.billows'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('225.0°F')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.text('Set on the Smoke X.')),
      findsOneWidget,
    );
  });

  testWidgets('offline Billows shows last observed state and last-known temp', (
    tester,
  ) async {
    final controller = demoBridgeController()
      ..phase = ConnectionPhase.offline
      ..offlineCache = true
      ..billowsAttachment = BillowsAttachment.detached
      ..billowsSeenThisSession = true
      ..smokeXChannel4SetKnown = true
      ..smokeXChannel4SetF = 250
      ..billowsLastDetectedAt = null
      ..billowsLostAt = null;
    addTearDown(controller.dispose);
    // Fixture time is fixed; anchor the age to it, not the wall clock.
    controller.billowsLastDetectedAt = controller.content.now.subtract(
      const Duration(minutes: 2),
    );
    controller.billowsLostAt = controller.content.now.subtract(
      const Duration(minutes: 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: BillowsSettingsScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Last observed state'), findsNothing);
    expect(find.text('Last observed status'), findsOneWidget);
    expect(find.text('Set temp (last known)'), findsOneWidget);
    expect(find.text('250.0°F'), findsOneWidget);
    expect(find.text('2 min ago'), findsWidgets);
    expect(find.text('Billows lost'), findsOneWidget);
    expect(find.text('Set target'), findsNothing);
    expect(find.text('Control'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('lost-this-session age comes from the real last detection', (
    tester,
  ) async {
    final controller = demoBridgeController()
      ..phase = ConnectionPhase.live
      ..billowsAttachment = BillowsAttachment.detached
      ..billowsSeenThisSession = true
      ..smokeXChannel4SetKnown = false;
    addTearDown(controller.dispose);
    controller.billowsLastDetectedAt = controller.content.now.subtract(
      const Duration(seconds: 90),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: BillowsSettingsScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 min ago'), findsWidgets);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Detected'), findsNothing);
  });

  test('no app path sends set_billows_target', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('ControlOp.setBillowsTarget')) {
        hits.add(entity.path);
      }
    }
    expect(
      hits,
      isEmpty,
      reason: 'Billows is observation-only; control op 6 is reserved',
    );
  });
}
