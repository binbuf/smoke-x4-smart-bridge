/// N15.2 — the real HTTP transport.
///
/// Implements `/api/v1` per `protocol/openapi.yaml`: JSON everywhere (even
/// errors), `Authorization: Bearer` when a token is set, streamed NDJSON/binary
/// sample reads and a WebSocket at `/api/v1/stream`.
///
/// **Deviation from the plan:** the task names Dio. This uses `dart:io`
/// instead, which keeps the whole transport layer pure Dart and in the
/// `dart test test/data` gate with no plugin, and needs no extra dependency
/// before a screen requires it. The wire behaviour is unchanged; a later task
/// may swap in Dio behind this same class if interceptors become useful.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/domain.dart';
import 'bridge_transport.dart';

class HttpTransport implements BridgeTransport {
  HttpTransport({
    required String baseUrl,
    this.token,
    HttpClient? client,
    this.timeout = const Duration(seconds: 8),
    this.sampleBatchSize = 64,
  }) : _client = client ?? HttpClient(),
       baseUri = _normalize(baseUrl) {
    _ownsClient = client == null;
    _client.connectionTimeout = timeout;
  }

  /// `http://host:port` with no trailing slash.
  final Uri baseUri;
  final String? token;
  final Duration timeout;
  final int sampleBatchSize;
  final HttpClient _client;
  late final bool _ownsClient;

  bool _closed = false;

  @override
  TransportKind get kind => TransportKind.http;

  @override
  TransportCapabilities get capabilities => TransportCapabilities.http;

  @override
  String get label => baseUri.host;

  /// The `ws://` or `wss://` URL for `/api/v1/stream`.
  Uri get streamUri => baseUri.replace(
    scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
    path: '/api/v1/stream',
  );

  Uri _uri(String path, [Map<String, String>? query]) => baseUri.replace(
    path: '/api/v1$path',
    queryParameters: query == null || query.isEmpty ? null : query,
  );

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_ownsClient) {
      _client.close(force: true);
    }
  }

  // ── request plumbing ─────────────────────────────────────────────────

  Future<Map<String, Object?>> _requestJson(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final res = await _send(method, path, body: body, query: query);
    final text = await utf8.decoder.bind(res).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _errorFrom(res.statusCode, text);
    }
    if (text.isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const TransportException(
        'malformed',
        'expected a JSON object response',
      );
    }
    return decoded.cast<String, Object?>();
  }

  Future<HttpClientResponse> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    if (_closed) {
      throw const TransportException('network', 'transport is closed');
    }
    try {
      final req = await _client
          .openUrl(method, _uri(path, query))
          .timeout(timeout);
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      return await req.close().timeout(timeout);
    } on TimeoutException {
      throw const TransportException('timeout', 'the bridge did not answer');
    } on SocketException catch (e) {
      throw TransportException(
        'network',
        e.message,
        detail: e.osError?.message,
      );
    } on HttpException catch (e) {
      throw TransportException('network', e.message);
    }
  }

  TransportException _errorFrom(int status, String text) {
    try {
      final body = jsonDecode(text);
      if (body is Map && body['error'] is Map) {
        final e = (body['error'] as Map).cast<String, Object?>();
        return TransportException(
          e['code'] as String? ?? 'http_$status',
          e['message'] as String? ?? 'request failed',
          detail: e['detail'],
          status: status,
        );
      }
    } on FormatException {
      // fall through to the status-only error
    }
    return TransportException(
      'http_$status',
      'request failed with status $status',
      status: status,
    );
  }

  // ── reads ────────────────────────────────────────────────────────────

  @override
  Future<BridgeStatus> status() async =>
      BridgeStatus.fromJson(await _requestJson('GET', '/status'));

  @override
  Future<LiveStatus> live({int windowS = 3600}) async => LiveStatus.fromJson(
    await _requestJson(
      'GET',
      '/live',
      query: {'window': '${windowS.clamp(1, 7200)}'},
    ),
  );

  @override
  Future<List<SessionInfo>> sessions() async {
    final body = await _requestJson('GET', '/sessions');
    final raw = body['sessions'];
    return [
      for (final s in raw is List ? raw : const [])
        SessionInfo.fromJson((s as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<SessionInfo> session(int sessionId) async =>
      SessionInfo.fromJson(await _requestJson('GET', '/sessions/$sessionId'));

  @override
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int? toT,
    int stride = 1,
  }) async* {
    final req = await _client
        .openUrl(
          'GET',
          _uri('/sessions/$sessionId/samples', {
            'from': '$fromT',
            if (toT != null) 'to': '$toT',
            'stride': '${stride.clamp(1, 1 << 20)}',
            'format': 'ndjson',
            'probes': '1,2,3,4',
          }),
        )
        .timeout(timeout);
    if (token != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final res = await req.close().timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final text = await utf8.decoder.bind(res).join();
      throw _errorFrom(res.statusCode, text);
    }
    var batch = <Sample>[];
    await for (final line
        in res
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(timeout)) {
      if (line.trim().isEmpty) {
        continue;
      }
      batch.add(_sampleFromNdjson(line));
      if (batch.length >= sampleBatchSize) {
        yield batch;
        batch = <Sample>[];
      }
    }
    if (batch.isNotEmpty) {
      yield batch;
    }
  }

  @override
  Future<List<Mark>> marks(int sessionId) async {
    final body = await _requestJson('GET', '/sessions/$sessionId/marks');
    final raw = body['marks'];
    return [
      for (final m in raw is List ? raw : const [])
        _markFromJson((m as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<Mark> postMark(
    int sessionId, {
    int? t,
    required MarkKind kind,
    int probe = 0,
    String text = '',
  }) async {
    final body = await _requestJson(
      'POST',
      '/sessions/$sessionId/marks',
      body: {
        't': ?t,
        'kind': _markKindToWire(kind),
        'probe': probe,
        'text': text,
      },
    );
    return _markFromJson(body);
  }

  // ── config ───────────────────────────────────────────────────────────

  @override
  Future<Map<String, Object?>> wifiConfig() async =>
      _requestJson('GET', '/config/wifi');

  @override
  Future<Map<String, Object?>> applyNetwork({
    required String mode,
    String? ssid,
    String? psk,
    String? user,
  }) => _requestJson(
    'POST',
    '/config/wifi',
    body: {'mode': mode, 'ssid': ?ssid, 'psk': ?psk, 'user': ?user},
  );

  @override
  Future<Map<String, Object?>> commitNetwork() async =>
      _requestJson('POST', '/config/wifi/commit');

  @override
  Future<Map<String, Object?>> deviceConfig() async =>
      _requestJson('GET', '/config/device');

  @override
  Future<void> setDeviceConfig(Map<String, Object?> patch) async {
    await _requestJson('POST', '/config/device', body: patch);
  }

  @override
  Future<Map<String, Object?>> alarmConfig() async =>
      _requestJson('GET', '/config/alarms');

  @override
  Future<void> setAlarmConfig(Map<String, Object?> patch) async {
    await _requestJson('POST', '/config/alarms', body: patch);
  }

  @override
  Future<void> setTime(int unixMs, {int? tzOffsetMin}) async {
    await _requestJson(
      'POST',
      '/time',
      body: {'unix_ms': unixMs, 'tz_offset_min': ?tzOffsetMin},
    );
  }

  @override
  Future<CookClockStatus> cookClock() async =>
      CookClockStatus.fromJson(await _requestJson('GET', '/cook-clock'));

  @override
  Future<CookClockStatus> setCookClock({
    int? elapsedS,
    int? startedUnixMs,
  }) async {
    assert(
      (elapsedS == null) != (startedUnixMs == null),
      'send exactly one of elapsedS / startedUnixMs',
    );
    return CookClockStatus.fromJson(
      await _requestJson(
        'POST',
        '/cook-clock',
        body: {'elapsed_s': ?elapsedS, 'started_unix_ms': ?startedUnixMs},
      ),
    );
  }

  @override
  Future<CookClockStatus> clearCookClock() async =>
      CookClockStatus.fromJson(await _requestJson('DELETE', '/cook-clock'));

  // ── verbs ────────────────────────────────────────────────────────────

  @override
  Future<void> pairSync() async => _requestJson('POST', '/pairing/sync');

  @override
  Future<void> unpair() async => _requestJson('POST', '/pairing/unpair');

  @override
  Future<void> restart() async => _requestJson('POST', '/restart');

  @override
  Future<void> factoryReset() async => _requestJson('POST', '/factory-reset');

  @override
  Future<void> powerOff() async => _requestJson('POST', '/power-off');

  @override
  Future<void> stopSession(int sessionId) async =>
      _requestJson('POST', '/sessions/$sessionId/stop');

  @override
  Future<void> deleteSession(int sessionId) async =>
      _requestJson('DELETE', '/sessions/$sessionId');

  @override
  Future<Map<String, Object?>> uploadOta(
    Stream<List<int>> image, {
    bool force = false,
  }) async {
    if (_closed) {
      throw const TransportException('network', 'transport is closed');
    }
    final uri = _uri('/ota', force ? {'force': '1'} : null);
    final req = await _client.openUrl('POST', uri).timeout(timeout);
    if (token != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    req.headers.contentType = ContentType.binary;
    // Streamed upload: the image never has to fit in memory twice.
    await for (final chunk in image) {
      req.add(chunk);
    }
    final res = await req.close().timeout(timeout);
    final text = await utf8.decoder.bind(res).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _errorFrom(res.statusCode, text);
    }
    if (text.isEmpty) {
      return const {};
    }
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }

  // ── stream ───────────────────────────────────────────────────────────

  @override
  Stream<TransportEvent> events() async* {
    try {
      final socket = await WebSocket.connect(
        streamUri.toString(),
        headers: token == null
            ? null
            : {HttpHeaders.authorizationHeader: 'Bearer $token'},
      ).timeout(timeout);
      await for (final frame in socket.timeout(const Duration(minutes: 5))) {
        if (frame is! String) {
          continue;
        }
        try {
          yield TransportEvent.fromJson(jsonDecode(frame));
        } on FormatException {
          continue; // a malformed frame is skipped, not fatal
        }
      }
    } on TimeoutException {
      throw const TransportException('timeout', 'the stream did not answer');
    } on SocketException catch (e) {
      throw TransportException('network', e.message);
    } on WebSocketException catch (e) {
      throw TransportException('network', e.message);
    }
  }

  // ── parse helpers ────────────────────────────────────────────────────

  Sample _sampleFromNdjson(String line) {
    final j = (jsonDecode(line) as Map).cast<String, Object?>();
    final raw = j['temps_f10'];
    final temps = <int?>[null, null, null, null];
    if (raw is List) {
      for (var i = 0; i < 4 && i < raw.length; i++) {
        final v = raw[i];
        temps[i] = v is num ? v.toInt() : null;
      }
    }
    return Sample(
      t: (j['t'] as num?)?.toInt() ?? 0,
      tempsF10: temps,
      unixMs: (j['unix_ms'] as num?)?.toInt(),
      billows: j['billows'] == true,
      rssi: (j['rssi'] as num?)?.toInt() ?? 0,
    );
  }

  Mark _markFromJson(Map<String, Object?> j) => Mark(
    t: (j['t'] as num?)?.toInt() ?? 0,
    kind: _markKindFromWire((j['kind'] as num?)?.toInt() ?? 0),
    probe: (j['probe'] as num?)?.toInt() ?? 0,
    text: j['text'] as String? ?? '',
  );

  static Uri _normalize(String baseUrl) {
    var text = baseUrl.trim();
    if (!text.contains('://')) {
      text = 'http://$text';
    }
    final uri = Uri.parse(text);
    return uri.replace(
      path: uri.path.endsWith('/')
          ? uri.path.substring(0, uri.path.length - 1)
          : uri.path,
    );
  }
}

/// `mark_rec.kind` wire values (records.yaml). App-only kinds ([MarkKind.spritz]
/// and [MarkKind.turn]) are written as `note` — the device has no slot for them
/// yet, and inventing one would desynchronise the generated record tables.
int _markKindToWire(MarkKind kind) => switch (kind) {
  MarkKind.note => 0,
  MarkKind.wrapped => 1,
  MarkKind.lidOpen => 2,
  MarkKind.fuel => 3,
  MarkKind.probeMoved => 4,
  MarkKind.alarm => 5,
  MarkKind.phaseChange => 6,
  MarkKind.autoDetected => 7,
  MarkKind.spritz => 0,
  MarkKind.turn => 0,
};

MarkKind _markKindFromWire(int value) {
  const kinds = [
    MarkKind.note,
    MarkKind.wrapped,
    MarkKind.lidOpen,
    MarkKind.fuel,
    MarkKind.probeMoved,
    MarkKind.alarm,
    MarkKind.phaseChange,
    MarkKind.autoDetected,
  ];
  if (value < 0 || value >= kinds.length) {
    return MarkKind.note;
  }
  return kinds[value];
}
