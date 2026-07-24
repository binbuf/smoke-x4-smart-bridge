/// One poll of the bridge, as it lands in the NDJSON trace.
library;

class TaskRow {
  const TaskRow({
    required this.name,
    required this.stackB,
    required this.marginB,
  });

  factory TaskRow.fromJson(Map<String, Object?> j) => TaskRow(
    name: j['name']! as String,
    stackB: (j['stack_b'] as num?)?.toInt() ?? 0,
    marginB: (j['margin_b'] as num?)?.toInt() ?? 0,
  );

  final String name;
  final int stackB;

  /// Bytes of stack never used. The DEVICE computes it, because it is what
  /// the threshold is stated against.
  final int marginB;

  Map<String, Object?> toJson() => {
    'name': name,
    'stack_b': stackB,
    'margin_b': marginB,
  };
}

class SoakSample {
  const SoakSample({
    required this.seq,
    required this.wallMs,
    required this.uptimeS,
    required this.freeHeap,
    required this.minFreeHeap,
    required this.largestFreeBlock,
    required this.packetsOk,
    required this.packetsBad,
    required this.storageUsedB,
    required this.reconnects,
    required this.wsDrops,
    required this.alarms,
    required this.sessionActive,
    required this.fw,
    required this.gate,
    required this.tasks,
  });

  factory SoakSample.fromJson(Map<String, Object?> j) => SoakSample(
    seq: (j['seq']! as num).toInt(),
    wallMs: (j['wall_ms']! as num).toInt(),
    uptimeS: (j['uptime_s'] as num?)?.toInt() ?? 0,
    freeHeap: (j['free_heap'] as num?)?.toInt() ?? 0,
    minFreeHeap: (j['min_free_heap'] as num?)?.toInt() ?? 0,
    largestFreeBlock: (j['largest_free_block'] as num?)?.toInt() ?? 0,
    packetsOk: (j['packets_ok'] as num?)?.toInt() ?? 0,
    packetsBad: (j['packets_bad'] as num?)?.toInt() ?? 0,
    storageUsedB: (j['storage_used_b'] as num?)?.toInt() ?? 0,
    reconnects: (j['reconnects'] as num?)?.toInt() ?? 0,
    wsDrops: (j['ws_drops'] as num?)?.toInt() ?? 0,
    alarms: (j['alarms'] as num?)?.toInt() ?? 0,
    sessionActive: j['session_active'] == true,
    fw: (j['fw'] as String?) ?? '',
    gate: (j['gate'] as String?) ?? '',
    tasks: [
      for (final t in (j['tasks'] as List? ?? const []))
        TaskRow.fromJson(t! as Map<String, Object?>),
    ],
  );

  /// Monotonic, contiguous, and the reason a resumed run neither loses nor
  /// duplicates a sample.
  final int seq;
  final int wallMs;
  final int uptimeS;
  final int freeHeap;
  final int minFreeHeap;

  /// R2's actual failure mode. A total free-heap number cannot see
  /// fragmentation: 80 KB free in 2 KB pieces cannot allocate a TLS
  /// buffer, and every heap number still looks fine.
  final int largestFreeBlock;
  final int packetsOk;
  final int packetsBad;
  final int storageUsedB;
  final int reconnects;
  final int wsDrops;
  final int alarms;
  final bool sessionActive;
  final String fw;
  final String gate;
  final List<TaskRow> tasks;

  Map<String, Object?> toJson() => {
    'seq': seq,
    'wall_ms': wallMs,
    'uptime_s': uptimeS,
    'free_heap': freeHeap,
    'min_free_heap': minFreeHeap,
    'largest_free_block': largestFreeBlock,
    'packets_ok': packetsOk,
    'packets_bad': packetsBad,
    'storage_used_b': storageUsedB,
    'reconnects': reconnects,
    'ws_drops': wsDrops,
    'alarms': alarms,
    'session_active': sessionActive,
    'fw': fw,
    'gate': gate,
    'tasks': [for (final t in tasks) t.toJson()],
  };
}
