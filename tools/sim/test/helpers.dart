import 'dart:convert';
import 'dart:io';

import 'package:sim/sim.dart';
import 'package:test/test.dart';

String repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/protocol/records.yaml').existsSync()) {
    if (dir.parent.path == dir.path) {
      throw StateError('repo root not found');
    }
    dir = dir.parent;
  }
  return dir.path;
}

Object? fixtureJson(String name) => jsonDecode(
  File('${repoRoot()}/protocol/fixtures/http/$name').readAsStringSync(),
);

Future<SimServer> startServer(SimState state) async {
  final server = SimServer(state);
  await server.start(port: 0, address: InternetAddress.loopbackIPv4);
  addTearDown(server.stop);
  return server;
}

final _client = HttpClient();

Future<(int, Object?)> getJson(SimServer s, String path) async {
  final req = await _client.get('127.0.0.1', s.port, path);
  final res = await req.close();
  final text = await utf8.decoder.bind(res).join();
  return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
}

Future<(int, List<int>)> getBytes(SimServer s, String path) async {
  final req = await _client.get('127.0.0.1', s.port, path);
  final res = await req.close();
  final bytes = <int>[];
  await for (final chunk in res) {
    bytes.addAll(chunk);
  }
  return (res.statusCode, bytes);
}

Future<(int, String)> getText(SimServer s, String path) async {
  final req = await _client.get('127.0.0.1', s.port, path);
  final res = await req.close();
  return (res.statusCode, await utf8.decoder.bind(res).join());
}

Future<(int, Object?)> postJson(SimServer s, String path, Object? body) async {
  final req = await _client.post('127.0.0.1', s.port, path);
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(body));
  final res = await req.close();
  final text = await utf8.decoder.bind(res).join();
  return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
}

/// "Byte-for-byte in shape": recursively identical key sets for maps; lists
/// are checked element-wise against the fixture's first element's shape.
/// Values may differ; null in either position is shape-compatible with any
/// scalar (the contract's nullable fields).
void expectSameShape(Object? actual, Object? fixture, [String path = '']) {
  if (fixture is Map) {
    expect(actual, isA<Map<String, Object?>>(), reason: 'at $path');
    final a = actual! as Map;
    expect(
      a.keys.toSet(),
      fixture.keys.toSet(),
      reason: 'key set mismatch at $path',
    );
    for (final k in fixture.keys) {
      expectSameShape(a[k], fixture[k], '$path.$k');
    }
  } else if (fixture is List) {
    expect(actual, isA<List<Object?>>(), reason: 'at $path');
    final a = actual! as List;
    if (fixture.isEmpty || a.isEmpty) {
      return;
    }
    final template = fixture.firstWhere((e) => e != null, orElse: () => null);
    if (template == null) {
      return;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] == null) {
        continue; // nullable entries (e.g. recent.series)
      }
      expectSameShape(a[i], template, '$path[$i]');
    }
  } else {
    // Scalars: nullable-compatible; otherwise same JSON type.
    if (actual == null || fixture == null) {
      return;
    }
    expect(
      actual.runtimeType == fixture.runtimeType ||
          (actual is num && fixture is num),
      isTrue,
      reason:
          'type mismatch at $path: '
          '${actual.runtimeType} vs ${fixture.runtimeType}',
    );
  }
}

/// A clock that starts at cook end (whole history "on flash").
NowMs pastEndClock(int endT) {
  var first = true;
  return () {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (first) {
      first = false;
      return now - (endT + 60) * 1000;
    }
    return now;
  };
}
