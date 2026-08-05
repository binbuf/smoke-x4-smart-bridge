/// A5 — `HttpTransport`: the third [BridgeTransport] implementation,
/// speaking the real device API over dio + the WebSocket stream (design
/// 08 §8.1, 06). The behavioural suite that defines "a transport" runs
/// against this and `MockTransport` from one harness — that is the claim
/// the whole architecture rests on.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/entities/entities.dart';
import '../dto/dto.dart' show SampleRec;
import 'bridge_transport.dart';
import 'wire_reader.dart';

/// F13.8 — `severity` is a device-derived property of the rule
/// (`protocol/records.yaml`'s `alarm_severity`), carried on the wire so a
/// client does not have to reimplement §9.2's table to colour an icon or
/// choose a notification channel.
///
/// Defaulting to WARNING for an absent or unknown value is the safe
/// direction: an older firmware's alarms stay visible and audible outside
/// quiet hours. Defaulting to critical would make every one of them
/// bypass quiet hours; defaulting to info would silence them.
AlarmSeverity severityFromWire(Object? v) => switch (v) {
  'critical' => AlarmSeverity.critical,
  'info' => AlarmSeverity.info,
  _ => AlarmSeverity.warning,
};

/// The device's error envelope, mapped by `code` so callers switch on
/// meaning — never on strings or status ints.
class BridgeApiException implements Exception {
  BridgeApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  bool get isBusy => code == 'busy';
  bool get isNotFound => code == 'not_found' || code == 'session_not_found';
  bool get isUnauthorized => code == 'unauthorized';

  @override
  String toString() => 'BridgeApiException($statusCode $code: $message)';
}

/// The WebSocket cap was hit (503 busy / 1013 close): live push is
/// unavailable but REST still works. Retrying is A7's job.
class BridgeStreamBusy implements Exception {
  const BridgeStreamBusy();
}

class HttpTransport implements BridgeTransport {
  HttpTransport(
    this.baseUrl, {
    Dio? dio,
    WebSocketChannel Function(Uri)? wsConnect,
  }) : _wsConnect = wsConnect ?? WebSocketChannel.connect {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
  }

  /// e.g. `http://192.168.4.1` or `http://smokebridge.local`.
  final String baseUrl;
  final WebSocketChannel Function(Uri) _wsConnect;
  late final Dio _dio;
  final _cancel = CancelToken();
  bool _closed = false;

  @override
  BridgeCapabilities get capabilities => const BridgeCapabilities(
    liveState: true,
    fullHistory: true,
    historyPreview: true,
    config: true,
    ota: true,
    mqtt: true,
  );

  // ── REST (A5.1) ─────────────────────────────────────────────────────

  Never _throwEnvelope(int status, Object? body) {
    if (body is Map && body['error'] is Map) {
      final err = body['error'] as Map;
      throw BridgeApiException(
        status,
        '${err['code'] ?? 'internal'}',
        '${err['message'] ?? ''}',
      );
    }
    throw BridgeApiException(status, 'internal', '$body');
  }

  Future<Object?> _getJson(String path) async {
    final res = await _dio.get<Object?>(
      path,
      cancelToken: _cancel,
      options: Options(
        validateStatus: (_) => true,
        responseType: ResponseType.json,
      ),
    );
    if ((res.statusCode ?? 0) != 200) {
      _throwEnvelope(res.statusCode ?? 0, res.data);
    }
    return res.data;
  }

  Future<Object?> _postJson(String path, Object? body) async {
    final res = await _dio.post<Object?>(
      path,
      data: body,
      cancelToken: _cancel,
      options: Options(
        validateStatus: (_) => true,
        responseType: ResponseType.json,
      ),
    );
    if ((res.statusCode ?? 0) != 200) {
      _throwEnvelope(res.statusCode ?? 0, res.data);
    }
    return res.data;
  }

  @override
  Future<BridgeStatus> status() async {
    final j = await _getJson('/api/v1/status') as Map;
    final device = (j['device'] as Map?) ?? {};
    final pairing = (j['pairing'] as Map?) ?? {};
    final session = (j['session'] as Map?) ?? {};
    final storage = (j['storage'] as Map?) ?? {};
    final power = (j['power'] as Map?) ?? {};
    final alarms = (j['alarms'] as List?) ?? [];
    return BridgeStatus(
      deviceId: '${pairing['device_id'] ?? device['id'] ?? ''}',
      model: '${device['model'] ?? ''}',
      fw: '${device['fw'] ?? ''}',
      uptimeS: (device['uptime_s'] as num?)?.toInt() ?? 0,
      paired: pairing['paired'] == true,
      numProbes: (pairing['num_probes'] as num?)?.toInt() ?? 0,
      lastPacketSAgo: (pairing['last_packet_s_ago'] as num?)?.toInt(),
      baseLost: pairing['base_lost'] == true,
      sessionActive: session['active'] == true,
      activeSessionId: session['active'] == true
          ? (session['id'] as num?)?.toInt()
          : null,
      storageFreePct: (storage['free_pct'] as num?)?.toInt() ?? 0,
      socPct: (power['soc_pct'] as num?)?.toInt(),
      charging: power['charging'] == true,
      alarms: [
        for (final a in alarms)
          if (a is Map)
            Alarm(
              id: (a['id'] as num?)?.toInt() ?? 0,
              rule: '${a['rule'] ?? ''}',
              probe: (a['probe'] as num?)?.toInt() ?? 0,
              sinceUnixMs: (a['since_unix_ms'] as num?)?.toInt(),
              acked: a['acked'] == true,
              severity: severityFromWire(a['severity']),
            ),
      ],
    );
  }

  /// A26 — `status.net` is the only signal this lane can honestly report.
  ///
  /// The phone's own Wi-Fi RSSI would be the *nearest* hop, and it is not
  /// available: reading it on Android needs the location permission the
  /// manifest promises never to take (A6.6). So this returns the bridge's
  /// uplink — and in AP mode, where the bridge has no uplink, the number of
  /// devices on its network instead. Neither is dressed up as the other.
  @override
  Future<LinkSignal> signal() async {
    final j = await _getJson('/api/v1/status') as Map;
    final net = (j['net'] as Map?) ?? {};
    final hosting = '${net['mode'] ?? ''}' == 'ap';
    final rssi = (net['rssi'] as num?)?.toInt();
    return LinkSignal(
      // 0 is the firmware's "not applicable" (AP mode has no upstream AP),
      // never a real reading — an antenna touching the router still reads
      // around −20.
      wifiDbm: (hosting || rssi == null || rssi == 0) ? null : rssi,
      ssid: '${net['ssid'] ?? ''}',
      apClients: hosting ? (net['ap_clients'] as num?)?.toInt() : null,
    );
  }

  @override
  Future<LiveState> live({Duration window = const Duration(hours: 1)}) async {
    final j = await _getJson('/api/v1/live?window=${window.inSeconds}') as Map;
    final probes = (j['probes'] as List?) ?? [];
    final temps = List<int?>.filled(4, null);
    // A9.1 needs names, roles and targets to decide which tile is large;
    // §6.2's /live already carries them, so one call answers both "what
    // is it reading" and "what is it called".
    final config = <Probe>[];
    for (final p in probes) {
      if (p is Map) {
        final n = (p['n'] as num?)?.toInt() ?? 0;
        if (n >= 1 && n <= 4) {
          // `attached: false` means detached — and a detached probe is
          // null, never 0, at every layer (04 §4.2).
          temps[n - 1] = p['attached'] == false
              ? null
              : (p['temp_f10'] as num?)?.toInt();
          config.add(
            Probe(
              n: n,
              name: '${p['name'] ?? ''}',
              role: switch (p['role']) {
                'pit' => ProbeRole.pit,
                'food' => ProbeRole.food,
                'ambient' => ProbeRole.ambient,
                _ => ProbeRole.unused,
              },
              targetF10: (p['target_f10'] as num?)?.toInt(),
              alarmEnabled: p['alarm_enabled'] == true,
              alarmMinF10: (p['min_f10'] as num?)?.toInt(),
              alarmMaxF10: (p['max_f10'] as num?)?.toInt(),
            ),
          );
        }
      }
    }
    config.sort((a, b) => a.n.compareTo(b.n));
    final recent = (j['recent'] as Map?) ?? {};
    final t0 = (recent['t0'] as num?)?.toInt() ?? 0;
    final stepS = (recent['step_s'] as num?)?.toInt() ?? 30;
    final series = (recent['series'] as List?) ?? [];
    final count = (recent['count'] as num?)?.toInt() ?? 0;
    final samples = <Sample>[
      for (var i = 0; i < count; i++)
        Sample(
          t: t0 + i * stepS,
          tempsF10: [
            for (var p = 0; p < 4; p++)
              p < series.length &&
                      series[p] is List &&
                      i < (series[p] as List).length
                  ? ((series[p] as List)[i] as num?)?.toInt()
                  : null,
          ],
        ),
    ];
    final billows = (j['billows'] as Map?) ?? {};
    return LiveState(
      t: (j['t'] as num?)?.toInt() ?? 0,
      unixMs: (j['unix_ms'] as num?)?.toInt(),
      tempsF10: temps,
      billows: billows['attached'] == true,
      recent: samples,
      probes: config,
    );
  }

  @override
  Future<List<CookSession>> sessions() async {
    final j = await _getJson('/api/v1/sessions') as Map;
    final list = (j['sessions'] as List?) ?? [];
    return [
      for (final s in list)
        if (s is Map)
          CookSession(
            id: (s['id'] as num?)?.toInt() ?? 0,
            name: '${s['name'] ?? ''}',
            startedUnixMs: (s['started_unix_ms'] as num?)?.toInt(),
            endedUnixMs: (s['ended_unix_ms'] as num?)?.toInt(),
            samplePeriodS: (s['sample_period_s'] as num?)?.toInt() ?? 30,
            sampleCount: (s['sample_count'] as num?)?.toInt() ?? 0,
            numProbes: (s['num_probes'] as num?)?.toInt() ?? 4,
            closed: s['closed'] == true,
            pinned: s['pinned'] == true,
          ),
    ];
  }

  @override
  Stream<List<Sample>> samples(
    int sessionId, {
    int fromT = 0,
    int? toT,
    int? bucketS,
  }) async* {
    // The sync path: format=bin, parsed through the same wire_reader the
    // fixtures verify, batches emitted as bytes arrive — never buffered
    // whole (the 54-day `long` scenario is why the discipline matters).
    final q = StringBuffer('format=bin&from=$fromT');
    if (toT != null) {
      q.write('&to=$toT');
    }
    if (bucketS != null && bucketS > 30) {
      q.write('&stride=${bucketS ~/ 30}');
    }
    final res = await _dio.get<ResponseBody>(
      '/api/v1/sessions/$sessionId/samples?$q',
      cancelToken: _cancel,
      options: Options(
        validateStatus: (_) => true,
        responseType: ResponseType.stream,
      ),
    );
    if ((res.statusCode ?? 0) != 200) {
      final bytes = await res.data!.stream.fold<BytesBuilder>(
        BytesBuilder(),
        (b, c) => b..add(c),
      );
      Object? body;
      try {
        body = jsonDecode(utf8.decode(bytes.takeBytes()));
      } on FormatException {
        body = null;
      }
      _throwEnvelope(res.statusCode ?? 0, body);
    }
    const batchSize = 500;
    final carry = BytesBuilder();
    var batch = <Sample>[];
    await for (final chunk in res.data!.stream) {
      carry.add(chunk);
      final bytes = carry.takeBytes();
      final whole = bytes.length - (bytes.length % SampleRec.size);
      if (whole > 0) {
        batch.addAll(samplesFromBin(Uint8List.sublistView(bytes, 0, whole)));
        carry.add(Uint8List.sublistView(bytes, whole));
      } else {
        carry.add(bytes);
      }
      while (batch.length >= batchSize) {
        yield batch.sublist(0, batchSize);
        batch = batch.sublist(batchSize);
      }
    }
    if (batch.isNotEmpty) {
      yield batch;
    }
  }

  @override
  Future<void> control(ControlCommand cmd) async {
    switch (cmd) {
      case StartSessionCommand():
        await _postJson('/api/v1/sessions', {});
      case StopSessionCommand():
        final s = await status();
        final id = s.activeSessionId;
        if (id != null) {
          await _postJson('/api/v1/sessions/$id/stop', null);
        }
      case MarkCommand(:final kind, :final probe, :final text):
        final s = await status();
        final id = s.activeSessionId;
        if (id != null) {
          await _postJson('/api/v1/sessions/$id/marks', {
            'kind': kind.index,
            'probe': probe,
            'text': text,
          });
        }
      case PairCommand():
        await _postJson('/api/v1/pairing/sync', null);
      case UnpairCommand():
        await _postJson('/api/v1/pairing/unpair', null);
      case SetTimeCommand(:final unixMs):
        await _postJson('/api/v1/time', {'unix_ms': unixMs});
      case AckAlarmCommand(:final alarmId):
        _ws?.sink.add(jsonEncode({'type': 'ack_alarm', 'id': alarmId}));
      // The three destructive verbs answer BEFORE they act (~500 ms), so a
      // 200 here means "scheduled", not "done". The socket dies immediately
      // after; a caller that never sees the 200 must treat it as unknown.
      case RebootCommand():
        await _postJson('/api/v1/restart', null);
      case FactoryResetCommand():
        await _postJson('/api/v1/factory-reset', null);
      case PowerOffCommand():
        await _postJson('/api/v1/power-off', null);
    }
  }

  @override
  Future<void> uploadFirmware(
    Stream<List<int>> image, {
    required int lengthBytes,
    bool force = false,
  }) async {
    // Streamed straight to the device — the app never materialises a
    // 1.3 MB image either, the same rule the firmware keeps on its side.
    // Progress is not returned here: it arrives on `events` as
    // BridgeOtaEvent, because the device is authoritative about its phase.
    final res = await _dio.post<Object?>(
      '/api/v1/ota',
      data: image,
      queryParameters: force ? const {'force': '1'} : const {},
      options: Options(
        validateStatus: (_) => true,
        responseType: ResponseType.json,
        contentType: 'application/octet-stream',
        headers: {Headers.contentLengthHeader: lengthBytes},
      ),
      cancelToken: _cancel,
    );
    if ((res.statusCode ?? 0) != 200) {
      // A 409 session_active surfaces as a BridgeApiException the screen
      // reads to show the refusal and offer the force path — deliberately,
      // never as an automatic retry.
      _throwEnvelope(res.statusCode ?? 0, res.data);
    }
  }

  @override
  Future<String> applyNetwork({
    required NetworkMode mode,
    String ssid = '',
    String psk = '',
  }) async {
    final body = <String, Object?>{'mode': mode.name};
    if (mode == NetworkMode.sta) {
      // Ignored for `ap` — the device generates that SSID/PSK itself.
      body['ssid'] = ssid;
      body['psk'] = psk;
    }
    final res = await _postJson('/api/v1/config/wifi', body);
    // Switching to AP returns generated credentials in `expect` because the
    // user needs to read them to join (06 §6.2); STA answers with a host and
    // no secret, so there is nothing to hand back.
    final expect = (res as Map?)?['expect'] as Map?;
    return (expect?['psk'] as String?) ?? '';
  }

  /// newapp §G.3 — `GET /api/v1/config/alarms`, the read-back half.
  @override
  Future<Map<String, Object?>> alarmConfig() async {
    final j = await _getJson('/api/v1/config/alarms');
    return j is Map ? j.cast<String, Object?>() : const {};
  }

  /// newapp §G.3 — `POST /api/v1/config/alarms`, a merge patch. Deliberately
  /// **not** fire-and-forget: the caller reads back with [alarmConfig] and
  /// compares before claiming anything was saved.
  @override
  Future<void> setAlarmConfig(Map<String, Object?> patch) =>
      _postJson('/api/v1/config/alarms', patch);

  @override
  Future<MqttConfig> mqttConfig() async {
    final j = await _getJson('/api/v1/config/mqtt') as Map;
    return MqttConfig(
      enabled: j['enabled'] == true,
      host: (j['host'] as String?) ?? '',
      port: (j['port'] as num?)?.toInt() ?? 1883,
      user: (j['user'] as String?) ?? '',
      prefix: (j['prefix'] as String?) ?? 'smokebridge',
      haDiscovery: j['ha_discovery'] == true,
      connected: j['connected'] == true,
    );
  }

  @override
  Future<void> setMqttConfig({
    bool? enabled,
    String? host,
    int? port,
    String? user,
    String? password,
    String? prefix,
    bool? haDiscovery,
  }) async {
    final body = <String, Object?>{};
    if (enabled != null) body['enabled'] = enabled;
    if (host != null) body['host'] = host;
    if (port != null) body['port'] = port;
    if (user != null) body['user'] = user;
    if (password != null) body['pass'] = password;
    if (prefix != null) body['prefix'] = prefix;
    if (haDiscovery != null) body['ha_discovery'] = haDiscovery;
    await _postJson('/api/v1/config/mqtt', body);
  }

  @override
  Future<void> configure(BridgeConfig cfg) async {
    final body = <String, Object?>{};
    if (cfg.displayUnits != null) {
      body['display_units'] = cfg.displayUnits;
    }
    if (cfg.batterySaver != null) {
      body['battery_saver'] = cfg.batterySaver!.name;
    }
    if (cfg.probes != null) {
      body['probes'] = [
        for (final p in cfg.probes!)
          {
            'n': p.n,
            'name': p.name,
            'role': p.role.name,
            'target_f10': p.targetF10,
            'alarm_enabled': p.alarmEnabled,
            if (p.alarmMinF10 != null) 'min_f10': p.alarmMinF10,
            if (p.alarmMaxF10 != null) 'max_f10': p.alarmMaxF10,
          },
      ];
    }
    await _postJson('/api/v1/config/device', body);
  }

  // ── WebSocket (A5.2) ────────────────────────────────────────────────

  WebSocketChannel? _ws;
  StreamController<BridgeEvent>? _events;

  @override
  Stream<BridgeEvent> get events {
    _events ??= StreamController<BridgeEvent>.broadcast(
      onListen: _openWs,
      onCancel: () {
        _ws?.sink.close();
        _ws = null;
      },
    );
    return _events!.stream;
  }

  void _openWs() {
    final wsUrl = baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final ws = _wsConnect(Uri.parse('$wsUrl/api/v1/stream'));
    _ws = ws;
    ws.stream.listen(
      (Object? data) {
        if (data is! String) {
          return;
        }
        final Object? frame;
        try {
          frame = jsonDecode(data);
        } on FormatException {
          return;
        }
        if (frame is! Map) {
          return;
        }
        final event = _mapFrame(frame);
        if (event != null) {
          _events?.add(event);
        }
      },
      onError: (Object e) {
        // A refused upgrade (the 2-client cap) surfaces as a typed
        // condition; REST keeps working. Retrying is A7's job (08 §8.4).
        _events?.addError(const BridgeStreamBusy());
      },
      onDone: () {
        if (!_closed) {
          _events?.addError(StateError('stream closed'));
        }
      },
    );
    ws.sink.add(
      jsonEncode({
        'type': 'subscribe',
        'topics': [
          'sample',
          'alarm',
          'session',
          'net',
          'power',
          'pairing',
          'ota',
        ],
      }),
    );
  }

  BridgeEvent? _mapFrame(Map<Object?, Object?> f) {
    switch (f['type']) {
      case 'sample':
        final temps = (f['temps_f10'] as List?) ?? [];
        final flags = (f['flags'] as Map?) ?? {};
        return BridgeEvent.sample(
          Sample(
            t: (f['t'] as num?)?.toInt() ?? 0,
            tempsF10: [
              for (var i = 0; i < 4; i++)
                i < temps.length ? (temps[i] as num?)?.toInt() : null,
            ],
            billows: flags['billows'] == true,
            rssi: (f['rssi'] as num?)?.toInt() ?? 0,
          ),
        );
      case 'alarm':
        return BridgeEvent.alarm(
          alarm: Alarm(
            id: (f['id'] as num?)?.toInt() ?? 0,
            rule: '${f['rule'] ?? ''}',
            probe: (f['probe'] as num?)?.toInt() ?? 0,
            valueF10: (f['value_f10'] as num?)?.toInt(),
            severity: severityFromWire(f['severity']),
          ),
          action: switch (f['action']) {
            'cleared' => AlarmAction.cleared,
            'acked' => AlarmAction.acked,
            _ => AlarmAction.raised,
          },
        );
      case 'session':
        return BridgeEvent.session(
          action: switch (f['action']) {
            'ended' => SessionAction.ended,
            'renamed' => SessionAction.renamed,
            _ => SessionAction.started,
          },
          sessionId: (f['id'] as num?)?.toInt() ?? 0,
          name: f['name'] as String?,
        );
      case 'net':
        return BridgeEvent.net(
          mode: '${f['mode'] ?? ''}',
          state: '${f['state'] ?? ''}',
          ip: f['ip'] as String?,
        );
      case 'power':
        return BridgeEvent.power(
          socPct: (f['soc_pct'] as num?)?.toInt() ?? 0,
          charging: f['charging'] == true,
          saver: f['saver'] == true,
        );
      case 'pairing':
        return BridgeEvent.pairing(
          paired: f['paired'] == true,
          deviceId: f['device_id'] as String?,
          numProbes: (f['num_probes'] as num?)?.toInt() ?? 0,
        );
      case 'ota':
        return BridgeEvent.ota(
          phase: '${f['phase'] ?? ''}',
          pct: (f['pct'] as num?)?.toInt() ?? 0,
        );
      case 'hello':
      case 'pong':
        return null; // transport-level, not surfaced
      default:
        return null; // unknown frame types are dropped: additive contract
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _cancel.cancel();
    await _ws?.sink.close();
    await _events?.close();
    _dio.close();
  }
}
