/// N0.8 — the harness has a test of its own.
///
/// A golden suite whose harness is untested is a suite that can pass by
/// describing nothing. These cases are what make the other golden files mean
/// something: a one-character change fails, a missing golden fails, and the
/// description is stable across runs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden.dart';

void main() {
  testWidgets('the description is stable across two identical pumps', (
    tester,
  ) async {
    await pumpForGolden(tester, const MaterialApp(home: Text('Pit')));
    final first = describeTree(tester);
    await pumpForGolden(tester, const MaterialApp(home: Text('Pit')));
    expect(describeTree(tester), first);
  });

  testWidgets('a one-character copy change changes the description', (
    tester,
  ) async {
    await pumpForGolden(tester, const MaterialApp(home: Text('Stop cook')));
    final before = describeTree(tester);
    await pumpForGolden(tester, const MaterialApp(home: Text('Stop cool')));
    expect(describeTree(tester), isNot(before));
  });

  testWidgets('a missing golden fails rather than writing itself', (
    tester,
  ) async {
    await pumpForGolden(tester, const MaterialApp(home: Text('x')));
    expect(
      () => expectGolden(
        tester,
        'a-golden-that-does-not-exist',
        allowUpdate: false,
      ),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('disabled controls are visible in the description', (
    tester,
  ) async {
    await pumpForGolden(
      tester,
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              FilledButton(onPressed: null, child: Text('Save')),
            ],
          ),
        ),
      ),
    );
    expect(describeTree(tester), contains('button disabled'));
  });

  testWidgets('semantics labels are described, because they are content', (
    tester,
  ) async {
    await pumpForGolden(
      tester,
      const MaterialApp(home: Text('—', semanticsLabel: 'Pit, unplugged')),
    );
    expect(describeTree(tester), contains('semantics "Pit, unplugged"'));
  });
}
