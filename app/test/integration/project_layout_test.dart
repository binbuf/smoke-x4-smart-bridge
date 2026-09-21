/// N0.4 — the folder layout is a contract the rest of the backlog builds on:
/// `lib/{app,design,domain,data,features,platform}` and
/// `test/{domain,design,features,golden,integration}`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the source and test trees match the N0.4 layout', () {
    const libDirs = <String>[
      'app',
      'design',
      'domain',
      'data',
      'features',
      'platform',
    ];
    const testDirs = <String>[
      'domain',
      'design',
      'features',
      'golden',
      'integration',
    ];

    final missing = <String>[
      for (final dir in libDirs)
        if (!Directory('lib/$dir').existsSync()) 'lib/$dir',
      for (final dir in testDirs)
        if (!Directory('test/$dir').existsSync()) 'test/$dir',
    ];

    expect(missing, isEmpty, reason: 'N0.4 layout is missing: $missing');
  });
}
