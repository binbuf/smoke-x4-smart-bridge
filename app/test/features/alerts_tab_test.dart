/// The Alerts tab's delivery verdict (design 13 §13.5.5, §13.5.7 banner 11).
///
/// This branch used to be a placeholder shipping in a quarter of the primary
/// navigation — and the wrong quarter to stub, because a fourteen-hour cook
/// running with notifications denied is a **silent total failure** the user
/// discovers at breakfast.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/features/alarms/alerts_tab.dart';

Widget _host(DeliveryStatus status, {Future<void> Function()? onSendTest}) =>
    MaterialApp(
      theme: SmokeTheme.dark,
      home: Scaffold(
        body: AlertsTab(status: status, onSendTest: onSendTest),
      ),
    );

const _allGood = DeliveryStatus(
  permissionGranted: true,
  monitoringEnabled: true,
  batteryExempt: true,
);

void main() {
  group('the verdict', () {
    test('everything on wakes you, and has nothing to fix', () {
      expect(_allGood.willWake, isTrue);
      expect(_allGood.blockers, isEmpty);
      expect(_allGood.worst, isNull);
    });

    test('denied notifications is the worst blocker, and it wins', () {
      const s = DeliveryStatus(
        permissionGranted: false,
        monitoringEnabled: false,
        batteryExempt: false,
      );
      expect(s.willWake, isFalse);
      expect(s.worst, DeliveryBlocker.permission);
      expect(s.blockers, [
        DeliveryBlocker.permission,
        DeliveryBlocker.monitoringOff,
        DeliveryBlocker.batteryOptimised,
      ]);
    });

    test('monitoring off alone still means you will not be woken', () {
      const s = DeliveryStatus(
        permissionGranted: true,
        monitoringEnabled: false,
        batteryExempt: true,
      );
      expect(s.willWake, isFalse);
      expect(s.worst, DeliveryBlocker.monitoringOff);
    });

    test('battery optimisation is a caveat, not a failure', () {
      const s = DeliveryStatus(
        permissionGranted: true,
        monitoringEnabled: true,
        batteryExempt: false,
      );
      // It is the difference between "woken at 3 a.m." and "told at 7 a.m.",
      // not between alerted and silent — so the verdict stays positive and
      // the caveat is stated underneath.
      expect(s.willWake, isTrue);
      expect(s.worst, DeliveryBlocker.batteryOptimised);
      expect(s.blockers, hasLength(1));
    });
  });

  group('the card', () {
    testWidgets('says you will be woken, plainly', (tester) async {
      await tester.pumpWidget(_host(_allGood));
      await tester.pump();

      expect(find.text('You’ll be woken'), findsOneWidget);
      expect(find.byKey(const Key('alerts-send-test')), findsOneWidget);
      // Nothing to fix, so no fix buttons.
      expect(find.byKey(const Key('alerts-fix-permission')), findsNothing);
    });

    testWidgets('names the blocker and offers its fix', (tester) async {
      await tester.pumpWidget(
        _host(
          const DeliveryStatus(
            permissionGranted: false,
            monitoringEnabled: true,
            batteryExempt: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('You won’t be woken'), findsOneWidget);
      expect(find.text('Notifications are blocked'), findsOneWidget);
      expect(find.byKey(const Key('alerts-fix-permission')), findsOneWidget);
    });

    testWidgets('the test alarm reports what happened', (tester) async {
      var sent = 0;
      await tester.pumpWidget(_host(_allGood, onSendTest: () async => sent++));
      await tester.pump();

      await tester.tap(find.byKey(const Key('alerts-send-test')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(sent, 1);
      expect(find.byKey(const Key('alerts-test-result')), findsOneWidget);
    });

    testWidgets('a failed test says so rather than claiming success', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(_allGood, onSendTest: () async => throw StateError('blocked')),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('alerts-send-test')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Couldn’t send it'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rules are named as unbuilt, not faked as dead switches', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_allGood));
      await tester.pump();

      // The old settings page rendered six always-on switches with
      // `onChanged: null`. There are no Switch widgets here at all.
      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('not editable yet'), findsOneWidget);
    });
  });
}
