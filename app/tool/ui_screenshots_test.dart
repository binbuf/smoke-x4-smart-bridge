import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/features/device/device_preview_screen.dart';
import 'package:smoke_bridge/features/history/history_screen.dart';
import 'package:smoke_bridge/features/settings/bridge_details.dart';
import 'package:smoke_bridge/features/settings/settings_details.dart';
import 'package:smoke_bridge/features/settings/settings_views.dart';
import 'package:smoke_bridge/features/setup/setup_screen.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/prototype/prototype_controller.dart';
import 'package:smoke_bridge/prototype/scenario_lab.dart';
import 'package:smoke_bridge/theme/app_theme.dart';

Future<void> _loadFont(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    final root =
        '${Platform.environment['FLUTTER_ROOT'] ?? r'D:\flutter'}/bin/cache/artifacts/material_fonts';
    await _loadFont('Roboto', '$root/roboto-regular.ttf');
    await _loadFont('Roboto', '$root/roboto-bold.ttf');
    await _loadFont('MaterialIcons', '$root/materialicons-regular.otf');
  });

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget screen, {
    Brightness brightness = Brightness.dark,
    bool settle = true,
    Future<void> Function(WidgetTester tester)? interact,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final theme = brightness == Brightness.dark
        ? AppTheme.dark()
        : AppTheme.light();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
          ),
          home: screen,
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    if (interact != null) {
      await interact(tester);
      await tester.pumpAndSettle();
    }
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('../screenshots/$name.png'),
    );
  }

  testWidgets('live dark', (tester) async {
    final controller = PrototypeController();
    await shot(tester, 'live_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('live light', (tester) async {
    final controller = PrototypeController();
    await shot(
      tester,
      'live_light',
      AppShell(controller: controller),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('live billows control', (tester) async {
    final controller = PrototypeController()
      ..billowsControlCapability = true
      ..billowsMode = BillowsMode.control;
    await shot(
      tester,
      'live_billows_control',
      AppShell(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('live offline cache', (tester) async {
    final controller = PrototypeController()
      ..phase = ConnectionPhase.offline
      ..offlineCache = true;
    await shot(tester, 'live_offline_cache', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('history dark', (tester) async {
    final controller = PrototypeController()
      ..tab = AppTab.history
      ..historyRange = HistoryRange.twentyFourHours
      ..historyMissingFromBridge = true;
    await shot(tester, 'history_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('history light', (tester) async {
    final controller = PrototypeController()..tab = AppTab.history;
    await shot(
      tester,
      'history_light',
      AppShell(controller: controller),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('history all dark', (tester) async {
    final controller = PrototypeController()
      ..tab = AppTab.history
      ..historyRange = HistoryRange.all
      ..historyEstimated = true;
    await shot(tester, 'history_all_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('history days dark', (tester) async {
    final controller = PrototypeController()
      ..tab = AppTab.history
      ..historyRange = HistoryRange.sevenDays;
    await shot(
      tester,
      'history_days_dark',
      AppShell(controller: controller),
      interact: (tester) async {
        await tester.drag(find.byType(ListView).first, const Offset(0, -520));
      },
    );
    controller.dispose();
  });

  testWidgets('history probe filter dark', (tester) async {
    final controller = PrototypeController()
      ..tab = AppTab.history
      ..historyRange = HistoryRange.oneHour
      ..historyProbe = 1;
    await shot(tester, 'history_filter_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('history no data dark', (tester) async {
    final controller = PrototypeController()
      ..tab = AppTab.history
      ..historyHasData = false
      ..phoneRecords = 0;
    await shot(tester, 'history_empty_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('history probe no data dark', (tester) async {
    final controller = PrototypeController()
      ..tab = AppTab.history
      ..historyOneProbe = true
      ..historyProbe = 1
      ..historyRange = HistoryRange.oneHour;
    await shot(
      tester,
      'history_probe_empty_dark',
      AppShell(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('settings dark', (tester) async {
    final controller = PrototypeController()..tab = AppTab.settings;
    await shot(tester, 'settings_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('settings light', (tester) async {
    final controller = PrototypeController()..tab = AppTab.settings;
    await shot(
      tester,
      'settings_light',
      AppShell(controller: controller),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('bridge details dark', (tester) async {
    final controller = PrototypeController();
    await shot(
      tester,
      'bridge_details_dark',
      BridgeDetailsScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('history storage dark', (tester) async {
    final controller = PrototypeController();
    await shot(
      tester,
      'history_storage_dark',
      HistoryStorageScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('appearance dark', (tester) async {
    final controller = PrototypeController();
    await shot(
      tester,
      'appearance_dark',
      AppearanceScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('setup dark', (tester) async {
    final controller = PrototypeController();
    await shot(
      tester,
      'setup_dark',
      SetupScreen(controller: controller, autoAdvance: false),
    );
    controller.dispose();
  });

  testWidgets('passkey dark', (tester) async {
    final controller = PrototypeController();
    await shot(
      tester,
      'passkey_dark',
      SetupScreen(
        controller: controller,
        initialStep: SetupStep.passkey,
        autoAdvance: false,
      ),
    );
    controller.dispose();
  });

  testWidgets('scenario lab dark', (tester) async {
    final controller = PrototypeController();
    await shot(
      tester,
      'scenario_lab_dark',
      ScenarioLabScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('oled page dark', (tester) async {
    final controller = PrototypeController();
    await shot(
      tester,
      'oled_page_dark',
      DevicePreviewScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('oled passkey dark', (tester) async {
    final controller = PrototypeController();
    await shot(
      tester,
      'oled_passkey_dark',
      DevicePreviewScreen(
        controller: controller,
        initialOverlay: DeviceOverlay.passkey,
      ),
    );
    controller.dispose();
  });

  testWidgets('re-pair dark', (tester) async {
    final controller = PrototypeController();
    await shot(tester, 're_pair_dark', RePairScreen(controller: controller));
    controller.dispose();
  });

  testWidgets('phone history dark', (tester) async {
    final controller = PrototypeController()..hasSavedData = true;
    await shot(
      tester,
      'phone_history_dark',
      SavedDataScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('billows settings control dark', (tester) async {
    final controller = PrototypeController()
      ..billowsControlCapability = true
      ..billowsMode = BillowsMode.control;
    await shot(
      tester,
      'billows_settings_control_dark',
      BillowsSettingsScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('factory reset confirmation dark', (tester) async {
    final controller = PrototypeController();
    await shot(
      tester,
      'confirm_factory_reset_dark',
      ConfirmationPreviewScreen(
        controller: controller,
        kind: DestructiveKind.factoryReset,
      ),
    );
    controller.dispose();
  });

  testWidgets('history standalone full screen dark', (tester) async {
    final controller = PrototypeController()
      ..tab = AppTab.history
      ..historyRange = HistoryRange.all
      ..historyEstimated = true;
    await shot(
      tester,
      'history_fullscreen_dark',
      HistoryScreen(controller: controller, fullScreen: true),
    );
    controller.dispose();
  });
}
