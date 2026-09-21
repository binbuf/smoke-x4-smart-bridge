/// A real loopback HTTP + WebSocket bridge for transport tests.
///
/// It is deliberately **not** the `tools/sim` package: the app is a standalone
/// Dart package, so importing the sim would drag the whole workspace in. This
/// server mirrors the sim's shapes for the subset [HttpTransport] uses, which
/// is exactly the contract a transport test should pin.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FakeBridgeServer {
  FakeBridgeServer({this.deviceId = '480001'});

  final String deviceId;
  HttpServer? _server;
  WebSocket? _socket;
  final List<(String, String)> requests = [];
  String? lastAuthHeader;
  bool failStatus = false;
  int statusCount = 0;

  int get port => _server!.port;
  String get baseUrl => 'http://127.0.0.1:$port';

  List<Map<String, Object?>> samples = [
    {
      't': 0,
      'temps_f10': [1000, null, null, 2200],
      'billows': false,
      'rssi': -60,
    },
    {
      't': 30,
      'temps_f10': [1050, null, null, 2210],
      'billows': true,
      'rssi': -58,
    },
    {
      't': 60,
      'temps_f10': [1100, null, null, 2220],
      'billows': true,
      'rssi': -57,
    },
  ];

  Map<String, Object?> statusJson() => {
    'device': {
      'id': deviceId,
      'model': 'sim',
      'fw': '1.4.2',
      'uptime_s': 3600,
      'free_heap': 168432,
      'min_free_heap': 141008,
      'reset_reason': 'poweron',
      'coredump_available': false,
    },
    'time': {
      'unix_ms': 1700000090000,
      'source': 'phone',
      'tz_offset_min': 0,
      'valid': true,
    },
    'net': {
      'mode': 'ap',
      'state': 'up',
      'ssid': 'SmokeBridge-A4F2',
      'rssi': -54,
      'ip': '192.168.4.1',
      'host': 'smokebridge.local',
      'ap_clients': 0,
    },
    'ble': {'advertising': true, 'connections': 0, 'bonded': 0},
    'pairing': {
      'paired': true,
      'device_id': 'X4-$deviceId',
      'model': 'X4',
      'num_probes': 4,
      'frequency_hz': 910500000,
      'last_packet_s_ago': 8,
      'base_lost': false,
    },
    'radio': {
      'rssi': -71,
      'snr': 9,
      'packets_ok': 120,
      'packets_bad': 0,
      'id_mismatch': 0,
    },
    'storage': {
      'total_b': 2490368,
      'used_b': 214016,
      'free_pct': 91,
      'sessions': 1,
      'oldest_session_id': 1,
    },
    'power': {'mv': 3894, 'soc_pct': 71, 'charging': true, 'saver': false},
    'session': {
      'active': true,
      'id': 1,
      'name': 'Sim Cook',
      'started_unix_ms': 1700000000000,
      'elapsed_s': 60,
      'samples': samples.length,
    },
    'cook_clock': {'set': true, 'elapsed_s': 60},
    'ota': {'slot': 'ota_0', 'pending_verify': false, 'gate': 'not_applicable'},
    'alarms': <Object?>[],
  };

  Map<String, Object?> sessionJson() => {
    'id': 1,
    'name': 'Sim Cook',
    'started_unix_ms': 1700000000000,
    'ended_unix_ms': null,
    'sample_period_s': 30,
    'sample_count': samples.length,
    'num_probes': 4,
    'probes': [
      {'n': 1, 'name': 'Brisket', 'role': 'food', 'target_f10': 2010},
    ],
    'closed': false,
    'pinned': false,
    'mark_count': 0,
  };

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_dispatch, onError: (Object _) {});
  }

  Future<void> stop() async {
    await _socket?.close();
    await _server?.close(force: true);
  }

  Future<void> _dispatch(HttpRequest req) async {
    requests.add((req.method, req.uri.path));
    lastAuthHeader = req.headers.value(HttpHeaders.authorizationHeader);
    final path = req.uri.path;
    try {
      if (path == '/api/v1/stream') {
        return await _upgrade(req);
      }
      if (path == '/api/v1/status') {
        statusCount++;
        if (failStatus) {
          return _json(req, 503, {
            'error': {
              'code': 'busy',
              'message': 'max_open_sockets reached',
              'detail': null,
            },
          });
        }
        return _json(req, 200, statusJson());
      }
      if (path == '/api/v1/live') {
        return _json(req, 200, {
          't': 60,
          'unix_ms': 1700000060000,
          'units_source': 'F',
          'billows': {'attached': true, 'target_f10': null},
          'probes': [
            {
              'n': 1,
              'name': 'Brisket',
              'role': 'food',
              'attached': true,
              'temp_f10': 1100,
              'alarm_enabled': false,
              'target_f10': 2010,
              'rate_f_per_hr': 4.2,
            },
          ],
        });
      }
      if (path == '/api/v1/sessions' && req.method == 'GET') {
        return _json(req, 200, {
          'sessions': [sessionJson()],
        });
      }
      if (path == '/api/v1/sessions/1/samples') {
        final from = int.tryParse(req.uri.queryParameters['from'] ?? '') ?? 0;
        final res = req.response;
        res.statusCode = 200;
        res.headers.contentType = ContentType('application', 'x-ndjson');
        for (final s in samples) {
          if ((s['t']! as int) >= from) {
            res.writeln(jsonEncode(s));
          }
        }
        return await res.close();
      }
      if (path == '/api/v1/sessions/1/marks') {
        if (req.method == 'GET') {
          return _json(req, 200, {
            'marks': [
              {'t': 10, 'kind': 1, 'probe': 1, 'text': 'Wrapped'},
            ],
          });
        }
        if (req.method == 'POST') {
          final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
          return _json(req, 200, body);
        }
      }
      if (path == '/api/v1/config/wifi' && req.method == 'POST') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        return _json(req, 200, {
          'accepted': true,
          'applying_in_ms': 500,
          'mode': body['mode'],
        });
      }
      if (path == '/api/v1/time') {
        return _json(req, 200, {'ok': true});
      }
      if (path == '/api/v1/cook-clock') {
        if (req.method == 'DELETE') {
          return _json(req, 200, {'set': false, 'elapsed_s': null});
        }
        if (req.method == 'POST') {
          final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
          if (body['started_unix_ms'] != null && body['elapsed_s'] != null) {
            return _json(req, 400, {
              'error': {'code': 'invalid_field', 'message': 'one of'},
            });
          }
          return _json(req, 200, {'set': true, 'elapsed_s': 42});
        }
        return _json(req, 200, {'set': true, 'elapsed_s': 60});
      }
      return _json(req, 404, {
        'error': {'code': 'not_found', 'message': 'no route'},
      });
    } on Object catch (e) {
      try {
        _json(req, 500, {
          'error': {'code': 'internal', 'message': '$e'},
        });
      } on Object {
        // The response was already sent; nothing to do.
      }
    }
  }

  Future<void> _upgrade(HttpRequest req) async {
    final socket = await WebSocketTransformer.upgrade(req);
    _socket = socket;
    socket.add(jsonEncode({'type': 'hello', 'fw': '1.4.2', 'api': 'v1'}));
    socket.add(
      jsonEncode({
        'type': 'sample',
        't': 90,
        'unix_ms': 1700000090000,
        'temps_f10': [1200, null, null, 2250],
        'flags': {'billows': true},
        'rssi': -55,
      }),
    );
  }

  void push(Object? frame) =>
      _socket?.add(frame is String ? frame : jsonEncode(frame));

  void _json(HttpRequest req, int status, Object? body) {
    final res = req.response;
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    res.close();
  }
}
