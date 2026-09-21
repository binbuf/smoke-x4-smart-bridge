/// N14 — the onboarding wizard, the gate and the exit gate.
///
/// The full walk runs through `SmokeApp` + the real router so the first-run
/// gate, every step, the passkey invariant and the persisted finish are all
/// exercised end to end.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/router.dart';
import 'package:smoke_bridge/app/smoke_app.dart';
import 'package:smoke_bridge/data/dev_panel.dart';
import 'package:smoke_bridge/data/model/app_settings.dart';
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/data/repository/prefs_repository.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/onboarding/onboarding.dart';
import 'package:smoke_bridge/features/shell/overlay.dart';
import 'package:smoke_bridge/features/shell/shell.dart';

import '../support/load_fonts.dart';

const int _now = 1700000000000;

/// A machine seeded with a given state so the widget tests can render a named
/// failure or a mid-flow step without walking there.
class _SeededMachine extends SetupMachine {
  _SeededMachine(this.initial);

  final SetupState initial;

  @override
  SetupState build() => initial;
}

void main() {
  setUpAll(loadAppFonts);

  late MockBridgeRepository repo;
  late MockPrefsRepository prefs;

  setUp(() {
    repo = MockBridgeRepository(nowMs: _now, initialScenario: 'idle');
    prefs = MockPrefsRepository();
  });

  tearDown(() async {
    await repo.dispose();
    await prefs.dispose();
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    OnboardStatus status = OnboardStatus.fresh,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    prefs = MockPrefsRepository(initial: AppSettings(onboardStatus: status));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeRepositoryProvider.overrideWithValue(repo),
          prefsProvider.overrideWithValue(prefs),
          shellPulseEnabledProvider.overrideWithValue(false),
          shellClockProvider.overrideWithValue(DateTime(2026, 9, 21, 9, 41)),
        ],
        child: SmokeApp(router: createAppRouter()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('onboarding-next')));
    await tester.pumpAndSettle();
  }

  group('first-run gating (N14.12)', () {
    testWidgets('the wizard shows when no bridge is known', (tester) async {
      await pumpApp(tester);
      expect(
        find.byKey(const ValueKey<String>('onboarding-surface')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('onboarding-body')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('onboarding-step-rail')),
        findsOneWidget,
      );
    });

    testWidgets('a later launch goes straight to the shell', (tester) async {
      await pumpApp(tester, status: OnboardStatus.paired);
      expect(
        find.byKey(const ValueKey<String>('onboarding-surface')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey<String>('live-page')), findsOneWidget);
    });
  });

  testWidgets('a factory-fresh state walks all eight steps to a live shell', (
    tester,
  ) async {
    await pumpApp(tester);

    // Step 1 — welcome.
    expect(find.text('Meet your SmokeBridge'), findsOneWidget);
    await tapNext(tester);

    // Step 2 — preflight: the primary is blocked until both are granted.
    expect(find.text('A couple of permissions'), findsOneWidget);
    final primary = tester.widget<PrimaryAction>(
      find.byKey(const ValueKey<String>('onboarding-next')),
    );
    expect(primary.onPressed, isNull, reason: 'no permissions yet');
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding-perm-allow-Bluetooth')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding-perm-allow-Notifications')),
    );
    await tester.pumpAndSettle();
    await tapNext(tester);

    // Step 3 — scan.
    expect(find.text('Looking for your bridge'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('onboarding-found-bridge')),
    );
    await tester.pumpAndSettle();
    await tapNext(tester);

    // Step 4 — passkey: the app coaches and never renders a code.
    expect(find.text('Enter the code from the bridge'), findsOneWidget);
    expect(find.text(kPasskeyPlaceholder), findsOneWidget);
    expect(find.textContaining('0000'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            RegExp(r'\d{6}').hasMatch(widget.data!) &&
            widget.data != kPasskeyPlaceholder,
      ),
      findsNothing,
      reason: 'the app cannot render a real six-digit code',
    );
    await tapNext(tester);

    // Step 5 — sync: the pure-listener notice.
    expect(find.text('Listening for your Smoke X4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('onboarding-listener-notice')),
      findsOneWidget,
    );
    await tapNext(tester);

    // Step 6 — network: three modes, Bluetooth active by default.
    expect(find.text('How should we stay in touch?'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('onboarding-mode-ble')), findsOne);
    expect(find.byKey(const ValueKey<String>('onboarding-mode-ap')), findsOne);
    expect(find.byKey(const ValueKey<String>('onboarding-mode-sta')), findsOne);
    await tester.tap(find.byKey(const ValueKey<String>('onboarding-mode-sta')));
    await tester.pumpAndSettle();
    await tapNext(tester);

    // Step 7 — name + units.
    expect(find.text('Almost there'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('onboarding-name-field')),
      'Patio Bridge',
    );
    await tester.tap(find.text('° Celsius'));
    await tester.pumpAndSettle();
    await tapNext(tester);

    // Step 8 — done, then finish.
    expect(find.text('You’re all set'), findsOneWidget);
    await tapNext(tester);

    // The wizard is gone, the shell is live, and the choice persisted.
    expect(
      find.byKey(const ValueKey<String>('onboarding-surface')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('live-page')), findsOneWidget);
    expect(prefs.current.onboardStatus, OnboardStatus.paired);
    expect(prefs.current.bridgeName, 'Patio Bridge');
    expect(prefs.current.units, TempUnit.celsius);
    expect(find.text('Welcome — you are connected'), findsOneWidget);
  });

  testWidgets('skip lands on a shell that offers a way to connect', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey<String>('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('onboarding-surface')),
      findsNothing,
    );
    expect(prefs.current.onboardStatus, OnboardStatus.skipped);
    expect(
      find.byKey(const ValueKey<String>('live-connect-bridge')),
      findsOneWidget,
    );
    expect(find.text('Connect a bridge'), findsOneWidget);
  });

  group('recovery paths (N14.5, N14.11)', () {
    testWidgets('"Can\'t find it?" opens the troubleshoot sub-flow', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapNext(tester); // welcome → preflight
      await tester.tap(
        find.byKey(const ValueKey<String>('onboarding-perm-allow-Bluetooth')),
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>('onboarding-perm-allow-Notifications'),
        ),
      );
      await tester.pumpAndSettle();
      await tapNext(tester); // preflight → scan

      await tester.tap(
        find.byKey(const ValueKey<String>('onboarding-troubleshoot-link')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('onboarding-troubleshoot')),
        findsOneWidget,
      );
      expect(find.text('Is the bridge powered?'), findsOneWidget);
      expect(find.text('Bluetooth on?'), findsOneWidget);
      expect(find.text('Restart the bridge'), findsOneWidget);

      // Try again returns to the scan step.
      await tester.tap(find.byKey(const ValueKey<String>('onboarding-next')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('onboarding-scan')),
        findsOneWidget,
      );
    });

    testWidgets('a denied permission is a resumable, named state', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(420, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final seeded = const SetupState(
        step: OnboardStep.preflight,
        fault: SetupFault.permissionDenied,
        permissions: <OnboardPermission, PermissionState>{
          OnboardPermission.bluetooth: PermissionState.denied,
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bridgeRepositoryProvider.overrideWithValue(repo),
            prefsProvider.overrideWithValue(prefs),
            setupStateProvider.overrideWith(() => _SeededMachine(seeded)),
          ],
          child: MaterialApp(
            theme: SmokeThemeData.dark(),
            home: Scaffold(
              body: OnboardingSurface(onDone: () {}, onSkip: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('onboarding-fault')),
        findsOneWidget,
      );
      expect(find.text('A permission was denied'), findsOneWidget);
      // The Allow control is still there: the state is resumable.
      await tester.tap(
        find.byKey(const ValueKey<String>('onboarding-perm-allow-Bluetooth')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('onboarding-fault')),
        findsNothing,
      );
    });

    testWidgets('a skipped base station reads "— not set up" on done', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(420, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final seeded = const SetupState(step: OnboardStep.sync);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bridgeRepositoryProvider.overrideWithValue(repo),
            prefsProvider.overrideWithValue(prefs),
            setupStateProvider.overrideWith(() => _SeededMachine(seeded)),
          ],
          child: MaterialApp(
            theme: SmokeThemeData.dark(),
            home: Scaffold(
              body: OnboardingSurface(onDone: () {}, onSkip: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('onboarding-skip-base')),
      );
      await tester.pumpAndSettle();
      // network → name → done.
      await tester.tap(find.byKey(const ValueKey<String>('onboarding-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('onboarding-next')));
      await tester.pumpAndSettle();

      expect(find.text('You’re all set'), findsOneWidget);
      final baseStatus = tester.widget<Text>(
        find.byKey(
          const ValueKey<String>('onboarding-hop-status-Base station'),
        ),
      );
      expect(baseStatus.data, 'Skipped');
      // Bluetooth and Network were never set, so they read "— not set up".
      expect(find.text('— not set up'), findsWidgets);
    });
  });

  testWidgets('the named overlay renders the same wizard body', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bridgeRepositoryProvider.overrideWithValue(repo),
          prefsProvider.overrideWithValue(prefs),
          shellPulseEnabledProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          theme: SmokeThemeData.dark(),
          home: const Scaffold(
            body: ShellOverlayHost(
              request: OverlayRequest(DevOverlay.onboarding),
              onDismiss: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('onboarding-body')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('onboarding-next')),
      findsOneWidget,
    );
  });
}

void _noop() {}
