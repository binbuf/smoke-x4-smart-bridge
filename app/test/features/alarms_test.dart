/// N11 — the Alerts sheet, the alarm detail and the two-tier exit gate.
///
/// Every surface is rendered through the real bodies against the mock
/// repository: the active list with its Device/Insight tags, acknowledge (which
/// silences but does not resolve), the delivery/test-alarm card, the two
/// separate rule groups, the app-tier rule editor and the preferences.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dev_panel.dart';
import 'package:smoke_bridge/data/model/alarm.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/data/repository/prefs_repository.dart';
import 'package:smoke_bridge/design/design.dart' hide AlarmTier;
import 'package:smoke_bridge/features/alarms/alarm_detail_sheet.dart';
import 'package:smoke_bridge/features/alarms/alarms_sheet.dart';
import 'package:smoke_bridge/features/shell/shell.dart';
import 'package:smoke_bridge/features/shell/shell_screen.dart';

import '../support/load_fonts.dart';

const int _now = 1700000000000;
final DateTime _clock = DateTime(2026, 9, 21, 9, 41);

class _Harness {
  DevOverlay? overlay;
  Map<String, String> props = const <String, String>{};
  String? toast;
  int closed = 0;
  ShellScreen? screen;
}

MockBridgeRepository _repo(String scenario) =>
    MockBridgeRepository(nowMs: _now, initialScenario: scenario);

Future<(_Harness, MockPrefsRepository)> _pump(
  WidgetTester tester,
  Widget child, {
  required MockBridgeRepository repo,
  MockPrefsRepository? prefs,
  _Harness? harness,
}) async {
  tester.view
    ..physicalSize = const Size(500, 4200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final p = prefs ?? MockPrefsRepository();
  addTearDown(p.dispose);
  final h = harness ?? _Harness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bridgeRepositoryProvider.overrideWithValue(repo),
        prefsProvider.overrideWithValue(p),
        alarmsNowProvider.overrideWithValue(_clock),
      ],
      child: MaterialApp(
        theme: SmokeThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShellScope(
              openOverlay: (overlay, [props = const <String, String>{}]) {
                h.overlay = overlay;
                h.props = props;
              },
              closeOverlay: () => h.closed++,
              showToast: (message) => h.toast = message,
              toggleFullGraph: () {},
              openScreen: (screen) => h.screen = screen,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (h, p);
}

void main() {
  setUpAll(loadAppFonts);

  group('exit gate — running raises, tags and acknowledges (N11.1/N11.2)', () {
    testWidgets('the active list carries both tiers, tagged', (tester) async {
      final repo = _repo('running');
      addTearDown(repo.dispose);
      await _pump(tester, const AlarmsSheetBody(onDone: _noop), repo: repo);

      expect(
        find.byKey(const ValueKey<String>('alarms-sheet')),
        findsOneWidget,
      );
      // The critical device alarm and the info app insight, both present.
      expect(
        find.byKey(const ValueKey<String>('alarms-active-pit_crash')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('alarms-active-eta_soon')),
        findsOneWidget,
      );
      // The two tiers are never merged untagged: both tags are on screen.
      expect(find.text('Device'), findsWidgets);
      expect(find.text('Insight'), findsWidgets);
      // The derived stall insight is shown once, untagged as a rule row.
      expect(
        find.byKey(const ValueKey<String>('alarms-finding-stallStarted')),
        findsOneWidget,
      );
    });

    testWidgets('acknowledging silences but does not resolve (N11.9)', (
      tester,
    ) async {
      final repo = _repo('running');
      addTearDown(repo.dispose);
      await _pump(tester, const AlarmsSheetBody(onDone: _noop), repo: repo);

      await tester.tap(
        find.byKey(const ValueKey<String>('alarms-ack-pit_crash')),
      );
      await tester.pumpAndSettle();

      // The alarm is still in the snapshot with acked: true — it is not gone.
      final alarm = repo.current.alarms.firstWhere((a) => a.id == 'pit_crash');
      expect(alarm.acked, isTrue);
      // Acknowledged rows leave the active list.
      expect(
        find.byKey(const ValueKey<String>('alarms-active-pit_crash')),
        findsNothing,
      );
    });

    testWidgets('all-clear replaces the list when nothing is active', (
      tester,
    ) async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      await _pump(tester, const AlarmsSheetBody(onDone: _noop), repo: repo);

      expect(
        find.byKey(const ValueKey<String>('alarms-all-clear')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('alarms-active-eta_soon')),
        findsNothing,
      );
    });
  });

  group(
    'exit gate — offline raises the bridge-unreachable insight (N11.15)',
    () {
      testWidgets('the insight shows once and can be acknowledged', (
        tester,
      ) async {
        final repo = _repo('offline');
        addTearDown(repo.dispose);
        await _pump(tester, const AlarmsSheetBody(onDone: _noop), repo: repo);

        expect(
          find.byKey(
            const ValueKey<String>('alarms-active-bridge_unreachable'),
          ),
          findsOneWidget,
        );
        // Not doubled by the derived finding of the same name.
        expect(
          find.byKey(
            const ValueKey<String>('alarms-finding-bridgeUnreachable'),
          ),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('alarms-ack-bridge_unreachable')),
        );
        await tester.pumpAndSettle();
        expect(
          repo.current.alarms
              .firstWhere((a) => a.ruleId == 'bridge_unreachable')
              .acked,
          isTrue,
        );
      });
    },
  );

  group('delivery (N11.3)', () {
    testWidgets('the verdict and Send a test alarm', (tester) async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      await _pump(tester, const AlarmsSheetBody(onDone: _noop), repo: repo);

      expect(
        find.byKey(const ValueKey<String>('alarms-delivery-verdict')),
        findsOneWidget,
      );
      expect(find.text('This phone will wake you'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('alarms-test')));
      await tester.pumpAndSettle();

      final test = repo.current.alarms.where((a) => a.ruleId == 'test_alarm');
      expect(test, hasLength(1));
      expect(test.single.severity, AlarmSeverity.critical);
      expect(
        find.byKey(ValueKey<String>('alarms-active-${test.single.id}')),
        findsOneWidget,
      );
    });
  });

  group('the two rule groups (N11.4/N11.5/N11.16)', () {
    testWidgets('nine device rules, toggled not invented', (tester) async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      await _pump(tester, const AlarmsSheetBody(onDone: _noop), repo: repo);

      expect(
        repo.alarmRules.where((r) => r.tier == AlarmTier.device),
        hasLength(9),
      );
      expect(find.text('authoritative'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(
          const ValueKey<String>('alarms-device-toggle-target_reached'),
        ),
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>('alarms-device-toggle-target_reached'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        repo.alarmRules.firstWhere((r) => r.id == 'target_reached').enabled,
        isFalse,
      );
    });

    testWidgets('three app rules, with an editor for the app tier only', (
      tester,
    ) async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      await _pump(tester, const AlarmsSheetBody(onDone: _noop), repo: repo);

      expect(
        repo.alarmRules.where((r) => r.tier == AlarmTier.app),
        hasLength(3),
      );
      expect(find.text('never overrides the bridge'), findsOneWidget);

      // Add an insight.
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('alarms-app-add')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('alarms-app-add')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('alarms-app-editor')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('alarms-app-name')),
        'Sauce split',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('alarms-app-save')));
      await tester.pumpAndSettle();
      expect(
        repo.alarmRules.where((r) => r.tier == AlarmTier.app),
        hasLength(4),
      );

      // Delete an app rule; the device rules are untouched.
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('alarms-app-delete-eta_soon')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('alarms-app-delete-eta_soon')),
      );
      await tester.pumpAndSettle();
      expect(
        repo.alarmRules.where((r) => r.tier == AlarmTier.app),
        hasLength(3),
      );
      expect(
        repo.alarmRules.where((r) => r.tier == AlarmTier.device),
        hasLength(9),
      );
      expect(repo.alarmRules.any((r) => r.id == 'eta_soon'), isFalse);
    });
  });

  group('preferences (N11.6)', () {
    testWidgets('the three toggles write the settings tree', (tester) async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      final (_, prefs) = await _pump(
        tester,
        const AlarmsSheetBody(onDone: _noop),
        repo: repo,
      );

      expect(prefs.current.preferManualAlarm, isFalse);
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('alarms-pref-prefer')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('alarms-pref-prefer')),
      );
      await tester.pumpAndSettle();
      expect(prefs.current.preferManualAlarm, isTrue);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('alarms-pref-quiet')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('alarms-pref-quiet')));
      await tester.pumpAndSettle();
      expect(prefs.current.quietHours, isFalse);

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('alarms-pref-monitoring')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('alarms-pref-monitoring')),
      );
      await tester.pumpAndSettle();
      expect(prefs.current.monitoring, isFalse);
      // The monitoring surface follows the setting.
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('alarms-monitoring-copy')),
            )
            .data,
        contains('Background monitoring is off'),
      );
    });
  });

  group('alarm detail (N11.7/N11.8)', () {
    testWidgets('severity card, why-fired rows and the three actions', (
      tester,
    ) async {
      final repo = _repo('running');
      addTearDown(repo.dispose);
      final harness = _Harness();
      await _pump(
        tester,
        AlarmDetailSheetBody(
          alarmId: 'pit_crash',
          onDone: () => harness.closed++,
        ),
        repo: repo,
        harness: harness,
      );

      expect(
        find.byKey(const ValueKey<String>('alarm-detail-severity')),
        findsOneWidget,
      );
      expect(find.text('Pit temperature falling fast'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('alarm-detail-tier')),
        findsOneWidget,
      );
      expect(find.text('Device'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('alarm-detail-why-rule')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('alarm-detail-why-trigger')),
        findsOneWidget,
      );

      // View on graph navigates to the Graph destination.
      await tester.tap(
        find.byKey(const ValueKey<String>('alarm-detail-graph')),
      );
      await tester.pumpAndSettle();
      expect(harness.screen, ShellScreen.graph);
    });

    testWidgets('Snooze silences without acknowledging (N11.8)', (
      tester,
    ) async {
      final repo = _repo('running');
      addTearDown(repo.dispose);
      final harness = _Harness();
      await _pump(
        tester,
        AlarmDetailSheetBody(
          alarmId: 'pit_crash',
          onDone: () => harness.closed++,
        ),
        repo: repo,
        harness: harness,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('alarm-detail-snooze')),
      );
      await tester.pumpAndSettle();

      final alarm = repo.current.alarms.firstWhere((a) => a.id == 'pit_crash');
      expect(alarm.acked, isFalse);
      expect(alarm.snoozedUntilMs, isNotNull);
      expect(harness.closed, 1);
    });

    testWidgets('Acknowledge closes and silences', (tester) async {
      final repo = _repo('running');
      addTearDown(repo.dispose);
      final harness = _Harness();
      await _pump(
        tester,
        AlarmDetailSheetBody(
          alarmId: 'eta_soon',
          onDone: () => harness.closed++,
        ),
        repo: repo,
        harness: harness,
      );

      await tester.tap(find.byKey(const ValueKey<String>('alarm-detail-ack')));
      await tester.pumpAndSettle();
      expect(
        repo.current.alarms.firstWhere((a) => a.id == 'eta_soon').acked,
        isTrue,
      );
      expect(harness.closed, 1);
      // An app alarm states its advisory nature.
      expect(find.textContaining('app insight'), findsOneWidget);
    });

    testWidgets('a gone alarm renders its named state, not an exception', (
      tester,
    ) async {
      final repo = _repo('idle');
      addTearDown(repo.dispose);
      await _pump(
        tester,
        const AlarmDetailSheetBody(alarmId: 'nope'),
        repo: repo,
      );

      expect(
        find.byKey(const ValueKey<String>('alarm-detail-missing')),
        findsOneWidget,
      );
      expect(find.textContaining('no longer active'), findsOneWidget);
    });
  });
}

void _noop() {}
