/// A24.9 — the disruptive-verb completion sheet: send → verify-by-drop → an
/// explicit done state, or an honest "still answering" when it never dropped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/design/design.dart';
import 'package:smoke_bridge/features/bridge/verb_progress.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: SmokeTheme.dark, home: Scaffold(body: child));

void main() {
  testWidgets('the drop is the confirmation: probe fails → done state', (
    tester,
  ) async {
    var sent = 0;
    await tester.pumpWidget(
      _wrap(
        VerbProgressSheet(
          verb: DisruptiveVerb.factoryReset,
          send: () async => sent++,
          // The bridge went down — exactly what a completed reset looks like.
          probe: () async => throw StateError('unreachable'),
          pollEvery: const Duration(milliseconds: 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sent, 1);
    expect(find.byKey(const Key('verb-done')), findsOneWidget);
    expect(find.text('Factory reset complete'), findsOneWidget);
    // The reset done-state offers the follow-through, not a bare "ok".
    expect(find.textContaining('forget “Smoke Bridge”'), findsOneWidget);
  });

  testWidgets('a confirmed reset forgets locally and offers setup', (
    tester,
  ) async {
    var forgot = 0;
    var setup = 0;
    await tester.pumpWidget(
      _wrap(
        VerbProgressSheet(
          verb: DisruptiveVerb.factoryReset,
          send: () async {},
          probe: () async => throw StateError('unreachable'),
          onCompleted: () => forgot++,
          onSetUpAgain: () => setup++,
          pollEvery: const Duration(milliseconds: 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The local forget happens at the moment the drop confirms the wipe —
    // not behind an extra tap the user might never make.
    expect(forgot, 1);
    await tester.tap(find.byKey(const Key('verb-setup-again')));
    await tester.pumpAndSettle();
    expect(setup, 1);
  });

  testWidgets('a bridge that never drops is reported, not celebrated', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        VerbProgressSheet(
          verb: DisruptiveVerb.restart,
          send: () async {},
          probe: () async {}, // still answering, every time
          pollEvery: const Duration(milliseconds: 10),
          maxPolls: 2,
        ),
      ),
    );
    // Let the two poll cycles (probe + 10 ms wait) run out.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byKey(const Key('verb-still-answering')), findsOneWidget);
    expect(find.byKey(const Key('verb-done')), findsNothing);
  });

  testWidgets('a reply that raced the drop still verifies by behaviour', (
    tester,
  ) async {
    // The answer-first discipline: the reply can race the link drop. The
    // bridge WAS reachable (first probe answers) and then went down — that
    // is a completed verb, even though the send itself threw.
    var probes = 0;
    await tester.pumpWidget(
      _wrap(
        VerbProgressSheet(
          verb: DisruptiveVerb.powerOff,
          send: () async => throw StateError('socket died mid-reply'),
          probe: () async {
            if (probes++ == 0) {
              return; // still up on the first look…
            }
            throw StateError('unreachable'); // …then it drops
          },
          pollEvery: const Duration(milliseconds: 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verb-done')), findsOneWidget);
    expect(find.text('The bridge is off'), findsOneWidget);
  });

  testWidgets('an unreachable bridge is an error, never a false "done"', (
    tester,
  ) async {
    // Send fails AND the very first probe fails: nothing was delivered.
    await tester.pumpWidget(
      _wrap(
        VerbProgressSheet(
          verb: DisruptiveVerb.factoryReset,
          send: () async => throw StateError('no route'),
          probe: () async => throw StateError('unreachable'),
          pollEvery: const Duration(milliseconds: 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verb-cant-reach')), findsOneWidget);
    expect(find.byKey(const Key('verb-done')), findsNothing);
    expect(find.textContaining('Nothing changed'), findsOneWidget);
  });
}
