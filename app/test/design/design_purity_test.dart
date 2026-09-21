/// N0.3 — `lib/design/` is presentation over plain values: stateless, and it
/// does not reach into `app/`, `data/` or `features/`. N3 fills it with tokens
/// and primitives; this guard keeps it a leaf.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _stateful = RegExp(r'\bStatefulWidget\b|\bState<|\bsetState\s*\(');
final RegExp _inwardImport = RegExp(
  r'''import\s+['"](package:flutter_riverpod|package:smoke_bridge/(?:app|data|features)/)''',
);

void main() {
  test('lib/design exists, is stateless, and depends on nothing inward', () {
    final design = Directory('lib/design');
    expect(design.existsSync(), isTrue, reason: 'N0.4 requires lib/design/');

    final violations = <String>[];
    for (final file
        in design
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      if (_stateful.hasMatch(source)) {
        violations.add('${file.path} (stateful)');
      }
      if (_inwardImport.hasMatch(source)) {
        violations.add('${file.path} (inward dependency)');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'lib/design/ primitives take plain values and render them; state '
          'belongs in features/. Offending files: $violations',
    );
  });
}
