/// N16.1 — the copy audit.
///
/// The copy discipline is the app's strongest asset and a must-not-regress:
/// honest words, no raw errors, predictions labelled "expected", and an absent
/// reading rendered as an em dash — never `0` (I3, I13, I15, research notes
/// §14.4).
///
/// Two kinds of check live here:
///
/// * **Source scans** over the presentation layer (`lib/features`,
///   `lib/design`), the same technique the layering and purity guards use. They
///   fail if a raw exception, a `toString()` of an error, or a debug print
///   reaches user-facing code.
/// * **Behavioural assertions** on the pure formatting layer, so the rule is
///   pinned to real output rather than to a comment.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/data.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/connection/connection_format.dart';
import 'package:smoke_bridge/features/live/live_format.dart';
import 'package:smoke_bridge/features/timeline/timeline_format.dart';

/// A raw exception object interpolated into a string.
final RegExp _exceptionInterpolation = RegExp(
  r'\$\{?(?:e|ex|err|error|exception)\b',
  caseSensitive: false,
);

/// `error.toString()` / `e.toString()` — the other way an exception leaks.
final RegExp _exceptionToString = RegExp(
  r'\b(?:e|ex|err|error|exception)\.toString\(\)',
  caseSensitive: false,
);

/// A user-facing widget or function that takes a raw error `Object`.
final RegExp _rawErrorParam = RegExp(
  r'\bObject\s*\??\s+(?:error|exception|err)\b',
);

/// Debug output that must not ship.
final RegExp _debugPrint = RegExp(r'\b(?:print|debugPrint)\s*\(');

/// Strips `//` comments so the scans match code, not prose.
String _code(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
    return '';
  }
  final index = line.indexOf('//');
  return index < 0 ? line : line.substring(0, index);
}

List<String> _scan(List<Directory> roots, RegExp pattern) {
  final hits = <String>[];
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
        if (pattern.hasMatch(_code(lines[i]))) {
          hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
  }
  return hits;
}

void main() {
  final presentation = <Directory>[
    Directory('lib/features'),
    Directory('lib/design'),
  ];

  group('source scan', () {
    test('no raw exception reaches user-facing code (I15)', () {
      expect(
        _scan(presentation, _exceptionInterpolation),
        isEmpty,
        reason: 'Failures become named states, never a stringified exception.',
      );
      expect(_scan(presentation, _exceptionToString), isEmpty);
      expect(
        _scan(presentation, _rawErrorParam),
        isEmpty,
        reason: 'User-facing widgets take named copy, not an `Object error`.',
      );
    });

    test('no debug print ships in the presentation layer', () {
      expect(_scan(presentation, _debugPrint), isEmpty);
    });
  });

  group('absent never zero (I3)', () {
    test('every absent formatter emits the em dash, never 0', () {
      expect(TempValue.absent().format(TempUnit.fahrenheit), '—');
      expect(TempValue.absent().format(TempUnit.celsius), '—');
      expect(fmtTemp0(null, TempUnit.fahrenheit), '—');
      expect(tempParts(null, TempUnit.fahrenheit).num, '—');
      expect(spokenTemp(null, TempUnit.fahrenheit), 'No reading');
      // And a real zero is still a real value.
      expect(TempValue.ofF10(0).format(TempUnit.fahrenheit), '0.0° F');
    });
  });

  group('expected says expected (N8.8)', () {
    test('a predicted rail node carries the word, an actual one does not', () {
      final predicted = TimelineEvent(
        atMs: 1700000000000,
        title: 'Wrap',
        note: '',
        actual: false,
      );
      final actual = TimelineEvent(
        atMs: 1700000000000,
        title: 'Wrapped',
        note: '',
        actual: true,
      );
      expect(railTimeLabel(predicted), endsWith('· expected'));
      expect(railTimeLabel(actual), isNot(contains('expected')));
    });
  });

  group('copy over error (I13/I15)', () {
    test('a wire error maps to named copy, not the raw token', () {
      final state = ConnectionState(
        phase: ConnectionPhase.error,
        error: 'wrong_password',
      );
      final copy = connectionErrorCopy(state);
      expect(copy, contains('password was rejected'));
      expect(copy, isNot(contains('wrong_password')));
      expect(copy, isNot(contains('Exception')));
    });

    test('an unknown wire error still gets human copy', () {
      final copy = connectionErrorCopy(
        const ConnectionState(phase: ConnectionPhase.error, error: 'kaboom'),
      );
      expect(copy, isNot(contains('kaboom')));
      expect(copy.trim(), isNotEmpty);
    });
  });
}
