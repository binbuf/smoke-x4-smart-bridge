// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SessionsTable extends Sessions
    with TableInfo<$SessionsTable, SessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bridgeIdMeta = const VerificationMeta(
    'bridgeId',
  );
  @override
  late final GeneratedColumn<String> bridgeId = GeneratedColumn<String>(
    'bridge_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _startedUnixMsMeta = const VerificationMeta(
    'startedUnixMs',
  );
  @override
  late final GeneratedColumn<int> startedUnixMs = GeneratedColumn<int>(
    'started_unix_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endedUnixMsMeta = const VerificationMeta(
    'endedUnixMs',
  );
  @override
  late final GeneratedColumn<int> endedUnixMs = GeneratedColumn<int>(
    'ended_unix_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _samplePeriodSMeta = const VerificationMeta(
    'samplePeriodS',
  );
  @override
  late final GeneratedColumn<int> samplePeriodS = GeneratedColumn<int>(
    'sample_period_s',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(30),
  );
  static const VerificationMeta _sampleCountMeta = const VerificationMeta(
    'sampleCount',
  );
  @override
  late final GeneratedColumn<int> sampleCount = GeneratedColumn<int>(
    'sample_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _numProbesMeta = const VerificationMeta(
    'numProbes',
  );
  @override
  late final GeneratedColumn<int> numProbes = GeneratedColumn<int>(
    'num_probes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(4),
  );
  static const VerificationMeta _closedMeta = const VerificationMeta('closed');
  @override
  late final GeneratedColumn<bool> closed = GeneratedColumn<bool>(
    'closed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("closed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    bridgeId,
    sessionId,
    name,
    startedUnixMs,
    endedUnixMs,
    samplePeriodS,
    sampleCount,
    numProbes,
    closed,
    pinned,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bridge_id')) {
      context.handle(
        _bridgeIdMeta,
        bridgeId.isAcceptableOrUnknown(data['bridge_id']!, _bridgeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bridgeIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('started_unix_ms')) {
      context.handle(
        _startedUnixMsMeta,
        startedUnixMs.isAcceptableOrUnknown(
          data['started_unix_ms']!,
          _startedUnixMsMeta,
        ),
      );
    }
    if (data.containsKey('ended_unix_ms')) {
      context.handle(
        _endedUnixMsMeta,
        endedUnixMs.isAcceptableOrUnknown(
          data['ended_unix_ms']!,
          _endedUnixMsMeta,
        ),
      );
    }
    if (data.containsKey('sample_period_s')) {
      context.handle(
        _samplePeriodSMeta,
        samplePeriodS.isAcceptableOrUnknown(
          data['sample_period_s']!,
          _samplePeriodSMeta,
        ),
      );
    }
    if (data.containsKey('sample_count')) {
      context.handle(
        _sampleCountMeta,
        sampleCount.isAcceptableOrUnknown(
          data['sample_count']!,
          _sampleCountMeta,
        ),
      );
    }
    if (data.containsKey('num_probes')) {
      context.handle(
        _numProbesMeta,
        numProbes.isAcceptableOrUnknown(data['num_probes']!, _numProbesMeta),
      );
    }
    if (data.containsKey('closed')) {
      context.handle(
        _closedMeta,
        closed.isAcceptableOrUnknown(data['closed']!, _closedMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bridgeId, sessionId};
  @override
  SessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionRow(
      bridgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bridge_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      startedUnixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_unix_ms'],
      ),
      endedUnixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_unix_ms'],
      ),
      samplePeriodS: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_period_s'],
      )!,
      sampleCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_count'],
      )!,
      numProbes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}num_probes'],
      )!,
      closed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}closed'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class SessionRow extends DataClass implements Insertable<SessionRow> {
  final String bridgeId;
  final int sessionId;
  final String name;
  final int? startedUnixMs;
  final int? endedUnixMs;
  final int samplePeriodS;
  final int sampleCount;
  final int numProbes;
  final bool closed;
  final bool pinned;
  const SessionRow({
    required this.bridgeId,
    required this.sessionId,
    required this.name,
    this.startedUnixMs,
    this.endedUnixMs,
    required this.samplePeriodS,
    required this.sampleCount,
    required this.numProbes,
    required this.closed,
    required this.pinned,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['bridge_id'] = Variable<String>(bridgeId);
    map['session_id'] = Variable<int>(sessionId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || startedUnixMs != null) {
      map['started_unix_ms'] = Variable<int>(startedUnixMs);
    }
    if (!nullToAbsent || endedUnixMs != null) {
      map['ended_unix_ms'] = Variable<int>(endedUnixMs);
    }
    map['sample_period_s'] = Variable<int>(samplePeriodS);
    map['sample_count'] = Variable<int>(sampleCount);
    map['num_probes'] = Variable<int>(numProbes);
    map['closed'] = Variable<bool>(closed);
    map['pinned'] = Variable<bool>(pinned);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      bridgeId: Value(bridgeId),
      sessionId: Value(sessionId),
      name: Value(name),
      startedUnixMs: startedUnixMs == null && nullToAbsent
          ? const Value.absent()
          : Value(startedUnixMs),
      endedUnixMs: endedUnixMs == null && nullToAbsent
          ? const Value.absent()
          : Value(endedUnixMs),
      samplePeriodS: Value(samplePeriodS),
      sampleCount: Value(sampleCount),
      numProbes: Value(numProbes),
      closed: Value(closed),
      pinned: Value(pinned),
    );
  }

  factory SessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionRow(
      bridgeId: serializer.fromJson<String>(json['bridgeId']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      name: serializer.fromJson<String>(json['name']),
      startedUnixMs: serializer.fromJson<int?>(json['startedUnixMs']),
      endedUnixMs: serializer.fromJson<int?>(json['endedUnixMs']),
      samplePeriodS: serializer.fromJson<int>(json['samplePeriodS']),
      sampleCount: serializer.fromJson<int>(json['sampleCount']),
      numProbes: serializer.fromJson<int>(json['numProbes']),
      closed: serializer.fromJson<bool>(json['closed']),
      pinned: serializer.fromJson<bool>(json['pinned']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bridgeId': serializer.toJson<String>(bridgeId),
      'sessionId': serializer.toJson<int>(sessionId),
      'name': serializer.toJson<String>(name),
      'startedUnixMs': serializer.toJson<int?>(startedUnixMs),
      'endedUnixMs': serializer.toJson<int?>(endedUnixMs),
      'samplePeriodS': serializer.toJson<int>(samplePeriodS),
      'sampleCount': serializer.toJson<int>(sampleCount),
      'numProbes': serializer.toJson<int>(numProbes),
      'closed': serializer.toJson<bool>(closed),
      'pinned': serializer.toJson<bool>(pinned),
    };
  }

  SessionRow copyWith({
    String? bridgeId,
    int? sessionId,
    String? name,
    Value<int?> startedUnixMs = const Value.absent(),
    Value<int?> endedUnixMs = const Value.absent(),
    int? samplePeriodS,
    int? sampleCount,
    int? numProbes,
    bool? closed,
    bool? pinned,
  }) => SessionRow(
    bridgeId: bridgeId ?? this.bridgeId,
    sessionId: sessionId ?? this.sessionId,
    name: name ?? this.name,
    startedUnixMs: startedUnixMs.present
        ? startedUnixMs.value
        : this.startedUnixMs,
    endedUnixMs: endedUnixMs.present ? endedUnixMs.value : this.endedUnixMs,
    samplePeriodS: samplePeriodS ?? this.samplePeriodS,
    sampleCount: sampleCount ?? this.sampleCount,
    numProbes: numProbes ?? this.numProbes,
    closed: closed ?? this.closed,
    pinned: pinned ?? this.pinned,
  );
  SessionRow copyWithCompanion(SessionsCompanion data) {
    return SessionRow(
      bridgeId: data.bridgeId.present ? data.bridgeId.value : this.bridgeId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      name: data.name.present ? data.name.value : this.name,
      startedUnixMs: data.startedUnixMs.present
          ? data.startedUnixMs.value
          : this.startedUnixMs,
      endedUnixMs: data.endedUnixMs.present
          ? data.endedUnixMs.value
          : this.endedUnixMs,
      samplePeriodS: data.samplePeriodS.present
          ? data.samplePeriodS.value
          : this.samplePeriodS,
      sampleCount: data.sampleCount.present
          ? data.sampleCount.value
          : this.sampleCount,
      numProbes: data.numProbes.present ? data.numProbes.value : this.numProbes,
      closed: data.closed.present ? data.closed.value : this.closed,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('bridgeId: $bridgeId, ')
          ..write('sessionId: $sessionId, ')
          ..write('name: $name, ')
          ..write('startedUnixMs: $startedUnixMs, ')
          ..write('endedUnixMs: $endedUnixMs, ')
          ..write('samplePeriodS: $samplePeriodS, ')
          ..write('sampleCount: $sampleCount, ')
          ..write('numProbes: $numProbes, ')
          ..write('closed: $closed, ')
          ..write('pinned: $pinned')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bridgeId,
    sessionId,
    name,
    startedUnixMs,
    endedUnixMs,
    samplePeriodS,
    sampleCount,
    numProbes,
    closed,
    pinned,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.bridgeId == this.bridgeId &&
          other.sessionId == this.sessionId &&
          other.name == this.name &&
          other.startedUnixMs == this.startedUnixMs &&
          other.endedUnixMs == this.endedUnixMs &&
          other.samplePeriodS == this.samplePeriodS &&
          other.sampleCount == this.sampleCount &&
          other.numProbes == this.numProbes &&
          other.closed == this.closed &&
          other.pinned == this.pinned);
}

class SessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<String> bridgeId;
  final Value<int> sessionId;
  final Value<String> name;
  final Value<int?> startedUnixMs;
  final Value<int?> endedUnixMs;
  final Value<int> samplePeriodS;
  final Value<int> sampleCount;
  final Value<int> numProbes;
  final Value<bool> closed;
  final Value<bool> pinned;
  final Value<int> rowid;
  const SessionsCompanion({
    this.bridgeId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.name = const Value.absent(),
    this.startedUnixMs = const Value.absent(),
    this.endedUnixMs = const Value.absent(),
    this.samplePeriodS = const Value.absent(),
    this.sampleCount = const Value.absent(),
    this.numProbes = const Value.absent(),
    this.closed = const Value.absent(),
    this.pinned = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String bridgeId,
    required int sessionId,
    this.name = const Value.absent(),
    this.startedUnixMs = const Value.absent(),
    this.endedUnixMs = const Value.absent(),
    this.samplePeriodS = const Value.absent(),
    this.sampleCount = const Value.absent(),
    this.numProbes = const Value.absent(),
    this.closed = const Value.absent(),
    this.pinned = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bridgeId = Value(bridgeId),
       sessionId = Value(sessionId);
  static Insertable<SessionRow> custom({
    Expression<String>? bridgeId,
    Expression<int>? sessionId,
    Expression<String>? name,
    Expression<int>? startedUnixMs,
    Expression<int>? endedUnixMs,
    Expression<int>? samplePeriodS,
    Expression<int>? sampleCount,
    Expression<int>? numProbes,
    Expression<bool>? closed,
    Expression<bool>? pinned,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bridgeId != null) 'bridge_id': bridgeId,
      if (sessionId != null) 'session_id': sessionId,
      if (name != null) 'name': name,
      if (startedUnixMs != null) 'started_unix_ms': startedUnixMs,
      if (endedUnixMs != null) 'ended_unix_ms': endedUnixMs,
      if (samplePeriodS != null) 'sample_period_s': samplePeriodS,
      if (sampleCount != null) 'sample_count': sampleCount,
      if (numProbes != null) 'num_probes': numProbes,
      if (closed != null) 'closed': closed,
      if (pinned != null) 'pinned': pinned,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? bridgeId,
    Value<int>? sessionId,
    Value<String>? name,
    Value<int?>? startedUnixMs,
    Value<int?>? endedUnixMs,
    Value<int>? samplePeriodS,
    Value<int>? sampleCount,
    Value<int>? numProbes,
    Value<bool>? closed,
    Value<bool>? pinned,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      bridgeId: bridgeId ?? this.bridgeId,
      sessionId: sessionId ?? this.sessionId,
      name: name ?? this.name,
      startedUnixMs: startedUnixMs ?? this.startedUnixMs,
      endedUnixMs: endedUnixMs ?? this.endedUnixMs,
      samplePeriodS: samplePeriodS ?? this.samplePeriodS,
      sampleCount: sampleCount ?? this.sampleCount,
      numProbes: numProbes ?? this.numProbes,
      closed: closed ?? this.closed,
      pinned: pinned ?? this.pinned,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bridgeId.present) {
      map['bridge_id'] = Variable<String>(bridgeId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (startedUnixMs.present) {
      map['started_unix_ms'] = Variable<int>(startedUnixMs.value);
    }
    if (endedUnixMs.present) {
      map['ended_unix_ms'] = Variable<int>(endedUnixMs.value);
    }
    if (samplePeriodS.present) {
      map['sample_period_s'] = Variable<int>(samplePeriodS.value);
    }
    if (sampleCount.present) {
      map['sample_count'] = Variable<int>(sampleCount.value);
    }
    if (numProbes.present) {
      map['num_probes'] = Variable<int>(numProbes.value);
    }
    if (closed.present) {
      map['closed'] = Variable<bool>(closed.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('bridgeId: $bridgeId, ')
          ..write('sessionId: $sessionId, ')
          ..write('name: $name, ')
          ..write('startedUnixMs: $startedUnixMs, ')
          ..write('endedUnixMs: $endedUnixMs, ')
          ..write('samplePeriodS: $samplePeriodS, ')
          ..write('sampleCount: $sampleCount, ')
          ..write('numProbes: $numProbes, ')
          ..write('closed: $closed, ')
          ..write('pinned: $pinned, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SamplesTable extends Samples with TableInfo<$SamplesTable, SampleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bridgeIdMeta = const VerificationMeta(
    'bridgeId',
  );
  @override
  late final GeneratedColumn<String> bridgeId = GeneratedColumn<String>(
    'bridge_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tMeta = const VerificationMeta('t');
  @override
  late final GeneratedColumn<int> t = GeneratedColumn<int>(
    't',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _p1Meta = const VerificationMeta('p1');
  @override
  late final GeneratedColumn<int> p1 = GeneratedColumn<int>(
    'p1',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _p2Meta = const VerificationMeta('p2');
  @override
  late final GeneratedColumn<int> p2 = GeneratedColumn<int>(
    'p2',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _p3Meta = const VerificationMeta('p3');
  @override
  late final GeneratedColumn<int> p3 = GeneratedColumn<int>(
    'p3',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _p4Meta = const VerificationMeta('p4');
  @override
  late final GeneratedColumn<int> p4 = GeneratedColumn<int>(
    'p4',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rssiMeta = const VerificationMeta('rssi');
  @override
  late final GeneratedColumn<int> rssi = GeneratedColumn<int>(
    'rssi',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _unixMsMeta = const VerificationMeta('unixMs');
  @override
  late final GeneratedColumn<int> unixMs = GeneratedColumn<int>(
    'unix_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bridgeId,
    sessionId,
    t,
    p1,
    p2,
    p3,
    p4,
    rssi,
    unixMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<SampleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bridge_id')) {
      context.handle(
        _bridgeIdMeta,
        bridgeId.isAcceptableOrUnknown(data['bridge_id']!, _bridgeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bridgeIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('t')) {
      context.handle(_tMeta, t.isAcceptableOrUnknown(data['t']!, _tMeta));
    } else if (isInserting) {
      context.missing(_tMeta);
    }
    if (data.containsKey('p1')) {
      context.handle(_p1Meta, p1.isAcceptableOrUnknown(data['p1']!, _p1Meta));
    }
    if (data.containsKey('p2')) {
      context.handle(_p2Meta, p2.isAcceptableOrUnknown(data['p2']!, _p2Meta));
    }
    if (data.containsKey('p3')) {
      context.handle(_p3Meta, p3.isAcceptableOrUnknown(data['p3']!, _p3Meta));
    }
    if (data.containsKey('p4')) {
      context.handle(_p4Meta, p4.isAcceptableOrUnknown(data['p4']!, _p4Meta));
    }
    if (data.containsKey('rssi')) {
      context.handle(
        _rssiMeta,
        rssi.isAcceptableOrUnknown(data['rssi']!, _rssiMeta),
      );
    }
    if (data.containsKey('unix_ms')) {
      context.handle(
        _unixMsMeta,
        unixMs.isAcceptableOrUnknown(data['unix_ms']!, _unixMsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bridgeId, sessionId, t};
  @override
  SampleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SampleRow(
      bridgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bridge_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      t: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}t'],
      )!,
      p1: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}p1'],
      ),
      p2: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}p2'],
      ),
      p3: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}p3'],
      ),
      p4: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}p4'],
      ),
      rssi: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rssi'],
      )!,
      unixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unix_ms'],
      ),
    );
  }

  @override
  $SamplesTable createAlias(String alias) {
    return $SamplesTable(attachedDatabase, alias);
  }
}

class SampleRow extends DataClass implements Insertable<SampleRow> {
  final String bridgeId;
  final int sessionId;

  /// Seconds since session start — monotonic, gap-preserving.
  final int t;
  final int? p1;
  final int? p2;
  final int? p3;
  final int? p4;
  final int rssi;

  /// NULL when the bridge had no clock.
  final int? unixMs;
  const SampleRow({
    required this.bridgeId,
    required this.sessionId,
    required this.t,
    this.p1,
    this.p2,
    this.p3,
    this.p4,
    required this.rssi,
    this.unixMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['bridge_id'] = Variable<String>(bridgeId);
    map['session_id'] = Variable<int>(sessionId);
    map['t'] = Variable<int>(t);
    if (!nullToAbsent || p1 != null) {
      map['p1'] = Variable<int>(p1);
    }
    if (!nullToAbsent || p2 != null) {
      map['p2'] = Variable<int>(p2);
    }
    if (!nullToAbsent || p3 != null) {
      map['p3'] = Variable<int>(p3);
    }
    if (!nullToAbsent || p4 != null) {
      map['p4'] = Variable<int>(p4);
    }
    map['rssi'] = Variable<int>(rssi);
    if (!nullToAbsent || unixMs != null) {
      map['unix_ms'] = Variable<int>(unixMs);
    }
    return map;
  }

  SamplesCompanion toCompanion(bool nullToAbsent) {
    return SamplesCompanion(
      bridgeId: Value(bridgeId),
      sessionId: Value(sessionId),
      t: Value(t),
      p1: p1 == null && nullToAbsent ? const Value.absent() : Value(p1),
      p2: p2 == null && nullToAbsent ? const Value.absent() : Value(p2),
      p3: p3 == null && nullToAbsent ? const Value.absent() : Value(p3),
      p4: p4 == null && nullToAbsent ? const Value.absent() : Value(p4),
      rssi: Value(rssi),
      unixMs: unixMs == null && nullToAbsent
          ? const Value.absent()
          : Value(unixMs),
    );
  }

  factory SampleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SampleRow(
      bridgeId: serializer.fromJson<String>(json['bridgeId']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      t: serializer.fromJson<int>(json['t']),
      p1: serializer.fromJson<int?>(json['p1']),
      p2: serializer.fromJson<int?>(json['p2']),
      p3: serializer.fromJson<int?>(json['p3']),
      p4: serializer.fromJson<int?>(json['p4']),
      rssi: serializer.fromJson<int>(json['rssi']),
      unixMs: serializer.fromJson<int?>(json['unixMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bridgeId': serializer.toJson<String>(bridgeId),
      'sessionId': serializer.toJson<int>(sessionId),
      't': serializer.toJson<int>(t),
      'p1': serializer.toJson<int?>(p1),
      'p2': serializer.toJson<int?>(p2),
      'p3': serializer.toJson<int?>(p3),
      'p4': serializer.toJson<int?>(p4),
      'rssi': serializer.toJson<int>(rssi),
      'unixMs': serializer.toJson<int?>(unixMs),
    };
  }

  SampleRow copyWith({
    String? bridgeId,
    int? sessionId,
    int? t,
    Value<int?> p1 = const Value.absent(),
    Value<int?> p2 = const Value.absent(),
    Value<int?> p3 = const Value.absent(),
    Value<int?> p4 = const Value.absent(),
    int? rssi,
    Value<int?> unixMs = const Value.absent(),
  }) => SampleRow(
    bridgeId: bridgeId ?? this.bridgeId,
    sessionId: sessionId ?? this.sessionId,
    t: t ?? this.t,
    p1: p1.present ? p1.value : this.p1,
    p2: p2.present ? p2.value : this.p2,
    p3: p3.present ? p3.value : this.p3,
    p4: p4.present ? p4.value : this.p4,
    rssi: rssi ?? this.rssi,
    unixMs: unixMs.present ? unixMs.value : this.unixMs,
  );
  SampleRow copyWithCompanion(SamplesCompanion data) {
    return SampleRow(
      bridgeId: data.bridgeId.present ? data.bridgeId.value : this.bridgeId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      t: data.t.present ? data.t.value : this.t,
      p1: data.p1.present ? data.p1.value : this.p1,
      p2: data.p2.present ? data.p2.value : this.p2,
      p3: data.p3.present ? data.p3.value : this.p3,
      p4: data.p4.present ? data.p4.value : this.p4,
      rssi: data.rssi.present ? data.rssi.value : this.rssi,
      unixMs: data.unixMs.present ? data.unixMs.value : this.unixMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SampleRow(')
          ..write('bridgeId: $bridgeId, ')
          ..write('sessionId: $sessionId, ')
          ..write('t: $t, ')
          ..write('p1: $p1, ')
          ..write('p2: $p2, ')
          ..write('p3: $p3, ')
          ..write('p4: $p4, ')
          ..write('rssi: $rssi, ')
          ..write('unixMs: $unixMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(bridgeId, sessionId, t, p1, p2, p3, p4, rssi, unixMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SampleRow &&
          other.bridgeId == this.bridgeId &&
          other.sessionId == this.sessionId &&
          other.t == this.t &&
          other.p1 == this.p1 &&
          other.p2 == this.p2 &&
          other.p3 == this.p3 &&
          other.p4 == this.p4 &&
          other.rssi == this.rssi &&
          other.unixMs == this.unixMs);
}

class SamplesCompanion extends UpdateCompanion<SampleRow> {
  final Value<String> bridgeId;
  final Value<int> sessionId;
  final Value<int> t;
  final Value<int?> p1;
  final Value<int?> p2;
  final Value<int?> p3;
  final Value<int?> p4;
  final Value<int> rssi;
  final Value<int?> unixMs;
  final Value<int> rowid;
  const SamplesCompanion({
    this.bridgeId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.t = const Value.absent(),
    this.p1 = const Value.absent(),
    this.p2 = const Value.absent(),
    this.p3 = const Value.absent(),
    this.p4 = const Value.absent(),
    this.rssi = const Value.absent(),
    this.unixMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SamplesCompanion.insert({
    required String bridgeId,
    required int sessionId,
    required int t,
    this.p1 = const Value.absent(),
    this.p2 = const Value.absent(),
    this.p3 = const Value.absent(),
    this.p4 = const Value.absent(),
    this.rssi = const Value.absent(),
    this.unixMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bridgeId = Value(bridgeId),
       sessionId = Value(sessionId),
       t = Value(t);
  static Insertable<SampleRow> custom({
    Expression<String>? bridgeId,
    Expression<int>? sessionId,
    Expression<int>? t,
    Expression<int>? p1,
    Expression<int>? p2,
    Expression<int>? p3,
    Expression<int>? p4,
    Expression<int>? rssi,
    Expression<int>? unixMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bridgeId != null) 'bridge_id': bridgeId,
      if (sessionId != null) 'session_id': sessionId,
      if (t != null) 't': t,
      if (p1 != null) 'p1': p1,
      if (p2 != null) 'p2': p2,
      if (p3 != null) 'p3': p3,
      if (p4 != null) 'p4': p4,
      if (rssi != null) 'rssi': rssi,
      if (unixMs != null) 'unix_ms': unixMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SamplesCompanion copyWith({
    Value<String>? bridgeId,
    Value<int>? sessionId,
    Value<int>? t,
    Value<int?>? p1,
    Value<int?>? p2,
    Value<int?>? p3,
    Value<int?>? p4,
    Value<int>? rssi,
    Value<int?>? unixMs,
    Value<int>? rowid,
  }) {
    return SamplesCompanion(
      bridgeId: bridgeId ?? this.bridgeId,
      sessionId: sessionId ?? this.sessionId,
      t: t ?? this.t,
      p1: p1 ?? this.p1,
      p2: p2 ?? this.p2,
      p3: p3 ?? this.p3,
      p4: p4 ?? this.p4,
      rssi: rssi ?? this.rssi,
      unixMs: unixMs ?? this.unixMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bridgeId.present) {
      map['bridge_id'] = Variable<String>(bridgeId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (t.present) {
      map['t'] = Variable<int>(t.value);
    }
    if (p1.present) {
      map['p1'] = Variable<int>(p1.value);
    }
    if (p2.present) {
      map['p2'] = Variable<int>(p2.value);
    }
    if (p3.present) {
      map['p3'] = Variable<int>(p3.value);
    }
    if (p4.present) {
      map['p4'] = Variable<int>(p4.value);
    }
    if (rssi.present) {
      map['rssi'] = Variable<int>(rssi.value);
    }
    if (unixMs.present) {
      map['unix_ms'] = Variable<int>(unixMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SamplesCompanion(')
          ..write('bridgeId: $bridgeId, ')
          ..write('sessionId: $sessionId, ')
          ..write('t: $t, ')
          ..write('p1: $p1, ')
          ..write('p2: $p2, ')
          ..write('p3: $p3, ')
          ..write('p4: $p4, ')
          ..write('rssi: $rssi, ')
          ..write('unixMs: $unixMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GapsTable extends Gaps with TableInfo<$GapsTable, GapRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GapsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bridgeIdMeta = const VerificationMeta(
    'bridgeId',
  );
  @override
  late final GeneratedColumn<String> bridgeId = GeneratedColumn<String>(
    'bridge_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromTMeta = const VerificationMeta('fromT');
  @override
  late final GeneratedColumn<int> fromT = GeneratedColumn<int>(
    'from_t',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toTMeta = const VerificationMeta('toT');
  @override
  late final GeneratedColumn<int> toT = GeneratedColumn<int>(
    'to_t',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<int> reason = GeneratedColumn<int>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detectedUnixMsMeta = const VerificationMeta(
    'detectedUnixMs',
  );
  @override
  late final GeneratedColumn<int> detectedUnixMs = GeneratedColumn<int>(
    'detected_unix_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bridgeId,
    sessionId,
    fromT,
    toT,
    reason,
    detectedUnixMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gaps';
  @override
  VerificationContext validateIntegrity(
    Insertable<GapRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bridge_id')) {
      context.handle(
        _bridgeIdMeta,
        bridgeId.isAcceptableOrUnknown(data['bridge_id']!, _bridgeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bridgeIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('from_t')) {
      context.handle(
        _fromTMeta,
        fromT.isAcceptableOrUnknown(data['from_t']!, _fromTMeta),
      );
    } else if (isInserting) {
      context.missing(_fromTMeta);
    }
    if (data.containsKey('to_t')) {
      context.handle(
        _toTMeta,
        toT.isAcceptableOrUnknown(data['to_t']!, _toTMeta),
      );
    } else if (isInserting) {
      context.missing(_toTMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('detected_unix_ms')) {
      context.handle(
        _detectedUnixMsMeta,
        detectedUnixMs.isAcceptableOrUnknown(
          data['detected_unix_ms']!,
          _detectedUnixMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_detectedUnixMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    bridgeId,
    sessionId,
    fromT,
    toT,
    reason,
  };
  @override
  GapRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GapRow(
      bridgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bridge_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      fromT: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}from_t'],
      )!,
      toT: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}to_t'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reason'],
      )!,
      detectedUnixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}detected_unix_ms'],
      )!,
    );
  }

  @override
  $GapsTable createAlias(String alias) {
    return $GapsTable(attachedDatabase, alias);
  }
}

class GapRow extends DataClass implements Insertable<GapRow> {
  final String bridgeId;
  final int sessionId;
  final int fromT;
  final int toT;

  /// [GapReason] index.
  final int reason;
  final int detectedUnixMs;
  const GapRow({
    required this.bridgeId,
    required this.sessionId,
    required this.fromT,
    required this.toT,
    required this.reason,
    required this.detectedUnixMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['bridge_id'] = Variable<String>(bridgeId);
    map['session_id'] = Variable<int>(sessionId);
    map['from_t'] = Variable<int>(fromT);
    map['to_t'] = Variable<int>(toT);
    map['reason'] = Variable<int>(reason);
    map['detected_unix_ms'] = Variable<int>(detectedUnixMs);
    return map;
  }

  GapsCompanion toCompanion(bool nullToAbsent) {
    return GapsCompanion(
      bridgeId: Value(bridgeId),
      sessionId: Value(sessionId),
      fromT: Value(fromT),
      toT: Value(toT),
      reason: Value(reason),
      detectedUnixMs: Value(detectedUnixMs),
    );
  }

  factory GapRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GapRow(
      bridgeId: serializer.fromJson<String>(json['bridgeId']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      fromT: serializer.fromJson<int>(json['fromT']),
      toT: serializer.fromJson<int>(json['toT']),
      reason: serializer.fromJson<int>(json['reason']),
      detectedUnixMs: serializer.fromJson<int>(json['detectedUnixMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bridgeId': serializer.toJson<String>(bridgeId),
      'sessionId': serializer.toJson<int>(sessionId),
      'fromT': serializer.toJson<int>(fromT),
      'toT': serializer.toJson<int>(toT),
      'reason': serializer.toJson<int>(reason),
      'detectedUnixMs': serializer.toJson<int>(detectedUnixMs),
    };
  }

  GapRow copyWith({
    String? bridgeId,
    int? sessionId,
    int? fromT,
    int? toT,
    int? reason,
    int? detectedUnixMs,
  }) => GapRow(
    bridgeId: bridgeId ?? this.bridgeId,
    sessionId: sessionId ?? this.sessionId,
    fromT: fromT ?? this.fromT,
    toT: toT ?? this.toT,
    reason: reason ?? this.reason,
    detectedUnixMs: detectedUnixMs ?? this.detectedUnixMs,
  );
  GapRow copyWithCompanion(GapsCompanion data) {
    return GapRow(
      bridgeId: data.bridgeId.present ? data.bridgeId.value : this.bridgeId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      fromT: data.fromT.present ? data.fromT.value : this.fromT,
      toT: data.toT.present ? data.toT.value : this.toT,
      reason: data.reason.present ? data.reason.value : this.reason,
      detectedUnixMs: data.detectedUnixMs.present
          ? data.detectedUnixMs.value
          : this.detectedUnixMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GapRow(')
          ..write('bridgeId: $bridgeId, ')
          ..write('sessionId: $sessionId, ')
          ..write('fromT: $fromT, ')
          ..write('toT: $toT, ')
          ..write('reason: $reason, ')
          ..write('detectedUnixMs: $detectedUnixMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(bridgeId, sessionId, fromT, toT, reason, detectedUnixMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GapRow &&
          other.bridgeId == this.bridgeId &&
          other.sessionId == this.sessionId &&
          other.fromT == this.fromT &&
          other.toT == this.toT &&
          other.reason == this.reason &&
          other.detectedUnixMs == this.detectedUnixMs);
}

class GapsCompanion extends UpdateCompanion<GapRow> {
  final Value<String> bridgeId;
  final Value<int> sessionId;
  final Value<int> fromT;
  final Value<int> toT;
  final Value<int> reason;
  final Value<int> detectedUnixMs;
  final Value<int> rowid;
  const GapsCompanion({
    this.bridgeId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.fromT = const Value.absent(),
    this.toT = const Value.absent(),
    this.reason = const Value.absent(),
    this.detectedUnixMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GapsCompanion.insert({
    required String bridgeId,
    required int sessionId,
    required int fromT,
    required int toT,
    required int reason,
    required int detectedUnixMs,
    this.rowid = const Value.absent(),
  }) : bridgeId = Value(bridgeId),
       sessionId = Value(sessionId),
       fromT = Value(fromT),
       toT = Value(toT),
       reason = Value(reason),
       detectedUnixMs = Value(detectedUnixMs);
  static Insertable<GapRow> custom({
    Expression<String>? bridgeId,
    Expression<int>? sessionId,
    Expression<int>? fromT,
    Expression<int>? toT,
    Expression<int>? reason,
    Expression<int>? detectedUnixMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bridgeId != null) 'bridge_id': bridgeId,
      if (sessionId != null) 'session_id': sessionId,
      if (fromT != null) 'from_t': fromT,
      if (toT != null) 'to_t': toT,
      if (reason != null) 'reason': reason,
      if (detectedUnixMs != null) 'detected_unix_ms': detectedUnixMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GapsCompanion copyWith({
    Value<String>? bridgeId,
    Value<int>? sessionId,
    Value<int>? fromT,
    Value<int>? toT,
    Value<int>? reason,
    Value<int>? detectedUnixMs,
    Value<int>? rowid,
  }) {
    return GapsCompanion(
      bridgeId: bridgeId ?? this.bridgeId,
      sessionId: sessionId ?? this.sessionId,
      fromT: fromT ?? this.fromT,
      toT: toT ?? this.toT,
      reason: reason ?? this.reason,
      detectedUnixMs: detectedUnixMs ?? this.detectedUnixMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bridgeId.present) {
      map['bridge_id'] = Variable<String>(bridgeId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (fromT.present) {
      map['from_t'] = Variable<int>(fromT.value);
    }
    if (toT.present) {
      map['to_t'] = Variable<int>(toT.value);
    }
    if (reason.present) {
      map['reason'] = Variable<int>(reason.value);
    }
    if (detectedUnixMs.present) {
      map['detected_unix_ms'] = Variable<int>(detectedUnixMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GapsCompanion(')
          ..write('bridgeId: $bridgeId, ')
          ..write('sessionId: $sessionId, ')
          ..write('fromT: $fromT, ')
          ..write('toT: $toT, ')
          ..write('reason: $reason, ')
          ..write('detectedUnixMs: $detectedUnixMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStatesTable extends SyncStates
    with TableInfo<$SyncStatesTable, SyncStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bridgeIdMeta = const VerificationMeta(
    'bridgeId',
  );
  @override
  late final GeneratedColumn<String> bridgeId = GeneratedColumn<String>(
    'bridge_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _highWaterTMeta = const VerificationMeta(
    'highWaterT',
  );
  @override
  late final GeneratedColumn<int> highWaterT = GeneratedColumn<int>(
    'high_water_t',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(-1),
  );
  static const VerificationMeta _deviceMinTMeta = const VerificationMeta(
    'deviceMinT',
  );
  @override
  late final GeneratedColumn<int> deviceMinT = GeneratedColumn<int>(
    'device_min_t',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceMaxTMeta = const VerificationMeta(
    'deviceMaxT',
  );
  @override
  late final GeneratedColumn<int> deviceMaxT = GeneratedColumn<int>(
    'device_max_t',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncUnixMsMeta = const VerificationMeta(
    'lastSyncUnixMs',
  );
  @override
  late final GeneratedColumn<int> lastSyncUnixMs = GeneratedColumn<int>(
    'last_sync_unix_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completeMeta = const VerificationMeta(
    'complete',
  );
  @override
  late final GeneratedColumn<bool> complete = GeneratedColumn<bool>(
    'complete',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("complete" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    bridgeId,
    sessionId,
    highWaterT,
    deviceMinT,
    deviceMaxT,
    lastSyncUnixMs,
    complete,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bridge_id')) {
      context.handle(
        _bridgeIdMeta,
        bridgeId.isAcceptableOrUnknown(data['bridge_id']!, _bridgeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bridgeIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('high_water_t')) {
      context.handle(
        _highWaterTMeta,
        highWaterT.isAcceptableOrUnknown(
          data['high_water_t']!,
          _highWaterTMeta,
        ),
      );
    }
    if (data.containsKey('device_min_t')) {
      context.handle(
        _deviceMinTMeta,
        deviceMinT.isAcceptableOrUnknown(
          data['device_min_t']!,
          _deviceMinTMeta,
        ),
      );
    }
    if (data.containsKey('device_max_t')) {
      context.handle(
        _deviceMaxTMeta,
        deviceMaxT.isAcceptableOrUnknown(
          data['device_max_t']!,
          _deviceMaxTMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_unix_ms')) {
      context.handle(
        _lastSyncUnixMsMeta,
        lastSyncUnixMs.isAcceptableOrUnknown(
          data['last_sync_unix_ms']!,
          _lastSyncUnixMsMeta,
        ),
      );
    }
    if (data.containsKey('complete')) {
      context.handle(
        _completeMeta,
        complete.isAcceptableOrUnknown(data['complete']!, _completeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bridgeId, sessionId};
  @override
  SyncStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateRow(
      bridgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bridge_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      highWaterT: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}high_water_t'],
      )!,
      deviceMinT: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}device_min_t'],
      ),
      deviceMaxT: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}device_max_t'],
      ),
      lastSyncUnixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_sync_unix_ms'],
      ),
      complete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}complete'],
      )!,
    );
  }

  @override
  $SyncStatesTable createAlias(String alias) {
    return $SyncStatesTable(attachedDatabase, alias);
  }
}

class SyncStateRow extends DataClass implements Insertable<SyncStateRow> {
  final String bridgeId;
  final int sessionId;

  /// Highest `t` this phone has stored, or -1.
  final int highWaterT;

  /// The device's buffer extent as of the last read.
  final int? deviceMinT;
  final int? deviceMaxT;
  final int? lastSyncUnixMs;

  /// A closed session fully drained from the device. See [SyncState.complete].
  final bool complete;
  const SyncStateRow({
    required this.bridgeId,
    required this.sessionId,
    required this.highWaterT,
    this.deviceMinT,
    this.deviceMaxT,
    this.lastSyncUnixMs,
    required this.complete,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['bridge_id'] = Variable<String>(bridgeId);
    map['session_id'] = Variable<int>(sessionId);
    map['high_water_t'] = Variable<int>(highWaterT);
    if (!nullToAbsent || deviceMinT != null) {
      map['device_min_t'] = Variable<int>(deviceMinT);
    }
    if (!nullToAbsent || deviceMaxT != null) {
      map['device_max_t'] = Variable<int>(deviceMaxT);
    }
    if (!nullToAbsent || lastSyncUnixMs != null) {
      map['last_sync_unix_ms'] = Variable<int>(lastSyncUnixMs);
    }
    map['complete'] = Variable<bool>(complete);
    return map;
  }

  SyncStatesCompanion toCompanion(bool nullToAbsent) {
    return SyncStatesCompanion(
      bridgeId: Value(bridgeId),
      sessionId: Value(sessionId),
      highWaterT: Value(highWaterT),
      deviceMinT: deviceMinT == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceMinT),
      deviceMaxT: deviceMaxT == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceMaxT),
      lastSyncUnixMs: lastSyncUnixMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncUnixMs),
      complete: Value(complete),
    );
  }

  factory SyncStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateRow(
      bridgeId: serializer.fromJson<String>(json['bridgeId']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      highWaterT: serializer.fromJson<int>(json['highWaterT']),
      deviceMinT: serializer.fromJson<int?>(json['deviceMinT']),
      deviceMaxT: serializer.fromJson<int?>(json['deviceMaxT']),
      lastSyncUnixMs: serializer.fromJson<int?>(json['lastSyncUnixMs']),
      complete: serializer.fromJson<bool>(json['complete']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bridgeId': serializer.toJson<String>(bridgeId),
      'sessionId': serializer.toJson<int>(sessionId),
      'highWaterT': serializer.toJson<int>(highWaterT),
      'deviceMinT': serializer.toJson<int?>(deviceMinT),
      'deviceMaxT': serializer.toJson<int?>(deviceMaxT),
      'lastSyncUnixMs': serializer.toJson<int?>(lastSyncUnixMs),
      'complete': serializer.toJson<bool>(complete),
    };
  }

  SyncStateRow copyWith({
    String? bridgeId,
    int? sessionId,
    int? highWaterT,
    Value<int?> deviceMinT = const Value.absent(),
    Value<int?> deviceMaxT = const Value.absent(),
    Value<int?> lastSyncUnixMs = const Value.absent(),
    bool? complete,
  }) => SyncStateRow(
    bridgeId: bridgeId ?? this.bridgeId,
    sessionId: sessionId ?? this.sessionId,
    highWaterT: highWaterT ?? this.highWaterT,
    deviceMinT: deviceMinT.present ? deviceMinT.value : this.deviceMinT,
    deviceMaxT: deviceMaxT.present ? deviceMaxT.value : this.deviceMaxT,
    lastSyncUnixMs: lastSyncUnixMs.present
        ? lastSyncUnixMs.value
        : this.lastSyncUnixMs,
    complete: complete ?? this.complete,
  );
  SyncStateRow copyWithCompanion(SyncStatesCompanion data) {
    return SyncStateRow(
      bridgeId: data.bridgeId.present ? data.bridgeId.value : this.bridgeId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      highWaterT: data.highWaterT.present
          ? data.highWaterT.value
          : this.highWaterT,
      deviceMinT: data.deviceMinT.present
          ? data.deviceMinT.value
          : this.deviceMinT,
      deviceMaxT: data.deviceMaxT.present
          ? data.deviceMaxT.value
          : this.deviceMaxT,
      lastSyncUnixMs: data.lastSyncUnixMs.present
          ? data.lastSyncUnixMs.value
          : this.lastSyncUnixMs,
      complete: data.complete.present ? data.complete.value : this.complete,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateRow(')
          ..write('bridgeId: $bridgeId, ')
          ..write('sessionId: $sessionId, ')
          ..write('highWaterT: $highWaterT, ')
          ..write('deviceMinT: $deviceMinT, ')
          ..write('deviceMaxT: $deviceMaxT, ')
          ..write('lastSyncUnixMs: $lastSyncUnixMs, ')
          ..write('complete: $complete')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bridgeId,
    sessionId,
    highWaterT,
    deviceMinT,
    deviceMaxT,
    lastSyncUnixMs,
    complete,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateRow &&
          other.bridgeId == this.bridgeId &&
          other.sessionId == this.sessionId &&
          other.highWaterT == this.highWaterT &&
          other.deviceMinT == this.deviceMinT &&
          other.deviceMaxT == this.deviceMaxT &&
          other.lastSyncUnixMs == this.lastSyncUnixMs &&
          other.complete == this.complete);
}

class SyncStatesCompanion extends UpdateCompanion<SyncStateRow> {
  final Value<String> bridgeId;
  final Value<int> sessionId;
  final Value<int> highWaterT;
  final Value<int?> deviceMinT;
  final Value<int?> deviceMaxT;
  final Value<int?> lastSyncUnixMs;
  final Value<bool> complete;
  final Value<int> rowid;
  const SyncStatesCompanion({
    this.bridgeId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.highWaterT = const Value.absent(),
    this.deviceMinT = const Value.absent(),
    this.deviceMaxT = const Value.absent(),
    this.lastSyncUnixMs = const Value.absent(),
    this.complete = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStatesCompanion.insert({
    required String bridgeId,
    required int sessionId,
    this.highWaterT = const Value.absent(),
    this.deviceMinT = const Value.absent(),
    this.deviceMaxT = const Value.absent(),
    this.lastSyncUnixMs = const Value.absent(),
    this.complete = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bridgeId = Value(bridgeId),
       sessionId = Value(sessionId);
  static Insertable<SyncStateRow> custom({
    Expression<String>? bridgeId,
    Expression<int>? sessionId,
    Expression<int>? highWaterT,
    Expression<int>? deviceMinT,
    Expression<int>? deviceMaxT,
    Expression<int>? lastSyncUnixMs,
    Expression<bool>? complete,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bridgeId != null) 'bridge_id': bridgeId,
      if (sessionId != null) 'session_id': sessionId,
      if (highWaterT != null) 'high_water_t': highWaterT,
      if (deviceMinT != null) 'device_min_t': deviceMinT,
      if (deviceMaxT != null) 'device_max_t': deviceMaxT,
      if (lastSyncUnixMs != null) 'last_sync_unix_ms': lastSyncUnixMs,
      if (complete != null) 'complete': complete,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStatesCompanion copyWith({
    Value<String>? bridgeId,
    Value<int>? sessionId,
    Value<int>? highWaterT,
    Value<int?>? deviceMinT,
    Value<int?>? deviceMaxT,
    Value<int?>? lastSyncUnixMs,
    Value<bool>? complete,
    Value<int>? rowid,
  }) {
    return SyncStatesCompanion(
      bridgeId: bridgeId ?? this.bridgeId,
      sessionId: sessionId ?? this.sessionId,
      highWaterT: highWaterT ?? this.highWaterT,
      deviceMinT: deviceMinT ?? this.deviceMinT,
      deviceMaxT: deviceMaxT ?? this.deviceMaxT,
      lastSyncUnixMs: lastSyncUnixMs ?? this.lastSyncUnixMs,
      complete: complete ?? this.complete,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bridgeId.present) {
      map['bridge_id'] = Variable<String>(bridgeId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (highWaterT.present) {
      map['high_water_t'] = Variable<int>(highWaterT.value);
    }
    if (deviceMinT.present) {
      map['device_min_t'] = Variable<int>(deviceMinT.value);
    }
    if (deviceMaxT.present) {
      map['device_max_t'] = Variable<int>(deviceMaxT.value);
    }
    if (lastSyncUnixMs.present) {
      map['last_sync_unix_ms'] = Variable<int>(lastSyncUnixMs.value);
    }
    if (complete.present) {
      map['complete'] = Variable<bool>(complete.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStatesCompanion(')
          ..write('bridgeId: $bridgeId, ')
          ..write('sessionId: $sessionId, ')
          ..write('highWaterT: $highWaterT, ')
          ..write('deviceMinT: $deviceMinT, ')
          ..write('deviceMaxT: $deviceMaxT, ')
          ..write('lastSyncUnixMs: $lastSyncUnixMs, ')
          ..write('complete: $complete, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $SamplesTable samples = $SamplesTable(this);
  late final $GapsTable gaps = $GapsTable(this);
  late final $SyncStatesTable syncStates = $SyncStatesTable(this);
  late final Index idxSamplesUnix = Index(
    'idx_samples_unix',
    'CREATE INDEX idx_samples_unix ON samples (bridge_id, unix_ms)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sessions,
    samples,
    gaps,
    syncStates,
    idxSamplesUnix,
  ];
}

typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String bridgeId,
      required int sessionId,
      Value<String> name,
      Value<int?> startedUnixMs,
      Value<int?> endedUnixMs,
      Value<int> samplePeriodS,
      Value<int> sampleCount,
      Value<int> numProbes,
      Value<bool> closed,
      Value<bool> pinned,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> bridgeId,
      Value<int> sessionId,
      Value<String> name,
      Value<int?> startedUnixMs,
      Value<int?> endedUnixMs,
      Value<int> samplePeriodS,
      Value<int> sampleCount,
      Value<int> numProbes,
      Value<bool> closed,
      Value<bool> pinned,
      Value<int> rowid,
    });

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bridgeId => $composableBuilder(
    column: $table.bridgeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedUnixMs => $composableBuilder(
    column: $table.startedUnixMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedUnixMs => $composableBuilder(
    column: $table.endedUnixMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get samplePeriodS => $composableBuilder(
    column: $table.samplePeriodS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get numProbes => $composableBuilder(
    column: $table.numProbes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get closed => $composableBuilder(
    column: $table.closed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bridgeId => $composableBuilder(
    column: $table.bridgeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedUnixMs => $composableBuilder(
    column: $table.startedUnixMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedUnixMs => $composableBuilder(
    column: $table.endedUnixMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get samplePeriodS => $composableBuilder(
    column: $table.samplePeriodS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get numProbes => $composableBuilder(
    column: $table.numProbes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get closed => $composableBuilder(
    column: $table.closed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bridgeId =>
      $composableBuilder(column: $table.bridgeId, builder: (column) => column);

  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get startedUnixMs => $composableBuilder(
    column: $table.startedUnixMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endedUnixMs => $composableBuilder(
    column: $table.endedUnixMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get samplePeriodS => $composableBuilder(
    column: $table.samplePeriodS,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get numProbes =>
      $composableBuilder(column: $table.numProbes, builder: (column) => column);

  GeneratedColumn<bool> get closed =>
      $composableBuilder(column: $table.closed, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionsTable,
          SessionRow,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (
            SessionRow,
            BaseReferences<_$AppDatabase, $SessionsTable, SessionRow>,
          ),
          SessionRow,
          PrefetchHooks Function()
        > {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bridgeId = const Value.absent(),
                Value<int> sessionId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> startedUnixMs = const Value.absent(),
                Value<int?> endedUnixMs = const Value.absent(),
                Value<int> samplePeriodS = const Value.absent(),
                Value<int> sampleCount = const Value.absent(),
                Value<int> numProbes = const Value.absent(),
                Value<bool> closed = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                bridgeId: bridgeId,
                sessionId: sessionId,
                name: name,
                startedUnixMs: startedUnixMs,
                endedUnixMs: endedUnixMs,
                samplePeriodS: samplePeriodS,
                sampleCount: sampleCount,
                numProbes: numProbes,
                closed: closed,
                pinned: pinned,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bridgeId,
                required int sessionId,
                Value<String> name = const Value.absent(),
                Value<int?> startedUnixMs = const Value.absent(),
                Value<int?> endedUnixMs = const Value.absent(),
                Value<int> samplePeriodS = const Value.absent(),
                Value<int> sampleCount = const Value.absent(),
                Value<int> numProbes = const Value.absent(),
                Value<bool> closed = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                bridgeId: bridgeId,
                sessionId: sessionId,
                name: name,
                startedUnixMs: startedUnixMs,
                endedUnixMs: endedUnixMs,
                samplePeriodS: samplePeriodS,
                sampleCount: sampleCount,
                numProbes: numProbes,
                closed: closed,
                pinned: pinned,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionsTable, SessionRow>(table),
                  BaseReferences<_$AppDatabase, $SessionsTable, SessionRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionsTable,
      SessionRow,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (SessionRow, BaseReferences<_$AppDatabase, $SessionsTable, SessionRow>),
      SessionRow,
      PrefetchHooks Function()
    >;
typedef $$SamplesTableCreateCompanionBuilder =
    SamplesCompanion Function({
      required String bridgeId,
      required int sessionId,
      required int t,
      Value<int?> p1,
      Value<int?> p2,
      Value<int?> p3,
      Value<int?> p4,
      Value<int> rssi,
      Value<int?> unixMs,
      Value<int> rowid,
    });
typedef $$SamplesTableUpdateCompanionBuilder =
    SamplesCompanion Function({
      Value<String> bridgeId,
      Value<int> sessionId,
      Value<int> t,
      Value<int?> p1,
      Value<int?> p2,
      Value<int?> p3,
      Value<int?> p4,
      Value<int> rssi,
      Value<int?> unixMs,
      Value<int> rowid,
    });

class $$SamplesTableFilterComposer
    extends Composer<_$AppDatabase, $SamplesTable> {
  $$SamplesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bridgeId => $composableBuilder(
    column: $table.bridgeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get t => $composableBuilder(
    column: $table.t,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get p1 => $composableBuilder(
    column: $table.p1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get p2 => $composableBuilder(
    column: $table.p2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get p3 => $composableBuilder(
    column: $table.p3,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get p4 => $composableBuilder(
    column: $table.p4,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rssi => $composableBuilder(
    column: $table.rssi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unixMs => $composableBuilder(
    column: $table.unixMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SamplesTableOrderingComposer
    extends Composer<_$AppDatabase, $SamplesTable> {
  $$SamplesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bridgeId => $composableBuilder(
    column: $table.bridgeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get t => $composableBuilder(
    column: $table.t,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get p1 => $composableBuilder(
    column: $table.p1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get p2 => $composableBuilder(
    column: $table.p2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get p3 => $composableBuilder(
    column: $table.p3,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get p4 => $composableBuilder(
    column: $table.p4,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rssi => $composableBuilder(
    column: $table.rssi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unixMs => $composableBuilder(
    column: $table.unixMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SamplesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SamplesTable> {
  $$SamplesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bridgeId =>
      $composableBuilder(column: $table.bridgeId, builder: (column) => column);

  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get t =>
      $composableBuilder(column: $table.t, builder: (column) => column);

  GeneratedColumn<int> get p1 =>
      $composableBuilder(column: $table.p1, builder: (column) => column);

  GeneratedColumn<int> get p2 =>
      $composableBuilder(column: $table.p2, builder: (column) => column);

  GeneratedColumn<int> get p3 =>
      $composableBuilder(column: $table.p3, builder: (column) => column);

  GeneratedColumn<int> get p4 =>
      $composableBuilder(column: $table.p4, builder: (column) => column);

  GeneratedColumn<int> get rssi =>
      $composableBuilder(column: $table.rssi, builder: (column) => column);

  GeneratedColumn<int> get unixMs =>
      $composableBuilder(column: $table.unixMs, builder: (column) => column);
}

class $$SamplesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SamplesTable,
          SampleRow,
          $$SamplesTableFilterComposer,
          $$SamplesTableOrderingComposer,
          $$SamplesTableAnnotationComposer,
          $$SamplesTableCreateCompanionBuilder,
          $$SamplesTableUpdateCompanionBuilder,
          (SampleRow, BaseReferences<_$AppDatabase, $SamplesTable, SampleRow>),
          SampleRow,
          PrefetchHooks Function()
        > {
  $$SamplesTableTableManager(_$AppDatabase db, $SamplesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SamplesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SamplesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SamplesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bridgeId = const Value.absent(),
                Value<int> sessionId = const Value.absent(),
                Value<int> t = const Value.absent(),
                Value<int?> p1 = const Value.absent(),
                Value<int?> p2 = const Value.absent(),
                Value<int?> p3 = const Value.absent(),
                Value<int?> p4 = const Value.absent(),
                Value<int> rssi = const Value.absent(),
                Value<int?> unixMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SamplesCompanion(
                bridgeId: bridgeId,
                sessionId: sessionId,
                t: t,
                p1: p1,
                p2: p2,
                p3: p3,
                p4: p4,
                rssi: rssi,
                unixMs: unixMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bridgeId,
                required int sessionId,
                required int t,
                Value<int?> p1 = const Value.absent(),
                Value<int?> p2 = const Value.absent(),
                Value<int?> p3 = const Value.absent(),
                Value<int?> p4 = const Value.absent(),
                Value<int> rssi = const Value.absent(),
                Value<int?> unixMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SamplesCompanion.insert(
                bridgeId: bridgeId,
                sessionId: sessionId,
                t: t,
                p1: p1,
                p2: p2,
                p3: p3,
                p4: p4,
                rssi: rssi,
                unixMs: unixMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SamplesTable, SampleRow>(table),
                  BaseReferences<_$AppDatabase, $SamplesTable, SampleRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SamplesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SamplesTable,
      SampleRow,
      $$SamplesTableFilterComposer,
      $$SamplesTableOrderingComposer,
      $$SamplesTableAnnotationComposer,
      $$SamplesTableCreateCompanionBuilder,
      $$SamplesTableUpdateCompanionBuilder,
      (SampleRow, BaseReferences<_$AppDatabase, $SamplesTable, SampleRow>),
      SampleRow,
      PrefetchHooks Function()
    >;
typedef $$GapsTableCreateCompanionBuilder =
    GapsCompanion Function({
      required String bridgeId,
      required int sessionId,
      required int fromT,
      required int toT,
      required int reason,
      required int detectedUnixMs,
      Value<int> rowid,
    });
typedef $$GapsTableUpdateCompanionBuilder =
    GapsCompanion Function({
      Value<String> bridgeId,
      Value<int> sessionId,
      Value<int> fromT,
      Value<int> toT,
      Value<int> reason,
      Value<int> detectedUnixMs,
      Value<int> rowid,
    });

class $$GapsTableFilterComposer extends Composer<_$AppDatabase, $GapsTable> {
  $$GapsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bridgeId => $composableBuilder(
    column: $table.bridgeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fromT => $composableBuilder(
    column: $table.fromT,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get toT => $composableBuilder(
    column: $table.toT,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get detectedUnixMs => $composableBuilder(
    column: $table.detectedUnixMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GapsTableOrderingComposer extends Composer<_$AppDatabase, $GapsTable> {
  $$GapsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bridgeId => $composableBuilder(
    column: $table.bridgeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fromT => $composableBuilder(
    column: $table.fromT,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get toT => $composableBuilder(
    column: $table.toT,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get detectedUnixMs => $composableBuilder(
    column: $table.detectedUnixMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GapsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GapsTable> {
  $$GapsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bridgeId =>
      $composableBuilder(column: $table.bridgeId, builder: (column) => column);

  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get fromT =>
      $composableBuilder(column: $table.fromT, builder: (column) => column);

  GeneratedColumn<int> get toT =>
      $composableBuilder(column: $table.toT, builder: (column) => column);

  GeneratedColumn<int> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<int> get detectedUnixMs => $composableBuilder(
    column: $table.detectedUnixMs,
    builder: (column) => column,
  );
}

class $$GapsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GapsTable,
          GapRow,
          $$GapsTableFilterComposer,
          $$GapsTableOrderingComposer,
          $$GapsTableAnnotationComposer,
          $$GapsTableCreateCompanionBuilder,
          $$GapsTableUpdateCompanionBuilder,
          (GapRow, BaseReferences<_$AppDatabase, $GapsTable, GapRow>),
          GapRow,
          PrefetchHooks Function()
        > {
  $$GapsTableTableManager(_$AppDatabase db, $GapsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GapsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GapsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GapsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bridgeId = const Value.absent(),
                Value<int> sessionId = const Value.absent(),
                Value<int> fromT = const Value.absent(),
                Value<int> toT = const Value.absent(),
                Value<int> reason = const Value.absent(),
                Value<int> detectedUnixMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GapsCompanion(
                bridgeId: bridgeId,
                sessionId: sessionId,
                fromT: fromT,
                toT: toT,
                reason: reason,
                detectedUnixMs: detectedUnixMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bridgeId,
                required int sessionId,
                required int fromT,
                required int toT,
                required int reason,
                required int detectedUnixMs,
                Value<int> rowid = const Value.absent(),
              }) => GapsCompanion.insert(
                bridgeId: bridgeId,
                sessionId: sessionId,
                fromT: fromT,
                toT: toT,
                reason: reason,
                detectedUnixMs: detectedUnixMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GapsTable, GapRow>(table),
                  BaseReferences<_$AppDatabase, $GapsTable, GapRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GapsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GapsTable,
      GapRow,
      $$GapsTableFilterComposer,
      $$GapsTableOrderingComposer,
      $$GapsTableAnnotationComposer,
      $$GapsTableCreateCompanionBuilder,
      $$GapsTableUpdateCompanionBuilder,
      (GapRow, BaseReferences<_$AppDatabase, $GapsTable, GapRow>),
      GapRow,
      PrefetchHooks Function()
    >;
typedef $$SyncStatesTableCreateCompanionBuilder =
    SyncStatesCompanion Function({
      required String bridgeId,
      required int sessionId,
      Value<int> highWaterT,
      Value<int?> deviceMinT,
      Value<int?> deviceMaxT,
      Value<int?> lastSyncUnixMs,
      Value<bool> complete,
      Value<int> rowid,
    });
typedef $$SyncStatesTableUpdateCompanionBuilder =
    SyncStatesCompanion Function({
      Value<String> bridgeId,
      Value<int> sessionId,
      Value<int> highWaterT,
      Value<int?> deviceMinT,
      Value<int?> deviceMaxT,
      Value<int?> lastSyncUnixMs,
      Value<bool> complete,
      Value<int> rowid,
    });

class $$SyncStatesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bridgeId => $composableBuilder(
    column: $table.bridgeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get highWaterT => $composableBuilder(
    column: $table.highWaterT,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deviceMinT => $composableBuilder(
    column: $table.deviceMinT,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deviceMaxT => $composableBuilder(
    column: $table.deviceMaxT,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSyncUnixMs => $composableBuilder(
    column: $table.lastSyncUnixMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get complete => $composableBuilder(
    column: $table.complete,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bridgeId => $composableBuilder(
    column: $table.bridgeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get highWaterT => $composableBuilder(
    column: $table.highWaterT,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deviceMinT => $composableBuilder(
    column: $table.deviceMinT,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deviceMaxT => $composableBuilder(
    column: $table.deviceMaxT,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSyncUnixMs => $composableBuilder(
    column: $table.lastSyncUnixMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get complete => $composableBuilder(
    column: $table.complete,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bridgeId =>
      $composableBuilder(column: $table.bridgeId, builder: (column) => column);

  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get highWaterT => $composableBuilder(
    column: $table.highWaterT,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deviceMinT => $composableBuilder(
    column: $table.deviceMinT,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deviceMaxT => $composableBuilder(
    column: $table.deviceMaxT,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSyncUnixMs => $composableBuilder(
    column: $table.lastSyncUnixMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get complete =>
      $composableBuilder(column: $table.complete, builder: (column) => column);
}

class $$SyncStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStatesTable,
          SyncStateRow,
          $$SyncStatesTableFilterComposer,
          $$SyncStatesTableOrderingComposer,
          $$SyncStatesTableAnnotationComposer,
          $$SyncStatesTableCreateCompanionBuilder,
          $$SyncStatesTableUpdateCompanionBuilder,
          (
            SyncStateRow,
            BaseReferences<_$AppDatabase, $SyncStatesTable, SyncStateRow>,
          ),
          SyncStateRow,
          PrefetchHooks Function()
        > {
  $$SyncStatesTableTableManager(_$AppDatabase db, $SyncStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bridgeId = const Value.absent(),
                Value<int> sessionId = const Value.absent(),
                Value<int> highWaterT = const Value.absent(),
                Value<int?> deviceMinT = const Value.absent(),
                Value<int?> deviceMaxT = const Value.absent(),
                Value<int?> lastSyncUnixMs = const Value.absent(),
                Value<bool> complete = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion(
                bridgeId: bridgeId,
                sessionId: sessionId,
                highWaterT: highWaterT,
                deviceMinT: deviceMinT,
                deviceMaxT: deviceMaxT,
                lastSyncUnixMs: lastSyncUnixMs,
                complete: complete,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bridgeId,
                required int sessionId,
                Value<int> highWaterT = const Value.absent(),
                Value<int?> deviceMinT = const Value.absent(),
                Value<int?> deviceMaxT = const Value.absent(),
                Value<int?> lastSyncUnixMs = const Value.absent(),
                Value<bool> complete = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion.insert(
                bridgeId: bridgeId,
                sessionId: sessionId,
                highWaterT: highWaterT,
                deviceMinT: deviceMinT,
                deviceMaxT: deviceMaxT,
                lastSyncUnixMs: lastSyncUnixMs,
                complete: complete,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStatesTable, SyncStateRow>(table),
                  BaseReferences<_$AppDatabase, $SyncStatesTable, SyncStateRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStatesTable,
      SyncStateRow,
      $$SyncStatesTableFilterComposer,
      $$SyncStatesTableOrderingComposer,
      $$SyncStatesTableAnnotationComposer,
      $$SyncStatesTableCreateCompanionBuilder,
      $$SyncStatesTableUpdateCompanionBuilder,
      (
        SyncStateRow,
        BaseReferences<_$AppDatabase, $SyncStatesTable, SyncStateRow>,
      ),
      SyncStateRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$SamplesTableTableManager get samples =>
      $$SamplesTableTableManager(_db, _db.samples);
  $$GapsTableTableManager get gaps => $$GapsTableTableManager(_db, _db.gaps);
  $$SyncStatesTableTableManager get syncStates =>
      $$SyncStatesTableTableManager(_db, _db.syncStates);
}
