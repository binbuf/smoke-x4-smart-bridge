/// A5: HttpTransport against the committed protocol fixtures — the REST
/// mappings byte-for-byte from protocol/fixtures/http, bin streaming
/// through the same wire_reader the sync engine uses, the WebSocket frame
/// mapping to BridgeEvent, and the busy path (the 2-client cap) surfacing
/// as a typed condition rather than a crash.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/dto/dto.dart';
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/data/transport/http_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'records_parity_test.dart' show repoRoot;
import 'transport_contract.dart';

/// Serves canned responses keyed by path prefix; records requests.
class FakeAdapter implements HttpClientAdapter {
  final Map<String, (int, Object)> routes = {};
  final List<String> requests = [];

  void json(String prefix, String fixtureName, {int status = 200}) {
    final body = File(
      '${repoRoot()}/protocol/fixtures/http/$fixtureName',
    ).readAsStringSync();
    routes[prefix] = (status, body);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final pathQ =
        options.uri.path +
        (options.uri.query.isEmpty ? '' : '?${options.uri.query}');
    requests.add('${options.method} $pathQ');
    for (final e in routes.entries) {
      if (pathQ.startsWith(e.key)) {
        final (status, body) = e.value;
        if (body is Uint8List) {
          return ResponseBody.fromBytes(
            body,
            status,
            headers: {
              Headers.contentTypeHeader: ['application/octet-stream'],
            },
          );
        }
        return ResponseBody.fromString(
          body as String,
          status,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
    }
    return ResponseBody.fromString(
      '{"error":{"code":"not_found","message":"no route"}}',
      404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class FakeWs implements WebSocketChannel {
  FakeWs() {
    _sinkController.stream.listen(sent.add);
  }

  final incoming = StreamController<Object?>.broadcast();
  final sent = <Object?>[];
  final _sinkController = StreamController<Object?>();

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _FakeSink(_sinkController, this);

  void push(Map<String, Object?> frame) => incoming.add(jsonEncode(frame));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._c, this._ws);
  final StreamController<Object?> _c;
  final FakeWs _ws;

  @override
  void add(Object? data) => _c.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await _ws.incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HttpTransport transportWith(FakeAdapter adapter, {FakeWs? ws}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://192.168.4.1'));
  dio.httpClientAdapter = adapter;
  return HttpTransport(
    'http://192.168.4.1',
    dio: dio,
    wsConnect: (_) => ws ?? FakeWs(),
  );
}

void main() {
  // A6.2: the shared behavioural contract, over the committed fixtures.
  runTransportContract(
    name: 'http',
    create: () async => transportWith(
      FakeAdapter()
        ..json('/api/v1/status', 'status.json')
        ..json('/api/v1/live', 'live-two-detached.json')
        // No committed fixture for an EMPTY session list, and the
        // contract only needs the shape here — the populated case is
        // covered by the fixture-backed tests below.
        ..routes['/api/v1/sessions'] = (200, '{"sessions":[]}'),
    ),
  );

  test('status maps the nested fixture to the flat BridgeStatus', () async {
    final a = FakeAdapter()..json('/api/v1/status', 'status.json');
    final t = transportWith(a);
    final s = await t.status();
    // Values pinned to protocol/fixtures/http/status.json.
    expect(s.deviceId, isNotEmpty);
    expect(s.paired, isTrue);
    expect(s.numProbes, 4);
    expect(s.sessionActive, isTrue);
    expect(s.activeSessionId, isNotNull);
    expect(s.storageFreePct, greaterThan(0));
    await t.close();
  });

  test('live: a detached probe is null, never 0', () async {
    final a = FakeAdapter()..json('/api/v1/live', 'live-two-detached.json');
    final t = transportWith(a);
    final live = await t.live();
    expect(live.tempsF10.where((v) => v == null).length, 2);
    expect(live.tempsF10.where((v) => v == 0), isEmpty);
    expect(live.recent, isNotEmpty);
    await t.close();
  });

  test('samples streams bin batches through wire_reader', () async {
    // Serve the brisket fixture body (the records after the header) as
    // the format=bin response — exactly what the device emits.
    final smk = File(
      '${repoRoot()}/protocol/fixtures/brisket-18h.smk',
    ).readAsBytesSync();
    final body = Uint8List.sublistView(smk, SessionHeader.size);
    final a = FakeAdapter();
    a.routes['/api/v1/sessions/27/samples'] = (200, body);
    final t = transportWith(a);

    final batches = await t.samples(27).toList();
    final total = batches.fold<int>(0, (n, b) => n + b.length);
    expect(total, body.length ~/ SampleRec.size);
    expect(batches.length, greaterThan(1)); // streamed, not one blob
    expect(a.requests.single, contains('format=bin'));
    await t.close();
  });

  test('an error envelope becomes a typed BridgeApiException', () async {
    final a = FakeAdapter()
      ..json(
        '/api/v1/sessions/99/samples',
        'error-session_not_found.json',
        status: 404,
      );
    final t = transportWith(a);
    await expectLater(
      t.samples(99).toList(),
      throwsA(
        isA<BridgeApiException>().having(
          (e) => e.isNotFound,
          'notFound',
          isTrue,
        ),
      ),
    );
    await t.close();
  });

  test('WebSocket frames map to BridgeEvents; unknown types drop', () async {
    final a = FakeAdapter();
    final ws = FakeWs();
    final t = transportWith(a, ws: ws);

    final got = <BridgeEvent>[];
    final sub = t.events.listen(got.add);
    await Future<void>.delayed(Duration.zero);

    ws.push({'type': 'hello', 'fw': '1.0'}); // transport-level: dropped
    ws.push({
      'type': 'sample',
      't': 120,
      'temps_f10': [2250, null, 950, 803],
      'rssi': -40,
      'flags': {'billows': false},
    });
    ws.push({'type': 'alarm', 'id': 3, 'rule': 'target', 'action': 'raised'});
    ws.push({'type': 'pairing', 'paired': true, 'num_probes': 4});
    ws.push({'type': 'mystery_future_frame', 'x': 1}); // dropped
    await Future<void>.delayed(Duration.zero);

    expect(got, hasLength(3));
    final sample = got[0] as BridgeSampleEvent;
    expect(sample.sample.tempsF10, [2250, null, 950, 803]);
    expect((got[1] as BridgeAlarmEvent).action, AlarmAction.raised);
    expect((got[2] as BridgePairingEvent).numProbes, 4);
    await sub.cancel();
    await t.close();
  });

  test('a refused stream surfaces BridgeStreamBusy, REST unaffected', () async {
    final a = FakeAdapter()..json('/api/v1/status', 'status.json');
    final ws = FakeWs();
    final t = transportWith(a, ws: ws);

    final errors = <Object>[];
    final sub = t.events.listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    ws.incoming.addError(WebSocketChannelException('503'));
    await Future<void>.delayed(Duration.zero);

    expect(errors.single, isA<BridgeStreamBusy>());
    // REST still works while live push is unavailable.
    expect((await t.status()).paired, isTrue);
    await sub.cancel();
    await t.close();
  });
}
