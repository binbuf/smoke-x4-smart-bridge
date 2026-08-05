// P2.1–P2.3 contract guard: protocol/openapi.yaml and the HTTP fixtures under
// protocol/fixtures/http/ must stay in lockstep with 06 §6.1–6.3.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Walk upward from cwd until we find the repo root (protocol/openapi.yaml).
String findRepoRoot() {
  var dir = Directory.current.absolute.path;
  while (true) {
    if (File(p.join(dir, 'protocol', 'openapi.yaml')).existsSync()) {
      return dir;
    }
    final parent = p.dirname(dir);
    if (parent == dir) {
      fail(
        'could not locate repo root (protocol/openapi.yaml) above '
        '${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// The full 06 §6.2 endpoint table, plus the captive-portal shims and the
/// static fallback — every one must appear in the spec.
const requiredPaths = <String>[
  '/api/v1/status',
  '/api/v1/live',
  '/api/v1/stream',
  '/api/v1/sessions',
  '/api/v1/sessions/{id}',
  '/api/v1/sessions/{id}/stop',
  '/api/v1/sessions/{id}/samples',
  '/api/v1/sessions/{id}/marks',
  '/api/v1/pairing',
  '/api/v1/pairing/sync',
  '/api/v1/pairing/unpair',
  '/api/v1/config/wifi',
  '/api/v1/config/device',
  '/api/v1/config/alarms',
  '/api/v1/time',
  '/api/v1/cook-clock',
  '/api/v1/radio',
  '/api/v1/ota',
  '/api/v1/debug/packets',
  '/api/v1/debug/coredump',
  '/api/v1/debug/tasks',
  '/',
  '/generate_204',
  '/gen_204',
  '/hotspot-detect.html',
  '/library/test/success.html',
  '/ncsi.txt',
  '/connecttest.txt',
];

/// The 06 §6.1 status → code table, in full.
const errorCodesByStatus = <String, List<String>>{
  '400': ['invalid_body', 'invalid_field', 'unsupported_mode'],
  '401': ['unauthorized'],
  '404': ['session_not_found', 'not_found'],
  // clock_unknown: POST /cook-clock was given an absolute started_unix_ms
  // and the device has no wall clock to measure it against.
  '409': ['session_active', 'not_paired', 'busy', 'clock_unknown'],
  '413': ['body_too_large'],
  '500': ['storage_error', 'internal'],
  '503': ['radio_unavailable', 'ota_in_progress'],
};

void main() {
  final root = findRepoRoot();
  final specFile = File(p.join(root, 'protocol', 'openapi.yaml'));
  final fixturesDir = p.join(root, 'protocol', 'fixtures', 'http');
  final spec = loadYaml(specFile.readAsStringSync()) as YamlMap;

  /// Resolve a local `#/a/b/c` JSON pointer against the spec.
  dynamic resolveRef(String ref) {
    expect(ref, startsWith('#/'), reason: 'only local refs are expected: $ref');
    dynamic node = spec;
    for (final part in ref.substring(2).split('/')) {
      expect(node, isA<YamlMap>(), reason: '$ref: $part not reachable');
      node = (node as YamlMap)[part];
      expect(node, isNotNull, reason: 'dangling \$ref: $ref (at "$part")');
    }
    return node;
  }

  /// Follow a `$ref` if the node is one; otherwise return the node itself.
  dynamic deref(dynamic node) {
    if (node is YamlMap && node[r'$ref'] is String) {
      return resolveRef(node[r'$ref'] as String);
    }
    return node;
  }

  group('openapi.yaml basics', () {
    test('is OpenAPI 3.0.3, titled Smoke Bridge Device API v1.0.0', () {
      expect(spec['openapi'], '3.0.3');
      final info = spec['info'] as YamlMap;
      expect(info['title'], 'Smoke Bridge Device API');
      expect(info['version'], '1.0.0');
    });

    test('every local \$ref in the document resolves', () {
      var count = 0;
      void walk(dynamic node) {
        if (node is YamlMap) {
          for (final entry in node.entries) {
            if (entry.key == r'$ref' && entry.value is String) {
              resolveRef(entry.value as String);
              count++;
            } else {
              walk(entry.value);
            }
          }
        } else if (node is YamlList) {
          node.forEach(walk);
        }
      }

      walk(spec);
      expect(count, greaterThan(50), reason: 'sanity: the spec is ref-heavy');
    });
  });

  group('§6.2 endpoint table', () {
    test('every path is present', () {
      final paths = spec['paths'] as YamlMap;
      final declared = paths.keys.map((k) => k.toString()).toSet();
      for (final path in requiredPaths) {
        expect(declared, contains(path), reason: 'missing path $path');
      }
    });

    test('sessions/{id}/samples carries all seven query parameters and '
        'all four response content types', () {
      final op =
          ((spec['paths'] as YamlMap)['/api/v1/sessions/{id}/samples']
                  as YamlMap)['get']
              as YamlMap;
      final params = (op['parameters'] as YamlList)
          .map(deref)
          .map((param) => (param as YamlMap)['name'] as String?)
          .whereType<String>()
          .toSet();
      for (final name in [
        'from',
        'to',
        'stride',
        'bucket',
        'agg',
        'format',
        'probes',
      ]) {
        expect(params, contains(name), reason: 'samples missing ?$name');
      }
      final content =
          ((op['responses'] as YamlMap)['200'] as YamlMap)['content']
              as YamlMap;
      final types = content.keys.map((k) => k.toString()).toSet();
      expect(
        types,
        containsAll(<String>[
          'application/octet-stream',
          'application/json',
          'application/x-ndjson',
          'text/csv',
        ]),
      );
    });
  });

  group('/live schema', () {
    test('probe temp_f10 is nullable and attached is a required boolean', () {
      final op =
          ((spec['paths'] as YamlMap)['/api/v1/live'] as YamlMap)['get']
              as YamlMap;
      final schema =
          deref(
                ((((op['responses'] as YamlMap)['200'] as YamlMap)['content']
                        as YamlMap)['application/json']
                    as YamlMap)['schema'],
              )
              as YamlMap;
      final probeSchema =
          deref((deref(schema['properties']['probes']) as YamlMap)['items'])
              as YamlMap;
      final props = probeSchema['properties'] as YamlMap;

      final tempF10 = props['temp_f10'] as YamlMap;
      expect(
        tempF10['nullable'],
        isTrue,
        reason: 'a detached probe must be null, not optional-with-default',
      );
      expect(
        tempF10.containsKey('default'),
        isFalse,
        reason: 'temp_f10 must not carry a default',
      );

      final attached = props['attached'] as YamlMap;
      expect(attached['type'], 'boolean');
      final required = (probeSchema['required'] as YamlList).map(
        (e) => e.toString(),
      );
      expect(required, contains('attached'));
    });

    test('recent.series entries are nullable arrays of nullable ints', () {
      final live = resolveRef('#/components/schemas/Live') as YamlMap;
      final recent = deref(live['properties']['recent']) as YamlMap;
      final series = recent['properties']['series'] as YamlMap;
      final items = series['items'] as YamlMap;
      expect(
        items['nullable'],
        isTrue,
        reason: 'a fully-detached probe series is null',
      );
      expect(
        (items['items'] as YamlMap)['nullable'],
        isTrue,
        reason: 'individual detached samples are null',
      );
    });
  });

  group('error model', () {
    test('ErrorCode enumerates exactly the §6.1 table', () {
      final schema = resolveRef('#/components/schemas/ErrorCode') as YamlMap;
      final declared = (schema['enum'] as YamlList)
          .map((e) => e.toString())
          .toSet();
      final expected = errorCodesByStatus.values
          .expand((codes) => codes)
          .toSet();
      expect(declared, expected);
    });

    test('every documented error code has a fixture matching the envelope', () {
      for (final code in errorCodesByStatus.values.expand((codes) => codes)) {
        final file = File(p.join(fixturesDir, 'error-$code.json'));
        expect(
          file.existsSync(),
          isTrue,
          reason: 'missing fixture error-$code.json',
        );
        final body = jsonDecode(file.readAsStringSync());
        expect(body, isA<Map<String, dynamic>>(), reason: 'error-$code.json');
        final error = (body as Map<String, dynamic>)['error'];
        expect(
          error,
          isA<Map<String, dynamic>>(),
          reason: 'error-$code.json lacks the envelope',
        );
        final envelope = error as Map<String, dynamic>;
        expect(
          envelope['code'],
          code,
          reason: 'error-$code.json carries the wrong code',
        );
        expect(envelope['message'], isA<String>());
        expect((envelope['message'] as String).isNotEmpty, isTrue);
      }
    });

    test('every 4xx/5xx response in the spec uses the error envelope', () {
      final paths = spec['paths'] as YamlMap;
      var checked = 0;
      for (final pathEntry in paths.entries) {
        final item = pathEntry.value as YamlMap;
        for (final opEntry in item.entries) {
          if (opEntry.value is! YamlMap) continue;
          final responses = (opEntry.value as YamlMap)['responses'];
          if (responses is! YamlMap) continue;
          for (final respEntry in responses.entries) {
            final status = int.tryParse(respEntry.key.toString());
            if (status == null || status < 400) continue;
            final response = deref(respEntry.value) as YamlMap;
            final json =
                ((response['content'] as YamlMap)['application/json']
                        as YamlMap)['schema']
                    as YamlMap;
            expect(
              json[r'$ref'],
              '#/components/schemas/ErrorEnvelope',
              reason:
                  '${pathEntry.key} ${opEntry.key} $status must use the '
                  'error envelope',
            );
            checked++;
          }
        }
      }
      expect(checked, greaterThan(40), reason: 'sanity: errors are everywhere');
    });
  });

  group('/stream concurrency cap', () {
    test('documents 503 busy for a third concurrent upgrade', () {
      final op =
          ((spec['paths'] as YamlMap)['/api/v1/stream'] as YamlMap)['get']
              as YamlMap;
      final description = op['description'] as String;
      expect(description, contains('max_open_sockets = 7'));
      expect(description.toLowerCase(), contains('2 concurrent websocket'));
      expect(description, contains('busy'));

      final resp503 = (op['responses'] as YamlMap)['503'] as YamlMap;
      expect(resp503['description'] as String, contains('busy'));
      final schema =
          ((resp503['content'] as YamlMap)['application/json']
                  as YamlMap)['schema']
              as YamlMap;
      expect(schema[r'$ref'], '#/components/schemas/ErrorEnvelope');
    });

    test('every §6.3 frame type is a component schema', () {
      final schemas = (spec['components'] as YamlMap)['schemas'] as YamlMap;
      for (final frame in [
        'WsHelloFrame',
        'WsSampleFrame',
        'WsAlarmFrame',
        'WsSessionFrame',
        'WsNetFrame',
        'WsPairingFrame',
        'WsPowerFrame',
        'WsOtaFrame',
        'WsSubscribeFrame',
        'WsPingFrame',
        'WsAckAlarmFrame',
      ]) {
        expect(
          schemas.containsKey(frame),
          isTrue,
          reason: 'missing WebSocket frame schema $frame',
        );
      }
    });
  });

  group('success fixtures', () {
    test('status.json parses with the §6.2 top-level keys', () {
      final body =
          jsonDecode(
                File(p.join(fixturesDir, 'status.json')).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final key in [
        'device',
        'time',
        'net',
        'ble',
        'pairing',
        'radio',
        'storage',
        'power',
        'session',
        'alarms',
      ]) {
        expect(
          body.containsKey(key),
          isTrue,
          reason: 'status.json missing top-level "$key"',
        );
      }
    });

    test('live-two-detached.json: probes 3+4 are null, never 0', () {
      final body =
          jsonDecode(
                File(
                  p.join(fixturesDir, 'live-two-detached.json'),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final probes = body['probes'] as List<dynamic>;
      expect(probes, hasLength(4));
      for (final i in [2, 3]) {
        final probe = probes[i] as Map<String, dynamic>;
        expect(probe['attached'], isFalse);
        expect(
          probe.containsKey('temp_f10'),
          isTrue,
          reason: 'detached temp_f10 is explicit null, not omitted',
        );
        expect(probe['temp_f10'], isNull);
      }
      final series =
          (body['recent'] as Map<String, dynamic>)['series'] as List<dynamic>;
      expect(series[2], isNull);
      expect(series[3], isNull);
    });

    test(
      'samples-bucketed-gaps.json: minmax buckets with a non-empty gaps array',
      () {
        final body =
            jsonDecode(
                  File(
                    p.join(fixturesDir, 'samples-bucketed-gaps.json'),
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(body['bucket_s'], 90);
        expect(body['agg'], 'minmax');
        final gaps = body['gaps'] as List<dynamic>;
        expect(gaps, isNotEmpty);
        final gap = gaps.first as Map<String, dynamic>;
        expect(gap['from'], isA<int>());
        expect(gap['to'], isA<int>());
        for (final series in body['series'] as List<dynamic>) {
          final entry = series as Map<String, dynamic>;
          for (final key in ['min', 'mean', 'max']) {
            expect(entry[key], hasLength(body['count'] as int));
          }
        }
      },
    );

    test('config/wifi accept fixtures: AP carries the PSK, STA never does', () {
      final ap =
          jsonDecode(
                File(
                  p.join(fixturesDir, 'config-wifi-accept-ap.json'),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final sta =
          jsonDecode(
                File(
                  p.join(fixturesDir, 'config-wifi-accept-sta.json'),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final body in [ap, sta]) {
        expect(body['accepted'], isTrue);
        expect(body['applying_in_ms'], isA<int>());
        expect(body['expect'], isA<Map<String, dynamic>>());
      }
      final apExpect = ap['expect'] as Map<String, dynamic>;
      expect(apExpect['mode'], 'ap');
      expect(apExpect['psk'], isA<String>());
      expect(apExpect['ssid'], isA<String>());
      expect(apExpect['ip'], isA<String>());
      final staExpect = sta['expect'] as Map<String, dynamic>;
      expect(staExpect['mode'], 'sta');
      expect(staExpect['host'], isA<String>());
      expect(
        staExpect.containsKey('psk'),
        isFalse,
        reason: 'a STA password must never be echoed',
      );
    });
  });
}
