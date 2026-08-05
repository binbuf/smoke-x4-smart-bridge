/// Branch stacks: opening a cook must not cost the app (design 13 §13.3.2,
/// §13.3.4).
///
/// The defect this pins is the one that made History a dead end. `/sessions/:id`
/// was a **root** route reached by `context.go`, so opening a cook unmounted
/// `AppShell` — which disposes the `ShellSession` and kills the live link —
/// replaced the tab bar with a full-screen page, and left the only way back a
/// chain of arrows terminating at `/`. One tap cost the tab bar, the
/// connection, the tab and the scroll position.
///
/// With `StatefulShellRoute.indexedStack` the detail is pushed **inside** the
/// Cooks branch: the shell stays mounted, the nav bar stays on screen, and back
/// is a branch pop.
///
/// The newapp §B.2 IA moves the paths (`/cook`→`/live`, `/history`→`/cooks`,
/// `/bridge`→`/device`, `/alerts` folded away) and every old one still resolves,
/// because a deep link a user saved or a notification already posted must not
/// land on a 404.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smoke_bridge/app/app_env.dart';
import 'package:smoke_bridge/app/router.dart';
import 'package:smoke_bridge/app/connection.dart';
import 'package:smoke_bridge/data/prefs/bridge_prefs.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/features/settings/settings_screen.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/features/shell/shell_session.dart';

import '../support/fake_env.dart';

/// A phone, with a **seeded** session so nothing dials a radio.
///
/// Both halves matter. The shell is adaptive, so the form factor is part of
/// the setup. And the session must not boot: a live one starts the connection
/// race — a BLE scan on a platform with no `flutter_blue_plus`, and backoff
/// timers that outlive the widget tree — none of which these assertions are
/// about. A seeded session is also never `LaunchNeedsOnboarding`, so the A9.5
/// setup gate does not fire and mask the navigation under test.
Future<GoRouter> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  AppEnv.instance = fakeEnv(
    prefs: InMemoryBridgePrefs(lastBridgeId: 'test-bridge'),
  );
  addTearDown(() => AppEnv.instance = null);

  final session = ShellSession.seeded(launch: const LaunchOffline());
  addTearDown(session.dispose);

  final router = createRouter(session: session);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(theme: SmokeTheme.dark, routerConfig: router),
  );
  await tester.pump();
  return router;
}

String _path(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets('opening a cook keeps the shell, the session and the nav bar', (
    tester,
  ) async {
    final router = await _pumpApp(tester);

    final shellBefore = tester.state<State>(find.byType(AppShell));

    router.go('${AppRoutes.cooks}/5');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_path(router), '/cooks/5');
    // The shell is the SAME State object — not rebuilt, so the connection
    // race did not restart and no ShellSession was disposed.
    expect(
      tester.state<State>(find.byType(AppShell)),
      same(shellBefore),
      reason: 'a pushed detail must not unmount the shell',
    );
    expect(
      find.byType(NavigationBar),
      findsOneWidget,
      reason: 'the tab bar survives an in-branch push',
    );
  });

  testWidgets('the legacy /sessions/:id deep link lands in the branch', (
    tester,
  ) async {
    final router = await _pumpApp(tester);

    router.go('${AppRoutes.sessions}/12');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_path(router), '/cooks/12');
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('every superseded path still resolves somewhere real', (
    tester,
  ) async {
    final router = await _pumpApp(tester);
    // A saved deep link and an already-posted notification both outlive an IA
    // change; landing them on a 404 is not a redesign, it is a regression.
    const moved = {
      '/cook': '/live',
      '/history': '/cooks',
      '/history/7': '/cooks/7',
      '/sessions': '/cooks',
      '/alerts': '/device/alarms',
      '/bridge': '/device',
      '/bridge/probes': '/device/settings/probes',
      '/bridge/alarms': '/device/alarms',
      '/settings': '/device',
      '/settings/network': '/device/settings/network',
    };
    for (final entry in moved.entries) {
      router.go(entry.key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_path(router), entry.value, reason: 'from ${entry.key}');
    }
  });

  testWidgets('/ and /settings redirect into their branches', (tester) async {
    final router = await _pumpApp(tester);

    expect(_path(router), AppRoutes.live, reason: 'the reader is the landing');

    router.go(AppRoutes.settings);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      _path(router),
      AppRoutes.device,
      reason:
          'settings folded into the Device branch — it used to be '
          'reachable only from a connection-sheet button labelled '
          '"Reach it directly by address"',
    );

    router.go(AppRoutes.home);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_path(router), AppRoutes.live);
  });

  testWidgets(
    'every device settings section is reachable at /device/settings/:section',
    (tester) async {
      final router = await _pumpApp(tester);

      for (final section in SettingsSection.deviceSections) {
        router.go('${AppRoutes.deviceSettings}/${section.slug}');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          _path(router),
          '/device/settings/${section.slug}',
          reason: 'section "${section.title}"',
        );
        expect(
          settingsSectionForSlug(section.slug),
          section,
          reason: 'slug must resolve back to its section',
        );
        // The shell frames it: a settings page is not a full-screen takeover.
        expect(find.byType(AppShell), findsOneWidget);
      }
    },
  );

  // Navigating to `/setup` cannot be exercised here: `SetupRoute` runs the
  // hop-0 preflight, which reaches `flutter_blue_plus` — unsupported on the
  // test platform. The setup flow has its own suite against a fake probe
  // (`setup_hop1_test.dart`); what belongs here is the *structural* claim.
  test('three branches, and setup is a gate rather than one of them', () {
    expect(AppRoutes.branchPaths, [
      AppRoutes.live,
      AppRoutes.cooks,
      AppRoutes.device,
    ]);
    expect(AppRoutes.branchPaths, isNot(contains(AppRoutes.setup)));
    expect(
      AppRoutes.branchPaths,
      isNot(contains(AppRoutes.alerts)),
      reason:
          '§B.1 — a permissions verdict is not a place a user spends fourteen '
          'hours; it is a banner on the screens that matter',
    );
  });

  test(
    'an unknown settings slug resolves to nothing rather than a wrong page',
    () {
      expect(settingsSectionForSlug('probes'), SettingsSection.probes);
      expect(settingsSectionForSlug('PROBES'), SettingsSection.probes);
      expect(settingsSectionForSlug('nonsense'), isNull);
    },
  );
}
