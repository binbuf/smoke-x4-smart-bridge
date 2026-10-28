import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Copy gate for 12 §12.6 and 13 §13.6.
///
/// The scanner reads the string literals in the product UI layer, strips
/// interpolation expressions (they are identifiers, not copy) and applies the
/// banned-term list case-insensitively. Comments, imports and code identifiers
/// are ignored. Debug/lab sources are intentionally outside the scan; the
/// Experimental lab and technical docs are the only allow-listed contexts.
void main() {
  test('product strings contain no banned term', () {
    final files = _productFiles();
    expect(files, isNotEmpty);

    final violations = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final literal in _stringLiterals(source)) {
        for (final term in bannedTermsIn(literal.value, path: file.path)) {
          violations.add(
            '${_relative(file.path)}:${_lineOf(source, literal.offset)}: '
            '"$term" in "${literal.value}"',
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Banned product copy (12 §12.6):\n${violations.join('\n')}\n'
          'Technical docs and the Experimental lab are exempt; product copy '
          'is not.',
    );
  });

  test('the gate rejects a deliberately injected banned term', () {
    expect(bannedTermsIn('Dashboard'), contains('Dashboard'));
    expect(bannedTermsIn('A clean dashboard view'), contains('Dashboard'));
    expect(bannedTermsIn('Device log and Sessions'), isNotEmpty);
    expect(bannedTermsIn('Cooks are grouped automatically'), isEmpty);
  });

  test('a banned term inside an interpolation is not copy', () {
    expect(bannedTermsIn(r'Signal ${view.rssi} dBm'), isEmpty);
  });

  test('the production tree carries no simulation or fixture copy', () {
    final offenders = <String>[];
    for (final file in _productFiles()) {
      for (final literal in _stringLiterals(file.readAsStringSync())) {
        final value = literal.value.toLowerCase();
        if (value.contains('simulated') || value.contains('simulation')) {
          offenders.add('${_relative(file.path)}: "${literal.value}"');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}

/// 12 §12.6. `Now` and `Cooks` are allowed as controls/labels; the banned
/// variants are the tab names and `cook sessions`, so those are encoded as
/// phrases rather than single words.
const bannedTerms = <String>[
  'Graph',
  'Probe history',
  'Dashboard',
  'Monitor',
  'Saved data',
  'Device log',
  'Bridge log',
  'Bridge storage',
  'Records',
  'Plot points',
  'Samples',
  'Sessions',
  'Aging',
  'Stale',
  'Frozen',
  'Last contact',
  'No new 4m',
  'No new 12m',
  'Attached',
  'Reporting',
  'Fan running',
  'Fan speed',
  'Read-only',
  'Monitor only',
  'Observe mode',
  'Bonding',
  'Bonded',
  'Connect to GATT',
  'Secure characteristics',
  'Current cook',
  'Cook started',
  'Set target',
  'Simulated',
  'Simulation',
  'Prototype',
  'in this build',
  'there is no OTA path',
  'MTU',
  'RSSI',
  'GATT',
  'characteristic',
  'backfill',
  'ring',
  'sector',
  'generation',
  'cook sessions',
];

/// Returns the banned terms in [value]. [path] enables the two narrow
/// allow-lists from 12 §12.6:
/// - `MTU`/`RSSI` under the Technical details section in Bridge details;
/// - the approved sentence that uses "records" as a verb (12 copy baseline).
List<String> bannedTermsIn(String value, {String? path}) {
  var text = _stripInterpolations(value);
  if (path != null && path.endsWith('bridge_details.dart')) {
    final label = text.trim();
    if (label == 'MTU' || label == 'RSSI') return const [];
  }
  if (text.contains('The Bridge records whenever')) {
    // "records" here is the verb in the approved 13 §13.4 empty-state copy.
    text = text.replaceAll('The Bridge records whenever', 'The Bridge stores whenever');
  }
  final hits = <String>[];
  for (final term in bannedTerms) {
    final pattern = RegExp(
      '\\b${RegExp.escape(term)}\\b',
      caseSensitive: false,
    );
    if (pattern.hasMatch(text)) hits.add(term);
  }
  return hits;
}

String _stripInterpolations(String value) {
  final buffer = StringBuffer();
  var depth = 0;
  for (var i = 0; i < value.length; i++) {
    if (value.startsWith(r'${', i)) {
      depth++;
      i++;
      continue;
    }
    if (depth > 0) {
      if (value[i] == '{') depth++;
      if (value[i] == '}') depth--;
      continue;
    }
    buffer.write(value[i]);
  }
  return buffer.toString();
}

List<File> _productFiles() {
  final roots = <Directory>[
    Directory('lib/features'),
    Directory('lib/widgets'),
  ];
  final files = <File>[];
  for (final root in roots) {
    for (final entity in root.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) files.add(entity);
    }
  }
  for (final path in const [
    'lib/app/strings.dart',
    'lib/app/bridge_controller.dart',
    'lib/app/view_state.dart',
    'lib/app/formatters.dart',
    'lib/domain/content.dart',
  ]) {
    files.add(File(path));
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String _relative(String path) =>
    path.replaceAll('\\', '/').replaceFirst(RegExp(r'^.*/lib/'), 'lib/');

int _lineOf(String source, int offset) =>
    source.substring(0, offset).split('\n').length;

class _Literal {
  const _Literal(this.offset, this.value);

  final int offset;
  final String value;
}

/// Snapshot of Dart string literals: single, double and triple-quoted, with
/// escapes decoded. Comments and non-string code are skipped.
Iterable<_Literal> _stringLiterals(String source) sync* {
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end + 1;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
      continue;
    }
    if (c != "'" && c != '"') {
      i++;
      continue;
    }
    final quote = c;
    final start = i;
    final triple = source.startsWith(quote * 3, i);
    i += triple ? 3 : 1;
    final buffer = StringBuffer();
    while (i < source.length) {
      if (triple && source.startsWith(quote * 3, i)) {
        i += 3;
        break;
      }
      if (!triple && source[i] == quote) {
        i++;
        break;
      }
      if (!triple && source[i] == '\n') break;
      if (source[i] == r'\' && i + 1 < source.length) {
        final escaped = source[i + 1];
        buffer.write(switch (escaped) {
          'n' => '\n',
          't' => '\t',
          'r' => '\r',
          _ => escaped,
        });
        i += 2;
        continue;
      }
      buffer.write(source[i]);
      i++;
    }
    yield _Literal(start, buffer.toString());
  }
}
