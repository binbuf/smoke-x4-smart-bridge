import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/smoke_bridge_app.dart';
import 'package:smoke_bridge/app/view_state.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/widgets/prototype_widgets.dart';

void main() {
  test('live view state is immutable and fully formatted', () {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);

    final view = controller.liveView;
    expect(view.probes, hasLength(4));
    expect(view.probes.first.valueText, '165.2');
    expect(view.probes.first.unitSuffix, '°F');
    expect(view.probes.first.trendText, startsWith('1h · '));
    expect(() => view.probes.add(view.probes.first), throwsUnsupportedError);

    controller.setUnits(Units.celsius);
    final celsius = controller.liveView;
    expect(celsius.probes.first.valueText, '74.0');
    expect(celsius.probes.first.unitSuffix, '°C');
  });

  test('history view state pre-computes stats, sorting and cooks', () {
    final controller = demoBridgeController()
      ..tab = AppTab.history
      ..historyRange = HistoryRange.twentyFourHours;
    addTearDown(controller.dispose);

    final view = controller.historyViewFor();
    expect(view, isA<HistoryViewState>());
    expect(view.noData, isFalse);
    expect(view.probeCount, 4);
    expect(view.probeMeta, '4 probes');
    expect(view.stats, hasLength(4));
    expect(view.cooks, isNotEmpty);
    expect(view.lastSyncedLabel, 'Synced 2 min ago');

    controller.setHistorySort(HistorySort.hottest);
    final hottest = controller.historyViewFor();
    final values = hottest.stats
        .map((stat) => stat.last)
        .whereType<double>()
        .toList();
    expect(values, isNotEmpty);
    for (var i = 1; i < values.length; i++) {
      expect(values[i - 1], greaterThanOrEqualTo(values[i]));
    }
  });

  test('setup, settings and bridge details expose formatted view state', () {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);

    final setup = controller.setupView;
    expect(setup.phoneRecordsLabel, '128,430');
    expect(setup.savedDataRange, 'Sep 1 – Oct 24, 2026');

    final settings = controller.settingsView;
    expect(settings.phoneRecordsLabel, '128,430');
    expect(settings.bridgeRecordsLabel, '24,810');
    expect(settings.themeModeLabel, 'System');
    expect(settings.tempChangeWindowMinutes, 5);
    controller.setTempChangeWindowMinutes(10);
    expect(controller.settingsView.tempChangeWindowMinutes, 10);

    final details = controller.bridgeDetailsView;
    expect(details.firmware, '0.1.0');
    expect(details.timeoutSubtitle, '1 min · screen turns off');
    expect(details.smokeXLabel, 'Receiving readings');
    expect(details.billows.setTempText, '225.0°F');
  });

  test('empty production content has no fixture values or history', () {
    final controller = BridgeController();
    addTearDown(controller.dispose);

    final live = controller.liveView;
    expect(live.probes.every((probe) => !probe.connected), isTrue);
    expect(live.probes.every((probe) => probe.lastHour.isEmpty), isTrue);

    final history = controller.historyView;
    expect(history.noData, isTrue);
    expect(history.cooks, isEmpty);
    expect(history.stats.every((stat) => stat.last == null), isTrue);

    final settings = controller.settingsView;
    expect(settings.savedDataRange, '—');
    expect(settings.savedDataSize, '0 B');
  });

  testWidgets('ProbeCard renders from ProbeView without a controller', (
    tester,
  ) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    final probe = controller.liveView.probes.first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 240,
            child: ProbeCard(
              probe: probe,
              units: Units.fahrenheit,
              isOffline: false,
              accent: Colors.orange,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('P1'), findsOneWidget);
    expect(find.textContaining('165.2', findRichText: true), findsOneWidget);
    expect(probe.changeText, isNotNull);
    expect(find.text(probe.changeText!), findsOneWidget);
    expect(find.textContaining('Min '), findsOneWidget);
  });

  testWidgets('release entrypoint hides the experimental lab', (tester) async {
    final controller = demoBridgeController();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SmokeBridgeApp(controller: controller, enableExperimentalLab: false),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav.experimental')), findsNothing);

    await tester.pumpWidget(
      SmokeBridgeApp(controller: controller, enableExperimentalLab: true),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nav.experimental')), findsOneWidget);
  });

  test('production tree does not import fixture data or prototype code', () {
    final production = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.contains('debug'))
        .toList();

    for (final file in production) {
      final source = file.readAsStringSync();
      expect(
        source.contains('debug/fixtures.dart'),
        isFalse,
        reason: '${file.path} must not import fixture generators',
      );
      expect(
        source.contains('debug/demo_content.dart'),
        isFalse,
        reason: '${file.path} must not import the demo adapter',
      );
      expect(
        source.contains('prototype/'),
        isFalse,
        reason: '${file.path} must not import prototype code',
      );
    }

    for (final path in [
      'lib/main.dart',
      'lib/app/bootstrap.dart',
      'lib/app/bridge_controller.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source.contains('debug/scenario_lab.dart'), isFalse, reason: path);
    }
  });
}
