/// A9.2 / A9.3 / A9.4 / A9.6 — the dashboard's widgets.
///
/// Every case here is a projection of a seeded snapshot: no transport, no
/// network, no plugin. The one assertion worth reading twice is the
/// detached tile's — it contains **no digit at all**, which is the last
/// place the M0 invariant could still be broken.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/features/chart/chart_viewport.dart';
import 'package:smoke_bridge/features/dashboard/dashboard.dart';
import 'package:smoke_bridge/data/transport/ble_transport.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';

import '../support/shapes.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: child),
    );

Iterable<String> _textsIn(WidgetTester tester, Finder scope) => tester
    .widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))
    .map((t) => t.data ?? '');

void main() {
  group('probe tiles', () {
    testWidgets('an attached headline tile shows the huge number', (
      tester,
    ) async {
      final snap = snapshotFor(syntheticCook(hours: 6));
      await tester.pumpWidget(
        _wrap(HeadlineProbeTile(view: snap.headlinePit!)),
      );
      expect(find.byKey(const Key('probe-tile-headline-1')), findsOneWidget);
      expect(find.textContaining('°'), findsWidgets);
      expect(find.text('target 250°'), findsOneWidget);
    });

    testWidgets('a detached headline tile contains no digit at all', (
      tester,
    ) async {
      final snap = snapshotFor(allDetached(hours: 1));
      await tester.pumpWidget(
        _wrap(HeadlineProbeTile(view: snap.probes.first)),
      );
      expect(find.byKey(const Key('probe-detached-1')), findsOneWidget);
      expect(find.text('unplugged'), findsOneWidget);
      final tile = find.byKey(const Key('probe-tile-headline-1'));
      for (final s in _textsIn(tester, tile)) {
        expect(
          RegExp(r'\d').hasMatch(s),
          isFalse,
          reason: 'a detached tile rendered "$s"',
        );
      }
    });

    testWidgets('a detached compact tile says unplugged, not 0', (
      tester,
    ) async {
      final snap = snapshotFor(allDetached(hours: 1));
      await tester.pumpWidget(_wrap(CompactProbeTile(view: snap.probes[2])));
      expect(find.text('unplugged'), findsOneWidget);
      expect(find.text('0°'), findsNothing);
    });

    testWidgets('a raised alarm shows an icon AND a word', (tester) async {
      final snap = snapshotFor(
        syntheticCook(hours: 6),
        alarms: const [
          Alarm(
            id: 1,
            rule: 'target_reached',
            probe: 1,
            severity: AlarmSeverity.critical,
          ),
        ],
      );
      await tester.pumpWidget(
        _wrap(HeadlineProbeTile(view: snap.headlinePit!)),
      );
      // Status never travels as colour alone.
      expect(find.byKey(const Key('probe-alarm-1')), findsOneWidget);
      expect(find.text('target_reached'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('a stall says it is normal, because that is the point', (
      tester,
    ) async {
      final snap = snapshotFor(syntheticCook(hours: 8));
      await tester.pumpWidget(
        _wrap(HeadlineProbeTile(view: snap.headlineFood!)),
      );
      expect(find.byKey(const Key('probe-stall-2')), findsOneWidget);
      expect(find.textContaining('normal'), findsOneWidget);
    });

    testWidgets('the tile reads correctly out loud', (tester) async {
      final snap = snapshotFor(syntheticCook(hours: 6));
      await tester.pumpWidget(
        _wrap(HeadlineProbeTile(view: snap.headlinePit!)),
      );
      final text = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const Key('probe-tile-headline-1')),
              matching: find.byType(Text),
            )
            .at(1),
      );
      expect(text.semanticsLabel, contains('Pit'));
      expect(text.semanticsLabel, anyOf(contains('degrees'), contains('°')));
    });
  });

  group('header strip', () {
    testWidgets('HTTP shows the address it actually reached', (tester) async {
      await tester.pumpWidget(
        _wrap(DashboardHeader(snapshot: snapshotFor(syntheticCook(hours: 2)))),
      );
      expect(find.byKey(const Key('dashboard-link-http')), findsOneWidget);
      expect(find.text('10.50.50.38'), findsOneWidget);
    });

    testWidgets('BLE says full history needs Wi-Fi', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DashboardHeader(
            snapshot: snapshotFor(
              syntheticCook(hours: 2),
              link: LinkKind.ble,
              fullHistory: false,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('dashboard-link-ble')), findsOneWidget);
    });

    testWidgets('offline is a state, not an error', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DashboardHeader(
            snapshot: snapshotFor(
              syntheticCook(hours: 2),
              link: LinkKind.offline,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('dashboard-link-offline')), findsOneWidget);
      expect(find.textContaining('saved data'), findsOneWidget);
    });

    testWidgets('no battery data renders absence, never 0%', (tester) async {
      await tester.pumpWidget(
        _wrap(DashboardHeader(snapshot: snapshotFor(syntheticCook(hours: 2)))),
      );
      expect(
        find.byKey(const Key('dashboard-battery-unknown')),
        findsOneWidget,
      );
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('a real percentage renders when there is one', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DashboardHeader(
            snapshot: snapshotFor(syntheticCook(hours: 2), socPct: 71),
          ),
        ),
      );
      expect(find.text('71%'), findsOneWidget);
    });

    testWidgets('base lost is stated: the bridge is fine, the base is not', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          DashboardHeader(
            snapshot: snapshotFor(syntheticCook(hours: 2), baseLost: true),
          ),
        ),
      );
      expect(find.byKey(const Key('dashboard-base-lost')), findsOneWidget);
      expect(find.textContaining('base station'), findsOneWidget);
    });

    testWidgets('a session with no clock shows elapsed time', (tester) async {
      final cook = syntheticCook(hours: 3);
      final snap = buildDashboard(
        status: statusFor(),
        live: LiveState(t: cook.last.t, tempsF10: cook.last.tempsF10),
        history: cook,
        link: LinkKind.http,
      );
      expect(snap.startedUnixMs, isNull);
      await tester.pumpWidget(_wrap(DashboardHeader(snapshot: snap)));
      expect(find.byKey(const Key('dashboard-elapsed')), findsOneWidget);
      expect(find.textContaining('1970'), findsNothing);
    });
  });

  group('session controls', () {
    testWidgets('stopping asks first, then sends exactly one command', (
      tester,
    ) async {
      final sent = <ControlCommand>[];
      await tester.pumpWidget(
        _wrap(
          SessionControls(
            snapshot: snapshotFor(syntheticCook(hours: 1)),
            onControl: (c) async => sent.add(c),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('control-stop')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('control-stop-confirm')), findsOneWidget);
      expect(sent, isEmpty);
      await tester.tap(find.byKey(const Key('control-stop-confirm-yes')));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(sent.single, isA<StopSessionCommand>());
    });

    testWidgets('starting a cook is one typed command', (tester) async {
      final sent = <ControlCommand>[];
      await tester.pumpWidget(
        _wrap(
          SessionControls(
            snapshot: snapshotFor(
              syntheticCook(hours: 1),
              sessionActive: false,
            ),
            onControl: (c) async => sent.add(c),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('control-start')));
      await tester.pumpAndSettle();
      expect(sent.single, isA<StartSessionCommand>());
    });

    testWidgets('marks are offered by name and sent as their kind', (
      tester,
    ) async {
      final sent = <ControlCommand>[];
      await tester.pumpWidget(
        _wrap(
          SessionControls(
            snapshot: snapshotFor(syntheticCook(hours: 1)),
            onControl: (c) async => sent.add(c),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('control-mark')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('control-mark-sheet')), findsOneWidget);
      expect(find.text('Wrapped'), findsOneWidget);
      // The firmware's own kinds are not on offer.
      expect(find.text('Alarm'), findsNothing);
      await tester.tap(find.byKey(const Key('mark-kind-wrapped')));
      await tester.pumpAndSettle();
      expect((sent.single as MarkCommand).kind, MarkKind.wrapped);
    });

    testWidgets('a typed refusal surfaces its meaning, not a stack trace', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SessionControls(
            snapshot: snapshotFor(
              syntheticCook(hours: 1),
              sessionActive: false,
            ),
            onControl: (_) async =>
                throw const BridgeUnsupportedException('control'),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('control-start')));
      await tester.pumpAndSettle();
      expect(find.textContaining('needs Wi-Fi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a transport that cannot control says why', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SessionControls(
            snapshot: snapshotFor(syntheticCook(hours: 1)),
            onControl: (_) async {},
            enabled: false,
            disabledReason: 'Not connected to the bridge.',
          ),
        ),
      );
      expect(
        find.byKey(const Key('session-controls-disabled')),
        findsOneWidget,
      );
      final stop = tester.widget<OutlinedButton>(
        find.byKey(const Key('control-stop')),
      );
      expect(stop.onPressed, isNull);
    });
  });

  group('the assembled screen', () {
    Widget view(
      List<Sample> cook, {
      Brightness brightness = Brightness.dark,
      List<Alarm> alarms = const [],
      bool fullHistory = true,
    }) {
      final snap = snapshotFor(
        cook,
        alarms: alarms,
        fullHistory: fullHistory,
        link: fullHistory ? LinkKind.http : LinkKind.ble,
      );
      return _wrap(
        DashboardView(
          snapshot: snap,
          viewport: ChartViewport.forSession(
            fromT: cook.isEmpty ? 0 : cook.first.t,
            toT: cook.isEmpty ? 60 : cook.last.t,
          ),
          onViewport: (_) {},
          onControl: (_) async {},
        ),
        brightness: brightness,
      );
    }

    testWidgets('renders a live cook with no network anywhere', (tester) async {
      await tester.pumpWidget(view(syntheticCook(hours: 6)));
      await tester.pump();
      expect(find.byKey(const Key('dashboard-view')), findsOneWidget);
      expect(find.byKey(const Key('probe-tile-headline-1')), findsOneWidget);
      expect(find.byKey(const Key('probe-tile-headline-2')), findsOneWidget);
      expect(find.byKey(const Key('probe-tile-compact-3')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no probes renders an explanation, not an error', (
      tester,
    ) async {
      await tester.pumpWidget(view(allDetached(hours: 1)));
      await tester.pump();
      expect(find.byKey(const Key('dashboard-no-probes')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives 320 dp and a 1.3x text scale', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: view(syntheticCook(hours: 6)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a degraded transport shows the capability notice', (
      tester,
    ) async {
      await tester.pumpWidget(
        view(syntheticCook(hours: 2), fullHistory: false),
      );
      await tester.pump();
      // The chart is below the fold on a phone-sized surface, so scroll to
      // it — a lazily-built list child is not in the tree until it is.
      await tester.dragUntilVisible(
        find.byKey(const Key('chart-capability-notice')),
        find.byKey(const Key('dashboard-view')),
        const Offset(0, -200),
      );
      expect(find.byKey(const Key('chart-capability-notice')), findsOneWidget);
    });

    testWidgets('renders in the light theme too', (tester) async {
      await tester.pumpWidget(
        view(syntheticCook(hours: 3), brightness: Brightness.light),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
