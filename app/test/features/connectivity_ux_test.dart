/// The connectivity surfaces, as pure widgets over plain values.
///
/// A24.1 / A24.8's chrome — the header chip naming the Wi-Fi mode and its retry
/// subtext, and the connection sheet's fallback controls — plus the two pieces
/// design 16 added to `/device`:
///
///  * [ConnectionModeCard], newapp §E.1's three plain choices. The rule it is
///    tested hardest against is that **the selection is read, never assumed**:
///    `NetMode _netMode = NetMode.sta` rendered as "Joined a network" while the
///    bridge hosted its own AP is the bug §16.6 names by line number.
///  * [SituationCard], the lead card of `/device`. Status hue is chrome only,
///    there is always an icon *and* a word, and a fix the app already made
///    carries no button at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/domain/situation/situation.dart';
import 'package:smoke_bridge/features/bridge/connection_mode_card.dart';
import 'package:smoke_bridge/features/bridge/situation_card.dart';
import 'package:smoke_bridge/features/dashboard/dashboard_snapshot.dart';
import 'package:smoke_bridge/features/shell/connection_sheet.dart';
import 'package:smoke_bridge/features/shell/system_status_bar.dart';
import 'package:smoke_bridge/ui/ui.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: SmokeTheme.dark,
  home: Scaffold(body: child),
);

/// The mode card lives in `/device`'s ListView, so a bare mount has to give it
/// somewhere to be tall.
Widget _scrolled(Widget child) => _wrap(SingleChildScrollView(child: child));

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

    testWidgets('the chip states the link and never a retry count', (
      tester,
    ) async {
      // 16 §16.3 opens by naming "Offline · retry 6" as the bug the whole
      // reconciliation layer exists to kill: a counter in the loudest chrome
      // in the app, saying nothing a tired person can act on, while the cause
      // — reflashed, out of range, hosting its own network — goes unnamed.
      // The chip states the link; the banner states the cause.
      await tester.pumpWidget(
        _wrap(
          const SystemStatusBar(
            link: LinkKind.ble,
            freshness: ProbeFreshness.live,
          ),
        ),
      );
      expect(find.text('Bluetooth'), findsOneWidget);
      expect(
        find.textContaining('retry'),
        findsNothing,
        reason: 'a retry count is a status code (§16.4 rule 4)',
      );
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

  group('ConnectionModeCard (§E.1)', () {
    testWidgets('all three choices are always on screen', (tester) async {
      await tester.pumpWidget(
        _scrolled(ConnectionModeCard(link: LinkKind.ble, onChoose: (_) {})),
      );
      expect(find.byKey(const Key('mode-bluetooth')), findsOneWidget);
      expect(find.byKey(const Key('mode-bridgeHosts')), findsOneWidget);
      expect(find.byKey(const Key('mode-joinsYours')), findsOneWidget);
    });

    testWidgets('nothing is selected until the link says which', (
      tester,
    ) async {
      // Reached over Wi-Fi, but nothing has said which network it is on.
      // Picking one would be a constructor default wearing a fact's clothes
      // — the exact bug §16.6 calls out by line number.
      await tester.pumpWidget(
        _scrolled(
          ConnectionModeCard(
            link: LinkKind.http,
            address: 'http://10.0.0.7',
            onChoose: (_) {},
          ),
        ),
      );
      expect(find.byKey(const Key('mode-in-use')), findsNothing);
      expect(choiceFor(link: LinkKind.http), isNull);
      expect(
        find.textContaining('has not said which network it is on'),
        findsOneWidget,
      );
    });

    testWidgets('a hosted bridge is named as hosted, never as joined', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scrolled(
          ConnectionModeCard(
            link: LinkKind.http,
            netMode: 'ap',
            address: 'http://192.168.4.1',
            onChoose: (_) {},
          ),
        ),
      );
      expect(find.byKey(const Key('mode-in-use')), findsOneWidget);
      expect(
        choiceFor(link: LinkKind.http, netMode: 'ap'),
        ConnectionChoice.bridgeHosts,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('bridge-connection-title')))
            .data,
        'The bridge’s own network',
      );
    });

    testWidgets(
      'over Bluetooth, what the bridge is doing is stated separately',
      (tester) async {
        // The bench failure, on screen: the app is on Bluetooth and the
        // bridge is off hosting its own network. Collapsing the two axes
        // would hide the one fact that explains everything.
        await tester.pumpWidget(
          _scrolled(
            ConnectionModeCard(
              link: LinkKind.ble,
              deviceNetMode: 'ap',
              onChoose: (_) {},
            ),
          ),
        );
        expect(find.byKey(const Key('bridge-device-netmode')), findsOneWidget);
        expect(
          find.textContaining('hosting its own network right now'),
          findsOneWidget,
        );
      },
    );

    testWidgets('offline, every choice is dimmed with its reason', (
      tester,
    ) async {
      var chosen = 0;
      await tester.pumpWidget(
        _scrolled(
          ConnectionModeCard(
            link: LinkKind.offline,
            disabledReason: 'The bridge has to be reachable.',
            onChoose: (_) => chosen++,
          ),
        ),
      );
      // Rendered, not hidden — and the reason sits under each of them.
      expect(
        find.text('The bridge has to be reachable.'),
        findsNWidgets(ConnectionChoice.values.length),
      );
      await tester.tap(find.byKey(const Key('mode-joinsYours')));
      await tester.pump();
      expect(chosen, 0);
    });

    testWidgets('choosing another mode reports it once', (tester) async {
      final picked = <ConnectionChoice>[];
      await tester.pumpWidget(
        _scrolled(ConnectionModeCard(link: LinkKind.ble, onChoose: picked.add)),
      );
      await tester.tap(find.byKey(const Key('mode-bridgeHosts')));
      await tester.pump();
      expect(picked, [ConnectionChoice.bridgeHosts]);

      // The live one is not a control — there is nothing to switch to.
      await tester.tap(find.byKey(const Key('mode-bluetooth')));
      await tester.pump();
      expect(picked, [ConnectionChoice.bridgeHosts]);
    });
  });

  group('SituationCard (§16.6)', () {
    testWidgets('the words are textHi, never the status hue', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SituationCard(
            situation: Situation(
              kind: SituationKind.bridgeWasReset,
              headline: 'This is a different bridge',
              detail: 'It answers to B811.',
              actionLabel: 'Use this bridge instead',
            ),
          ),
        ),
      );
      final headline = tester.widget<Text>(
        find.byKey(const Key('situation-headline')),
      );
      expect(headline.style!.color, SmokeTokens.dark.textHi);
      expect(headline.style!.color, isNot(StatusPalette.critical));
      // Icon and word, so the state survives a colour-blind reader.
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
    });

    testWidgets('a fix the app already made carries no button', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SituationCard(
            situation: Situation(
              kind: SituationKind.bridgeMovedAddress,
              headline: 'Learned your bridge’s new address',
              detail: 'It is at 10.0.0.42 now.',
              automatic: true,
              resolvedAutomatically: true,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('situation-action')), findsNothing);
      expect(find.text('Learned your bridge’s new address'), findsOneWidget);
    });

    test('green is transport health and nothing else', () {
      const reconnected = SituationCard(
        situation: Situation(
          kind: SituationKind.bridgeOutOfRange,
          headline: 'Reconnected to your bridge',
          automatic: true,
          resolvedAutomatically: true,
        ),
      );
      const clockSet = SituationCard(
        situation: Situation(
          kind: SituationKind.deviceClockUnset,
          headline: 'Set your bridge’s clock',
          automatic: true,
          resolvedAutomatically: true,
        ),
      );
      expect(reconnected.role, StatusRole.positive);
      // A clock is not a link, however pleasing setting it was.
      expect(clockSet.role, isNot(StatusRole.positive));
    });

    testWidgets('an action nothing can perform is dimmed, with its reason', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SituationCard(
            situation: Situation(
              kind: SituationKind.firmwareTooOld,
              headline: 'This bridge can only send the last 2 hours',
              actionLabel: 'Update the firmware',
            ),
            disabledReason: 'The bridge has to be reachable.',
          ),
        ),
      );
      expect(find.byKey(const Key('situation-action')), findsOneWidget);
      expect(find.byKey(const Key('situation-action-reason')), findsOneWidget);
    });
  });
}
