import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/formatters.dart';
import 'package:smoke_bridge/data/repository.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/features/device/device_preview_screen.dart';
import 'package:smoke_bridge/features/history/history_screen.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/theme/app_theme.dart';

/// T53: one conversion path, locale formatting and the persisted local
/// preferences. The widget cases assert a unit change reaches every visible
/// surface in the next frame, including an already-open Cook view.
void main() {
  group('temperature conversion', () {
    test('one path converts values and deltas, and never stores °C', () {
      expect(toDisplayTemperature(32, Units.fahrenheit), 32);
      expect(toDisplayTemperature(32, Units.celsius), 0);
      expect(toDisplayTemperature(212, Units.celsius), 100);
      expect(toDisplayTemperatureDelta(18, Units.celsius), 10);

      expect(temperatureValue(165.2, Units.fahrenheit), '165.2');
      expect(temperatureValue(165.2, Units.celsius), '74.0');
      // 13 §13.6: no space before the unit.
      expect(temperatureText(165.2, Units.fahrenheit), '165.2°F');
      expect(temperatureText(165.2, Units.celsius), '74.0°C');
      expect(temperatureText(null, Units.celsius), '—');
      expect(temperatureDeltaText(0.4, Units.fahrenheit), '+0.4°F');
    });

    test('a controller unit change repaints all pre-formatted surfaces', () {
      final controller = demoBridgeController();
      addTearDown(controller.dispose);

      final fahrenheitLive = controller.liveView;
      final fahrenheitHistory = controller.historyViewFor();
      expect(fahrenheitLive.probes.first.tempLabel, '165.2°F');
      expect(fahrenheitLive.billows!.setTempText, '225.0°F');
      expect(fahrenheitHistory.stats.first.last, isNotNull);
      expect(fahrenheitHistory.tempFor(fahrenheitHistory.stats.first.last),
          endsWith('°F'));

      controller.setUnits(Units.celsius);

      final celsiusLive = controller.liveView;
      final celsiusHistory = controller.historyViewFor();
      expect(celsiusLive.probes.first.tempLabel, '74.0°C');
      // Billows target is read-only and goes through the same conversion.
      expect(celsiusLive.billows!.setTempText, '107.2°C');
      expect(
        controller.bridgeDetailsView.billows.setTempText,
        '107.2°C',
      );
      expect(
        celsiusHistory.tempFor(celsiusHistory.stats.first.last),
        endsWith('°C'),
      );

      // Samples stay canonical °F; only presentation changed.
      expect(celsiusLive.probes.first.tempF, 165.2);
      expect(celsiusHistory.stats.first.last, fahrenheitHistory.stats.first.last);
      expect(celsiusHistory.fixture.series.first.points.first.valueF,
          fahrenheitHistory.fixture.series.first.points.first.valueF);
    });
  });

  group('locale formatting', () {
    test('counts group by locale', () {
      expect(commaInt(128430, locale: 'en_US'), '128,430');
      expect(commaInt(128430, locale: 'de_DE'), '128.430');
      expect(commaInt(999, locale: 'en_US'), '999');
      expect(commaInt(-128430, locale: 'en_US'), '-128,430');
      expect(storageSizeLabel(9250000, locale: 'en_US'), '9.3 MB');
    });

    test('dates use the locale and never hard-code AM/PM', () {
      final afternoon = DateTime(2026, 10, 27, 13, 5);
      expect(clockLabel(afternoon, use24Hour: true, locale: 'en_US'), '13:05');
      expect(clockLabel(afternoon, use24Hour: false, locale: 'en_US'),
          '1:05 PM');
      expect(
        clockLabel(afternoon, use24Hour: true, locale: 'en_US'),
        isNot(contains('PM')),
      );
      expect(shortDate(DateTime(2026, 9, 1), locale: 'en_US'), 'Sep 1');
      expect(
        shortDateWithYear(DateTime(2026, 9, 1), locale: 'en_US'),
        'Sep 1, 2026',
      );
      expect(
        dateRangeLabel(
          DateTime(2026, 9, 1),
          DateTime(2026, 10, 24),
          locale: 'en_US',
        ),
        'Sep 1 – Oct 24, 2026',
      );
      // A non-English locale picks its own month and clock markers.
      expect(shortDate(DateTime(2026, 3, 1), locale: 'fr_FR'), contains('mars'));
    });

    test('a 24-hour controller formats Bridge reading dates without AM/PM', () {
      final controller = BridgeController(use24Hour: true)
        ..bridgeOldestReadingAt = DateTime(2026, 10, 27, 13, 5);
      addTearDown(controller.dispose);
      final label = controller.settingsView.bridgeOldestReadingLabel;
      expect(label, contains('13:05'));
      expect(label, isNot(contains('PM')));
    });
  });

  group('persisted local preferences', () {
    test('units, Appearance and the Live change window survive relaunch', () async {
      final repository = EmptyBridgeRepository();
      final first = BridgeController(repository: repository);
      first.setUnits(Units.celsius);
      first.setTempChangeWindowMinutes(30);
      first.setThemeMode(ThemeMode.dark);
      await _waitForStored(repository, first);

      final relaunched = BridgeController(repository: repository);
      addTearDown(relaunched.dispose);
      await relaunched.prepareLaunch();

      expect(relaunched.units, Units.celsius);
      expect(relaunched.tempChangeWindowMinutes, 30);
      expect(relaunched.themeMode, ThemeMode.dark);
      expect(relaunched.settingsView.tempChangeWindowMinutes, 30);
      await first.repository.close();
      first.dispose();
    });

    test('an out-of-range saved window is clamped on launch', () async {
      final repository = EmptyBridgeRepository();
      await repository.preferences.write(
        BridgeController.changeWindowPreferenceKey,
        '999',
      );
      final controller = BridgeController(repository: repository);
      addTearDown(controller.dispose);
      await controller.loadLocalPreferences();
      expect(controller.tempChangeWindowMinutes, 60);
    });
  });

  testWidgets('Live, History, Cooks and Billows repaint in the next frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = demoBridgeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: AppShell(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Live probes and the read-only Billows target agree in °F.
    Finder inKey(String key, Finder matching) =>
        find.descendant(of: find.byKey(Key(key)), matching: matching);
    expect(
      inKey('live.probe.1', find.text('165.2°F')),
      findsOneWidget,
    );
    expect(inKey('live.billows', find.text('225.0°F')), findsOneWidget);
    expect(inKey('live.probe.4', find.text('225.0°F')), findsOneWidget);

    controller.setUnits(Units.celsius);
    await tester.pump(); // one frame, no navigation or reopening
    expect(inKey('live.probe.1', find.text('74.0°C')), findsOneWidget);
    expect(inKey('live.billows', find.text('107.2°C')), findsOneWidget);
    expect(inKey('live.probe.4', find.text('107.2°C')), findsOneWidget);
    expect(find.textContaining('°F'), findsNothing);

    // History Summary follows the same change while it is already open.
    controller.setUnits(Units.fahrenheit);
    controller.setTab(AppTab.history);
    await tester.pump();
    expect(inKey('history.summary', find.text('°F')), findsOneWidget);

    controller.setUnits(Units.celsius);
    await tester.pump();
    expect(inKey('history.summary', find.text('°C')), findsOneWidget);
    final celsiusView = controller.historyViewFor();
    final celsiusLast = celsiusView.valueFor(celsiusView.stats.first.last);
    expect(
      inKey('history.summary', find.text('$celsiusLast°')),
      findsWidgets,
    );
    expect(find.textContaining('°F'), findsNothing);

    // An open Cook view also follows the live change.
    final cook = controller.historyView.cooks.first;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: PastCookScreen(controller: controller, cook: cook),
      ),
    );
    await tester.pumpAndSettle();
    controller.setUnits(Units.fahrenheit);
    await tester.pump();
    expect(find.textContaining('°F'), findsWidgets);

    controller.setUnits(Units.celsius);
    await tester.pump();
    expect(find.textContaining('°C'), findsWidgets);
    expect(find.textContaining('°F'), findsNothing);

    // The app-side OLED preview converts through the same view state.
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: DevicePreviewScreen(controller: controller, initialPage: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('107.2°C'), findsOneWidget);
    controller.setUnits(Units.fahrenheit);
    await tester.pump();
    expect(find.text('225.0°F'), findsOneWidget);
  });
}

Future<void> _waitForStored(
  EmptyBridgeRepository repository,
  BridgeController controller,
) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final units = await repository.preferences.read(
      BridgeController.unitsPreferenceKey,
    );
    final window = await repository.preferences.read(
      BridgeController.changeWindowPreferenceKey,
    );
    final theme = await repository.preferences.read(
      BridgeController.themePreferenceKey,
    );
    if (units == 'celsius' && window == '30' && theme == 'dark') return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('preferences were not persisted');
}
