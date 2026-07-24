/// The fake bridge's HTTP + WebSocket server (T3.1–T3.4), implementing the
/// protocol/openapi.yaml contract: every response JSON (even errors), hard
/// caps stated and enforced, streamed history, deferred Wi-Fi reconfigure.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bridge_protocol/bridge_protocol.dart';

import 'payloads.dart';
import 'state.dart';

class SimServer {
  SimServer(this.state, {this.maxOpenSockets = 7, this.maxWsClients = 2});

  final SimState state;
  final int maxOpenSockets;
  final int maxWsClients;

  HttpServer? _server;
  final List<WebSocket> _wsClients = [];
  final Set<Timer> _timers = {};
  int _openRequests = 0;

  int get port => _server!.port;
  int get wsClientCount => _wsClients.length;

  Future<void> start({int port = 8080, InternetAddress? address}) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    _server = server;
    server.listen(_dispatch, onError: (Object _) {});
    _startReplayPush();
  }

  Future<void> stop() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    for (final ws in List.of(_wsClients)) {
      await ws.close();
    }
    await _server?.close(force: true);
  }

  // ── plumbing ──────────────────────────────────────────────────────

  Future<void> _dispatch(HttpRequest req) async {
    _openRequests++;
    try {
      if (_openRequests > maxOpenSockets) {
        return _json(
          req,
          503,
          errorBody('busy', 'max_open_sockets ($maxOpenSockets) reached'),
        );
      }
      if (state.otaInProgress && req.uri.path != '/api/v1/status') {
        return _json(
          req,
          503,
          errorBody('ota_in_progress', 'firmware update running'),
        );
      }
      await _route(req);
    } on FormatException catch (e) {
      _json(req, 400, errorBody('invalid_body', e.message));
    } catch (e) {
      _json(req, 500, errorBody('internal', '$e'));
    } finally {
      _openRequests--;
    }
  }

  void _json(HttpRequest req, int status, Object? body) {
    final res = req.response;
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.write(const JsonEncoder.withIndent('  ').convert(body));
    res.close();
  }

  Future<Map<String, Object?>> _body(HttpRequest req) async {
    final text = await utf8.decoder.bind(req).join();
    if (text.isEmpty) {
      return {};
    }
    final parsed = jsonDecode(text);
    if (parsed is! Map<String, Object?>) {
      throw const FormatException('body must be a JSON object');
    }
    return parsed;
  }

  // ── routing ───────────────────────────────────────────────────────

  Future<void> _route(HttpRequest req) async {
    final path = req.uri.path;
    final method = req.method;

    // Captive-portal shims (05 §5.8.1).
    switch (path) {
      case '/generate_204' || '/gen_204':
        req.response.statusCode = 204;
        return req.response.close();
      case '/hotspot-detect.html' || '/library/test/success.html':
        req.response.headers.contentType = ContentType.html;
        req.response.write(
          '<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>',
        );
        return req.response.close();
      case '/ncsi.txt':
        req.response.write('Microsoft NCSI');
        return req.response.close();
      case '/connecttest.txt':
        req.response.write('Microsoft Connect Test');
        return req.response.close();
    }

    if (!path.startsWith('/api/v1')) {
      // D13: no device web UI in MVP — a small built-in page points at the app.
      req.response.headers.contentType = ContentType.html;
      req.response.write(
        '<html><body><h1>Smoke Bridge (sim)</h1><p>Use the Smoke Bridge '
        'app, or GET /api/v1/status.</p></body></html>',
      );
      return req.response.close();
    }

    final api = path.substring('/api/v1'.length);
    final vT = state.virtualT();

    switch ((method, api)) {
      case ('GET', '/status'):
        return _json(req, 200, statusJson(state));

      case ('GET', '/live'):
        final window =
            int.tryParse(req.uri.queryParameters['window'] ?? '') ?? 3600;
        return _json(req, 200, liveJson(state, window.clamp(1, 7200)));

      case ('GET', '/stream'):
        return _upgradeWs(req);

      case ('GET', '/sessions'):
        return _json(req, 200, {
          'sessions': [sessionJson(state)],
        });

      case ('POST', '/sessions'):
        if (!state.sessionEnded(vT)) {
          return _json(
            req,
            409,
            errorBody('session_active', 'a session is already running'),
          );
        }
        return _json(req, 200, sessionJson(state));

      case ('GET', '/pairing'):
        return _json(req, 200, {
          'paired': state.paired,
          'sync_active': state.syncActive,
          'device_id': state.paired ? state.header.deviceId : null,
          'model': state.paired ? 'X4' : null,
          'num_probes': state.paired ? state.header.numProbes : 0,
          'frequency_hz': state.paired ? 910500000 : null,
        });

      case ('POST', '/pairing/sync'):
        state.syncActive = true;
        _after(const Duration(seconds: 2), () {
          state
            ..paired = true
            ..syncActive = false;
          _push({
            'type': 'pairing',
            'paired': true,
            'device_id': state.header.deviceId,
            'num_probes': state.header.numProbes,
          });
        });
        return _json(req, 200, {'ok': true, 'sync_active': true});

      case ('POST', '/pairing/unpair'):
        state.paired = false;
        _push({'type': 'pairing', 'paired': false});
        return _json(req, 200, {'ok': true});

      case ('GET', '/config/wifi'):
        // Never a stored STA password; the AP PSK IS returned — the user
        // needs to read it back (06 §6.2).
        return _json(req, 200, {
          'mode': state.netMode,
          'sta': {'ssid': state.staSsid, 'auth': 'wpa2_psk'},
          'ap': {'ssid': state.apSsid, 'psk': state.apPsk, 'ip': '192.168.4.1'},
        });

      case ('POST', '/config/wifi'):
        return _configWifi(req);

      case ('GET', '/config/device'):
        return _json(req, 200, state.deviceConfig);

      case ('POST', '/config/device'):
        state.deviceConfig = {...state.deviceConfig, ...await _body(req)};
        return _json(req, 200, {'ok': true});

      case ('GET', '/config/alarms'):
        return _json(req, 200, state.alarmConfig);

      case ('POST', '/config/alarms'):
        state.alarmConfig = {...state.alarmConfig, ...await _body(req)};
        return _json(req, 200, {'ok': true});

      case ('POST', '/time'):
        final body = await _body(req);
        final unixMs = body['unix_ms'];
        if (unixMs is! int) {
          return _json(
            req,
            400,
            errorBody('invalid_field', 'unix_ms must be int'),
          );
        }
        state
          ..clockValid = true
          ..timeSource = 'phone'
          ..tzOffsetMin = body['tz_offset_min'] is int
              ? body['tz_offset_min']! as int
              : state.tzOffsetMin;
        return _json(req, 200, {'ok': true});

      case ('GET', '/radio'):
        return _json(req, 200, {
          'frequency_hz': 910500000,
          'spreading_factor': 9,
          'bandwidth_khz': 125,
          'rssi': -71,
          'snr': 9,
          'packets_ok': state.packetsOk(vT),
          'packets_bad': 0,
          'id_mismatch': 0,
        });

      case ('POST', '/radio'):
        return _json(req, 200, {'ok': true});

      case ('POST', '/ota'):
        return _ota(req);

      case ('GET', '/debug/packets'):
        final visible = state.liveVisible(vT);
        return _json(req, 200, {
          'packets': [
            for (final r
                in visible.length > 64
                    ? visible.sublist(visible.length - 64)
                    : visible)
              {
                'uptime_s': r.t,
                'rssi': r.rssi,
                'snr': 9,
                'payload': _fakePayload(state, r),
              },
          ],
        });

      case ('GET', '/debug/novelty'):
        // The F4.3 pinned log, verbatim text — the read half of M1's
        // capture work (F4.4). The sim synthesises the lines its replay
        // state implies.
        req.response.headers.contentType = ContentType(
          'text',
          'plain',
          charset: 'utf-8',
        );
        req.response.write(noveltyText(state, vT));
        return req.response.close();

      case ('GET', '/debug/coredump'):
        return _json(req, 404, errorBody('not_found', 'no coredump stored'));

      // V3.1 — so the soak recorder is developable against the sim.
      case ('GET', '/debug/tasks'):
        return _json(req, 200, debugTasksJson(state));
    }

    // /sessions/{id}[...]
    final sessionMatch = RegExp(r'^/sessions/(\d+)(/.*)?$').firstMatch(api);
    if (sessionMatch != null) {
      final id = int.parse(sessionMatch.group(1)!);
      final sub = sessionMatch.group(2) ?? '';
      if (id != state.header.sessionId) {
        return _json(
          req,
          404,
          errorBody('session_not_found', 'no session $id', {'id': id}),
        );
      }
      switch ((method, sub)) {
        case ('GET', ''):
          return _json(req, 200, sessionJson(state));
        case ('PATCH', ''):
          await _body(req); // accepted; sim keeps its fixture name
          return _json(req, 200, sessionJson(state));
        case ('DELETE', ''):
          if (!state.sessionEnded(vT)) {
            return _json(
              req,
              409,
              errorBody(
                'session_active',
                'refusing to delete the active session',
              ),
            );
          }
          return _json(req, 200, {'ok': true});
        case ('POST', '/stop'):
          state.sessionStopped = true;
          _push({
            'type': 'session',
            'action': 'ended',
            'id': state.header.sessionId,
          });
          return _json(req, 200, {'ok': true});
        case ('GET', '/samples'):
          return _samples(req);
        case ('GET', '/marks'):
          return _json(req, 200, {
            'marks': [for (final m in state.marks) markJson(m)],
          });
        case ('POST', '/marks'):
          final body = await _body(req);
          final mark = MarkRec(
            t: body['t'] is int ? body['t']! as int : vT,
            kind: body['kind'] is int ? body['kind']! as int : 0,
            probe: body['probe'] is int ? body['probe']! as int : 0,
            textRaw: utf8ToPadded('${body['text'] ?? ''}', 24),
          );
          state.marks.add(mark);
          return _json(req, 200, markJson(mark));
      }
    }

    return _json(req, 404, errorBody('not_found', 'no route $method $api'));
  }

  // ── the workhorse: streamed history (T3.2) ────────────────────────

  Future<void> _samples(HttpRequest req) async {
    final q = req.uri.queryParameters;
    final all = state.samples;
    final lastT = all.isEmpty ? 0 : all.last.t;
    final from = int.tryParse(q['from'] ?? '') ?? 0;
    final to = int.tryParse(q['to'] ?? '') ?? lastT;
    final stride = int.tryParse(q['stride'] ?? '') ?? 1;
    final bucket = int.tryParse(q['bucket'] ?? '') ?? 0;
    final agg = q['agg'] ?? (bucket > 0 ? 'mean' : 'none');
    final format = q['format'] ?? 'bin';
    final probes = (q['probes'] ?? '1,2,3,4')
        .split(',')
        .map(int.parse)
        .where((p) => p >= 1 && p <= 4)
        .toList();
    if (stride < 1 || bucket < 0 || from < 0 || to < from) {
      return _json(
        req,
        400,
        errorBody('invalid_field', 'bad range/stride/bucket'),
      );
    }
    if (!['none', 'mean', 'minmax'].contains(agg) ||
        !['bin', 'json', 'ndjson', 'csv'].contains(format)) {
      return _json(req, 400, errorBody('invalid_field', 'bad agg/format'));
    }

    var selected = [
      for (final r in all)
        if (r.t >= from && r.t <= to) r,
    ];
    if (stride > 1) {
      selected = [
        for (var i = 0; i < selected.length; i += stride) selected[i],
      ];
    }

    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');

    if (bucket > 0 && agg != 'none') {
      return _json(
        req,
        200,
        bucketedJson(
          state,
          selected,
          from: from,
          to: to,
          bucketS: bucket,
          agg: agg,
          probes: probes,
        ),
      );
    }

    switch (format) {
      case 'bin':
        // Byte-identical to the stored records: the app's sync path.
        res.headers.contentType = ContentType.binary;
        for (final r in selected) {
          res.add(r.encode());
        }
        return res.close();
      case 'ndjson':
        res.headers.contentType = ContentType('application', 'x-ndjson');
        for (final r in selected) {
          res.writeln(
            jsonEncode({
              't': r.t,
              'temps_f10': [for (var i = 0; i < 4; i++) r.tempOrNull(i)],
              'billows': r.billows,
              'rssi': r.rssi,
            }),
          );
        }
        return res.close();
      case 'csv':
        res.headers.contentType = ContentType('text', 'csv');
        res.writeln('t_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi');
        for (final r in selected) {
          res.writeln(csvLine(state, r));
        }
        return res.close();
      default: // json
        return _json(
          req,
          200,
          plainSamplesJson(state, selected, from: from, to: to, probes: probes),
        );
    }
  }

  // ── config/wifi: answer FIRST, apply after 500 ms (05 §5.4) ───────

  Future<void> _configWifi(HttpRequest req) async {
    final body = await _body(req);
    final mode = body['mode'];
    if (mode != 'ap' && mode != 'sta') {
      return _json(
        req,
        400,
        errorBody('unsupported_mode', 'mode must be ap|sta'),
      );
    }
    final Map<String, Object?> expect = mode == 'ap'
        ? {
            'mode': 'ap',
            'ssid': state.apSsid,
            'psk': state.apPsk,
            'ip': '192.168.4.1',
          }
        : {'mode': 'sta', 'host': 'smokebridge.local'};
    _json(req, 200, {
      'accepted': true,
      'applying_in_ms': 500,
      'expect': expect,
    });
    _after(const Duration(milliseconds: 500), () {
      state.netMode = mode as String;
      if (mode == 'sta' && body['ssid'] is String) {
        state.staSsid = body['ssid']! as String;
      }
      if (mode == 'sta' && body['psk'] is String) {
        state.staPsk = body['psk']! as String;
      }
      _push({
        'type': 'net',
        'mode': state.netMode,
        'state': 'up',
        'ip': state.netMode == 'sta' ? '192.168.1.42' : '192.168.4.1',
      });
    });
  }

  // ── OTA (T3.4) ────────────────────────────────────────────────────

  Future<void> _ota(HttpRequest req) async {
    final force = req.uri.queryParameters['force'] == '1';
    if (state.otaInProgress) {
      return _json(
        req,
        503,
        errorBody('ota_in_progress', 'an update is already being written'),
      );
    }
    if (!state.sessionEnded(state.virtualT()) && !force) {
      return _json(
        req,
        409,
        errorBody(
          'session_active',
          'refusing OTA mid-cook without ?force=1 — nobody should discover '
              'a bad flash 14 hours into a brisket',
        ),
      );
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in req) {
      body.add(chunk);
      // The header is all the validator needs; the rest is only counted.
      if (body.length > 1 << 20) break;
    }
    final bytes = body.takeBytes();
    if (bytes.isEmpty) {
      return _json(req, 400, errorBody('invalid_body', 'empty image'));
    }
    // F14.6 — the sim validates the image header with the SAME rules the
    // device uses. A fake that accepts `[1, 2, 3, 4]` as firmware gives
    // the app path false confidence in exactly the case that costs a
    // board (§12.6 rule 8).
    final image = inspectOtaImage(bytes);
    if (!image.ok) {
      return _json(req, 400, errorBody('invalid_body', image.reason));
    }
    state
      ..otaInProgress = true
      ..otaPct = 0;
    for (final pct in [10, 40, 80, 100]) {
      _after(Duration(milliseconds: 100 * (pct ~/ 10)), () {
        state.otaPct = pct;
        _push({'type': 'ota', 'phase': 'writing', 'pct': pct});
      });
    }
    _after(const Duration(milliseconds: 1200), () {
      _push({'type': 'ota', 'phase': 'verifying', 'pct': 100});
    });
    _after(const Duration(milliseconds: 1500), () {
      state
        ..otaInProgress = false
        ..otaSlot = state.otaSlot == 'ota_0' ? 'ota_1' : 'ota_0'
        ..fw = image.version;
      // `rebooting` is the device's terminal phase; the spec's enum has
      // no `done`, and the sim used to emit one.
      _push({'type': 'ota', 'phase': 'rebooting', 'pct': 100});
    });
    return _json(req, 200, {
      'accepted': true,
      'image_size_b': bytes.length,
      'slot': state.otaSlot == 'ota_0' ? 'ota_1' : 'ota_0',
      'version': image.version,
      'project': image.project,
      'rebooting_in_ms': 500,
    });
  }

  // ── WebSocket (T3.3) ──────────────────────────────────────────────

  Future<void> _upgradeWs(HttpRequest req) async {
    if (_wsClients.length >= maxWsClients) {
      // The documented cap: a third client gets 503 busy (06 §6.3).
      return _json(
        req,
        503,
        errorBody('busy', '$maxWsClients WebSocket clients already connected', {
          'max_ws_clients': maxWsClients,
        }),
      );
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.pingInterval = const Duration(seconds: 30);
    _wsClients.add(ws);

    var topics = {
      'sample',
      'alarm',
      'session',
      'net',
      'power',
      'pairing',
      'ota',
    };
    ws.listen(
      (Object? data) {
        if (data is! String) {
          return;
        }
        final Object? msg;
        try {
          msg = jsonDecode(data);
        } on FormatException {
          return;
        }
        if (msg is! Map) {
          return;
        }
        switch (msg['type']) {
          case 'subscribe':
            final t = msg['topics'];
            if (t is List) {
              topics = {...t.cast<String>()};
            }
          case 'ping':
            ws.add(jsonEncode({'type': 'pong'}));
          case 'ack_alarm':
            if (msg['id'] is int) {
              state.ackedAlarms.add(msg['id'] as int);
            }
        }
      },
      onDone: () => _wsClients.remove(ws),
      onError: (Object _) => _wsClients.remove(ws),
    );
    _topicFilters[ws] = () => topics;

    // hello immediately, then the current sample, so a client has state
    // without a separate GET.
    ws.add(
      jsonEncode({
        'type': 'hello',
        'fw': state.fw,
        'api': 'v1',
        'server_time_ms': state.clockValid
            ? state.header.startedUnixMs + state.virtualT() * 1000
            : null,
      }),
    );
    final visible = state.liveVisible(state.virtualT());
    if (visible.isNotEmpty) {
      ws.add(jsonEncode(_sampleFrame(visible.last)));
    }
  }

  final Map<WebSocket, Set<String> Function()> _topicFilters = {};

  Map<String, Object?> _sampleFrame(SampleRec r) => {
    'type': 'sample',
    't': r.t,
    'unix_ms': state.clockValid
        ? state.header.startedUnixMs + r.t * 1000
        : null,
    'temps_f10': [for (var i = 0; i < 4; i++) r.tempOrNull(i)],
    'flags': {'billows': r.billows},
    'rssi': r.rssi,
  };

  void _push(Map<String, Object?> frame) {
    final type = frame['type'] as String;
    for (final ws in List.of(_wsClients)) {
      final topics = _topicFilters[ws]?.call();
      if (topics != null && !topics.contains(type) && type != 'hello') {
        continue;
      }
      ws.add(jsonEncode(frame));
    }
  }

  // ── replay push loop ──────────────────────────────────────────────

  int _pushedThroughT = -1;

  void _startReplayPush() {
    _pushedThroughT = state.virtualT();
    final periodMs = state.speed > 0
        ? ((state.header.samplePeriodS * 1000) / state.speed)
              .clamp(20, 30000)
              .round()
        : 30000;
    final timer = Timer.periodic(Duration(milliseconds: periodMs), (_) {
      final vT = state.virtualT();
      for (final r in state.liveVisible(vT)) {
        if (r.t > _pushedThroughT) {
          _push(_sampleFrame(r));
        }
      }
      if (state.sessionEnded(vT) && !_sessionEndPushed) {
        _sessionEndPushed = true;
        _push({
          'type': 'session',
          'action': 'ended',
          'id': state.header.sessionId,
        });
      }
      _pushedThroughT = vT;
    });
    _timers.add(timer);
  }

  bool _sessionEndPushed = false;

  void _after(Duration d, void Function() fn) {
    late final Timer t;
    t = Timer(d, () {
      _timers.remove(t);
      fn();
    });
    _timers.add(t);
  }
}

String _fakePayload(SimState s, SampleRec r) {
  final fields = <String>[s.header.deviceId, '30', '1', r.newAlarm ? '1' : '0'];
  for (var i = 0; i < 4; i++) {
    final v = r.tempOrNull(i);
    fields.addAll(
      v == null ? ['3', '0', '0', '0', '0'] : ['0', '$v', '0', '0', '0'],
    );
  }
  fields.addAll([r.billows ? '1' : '0', '0']);
  return '${fields.join(',')},';
}
