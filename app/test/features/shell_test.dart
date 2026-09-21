/// N4 — shell chrome, overlay framework and toast.
///
/// These tests pin the pieces the shell is assembled from: the screen model,
/// the bottom nav, the app-bar variants, the alerts bell, the overlay resolver
/// and host, the fullscreen graph host, the toast and the scroll reset.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dev_panel.dart';
import 'package:smoke_bridge/data/model/connection_state.dart' as bridge;
import 'package:smoke_bridge/data/providers.dart';
import 'package:smoke_bridge/data/repository/mock_bridge_repository.dart';
import 'package:smoke_bridge/data/repository/prefs_repository.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/shell/alerts_bell.dart';
import 'package:smoke_bridge/features/shell/app_bar.dart';
import 'package:smoke_bridge/features/shell/bottom_nav.dart';
import 'package:smoke_bridge/features/shell/graph_host.dart';
import 'package:smoke_bridge/features/shell/overlay.dart';
import 'package:smoke_bridge/features/shell/phone_frame.dart';
import 'package:smoke_bridge/features/shell/shell.dart';
import 'package:smoke_bridge/features/shell/shell_screen.dart';
import 'package:smoke_bridge/features/shell/toast.dart';
import 'package:smoke_bridge/features/shell/transport_status.dart';

import '../support/load_fonts.dart';

/// The overlay bodies (N5) read the repository, so every harness gets a scope.
Widget wrap(Widget child) => ProviderScope(
  overrides: [
    bridgeRepositoryProvider.overrideWith((ref) {
      final repo = MockBridgeRepository(nowMs: 1700000000000);
      ref.onDispose(repo.dispose);
      return repo;
    }),
    prefsProvider.overrideWith((ref) {
      final prefs = MockPrefsRepository();
      ref.onDispose(prefs.dispose);
      return prefs;
    }),
  ],
  child: MaterialApp(
    theme: SmokeThemeData.dark(),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  group('screen model (N4.2/N4.3)', () {
    test('screenFromPath resolves every route', () {
      expect(screenFromPath('/live'), ShellScreen.live);
      expect(screenFromPath('/temps'), ShellScreen.temps);
      expect(screenFromPath('/timeline'), ShellScreen.timeline);
      expect(screenFromPath('/graph'), ShellScreen.graph);
      expect(screenFromPath('/settings'), ShellScreen.settings);
      expect(screenFromPath('/settings/history'), ShellScreen.history);
      expect(screenFromPath('/settings/history/abc'), ShellScreen.cookDetail);
      expect(screenFromPath('/nonsense'), ShellScreen.live);
      expect(screenFromPath('/graph?overlay=probe'), ShellScreen.graph);
    });

    test('history and cook detail highlight Settings in the nav', () {
      expect(ShellScreen.history.navDestination, ShellScreen.settings);
      expect(ShellScreen.cookDetail.navDestination, ShellScreen.settings);
      expect(ShellScreen.live.navDestination, ShellScreen.live);
    });

    test('pathForDevScreen maps the dev vocabulary', () {
      expect(pathForDevScreen(DevScreen.timeline), '/timeline');
      expect(pathForDevScreen(DevScreen.history), '/settings/history');
    });
  });

  group('bottom nav (N4.2)', () {
    testWidgets('renders five destinations and reports taps', (tester) async {
      ShellScreen? tapped;
      await tester.pumpWidget(
        wrap(
          ShellBottomNav(
            current: ShellScreen.live,
            unackedAlarms: 0,
            onSelect: (screen) => tapped = screen,
          ),
        ),
      );

      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Temps'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Graph'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('shell-nav-live-dot')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('shell-nav-timeline')),
      );
      expect(tapped, ShellScreen.timeline);
    });

    testWidgets('shows the unacked dot on Live only', (tester) async {
      await tester.pumpWidget(
        wrap(
          ShellBottomNav(
            current: ShellScreen.live,
            unackedAlarms: 2,
            onSelect: (_) {},
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('shell-nav-live-dot')),
        findsOneWidget,
      );
    });
  });

  group('app bar (N4.4)', () {
    testWidgets('live shows the transport chip and no title', (tester) async {
      await tester.pumpWidget(
        wrap(
          ShellAppBar(
            screen: ShellScreen.live,
            unackedAlarms: 0,
            transport: TransportStatus.unknown,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('shell-transport-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('shell-appbar-title')),
        findsNothing,
      );
    });

    testWidgets('graph shows title, sub and no back/plus', (tester) async {
      await tester.pumpWidget(
        wrap(
          ShellAppBar(
            screen: ShellScreen.graph,
            unackedAlarms: 0,
            transport: TransportStatus.unknown,
          ),
        ),
      );

      expect(find.text('Graph'), findsOneWidget);
      expect(find.text('All probes'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('shell-appbar-back')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('shell-appbar-plus')),
        findsNothing,
      );
    });

    testWidgets('history shows back and plus, cook detail only back', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ShellAppBar(
            screen: ShellScreen.history,
            unackedAlarms: 0,
            transport: TransportStatus.unknown,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('shell-appbar-back')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('shell-appbar-plus')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        wrap(
          ShellAppBar(
            screen: ShellScreen.cookDetail,
            unackedAlarms: 0,
            transport: TransportStatus.unknown,
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('shell-appbar-back')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('shell-appbar-plus')),
        findsNothing,
      );
    });
  });

  group('alerts bell (N4.5)', () {
    testWidgets('badge only appears with unacked alarms', (tester) async {
      await tester.pumpWidget(wrap(const AlertsBell(count: 0)));
      expect(
        find.byKey(const ValueKey<String>('shell-alert-badge')),
        findsNothing,
      );

      await tester.pumpWidget(wrap(const AlertsBell(count: 3)));
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('transport status (N4.4)', () {
    test('maps the dual-link state', () {
      final offline = TransportStatus.from(
        const bridge.ConnectionState(phase: bridge.ConnectionPhase.offline),
      );
      expect(offline.label, 'Offline');
      expect(offline.phase, TransportPhase.offline);

      final bt = TransportStatus.from(
        const bridge.ConnectionState(
          phase: bridge.ConnectionPhase.connected,
          primary: bridge.LinkPrimary.bt,
        ),
      );
      expect(bt.label, 'Bluetooth');
      expect(bt.primary, TransportPrimary.bt);

      final ap = TransportStatus.from(
        const bridge.ConnectionState(
          phase: bridge.ConnectionPhase.connected,
          primary: bridge.LinkPrimary.wifi,
          wifi: bridge.LinkState(connected: true, mode: bridge.WifiMode.ap),
        ),
      );
      expect(ap.label, 'Bridge Wi-Fi');
      expect(ap.wifiAp, isTrue);
    });
  });

  group('overlay resolver (N4.7)', () {
    test('every overlay resolves to a titled presentation', () {
      for (final overlay in DevOverlay.values) {
        final content = resolveOverlay(OverlayRequest(overlay));
        expect(content.title, isNotEmpty, reason: overlay.name);
      }
    });

    test('only adopt, editStart and confirm are modals', () {
      final modals = <DevOverlay>{};
      for (final overlay in DevOverlay.values) {
        if (resolveOverlay(OverlayRequest(overlay)) is ModalOverlay) {
          modals.add(overlay);
        }
      }
      expect(modals, {
        DevOverlay.adopt,
        DevOverlay.editStart,
        DevOverlay.confirm,
      });
    });

    test('probe and confirm carry their props', () {
      final probe = resolveOverlay(
        OverlayRequest(DevOverlay.probe, {'jack': '3'}),
      );
      expect(probe.title, 'Probe 3');

      final confirm = resolveOverlay(
        OverlayRequest(DevOverlay.confirm, {'title': 'Forget bridge?'}),
      );
      expect(confirm.title, 'Forget bridge?');
    });

    test('every overlay name round-trips through a location', () {
      for (final overlay in DevOverlay.values) {
        final location = locationWithOverlay('/graph', overlay, const {
          'jack': '2',
        });
        expect(baseLocation(location), '/graph');
        final request = overlayRequestFromLocation(location);
        expect(request, isNotNull, reason: overlay.name);
        expect(request!.name, overlay);
        expect(request.props['jack'], '2');
      }
    });
  });

  group('overlay host (N4.6)', () {
    testWidgets('every named overlay opens and dismisses', (tester) async {
      for (final overlay in DevOverlay.values) {
        var dismissed = 0;
        await tester.pumpWidget(
          wrap(
            ShellOverlayHost(
              request: OverlayRequest(overlay),
              onDismiss: () => dismissed++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('shell-overlay-title')),
          findsOneWidget,
          reason: overlay.name,
        );
        await tester.tapAt(const Offset(400, 20));
        expect(dismissed, 1, reason: overlay.name);
      }
    });

    testWidgets('a sheet opens by name and dismisses on scrim tap', (
      tester,
    ) async {
      var dismissed = 0;
      await tester.pumpWidget(
        wrap(
          ShellOverlayHost(
            request: const OverlayRequest(DevOverlay.connect),
            onDismiss: () => dismissed++,
          ),
        ),
      );

      expect(find.text('Connection'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('shell-overlay-sheet')),
        findsOneWidget,
      );

      await tester.tapAt(const Offset(400, 20));
      expect(dismissed, 1);
    });

    testWidgets('a modal opens by name and dismisses on scrim tap', (
      tester,
    ) async {
      var dismissed = 0;
      await tester.pumpWidget(
        wrap(
          ShellOverlayHost(
            request: const OverlayRequest(DevOverlay.adopt),
            onDismiss: () => dismissed++,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('shell-overlay-modal')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(20, 20));
      expect(dismissed, 1);
    });
  });

  group('imperative framework (N4.6)', () {
    testWidgets('showSheet renders the chrome and dismisses', (tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showSheet(
                context,
                title: 'Hello sheet',
                sub: 'A sub',
                body: const Text('Body'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Hello sheet'), findsOneWidget);

      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();
      expect(find.text('Hello sheet'), findsNothing);
    });

    testWidgets('showModalCard resolves true on confirm', (tester) async {
      bool? result;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalCard(
                  context,
                  title: 'Delete?',
                  body: const Text('Careful'),
                  confirmLabel: 'Delete',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('shell-overlay-confirm')),
      );
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('fullscreen graph host (N4.8)', () {
    testWidgets('dismisses on scrim tap', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        wrap(
          ShellFullscreenGraphHost(
            onDismiss: () => dismissed++,
            child: const Text('chart'),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('shell-graph-host')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(4, 4));
      expect(dismissed, 1);
    });
  });

  group('toast (N4.9)', () {
    testWidgets('shows and hides a transient message', (tester) async {
      final controller = ShellToastController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(wrap(ShellToastHost(controller: controller)));

      controller.show('Added to the cook');
      await tester.pump();
      expect(find.text('Added to the cook'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Added to the cook'), findsNothing);
    });
  });

  group('scroll reset (N4.11)', () {
    testWidgets('resets to the top when the destination changes', (
      tester,
    ) async {
      var token = 'live';
      late StateSetter setState;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 300,
            child: StatefulBuilder(
              builder: (context, setter) {
                setState = setter;
                return ShellScrollHost(
                  resetToken: token,
                  child: Column(
                    children: <Widget>[
                      for (var i = 0; i < 60; i++)
                        SizedBox(height: 40, child: Text('row $i')),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      await tester.drag(find.text('row 0'), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));

      setState(() => token = 'graph');
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, 0);
    });
  });
}
