import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/motion.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/features/settings/settings_details.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/theme/app_theme.dart';

/// T54 accessibility gate: WCAG AA contrast, 48 dp targets, screen-reader
/// semantics, reduced motion and no colour-only status.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Brightness brightness = Brightness.dark,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('WCAG AA contrast', () {
    for (final brightness in Brightness.values) {
      testWidgets('status and primary text clear 4.5:1 in $brightness', (
        tester,
      ) async {
        final theme = brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light();
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        final scheme = theme.colorScheme;
        final surfaces = <String, Color>{
          'surface': scheme.surface,
          'scaffold': theme.scaffoldBackgroundColor,
          'card': theme.cardTheme.color ?? scheme.surface,
          'raised': scheme.surfaceContainerHigh,
          'highest': scheme.surfaceContainerHighest,
        };
        final foregrounds = <String, Color>{
          'onSurface': scheme.onSurface,
          'primary': scheme.primary,
          'error': scheme.error,
          'live': StatusColors.live(context),
          'aging': StatusColors.aging(context),
          'stale': StatusColors.stale(context),
        };
        for (final background in surfaces.entries) {
          for (final foreground in foregrounds.entries) {
            final ratio = _contrast(foreground.value, background.value);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '${foreground.key} on ${background.key} is '
                  '${ratio.toStringAsFixed(2)}:1 in $brightness',
            );
          }
        }
        // Probe series colours are also used for small legend labels.
        for (final color in ProbeColors.of(context)) {
          for (final background in surfaces.entries) {
            expect(
              _contrast(color, background.value),
              greaterThanOrEqualTo(4.5),
              reason: 'probe colour ${color.toARGB32().toRadixString(16)} on '
                  '${background.key} in $brightness',
            );
          }
        }
      });
    }
  });

  group('48 dp touch targets', () {
    testWidgets('History chart controls and filters are at least 48 dp', (
      tester,
    ) async {
      final controller = demoBridgeController()..tab = AppTab.history;
      addTearDown(controller.dispose);
      await pump(tester, AppShell(controller: controller));

      for (final key in const [
        'history.range.menu',
        'history.filter.menu',
        'history.zoom.out',
        'history.zoom.in',
        'history.zoom.fit',
        'history.chart.help',
        'history.chart.fullscreen',
      ]) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(
          size.width,
          greaterThanOrEqualTo(48),
          reason: '$key width ${size.width}',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(48),
          reason: '$key height ${size.height}',
        );
      }

      await tester.tap(find.byKey(const Key('history.zoom.in')));
      await tester.pumpAndSettle();
      final now = tester.getSize(find.byKey(const Key('history.zoom.now')));
      expect(now.width, greaterThanOrEqualTo(48));
      expect(now.height, greaterThanOrEqualTo(48));
    });

    testWidgets('destructive confirmation actions are at least 48 dp', (
      tester,
    ) async {
      final controller = demoBridgeController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        ConfirmationPreviewScreen(
          controller: controller,
          kind: DestructiveKind.powerOff,
        ),
      );

      expect(find.text('Power off the Bridge?'), findsOneWidget);
      final action = find.widgetWithText(FilledButton, 'Power off');
      final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      for (final target in [action, cancel]) {
        final size = tester.getSize(target);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });
  });

  group('screen-reader semantics', () {
    testWidgets('connection, probes, chart, filters and Summary are spoken', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = demoBridgeController();
      addTearDown(controller.dispose);
      await pump(tester, AppShell(controller: controller));

      expect(
        find.bySemanticsLabel(RegExp('Connection details')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('App to Bridge:')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Bridge to Smoke X:')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Probe 1,')), findsWidgets);

      controller.setTab(AppTab.history);
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('History chart from')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Probe 1, latest')), findsOneWidget);

      // Filter menus are labelled by their tooltips for assistive technology.
      expect(find.byTooltip('History range'), findsOneWidget);
      expect(find.byTooltip('Filter by probe'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('destructive actions announce the action and title', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = demoBridgeController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        ConfirmationPreviewScreen(
          controller: controller,
          kind: DestructiveKind.factoryReset,
        ),
      );

      expect(
        find.bySemanticsLabel(RegExp('Factory reset this Bridge\\?')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Factory reset')),
        findsWidgets,
      );
      handle.dispose();
    });
  });

  group('motion and colour', () {
    testWidgets('reduced motion collapses transitions', (tester) async {
      late Duration normal;
      late Duration reduced;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (context) {
              normal = AppMotion.duration(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              reduced = AppMotion.duration(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(normal, AppMotion.standard);
      expect(reduced, Duration.zero);
    });

    for (final brightness in Brightness.values) {
      testWidgets('status carries a label and icon, never colour alone ($brightness)', (
        tester,
      ) async {
        final controller = demoBridgeController()
          ..probeHealth = ProbeHealth.aging;
        addTearDown(controller.dispose);
        await pump(tester, AppShell(controller: controller), brightness: brightness);

        expect(find.text('Updated 62s ago'), findsWidgets);
        expect(find.byIcon(Icons.schedule), findsWidgets);

        final offline = demoBridgeController()
          ..phase = ConnectionPhase.offline
          ..offlineCache = false;
        addTearDown(offline.dispose);
        await pump(tester, AppShell(controller: offline), brightness: brightness);
        expect(find.text('Bridge disconnected · nothing saved yet'), findsOneWidget);
        expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      });
    }

    testWidgets('the X4 warning uses an amber icon plus a dialog title', (
      tester,
    ) async {
      final controller = demoBridgeController()
        ..phase = ConnectionPhase.live
        ..smokeXStatus = SmokeXStatus.pairedLive
        ..smokeXAgeOverride = const Duration(minutes: 4);
      addTearDown(controller.dispose);
      await pump(tester, AppShell(controller: controller));

      final warning = tester.widget<Icon>(
        find.byKey(const Key('live.smokeXWarning')),
      );
      expect(warning.icon, Icons.warning_amber_rounded);
      expect(warning.color, StatusColors.aging(tester.element(find.byKey(const Key('live.smokeXWarning')))));

      await tester.tap(find.byKey(const Key('live.smokeXWarning')));
      await tester.pumpAndSettle();
      expect(find.text('No data from Smoke X'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    });
  });
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

double _luminance(Color color) {
  double channel(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
