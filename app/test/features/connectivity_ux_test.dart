/// A24.1 / A24.8 — the connectivity chrome: the header chip naming the Wi-Fi
/// mode (and its retry subtext), and the connection sheet's controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/shell/connection_sheet.dart';
import 'package:smoke_bridge/features/shell/system_status_bar.dart';
import 'package:smoke_bridge/ui/ui.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: SmokeTheme.dark,
  home: Scaffold(body: child),
);

void main() {
  group('SystemStatusBar', () {
    testWidgets('hosting AP reads "Wi-Fi (hosted)"', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SystemStatusBar(
            link: LinkKind.http,
            netMode: 'ap',
            freshness: ProbeFreshness.live,
          ),
        ),
      );
      expect(find.text('Wi-Fi (hosted)'), findsOneWidget);
    });

    testWidgets('joined STA reads "Wi-Fi"', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SystemStatusBar(
            link: LinkKind.http,
            netMode: 'sta',
            freshness: ProbeFreshness.live,
          ),
        ),
      );
      expect(find.text('Wi-Fi'), findsOneWidget);
    });

    testWidgets('a degraded BLE link with retries reads the count', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SystemStatusBar(
            link: LinkKind.ble,
            freshness: ProbeFreshness.live,
            attempt: 2,
          ),
        ),
      );
      expect(find.text('Bluetooth · retry 2'), findsOneWidget);
    });

    testWidgets('the chip is tappable when onTap is wired', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(
          SystemStatusBar(
            link: LinkKind.ble,
            freshness: ProbeFreshness.live,
            onTap: () => tapped++,
          ),
        ),
      );
      await tester.tap(find.text('Bluetooth'));
      expect(tapped, 1);
    });
  });

  group('ConnectionSheet', () {
    testWidgets('renders the current link and the fallback story', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ConnectionSheet(
            link: LinkKind.http,
            netMode: 'sta',
            address: 'http://smokebridge.local',
            preferred: PreferredTransport.auto,
            holdBle: true,
            onPreferredChanged: (_) {},
            onHoldBleChanged: (_) {},
          ),
        ),
      );
      expect(find.text('Connection'), findsOneWidget);
      expect(find.byKey(const Key('connection-current')), findsOneWidget);
      expect(find.byKey(const Key('connection-story')), findsOneWidget);
    });

    testWidgets('choosing Bluetooth reports the preference', (tester) async {
      PreferredTransport? picked;
      await tester.pumpWidget(
        _wrap(
          ConnectionSheet(
            link: LinkKind.http,
            preferred: PreferredTransport.auto,
            holdBle: true,
            onPreferredChanged: (t) => picked = t,
            onHoldBleChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('Bluetooth'));
      await tester.pump();
      expect(picked, PreferredTransport.ble);
    });

    testWidgets('toggling the backup switch reports it', (tester) async {
      bool? held;
      await tester.pumpWidget(
        _wrap(
          ConnectionSheet(
            link: LinkKind.http,
            preferred: PreferredTransport.auto,
            holdBle: true,
            onPreferredChanged: (_) {},
            onHoldBleChanged: (v) => held = v,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('connection-hold-ble')));
      await tester.pump();
      expect(held, isFalse);
    });

    testWidgets('the manual-address shortcut fires its callback', (
      tester,
    ) async {
      var reached = 0;
      await tester.pumpWidget(
        _wrap(
          ConnectionSheet(
            link: LinkKind.offline,
            preferred: PreferredTransport.auto,
            holdBle: true,
            onPreferredChanged: (_) {},
            onHoldBleChanged: (_) {},
            onReachDirectly: () => reached++,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('connection-reach-directly')));
      expect(reached, 1);
    });
  });
}
