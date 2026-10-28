import 'dart:convert';
import 'dart:io';

/// Writes `screenshots/manifest.json` for the reviewed golden set.
///
/// Run after an intentional screenshot review:
///   cd app
///   flutter test --update-goldens tool/ui_screenshots_test.dart
///   dart run tool/screenshot_manifest.dart
///
/// `test/screenshot_manifest_test.dart` fails when a golden changes or a new
/// PNG appears without the manifest being regenerated, so a screenshot diff is
/// never accepted silently.
void main() {
  final directory = Directory('screenshots');
  final entries = <String, Object>{};
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final bytes = file.readAsBytesSync();
    final size = _pngSize(bytes);
    entries[_name(file)] = {
      'width': size.width,
      'height': size.height,
      'fnv1a': _fnv1a(bytes),
    };
  }
  File('screenshots/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(entries)}\n',
  );
  stdout.writeln('Wrote screenshots/manifest.json for ${files.length} shots.');
}

String _name(File file) => file.uri.pathSegments.last;

({int width, int height}) _pngSize(List<int> bytes) => (
  width: _readUint32(bytes, 16),
  height: _readUint32(bytes, 20),
);

int _readUint32(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

/// 32-bit FNV-1a: small, dependency-free and stable across Dart/Python.
String _fnv1a(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
