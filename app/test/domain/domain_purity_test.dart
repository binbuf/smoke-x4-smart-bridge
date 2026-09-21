/// N0.3 — `lib/domain/` is pure Dart: no Flutter, no `dart:ui`. Domain logic is
/// host-testable with no binding (components_research_notes.md §6, §10). CI's
/// grep is the belt; this is the braces and is what fails on a clean checkout.
library;

import 'dart:io';

import 'package:test/test.dart';

final RegExp _flutterImport = RegExp(
  r'''import\s+['"](package:flutter(?:/[^'"]*)?|dart:ui)['"]''',
);

void main() {
  test('lib/domain exists and contains no Flutter or dart:ui imports', () {
    final domain = Directory('lib/domain');
    expect(domain.existsSync(), isTrue, reason: 'N0.4 requires lib/domain/');

    final violations = <String>[];
    for (final file
        in domain
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      if (_flutterImport.hasMatch(file.readAsStringSync())) {
        violations.add(file.path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'lib/domain/ must stay pure Dart so its logic is host-testable '
          'without a Flutter binding. Offending files: $violations',
    );
  });
}
