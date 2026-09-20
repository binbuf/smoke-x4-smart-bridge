/// The §E.3 mode switch, as a surface.
///
/// The protocol itself is tested in `netmode_switch_test.dart`; this is about
/// the four screens over it, and the UI rule §E.3 ends on: **never a dead
/// control and never an unexplained spinner.** So every phase here is asserted
/// to carry words, the rollback is asserted to read as a plan rather than an
/// error, and the key the device generates for its own network is asserted to
/// reach the screen — it exists in exactly two places, the bridge and this
/// sheet, and losing it strands somebody in the yard.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/bridge/netmode_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: SmokeTheme.dark,
  home: Scaffold(body: child),
);

Widget _sheet({
  required NetworkMode target,
  Future<String> Function(NetworkMode, String, String)? apply,
  Future<bool> Function()? probe,
  Future<void> Function()? commit,
  String knownSsid = '',
}) => _wrap(
  NetModeSheet(
    target: target,
    apply: apply ?? (_, _, _) async => '',
    probe: probe ?? () async => true,
    commit: commit ?? () async {},
    knownSsid: knownSsid,
    attemptDelay: Duration.zero,
    maxAttempts: 2,
  ),
);

void main() {
  testWidgets('the cost is stated before anything is sent', (tester) async {
    var applied = 0;
    await tester.pumpWidget(
      _sheet(
        target: NetworkMode.ap,
        apply: (_, _, _) async {
          applied++;
          return 'hunt-oak-mesa';
        },
      ),
    );

    // The sentence that stops a mode switch being frightening: whatever
    // happens, it undoes itself and nobody walks to the smoker.
    expect(find.byKey(const Key('netmode-cost')), findsOneWidget);
    expect(find.textContaining('puts back what was working'), findsOneWidget);
    // Nothing has been sent yet.
    expect(applied, 0);
    // The escape hatch names the outcome, not the dialog mechanic.
    expect(find.text('Leave it as it is'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('joining a network cannot start without one named', (
    tester,
  ) async {
    await tester.pumpWidget(_sheet(target: NetworkMode.sta));

    // Present and disabled — a bridge cannot join a network nobody named,
    // and the empty field above it is the reason.
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const Key('netmode-go')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('netmode-ssid')), 'Backyard');
    await tester.pump();
    final live = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const Key('netmode-go')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(live.onPressed, isNotNull);
  });

  testWidgets('a switch that is found and confirmed says so', (tester) async {
    var committed = 0;
    await tester.pumpWidget(
      _sheet(
        target: NetworkMode.ap,
        commit: () async => committed++,
      ),
    );
    await tester.tap(find.byKey(const Key('netmode-go')));
    await tester.pumpAndSettle();

    expect(committed, 1);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('netmode-phase-title')))
          .data,
      'Done',
    );
  });

  testWidgets('the key the device generated reaches the screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sheet(
        target: NetworkMode.ap,
        apply: (_, _, _) async => 'hunt-oak-mesa',
      ),
    );
    await tester.tap(find.byKey(const Key('netmode-go')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('netmode-ap-key')), findsOneWidget);
    expect(find.text('hunt-oak-mesa'), findsOneWidget);
    expect(find.textContaining('Write this down'), findsOneWidget);
  });

  testWidgets('a bridge nobody could find reads as a plan, not an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _sheet(target: NetworkMode.ap, probe: () async => false),
    );
    await tester.tap(find.byKey(const Key('netmode-go')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('netmode-phase-title')))
          .data,
      'Couldn’t reach the bridge',
    );
    // With a real number on it, because the countdown is a fact the user
    // should not have to take on faith.
    expect(find.textContaining('It will go back to the network'), findsOneWidget);
    expect(find.text('Wait for it to come back'), findsOneWidget);
  });

  testWidgets('a bridge that refused says nothing changed', (tester) async {
    await tester.pumpWidget(
      _sheet(
        target: NetworkMode.ap,
        apply: (_, _, _) async => throw const _Refusal('That key is too short.'),
      ),
    );
    await tester.tap(find.byKey(const Key('netmode-go')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('netmode-phase-title')))
          .data,
      'The bridge said no',
    );
    expect(find.textContaining('Nothing changed'), findsOneWidget);
  });

  testWidgets('a link that died mid-switch is hunted, not reported as failed', (
    tester,
  ) async {
    // The reply may simply have been lost while the interface came down,
    // which is indistinguishable from a refusal at the transport layer — so
    // the sheet goes looking, exactly as if it had been accepted.
    var probes = 0;
    await tester.pumpWidget(
      _sheet(
        target: NetworkMode.ap,
        apply: (_, _, _) async => throw StateError('link gone'),
        probe: () async {
          probes++;
          return true;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('netmode-go')));
    await tester.pumpAndSettle();

    expect(probes, greaterThan(0));
    expect(
      tester
          .widget<Text>(find.byKey(const Key('netmode-phase-title')))
          .data,
      'Done',
    );
  });
}

class _Refusal implements BridgeRefusal {
  const _Refusal(this.message);
  @override
  final String message;
}
