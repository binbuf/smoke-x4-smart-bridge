/// N3.7 / exit gate — screens may not introduce a raw colour or a `Duration`
/// literal.
///
/// Tokens live in `lib/design/`; a screen reads them from `Theme.of(context)`.
/// The two expressions this test bans are the ones that silently escape the
/// theme: a `Duration(...)` literal (which ignores reduced motion) and a colour
/// constructor or `Colors.*` constant (which does not retint with the theme).
///
/// Scope is the presentation layer — `lib/features/` and `lib/app/`. The pure
/// domain (`lib/domain/`) legitimately uses `Duration` for time arithmetic and
/// carries no colours.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _duration = RegExp(r'\bDuration\s*\(');
final RegExp _rawColour = RegExp(
  r'\bColor\s*\(|\bColor\.from(?:ARGB|RGBO)\b|\bColors\.\w+',
);

void main() {
  test('no Duration literal or raw colour outside lib/design/', () {
    final roots = <Directory>[Directory('lib/features'), Directory('lib/app')];
    final violations = <String>[];

    for (final root in roots) {
      if (!root.existsSync()) {
        continue;
      }
      for (final file
          in root
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (_duration.hasMatch(line)) {
            violations.add('${file.path}:${i + 1} Duration literal: $line');
          }
          if (_rawColour.hasMatch(line)) {
            violations.add('${file.path}:${i + 1} raw colour: $line');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Screens take motion from SmokeMotion and colour from SmokeTokens. '
          'Offending lines:\n${violations.join('\n')}',
    );
  });

  test('the design system defines its own motion tokens', () {
    final motion = File('lib/design/motion.dart');
    expect(motion.existsSync(), isTrue);
    final source = motion.readAsStringSync();
    expect(source, contains('milliseconds: 120'));
    expect(source, contains('milliseconds: 220'));
    expect(source, contains('milliseconds: 600'));
    expect(source, contains('milliseconds: 800'));
    expect(source, contains('seconds: 2'));
  });
}
