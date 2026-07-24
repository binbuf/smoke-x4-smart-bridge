/// JSON payload builders, shaped byte-for-byte like the P2.3 fixtures in
/// protocol/fixtures/http/ — the sim and the app tests read the same files,
/// so a contract change breaks both at once.
library;

import 'package:bridge_protocol/bridge_protocol.dart';

import 'state.dart';

Map<String, Object?> errorBody(String code, String message, [Object? detail]) =>
    {
      'error': {'code': code, 'message': message, 'detail': detail},
    };

Map<String, Object?> statusJson(SimState s) {
  final vT = s.virtualT();
  final ended = s.sessionEnded(vT);
  final lastAgo = s.lastPacketAgo(vT);
  return {
    'device': {
      'id': s.deviceIdShort,
      'model': 'sim',
      'fw': s.fw,
      'uptime_s': vT,
      'free_heap': 168432,
      'min_free_heap': 141008,
      'reset_reason': 'poweron',
      'coredump_available': false,
    },
    'time': {
      'unix_ms': s.clockValid ? s.header.startedUnixMs + vT * 1000 : null,
      'source': s.clockValid ? s.timeSource : 'none',
      'tz_offset_min': s.tzOffsetMin,
      'valid': s.clockValid,
    },
    'net': {
      'mode': s.netMode,
      'state': 'up',
      'ssid': s.netMode == 'sta' ? s.staSsid : s.apSsid,
      'rssi': -54,
      'ip': s.netMode == 'sta' ? '192.168.1.42' : '192.168.4.1',
      'host': 'smokebridge.local',
      'ap_clients': 0,
    },
    'ble': {'advertising': true, 'connections': 0, 'bonded': 0},
    'pairing': {
      'paired': s.paired,
      'device_id': s.paired ? s.header.deviceId : null,
      'model': s.paired ? 'X4' : null,
      'num_probes': s.paired ? s.header.numProbes : 0,
      'frequency_hz': s.paired ? 910500000 : null,
      'last_packet_s_ago': lastAgo,
      'base_lost': s.baseLostAt(vT),
    },
    'radio': {
      'rssi': -71,
      'snr': 9,
      'packets_ok': s.packetsOk(vT),
      'packets_bad': 0,
      'id_mismatch': 0,
    },
    'storage': {
      'total_b': 2490368,
      'used_b': s.storageFull ? 2440368 : 214016,
      'free_pct': s.storageFull ? 2 : 91,
      'sessions': 1,
      'oldest_session_id': s.header.sessionId,
    },
    'power': {'mv': 3894, 'soc_pct': 71, 'charging': true, 'saver': false},
    'session': {
      'active': !ended,
      'id': s.header.sessionId,
      'name': s.header.name,
      'started_unix_ms': s.clockValid ? s.header.startedUnixMs : null,
      'elapsed_s': ended ? (s.samples.isEmpty ? 0 : s.samples.last.t) : vT,
      'samples': s.liveVisible(vT).length,
    },
    // F11b.11 / F14.8 — additive objects the device now carries (06 §6.5).
    'display': {'i2c_ok': 18422, 'i2c_err': 0},
    'ota': {
      'slot': s.otaSlot,
      'pending_verify': false,
      // A sim is never pending verify: there is nothing to confirm and
      // nothing to roll back, and reporting `passed` would be the
      // /status.ble stub all over again.
      'gate': 'not_applicable',
      'failed': null,
    },
    'alarms': <Object?>[],
  };
}

/// V3.1 — the soak's evidence, over HTTP. `largest_free_block_b` is the
/// field a total free-heap number cannot express (R2).
Map<String, Object?> debugTasksJson(SimState s) {
  final vT = s.virtualT();
  return {
    'heap': {
      'free_b': 92160,
      'min_free_b': 80116,
      'largest_free_block_b': 40960,
    },
    'tasks': [
      for (final t in const [
        ('lora_rx', 4096, 1360, 6, 1),
        ('smoke_x', 3072, 1120, 5, 0),
        ('cook_store', 4096, 1840, 4, 0),
        ('app_ui', 4096, 1520, 3, 0),
        ('app_alarm', 3072, 1280, 4, 0),
        ('app_net', 3072, 1040, 4, 0),
        ('app_power', 2560, 1180, 2, 0),
        ('ws_push', 4096, 1240, 4, 0),
        ('ble_push', 4096, 1600, 4, 0),
        // The rows main/tasks.h cannot account for, which is why the
        // trace facility is enabled at all.
        ('httpd', 0, 2048, 5, -1),
        ('sys_evt', 0, 1600, 5, -1),
      ])
        {
          'name': t.$1,
          'stack_b': t.$2,
          // A little drift with virtual time, so a soak run against the
          // sim exercises a trend rather than a constant.
          'high_water_b': t.$3 - (vT ~/ 3600).clamp(0, 200),
          'margin_b': t.$3 - (vT ~/ 3600).clamp(0, 200),
          'priority': t.$4,
          'core': t.$5,
        },
    ],
  };
}

String _roleName(int role) =>
    const ['unused', 'pit', 'food', 'ambient'][role.clamp(0, 3)];

Map<String, Object?> liveJson(SimState s, int windowS) {
  final vT = s.virtualT();
  final visible = s.liveVisible(vT);
  final last = visible.isEmpty ? null : visible.last;
  final windowFrom = (last?.t ?? 0) - windowS;
  final recent = [
    for (final r in visible)
      if (r.t > windowFrom) r,
  ];

  // Per-probe 10-minute rate over the recent window (°F/hr, 1 decimal).
  double? rate(int i) {
    final pts = [
      for (final r in recent)
        if (r.t > (last?.t ?? 0) - 600 && r.tempOrNull(i) != null)
          (t: r.t, f: r.temp[i] / 10.0),
    ];
    if (pts.length < 12) {
      return null;
    }
    final n = pts.length;
    final meanT = pts.fold<double>(0, (a, p) => a + p.t) / n;
    final meanF = pts.fold<double>(0, (a, p) => a + p.f) / n;
    var sxx = 0.0;
    var sxy = 0.0;
    for (final p in pts) {
      sxx += (p.t - meanT) * (p.t - meanT);
      sxy += (p.t - meanT) * (p.f - meanF);
    }
    if (sxx == 0) {
      return null;
    }
    return double.parse((sxy / sxx * 3600).toStringAsFixed(1));
  }

  final h = s.header;
  return {
    't': last?.t ?? 0,
    'unix_ms': s.clockValid && last != null
        ? h.startedUnixMs + last.t * 1000
        : null,
    'units_source': (last != null && last.sourceCelsius) ? 'C' : 'F',
    'billows': {'attached': last?.billows ?? false, 'target_f10': null},
    'probes': [
      for (var i = 0; i < 4; i++)
        if (last != null && last.tempOrNull(i) != null)
          {
            'n': i + 1,
            'name': h.probeName[i],
            'role': _roleName(h.probeRole[i]),
            'attached': true,
            'temp_f10': last.temp[i],
            'alarm_enabled':
                last.p1Alarm && i == 0 ||
                last.p2Alarm && i == 1 ||
                last.p3Alarm && i == 2 ||
                last.p4Alarm && i == 3,
            'target_f10': h.probeTarget[i] == 0 ? null : h.probeTarget[i],
            'rate_f_per_hr': rate(i),
          }
        else
          {'n': i + 1, 'attached': false, 'temp_f10': null},
    ],
    'recent': {
      't0': recent.isEmpty ? 0 : recent.first.t,
      'step_s': h.samplePeriodS,
      'count': recent.length,
      'series': [
        for (var i = 0; i < 4; i++)
          if (recent.every((r) => r.tempOrNull(i) == null))
            null
          else
            [for (final r in recent) r.tempOrNull(i)],
      ],
    },
  };
}

Map<String, Object?> sessionJson(SimState s) {
  final vT = s.virtualT();
  final ended = s.sessionEnded(vT);
  final h = s.header;
  return {
    'id': h.sessionId,
    'name': h.name,
    'started_unix_ms': s.clockValid ? h.startedUnixMs : null,
    'ended_unix_ms': ended && s.clockValid && s.samples.isNotEmpty
        ? h.startedUnixMs + s.samples.last.t * 1000
        : null,
    'sample_period_s': h.samplePeriodS,
    'sample_count': h.sampleCount,
    'num_probes': h.numProbes,
    'probes': [
      for (var i = 0; i < 4; i++)
        {
          'n': i + 1,
          'name': h.probeName[i],
          'role': _roleName(h.probeRole[i]),
          'target_f10': h.probeTarget[i] == 0 ? null : h.probeTarget[i],
        },
    ],
    'closed': ended,
    'pinned': h.pinned,
    'mark_count': s.marks.length,
  };
}

Map<String, Object?> markJson(MarkRec m) => {
  't': m.t,
  'kind': m.kind,
  'probe': m.probe,
  'text': m.text,
};

/// Gaps from `t` deltas > 45 s — only possible because samples carry time.
List<Map<String, int>> gapsJson(List<SampleRec> records) {
  final gaps = <Map<String, int>>[];
  for (var i = 1; i < records.length; i++) {
    if (records[i].t - records[i - 1].t > 45) {
      gaps.add({'from': records[i - 1].t, 'to': records[i].t});
    }
  }
  return gaps;
}

/// The bucketed minmax/mean shape of samples-bucketed-gaps.json. Buckets are
/// [from + i·bucket, from + (i+1)·bucket); a record at exactly `to` lands in
/// the last bucket so `count == ceil((to − from) / bucket)` holds.
Map<String, Object?> bucketedJson(
  SimState s,
  List<SampleRec> records, {
  required int from,
  required int to,
  required int bucketS,
  required String agg,
  required List<int> probes,
}) {
  final count = ((to - from) + bucketS - 1) ~/ bucketS;
  final series = <Map<String, Object?>>[];
  for (final probe in probes) {
    final i = probe - 1;
    final mins = List<int?>.filled(count, null);
    final means = List<int?>.filled(count, null);
    final maxs = List<int?>.filled(count, null);
    final sums = List<int>.filled(count, 0);
    final ns = List<int>.filled(count, 0);
    for (final r in records) {
      final v = r.tempOrNull(i);
      if (v == null) {
        continue;
      }
      var b = (r.t - from) ~/ bucketS;
      if (b >= count) {
        b = count - 1; // t == to
      }
      mins[b] = mins[b] == null || v < mins[b]! ? v : mins[b];
      maxs[b] = maxs[b] == null || v > maxs[b]! ? v : maxs[b];
      sums[b] += v;
      ns[b]++;
    }
    for (var b = 0; b < count; b++) {
      if (ns[b] > 0) {
        means[b] = (sums[b] / ns[b]).round();
      }
    }
    series.add({
      'probe': probe,
      if (agg == 'minmax') 'min': mins,
      'mean': means,
      if (agg == 'minmax') 'max': maxs,
    });
  }
  return {
    'session_id': s.header.sessionId,
    'from': from,
    'to': to,
    'bucket_s': bucketS,
    'agg': agg,
    'count': count,
    'probes': probes,
    'series': series,
    'gaps': gapsJson(records),
  };
}

Map<String, Object?> plainSamplesJson(
  SimState s,
  List<SampleRec> records, {
  required int from,
  required int to,
  required List<int> probes,
}) => {
  'session_id': s.header.sessionId,
  'from': from,
  'to': to,
  'count': records.length,
  'probes': probes,
  'samples': [
    for (final r in records)
      {
        't': r.t,
        'temps_f10': [for (final probe in probes) r.tempOrNull(probe - 1)],
        'billows': r.billows,
        'rssi': r.rssi,
      },
  ],
  'gaps': gapsJson(records),
};

/// The novelty-log lines the sim's replay state implies (F4.4): the sync
/// beacon and the first state packet of each class, in the on-device
/// plain-text format `<t_ms> <reason> <value> <payload>`.
String noveltyText(SimState s, int vT) {
  final visible = s.liveVisible(vT);
  final b = StringBuffer();
  if (s.paired) {
    b.writeln(
      '0 sync 020001@910500000 020001,${s.header.deviceId},160,32,69,54,',
    );
  }
  if (visible.isNotEmpty) {
    final first = visible.first;
    final cls = s.header.numProbes == 4 ? 'state26' : 'state16';
    b.writeln(
      '${first.t * 1000} first $cls '
      '${s.header.deviceId},30,1,${first.newAlarm ? 1 : 0},...',
    );
  }
  return b.toString();
}

/// CSV per 04 §4.10: detached probes are EMPTY fields, never 0.
String csvLine(SimState s, SampleRec r) {
  final iso = s.clockValid
      ? DateTime.fromMillisecondsSinceEpoch(
          s.header.startedUnixMs + r.t * 1000,
          isUtc: true,
        ).toIso8601String()
      : '';
  final temps = [
    for (var i = 0; i < 4; i++)
      r.tempOrNull(i) == null ? '' : (r.temp[i] / 10).toStringAsFixed(1),
  ];
  return '${r.t},$iso,${temps.join(',')},${r.billows ? 1 : 0},${r.rssi}';
}
