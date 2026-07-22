import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:protogen/src/emit_c.dart';
import 'package:protogen/src/emit_dart.dart';
import 'package:protogen/src/spec.dart';

/// Regenerates the committed codec files from protocol/records.yaml.
///
///   dart run protogen            regenerate in place
///   dart run protogen --check    exit 1 if any committed file is stale
void main(List<String> args) {
  final check = args.contains('--check');
  final root = _repoRoot();
  final spec = ProtocolSpec.load(p.join(root, 'protocol', 'records.yaml'));

  final cOut = emitC(spec);
  final dartOut = _format(emitDart(spec));

  final targets = <String, String>{
    p.join(root, 'protocol', 'gen', 'record_gen.h'): cOut,
    p.join(root, 'protocol', 'gen', 'records.g.dart'): dartOut,
    p.join(root, 'tools', 'bridge_protocol', 'lib', 'records.g.dart'): dartOut,
    p.join(root, 'app', 'lib', 'data', 'dto', 'records.g.dart'): dartOut,
  };

  var stale = false;
  targets.forEach((path, content) {
    final file = File(path);
    final current =
        file.existsSync() ? file.readAsStringSync().replaceAll('\r\n', '\n') : null;
    if (current == content) return;
    if (check) {
      stderr.writeln('stale: ${p.relative(path, from: root)}');
      stale = true;
    } else {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
      stdout.writeln('wrote ${p.relative(path, from: root)}');
    }
  });

  if (check && stale) {
    stderr.writeln('protocol/gen is stale — run: dart run protogen');
    exitCode = 1;
  } else if (check) {
    stdout.writeln('protocol/gen is current');
  }
}

/// Formats emitted Dart through `dart format` so committed output is stable
/// under the repo-wide format check.
String _format(String source) {
  final tmp = File(p.join(
    Directory.systemTemp.createTempSync('protogen').path,
    'records.g.dart',
  ));
  tmp.writeAsStringSync(source);
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['format', tmp.path],
  );
  if (result.exitCode != 0) {
    throw StateError('dart format failed on emitted code:\n${result.stderr}');
  }
  final formatted = tmp.readAsStringSync().replaceAll('\r\n', '\n');
  tmp.parent.deleteSync(recursive: true);
  return formatted;
}

String _repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, 'protocol', 'records.yaml')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not locate repo root (protocol/records.yaml)');
    }
    dir = parent;
  }
}
