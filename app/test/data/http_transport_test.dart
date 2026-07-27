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
// `dto.dart` re-exports the generated `AlarmSeverity` (records.yaml's
// alarm_severity, added in M5 so C and Dart share the three names). The
// DOMAIN type of the same name is the one the app uses; hiding the wire
// one here is the narrower fix, and it is where the two would otherwise
// collide.
import 'package:smoke_bridge/data/dto/dto.dart' hide AlarmSeverity;
import 'package:smoke_bridge/data/transport/bridge_transport.dart';
import 'package:smoke_bridge/data/transport/http_transport.dart';
import 'package:smoke_bridge/data/transport/mock_transport.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'records_parity_test.dart' show repoRoot;
import 'transport_contract.dart';

/// Serves canned responses keyed by path prefix; records requests.
class FakeAdapter implements HttpClientAdapter {
  final Map<String, (int, Object)> routes = {};
  final List<String> requests = [];

  /// A12.6 — the bytes the last request streamed, drained so a test can
  /// assert the whole image reached the wire.
  int lastRequestBodyLength = 0;

  /// The last non-streamed request body, so a test can assert *what* was
  /// sent and not merely which route was hit.
  Object? lastRequestBody;

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
    lastRequestBody = options.data;
    if (requestStream != null) {
      lastRequestBodyLength = 0;
      await for (final chunk in requestStream) {
        lastRequestBodyLength += chunk.length;
      }
    }
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

  test('F13.8 — alarm severity comes off the wire, not from a guess', () async {
    // The app used to default every alarm to `warning`, which quietly
    // meant a target_reached at 03:40 could be silenced by quiet hours.
    // The device derives severity from the rule (09 §9.2) and now says
    // so; an ABSENT or unknown value stays warning, which keeps an older
    // firmware's alarms visible and audible outside quiet hours.
    final a = FakeAdapter()
      ..routes['/api/v1/status'] = (
        200,
        '{"device":{"id":"A4F2"},"alarms":['
            '{"id":1,"rule":"target_reached","severity":"critical",'
            '"probe":2,"since_unix_ms":null,"acked":false},'
            '{"id":2,"rule":"base_lost","severity":"warning","probe":0,'
            '"since_unix_ms":null,"acked":false},'
            '{"id":3,"rule":"storage_low","probe":0,'
            '"since_unix_ms":null,"acked":true}]}',
      );
    final t = transportWith(a);
    final s = await t.status();
    expect(s.alarms.map((x) => x.severity), [
      AlarmSeverity.critical,
      AlarmSeverity.warning,
      AlarmSeverity.warning,
    ]);
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

  group('A12.6 — firmware upload', () {
    Stream<List<int>> image(int n) =>
        Stream.fromIterable([List<int>.filled(n, 0xAB)]);

    test('streams the whole image to POST /ota and completes', () async {
      final a = FakeAdapter();
      a.routes['/api/v1/ota'] = (
        200,
        '{"accepted":true,"image_size_b":2048,"slot":"ota_1",'
            '"version":"1.0.1","project":"smoke_bridge","rebooting_in_ms":500}',
      );
      final t = transportWith(a);
      await t.uploadFirmware(image(2048), lengthBytes: 2048);
      expect(a.requests.single, 'POST /api/v1/ota');
      // Nothing is materialised: the whole image reached the wire.
      expect(a.lastRequestBodyLength, 2048);
      await t.close();
    });

    test('a 409 surfaces as a typed refusal, not a retry', () async {
      final a = FakeAdapter();
      a.routes['/api/v1/ota'] = (
        409,
        '{"error":{"code":"session_active","message":"a cook is running"}}',
      );
      final t = transportWith(a);
      // The refusal is thrown for the screen to render; the transport
      // NEVER retries with force on its own.
      await expectLater(
        t.uploadFirmware(image(64), lengthBytes: 64),
        throwsA(
          isA<BridgeApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.code, 'code', 'session_active'),
        ),
      );
      expect(a.requests, ['POST /api/v1/ota']); // exactly one attempt
      await t.close();
    });

    test('force carries ?force=1', () async {
      final a = FakeAdapter();
      a.routes['/api/v1/ota'] = (200, '{"accepted":true}');
      final t = transportWith(a);
      await t.uploadFirmware(image(16), lengthBytes: 16, force: true);
      expect(a.requests.single, 'POST /api/v1/ota?force=1');
      await t.close();
    });

    test('the mock refuses OTA rather than pretending', () async {
      // capabilities.ota is false, so the button is absent; a caller that
      // ignores the flag gets an honest throw, not a silent drop.
      final mock = MockTransport.fromSmkBytes(
        File(
          '${repoRoot()}/protocol/fixtures/brisket-18h.smk',
        ).readAsBytesSync(),
      );
      expect(mock.capabilities.ota, isFalse);
      expect(
        () => mock.uploadFirmware(image(4), lengthBytes: 4),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  // D15 — the button can only cycle views and sleep, so every one of these
  // now has to reach the bridge over the wire or it cannot happen at all.
  group('D15 — the controls that left the button', () {
    const deferred = '{"accepted":true,"acting_in_ms":500}';

    test('reboot, factory reset and power off hit their own routes', () async {
      final a = FakeAdapter();
      a.routes['/api/v1/restart'] = (200, deferred);
      a.routes['/api/v1/factory-reset'] = (200, deferred);
      a.routes['/api/v1/power-off'] = (
        200,
        '{"accepted":true,"acting_in_ms":500,"wake_requires_button":true}',
      );
      final t = transportWith(a);

      await t.control(const ControlCommand.reboot());
      await t.control(const ControlCommand.factoryReset());
      await t.control(const ControlCommand.powerOff());

      expect(a.requests, [
        'POST /api/v1/restart',
        'POST /api/v1/factory-reset',
        'POST /api/v1/power-off',
      ]);
      await t.close();
    });

    test('a refused verb surfaces as a typed error, not silence', () async {
      final a = FakeAdapter();
      a.routes['/api/v1/power-off'] = (
        501,
        '{"error":{"code":"unsupported","message":"no power control"}}',
      );
      final t = transportWith(a);
      await expectLater(
        t.control(const ControlCommand.powerOff()),
        throwsA(isA<BridgeApiException>()),
      );
      await t.close();
    });

    test('battery saver travels as the tri-state, not a bool', () async {
      final a = FakeAdapter();
      a.routes['/api/v1/config/device'] = (200, '{}');
      final t = transportWith(a);

      await t.configure(
        const BridgeConfig(batterySaver: BatterySaverMode.auto),
      );
      expect(a.requests.last, 'POST /api/v1/config/device');
      expect((a.lastRequestBody! as Map)['battery_saver'], 'auto');

      await t.configure(const BridgeConfig(batterySaver: BatterySaverMode.off));
      expect((a.lastRequestBody! as Map)['battery_saver'], 'off');
      await t.close();
    });

    test(
      'switching to AP returns the generated key to show the user',
      () async {
        final a = FakeAdapter();
        a.routes['/api/v1/config/wifi'] = (
          200,
          '{"accepted":true,"applying_in_ms":500,"expect":'
              '{"mode":"ap","ssid":"SmokeBridge-A4F2","psk":"Gk7mR2xQpT",'
              '"ip":"192.168.4.1"}}',
        );
        final t = transportWith(a);
        final psk = await t.applyNetwork(mode: NetworkMode.ap);
        expect(a.requests.single, 'POST /api/v1/config/wifi');
        expect((a.lastRequestBody! as Map)['mode'], 'ap');
        // The phone has to leave its own network to rejoin, so it needs this.
        expect(psk, 'Gk7mR2xQpT');
        await t.close();
      },
    );

    test(
      'joining a network sends the credentials and keeps no secret',
      () async {
        final a = FakeAdapter();
        a.routes['/api/v1/config/wifi'] = (
          200,
          '{"accepted":true,"applying_in_ms":500,'
              '"expect":{"mode":"sta","host":"smokebridge.local"}}',
        );
        final t = transportWith(a);
        final psk = await t.applyNetwork(
          mode: NetworkMode.sta,
          ssid: 'Backyard',
          psk: 'hunter2',
        );
        final body = a.lastRequestBody! as Map;
        expect(body['mode'], 'sta');
        expect(body['ssid'], 'Backyard');
        expect(body['psk'], 'hunter2');
        // STA answers with a host, not a key — nothing to hand back.
        expect(psk, '');
        await t.close();
      },
    );
  });
}
