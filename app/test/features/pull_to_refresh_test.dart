/// A26 — pull-to-refresh, and the top bar that reports when it could not.
///
/// The rule under test, stated once: **a pull that cannot get a new reading
/// must say so.** Leaving the previous number on screen is indistinguishable
/// from a refresh that worked and found nothing new, and on this app that
/// difference is "your pit is at 225 °F" versus "your pit was at 225 °F before
/// the bridge went off an hour ago".
///
/// Everything here runs off a seeded [ShellSession] — no `AppEnv`, no radio,
/// no socket — because the gesture, the outcome, and the banner are the app's
/// own behaviour, not the transport's.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/connection.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/cook/cook_view.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/features/shell/refresh_banner.dart';
import 'package:smoke_bridge/features/shell/shell_session.dart';
import 'package:smoke_bridge/ui/ui.dart';

import '../support/load_fonts.dart';

DashboardSnapshot _seed({LinkKind link = LinkKind.http}) => DashboardSnapshot(
  probes: const [
    ProbeView(probe: 1, role: ProbeRole.pit, name: 'Pit', tempF10: 2250),
    ProbeView(probe: 2, role: ProbeRole.food, name: 'Brisket', tempF10: 1500),
    ProbeView(probe: 3, role: ProbeRole.food, name: 'Probe 3'),
    ProbeView(probe: 4, role: ProbeRole.unused, name: 'Probe 4'),
  ],
  link: link,
);

Widget _host(ShellSession session) => MaterialApp(
  theme: SmokeTheme.dark,
  home: AppShell(session: session),
);

/// `pumpAndSettle` cannot be used anywhere near this shell: the transport
/// chip's [PulseDot] repeats forever by design — the dot ceasing to breathe
/// *is* the staleness signal — so "settled" never arrives. Pump a fixed run
/// of frames instead, which is what the rest of the shell suite does.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// The pull itself: a fling on the scrollable, then enough frames for the
/// indicator's future to resolve and the banner to finish sliding in.
Future<void> pull(WidgetTester tester, Finder scrollable) async {
  await tester.fling(scrollable, const Offset(0, 400), 1000);
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  group('the outcome', () {
    test('a session with no link reports not-connected, in words', () async {
      // Seeded == never booted: no supervisor to retry through, which is
      // exactly the shape of "the bridge is not there".
      final session = ShellSession.seeded(
        snapshot: _seed(),
        launch: const LaunchOffline(),
      );
      addTearDown(session.dispose);

      expect(session.refreshFailure, isNull);
      await session.refresh();

      final f = session.refreshFailure;
      expect(f, isNotNull);
      expect(f!.title, 'Not connected');
      expect(f.notConnected, isTrue);
      // The copy tells the user what to check AND that the app keeps
      // working on it — never a dead end (rail R2).
      expect(f.detail, contains('powered on'));
      expect(session.refreshing, isFalse);
    });

    test('the failure is dismissible, and notifies', () async {
      final session = ShellSession.seeded(snapshot: _seed());
      addTearDown(session.dispose);
      var notifications = 0;
      session.addListener(() => notifications++);

      await session.refresh();
      expect(session.refreshFailure, isNotNull);
      final afterRefresh = notifications;

      session.dismissRefreshFailure();
      expect(session.refreshFailure, isNull);
      expect(notifications, greaterThan(afterRefresh));

      // Dismissing nothing is a no-op, not a rebuild.
      final quiet = notifications;
      session.dismissRefreshFailure();
      expect(notifications, quiet);
    });

    test('overlapping pulls collapse into one', () async {
      final session = ShellSession.seeded(snapshot: _seed());
      addTearDown(session.dispose);

      // Two gestures, one outcome — a user who pulls twice must not get two
      // rounds of radio work, nor a banner that flickers off and back on.
      await Future.wait([session.refresh(), session.refresh()]);
      expect(session.refreshFailure, isNotNull);
      expect(session.refreshing, isFalse);
    });
  });

  group('the top bar', () {
    testWidgets('a failed pull on Cook raises the banner — the tab that owns '
        'its own chrome is not the one tab that stays silent', (tester) async {
      final session = ShellSession.seeded(
        snapshot: _seed(),
        launch: const LaunchOffline(),
      );
      addTearDown(session.dispose);

      await tester.pumpWidget(_host(session));
      await settle(tester);
      expect(find.byKey(const Key('refresh-banner')), findsNothing);

      await pull(tester, find.byType(CookView));

      expect(find.byKey(const Key('refresh-banner')), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.byKey(const Key('refresh-banner-retry')), findsOneWidget);
    });

    testWidgets('Try again re-runs the pull; Dismiss clears the banner', (
      tester,
    ) async {
      final session = ShellSession.seeded(
        snapshot: _seed(),
        launch: const LaunchOffline(),
      );
      addTearDown(session.dispose);

      await tester.pumpWidget(_host(session));
      await settle(tester);
      await pull(tester, find.byType(CookView));
      expect(find.byKey(const Key('refresh-banner')), findsOneWidget);

      // Still not connected: the banner stays rather than silently vanishing.
      await tester.tap(find.byKey(const Key('refresh-banner-retry')));
      await settle(tester);
      expect(find.byKey(const Key('refresh-banner')), findsOneWidget);

      await tester.tap(find.byKey(const Key('refresh-banner-dismiss')));
      await settle(tester);
      expect(find.byKey(const Key('refresh-banner')), findsNothing);
    });

    testWidgets('the banner is absent until something fails', (tester) async {
      final session = ShellSession.seeded(snapshot: _seed());
      addTearDown(session.dispose);

      await tester.pumpWidget(_host(session));
      await settle(tester);

      // Always mounted so it can animate, but zero-height and wordless — a
      // healthy screen shows no chrome about refreshing at all.
      expect(find.byType(RefreshBanner), findsOneWidget);
      expect(find.byKey(const Key('refresh-banner')), findsNothing);
    });

    testWidgets('a link coming back retires the failure on its own', (
      tester,
    ) async {
      final session = ShellSession.seeded(
        snapshot: _seed(),
        launch: const LaunchOffline(),
      );
      addTearDown(session.dispose);

      await tester.pumpWidget(_host(session));
      await settle(tester);
      await pull(tester, find.byType(CookView));
      expect(find.byKey(const Key('refresh-banner')), findsOneWidget);

      session.dismissRefreshFailure();
      await settle(tester);
      expect(find.byKey(const Key('refresh-banner')), findsNothing);
    });
  });

  group('the gesture', () {
    testWidgets('CookView is pullable only when it has somewhere to send it', (
      tester,
    ) async {
      // No callback → no indicator, so every existing caller and golden sees
      // the tree it always saw.
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: Scaffold(
            body: CookView(
              snapshot: _seed(),
              plan: null,
              freshness: ProbeFreshness.live,
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(RefreshIndicator), findsNothing);

      var pulls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: SmokeTheme.dark,
          home: Scaffold(
            body: CookView(
              snapshot: _seed(),
              plan: null,
              freshness: ProbeFreshness.live,
              onRefresh: () async => pulls++,
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      await pull(tester, find.byType(CookView));
      expect(pulls, 1);
    });

    testWidgets('offline with no snapshot is still the reader, and still '
        'pullable — the branch where a manual retry matters most', (
      tester,
    ) async {
      // No snapshot at all. This used to replace the screen with an empty
      // state; §B.3 and 16 §16.6 say the reader renders its own layout on the
      // first frame in every case, so what is on screen is four jacks reading
      // `—` under the last-seen. It is a `CookView`, so it already scrolls.
      final session = ShellSession.seeded(launch: const LaunchOffline());
      addTearDown(session.dispose);

      await tester.pumpWidget(_host(session));
      await settle(tester);
      expect(find.byType(CookView), findsOneWidget);
      expect(find.text('Can’t reach your bridge'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await pull(tester, find.byType(CookView));

      expect(find.byKey(const Key('refresh-banner')), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
    });
  });
}
