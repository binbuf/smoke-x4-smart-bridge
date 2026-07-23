// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $BridgesTable extends Bridges with TableInfo<$BridgesTable, BridgeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BridgesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
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
  static const VerificationMeta _lastSeenUnixMsMeta = const VerificationMeta(
    'lastSeenUnixMs',
  );
  @override
  late final GeneratedColumn<int> lastSeenUnixMs = GeneratedColumn<int>(
    'last_seen_unix_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, lastSeenUnixMs];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bridges';
  @override
  VerificationContext validateIntegrity(
    Insertable<BridgeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('last_seen_unix_ms')) {
      context.handle(
        _lastSeenUnixMsMeta,
        lastSeenUnixMs.isAcceptableOrUnknown(
          data['last_seen_unix_ms']!,
          _lastSeenUnixMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BridgeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BridgeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      lastSeenUnixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_unix_ms'],
      ),
    );
  }

  @override
  $BridgesTable createAlias(String alias) {
    return $BridgesTable(attachedDatabase, alias);
  }
}

class BridgeRow extends DataClass implements Insertable<BridgeRow> {
  final String id;
  final String name;
  final int? lastSeenUnixMs;
  const BridgeRow({required this.id, required this.name, this.lastSeenUnixMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || lastSeenUnixMs != null) {
      map['last_seen_unix_ms'] = Variable<int>(lastSeenUnixMs);
    }
    return map;
  }

  BridgesCompanion toCompanion(bool nullToAbsent) {
    return BridgesCompanion(
      id: Value(id),
      name: Value(name),
      lastSeenUnixMs: lastSeenUnixMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenUnixMs),
    );
  }

  factory BridgeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BridgeRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      lastSeenUnixMs: serializer.fromJson<int?>(json['lastSeenUnixMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'lastSeenUnixMs': serializer.toJson<int?>(lastSeenUnixMs),
    };
  }

  BridgeRow copyWith({
    String? id,
    String? name,
    Value<int?> lastSeenUnixMs = const Value.absent(),
  }) => BridgeRow(
    id: id ?? this.id,
    name: name ?? this.name,
    lastSeenUnixMs: lastSeenUnixMs.present
        ? lastSeenUnixMs.value
        : this.lastSeenUnixMs,
  );
  BridgeRow copyWithCompanion(BridgesCompanion data) {
    return BridgeRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      lastSeenUnixMs: data.lastSeenUnixMs.present
          ? data.lastSeenUnixMs.value
          : this.lastSeenUnixMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BridgeRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('lastSeenUnixMs: $lastSeenUnixMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, lastSeenUnixMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BridgeRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.lastSeenUnixMs == this.lastSeenUnixMs);
}

class BridgesCompanion extends UpdateCompanion<BridgeRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int?> lastSeenUnixMs;
  final Value<int> rowid;
  const BridgesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.lastSeenUnixMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BridgesCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    this.lastSeenUnixMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<BridgeRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? lastSeenUnixMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (lastSeenUnixMs != null) 'last_seen_unix_ms': lastSeenUnixMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BridgesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int?>? lastSeenUnixMs,
    Value<int>? rowid,
  }) {
    return BridgesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      lastSeenUnixMs: lastSeenUnixMs ?? this.lastSeenUnixMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (lastSeenUnixMs.present) {
      map['last_seen_unix_ms'] = Variable<int>(lastSeenUnixMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BridgesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('lastSeenUnixMs: $lastSeenUnixMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

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
  static const VerificationMeta _flagsMeta = const VerificationMeta('flags');
  @override
  late final GeneratedColumn<int> flags = GeneratedColumn<int>(
    'flags',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  @override
  List<GeneratedColumn> get $columns => [
    bridgeId,
    sessionId,
    t,
    p1,
    p2,
    p3,
    p4,
    flags,
    rssi,
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
    if (data.containsKey('flags')) {
      context.handle(
        _flagsMeta,
        flags.isAcceptableOrUnknown(data['flags']!, _flagsMeta),
      );
    }
    if (data.containsKey('rssi')) {
      context.handle(
        _rssiMeta,
        rssi.isAcceptableOrUnknown(data['rssi']!, _rssiMeta),
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
      flags: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}flags'],
      )!,
      rssi: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rssi'],
      )!,
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
  final int flags;
  final int rssi;
  const SampleRow({
    required this.bridgeId,
    required this.sessionId,
    required this.t,
    this.p1,
    this.p2,
    this.p3,
    this.p4,
    required this.flags,
    required this.rssi,
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
    map['flags'] = Variable<int>(flags);
    map['rssi'] = Variable<int>(rssi);
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
      flags: Value(flags),
      rssi: Value(rssi),
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
      flags: serializer.fromJson<int>(json['flags']),
      rssi: serializer.fromJson<int>(json['rssi']),
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
      'flags': serializer.toJson<int>(flags),
      'rssi': serializer.toJson<int>(rssi),
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
    int? flags,
    int? rssi,
  }) => SampleRow(
    bridgeId: bridgeId ?? this.bridgeId,
    sessionId: sessionId ?? this.sessionId,
    t: t ?? this.t,
    p1: p1.present ? p1.value : this.p1,
    p2: p2.present ? p2.value : this.p2,
    p3: p3.present ? p3.value : this.p3,
    p4: p4.present ? p4.value : this.p4,
    flags: flags ?? this.flags,
    rssi: rssi ?? this.rssi,
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
      flags: data.flags.present ? data.flags.value : this.flags,
      rssi: data.rssi.present ? data.rssi.value : this.rssi,
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
          ..write('flags: $flags, ')
          ..write('rssi: $rssi')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(bridgeId, sessionId, t, p1, p2, p3, p4, flags, rssi);
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
          other.flags == this.flags &&
          other.rssi == this.rssi);
}

class SamplesCompanion extends UpdateCompanion<SampleRow> {
  final Value<String> bridgeId;
  final Value<int> sessionId;
  final Value<int> t;
  final Value<int?> p1;
  final Value<int?> p2;
  final Value<int?> p3;
  final Value<int?> p4;
  final Value<int> flags;
  final Value<int> rssi;
  final Value<int> rowid;
  const SamplesCompanion({
    this.bridgeId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.t = const Value.absent(),
    this.p1 = const Value.absent(),
    this.p2 = const Value.absent(),
    this.p3 = const Value.absent(),
    this.p4 = const Value.absent(),
    this.flags = const Value.absent(),
    this.rssi = const Value.absent(),
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
    this.flags = const Value.absent(),
    this.rssi = const Value.absent(),
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
    Expression<int>? flags,
    Expression<int>? rssi,
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
      if (flags != null) 'flags': flags,
      if (rssi != null) 'rssi': rssi,
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
    Value<int>? flags,
    Value<int>? rssi,
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
      flags: flags ?? this.flags,
      rssi: rssi ?? this.rssi,
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
    if (flags.present) {
      map['flags'] = Variable<int>(flags.value);
    }
    if (rssi.present) {
      map['rssi'] = Variable<int>(rssi.value);
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
          ..write('flags: $flags, ')
          ..write('rssi: $rssi, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MarksTable extends Marks with TableInfo<$MarksTable, MarkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
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
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _probeMeta = const VerificationMeta('probe');
  @override
  late final GeneratedColumn<int> probe = GeneratedColumn<int>(
    'probe',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _text_Meta = const VerificationMeta('text_');
  @override
  late final GeneratedColumn<String> text_ = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bridgeId,
    sessionId,
    t,
    kind,
    probe,
    text_,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<MarkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
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
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('probe')) {
      context.handle(
        _probeMeta,
        probe.isAcceptableOrUnknown(data['probe']!, _probeMeta),
      );
    }
    if (data.containsKey('text')) {
      context.handle(
        _text_Meta,
        text_.isAcceptableOrUnknown(data['text']!, _text_Meta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MarkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MarkRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
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
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kind'],
      )!,
      probe: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}probe'],
      )!,
      text_: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
    );
  }

  @override
  $MarksTable createAlias(String alias) {
    return $MarksTable(attachedDatabase, alias);
  }
}

class MarkRow extends DataClass implements Insertable<MarkRow> {
  final int id;
  final String bridgeId;
  final int sessionId;
  final int t;
  final int kind;
  final int probe;
  final String text_;
  const MarkRow({
    required this.id,
    required this.bridgeId,
    required this.sessionId,
    required this.t,
    required this.kind,
    required this.probe,
    required this.text_,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['bridge_id'] = Variable<String>(bridgeId);
    map['session_id'] = Variable<int>(sessionId);
    map['t'] = Variable<int>(t);
    map['kind'] = Variable<int>(kind);
    map['probe'] = Variable<int>(probe);
    map['text'] = Variable<String>(text_);
    return map;
  }

  MarksCompanion toCompanion(bool nullToAbsent) {
    return MarksCompanion(
      id: Value(id),
      bridgeId: Value(bridgeId),
      sessionId: Value(sessionId),
      t: Value(t),
      kind: Value(kind),
      probe: Value(probe),
      text_: Value(text_),
    );
  }

  factory MarkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MarkRow(
      id: serializer.fromJson<int>(json['id']),
      bridgeId: serializer.fromJson<String>(json['bridgeId']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      t: serializer.fromJson<int>(json['t']),
      kind: serializer.fromJson<int>(json['kind']),
      probe: serializer.fromJson<int>(json['probe']),
      text_: serializer.fromJson<String>(json['text_']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bridgeId': serializer.toJson<String>(bridgeId),
      'sessionId': serializer.toJson<int>(sessionId),
      't': serializer.toJson<int>(t),
      'kind': serializer.toJson<int>(kind),
      'probe': serializer.toJson<int>(probe),
      'text_': serializer.toJson<String>(text_),
    };
  }

  MarkRow copyWith({
    int? id,
    String? bridgeId,
    int? sessionId,
    int? t,
    int? kind,
    int? probe,
    String? text_,
  }) => MarkRow(
    id: id ?? this.id,
    bridgeId: bridgeId ?? this.bridgeId,
    sessionId: sessionId ?? this.sessionId,
    t: t ?? this.t,
    kind: kind ?? this.kind,
    probe: probe ?? this.probe,
    text_: text_ ?? this.text_,
  );
  MarkRow copyWithCompanion(MarksCompanion data) {
    return MarkRow(
      id: data.id.present ? data.id.value : this.id,
      bridgeId: data.bridgeId.present ? data.bridgeId.value : this.bridgeId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      t: data.t.present ? data.t.value : this.t,
      kind: data.kind.present ? data.kind.value : this.kind,
      probe: data.probe.present ? data.probe.value : this.probe,
      text_: data.text_.present ? data.text_.value : this.text_,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MarkRow(')
          ..write('id: $id, ')
          ..write('bridgeId: $bridgeId, ')
          ..write('sessionId: $sessionId, ')
          ..write('t: $t, ')
          ..write('kind: $kind, ')
          ..write('probe: $probe, ')
          ..write('text_: $text_')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, bridgeId, sessionId, t, kind, probe, text_);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MarkRow &&
          other.id == this.id &&
          other.bridgeId == this.bridgeId &&
          other.sessionId == this.sessionId &&
          other.t == this.t &&
          other.kind == this.kind &&
          other.probe == this.probe &&
          other.text_ == this.text_);
}

class MarksCompanion extends UpdateCompanion<MarkRow> {
  final Value<int> id;
  final Value<String> bridgeId;
  final Value<int> sessionId;
  final Value<int> t;
  final Value<int> kind;
  final Value<int> probe;
  final Value<String> text_;
  const MarksCompanion({
    this.id = const Value.absent(),
    this.bridgeId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.t = const Value.absent(),
    this.kind = const Value.absent(),
    this.probe = const Value.absent(),
    this.text_ = const Value.absent(),
  });
  MarksCompanion.insert({
    this.id = const Value.absent(),
    required String bridgeId,
    required int sessionId,
    required int t,
    required int kind,
    this.probe = const Value.absent(),
    this.text_ = const Value.absent(),
  }) : bridgeId = Value(bridgeId),
       sessionId = Value(sessionId),
       t = Value(t),
       kind = Value(kind);
  static Insertable<MarkRow> custom({
    Expression<int>? id,
    Expression<String>? bridgeId,
    Expression<int>? sessionId,
    Expression<int>? t,
    Expression<int>? kind,
    Expression<int>? probe,
    Expression<String>? text_,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bridgeId != null) 'bridge_id': bridgeId,
      if (sessionId != null) 'session_id': sessionId,
      if (t != null) 't': t,
      if (kind != null) 'kind': kind,
      if (probe != null) 'probe': probe,
      if (text_ != null) 'text': text_,
    });
  }

  MarksCompanion copyWith({
    Value<int>? id,
    Value<String>? bridgeId,
    Value<int>? sessionId,
    Value<int>? t,
    Value<int>? kind,
    Value<int>? probe,
    Value<String>? text_,
  }) {
    return MarksCompanion(
      id: id ?? this.id,
      bridgeId: bridgeId ?? this.bridgeId,
      sessionId: sessionId ?? this.sessionId,
      t: t ?? this.t,
      kind: kind ?? this.kind,
      probe: probe ?? this.probe,
      text_: text_ ?? this.text_,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bridgeId.present) {
      map['bridge_id'] = Variable<String>(bridgeId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (t.present) {
      map['t'] = Variable<int>(t.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (probe.present) {
      map['probe'] = Variable<int>(probe.value);
    }
    if (text_.present) {
      map['text'] = Variable<String>(text_.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MarksCompanion(')
          ..write('id: $id, ')
          ..write('bridgeId: $bridgeId, ')
          ..write('sessionId: $sessionId, ')
          ..write('t: $t, ')
          ..write('kind: $kind, ')
          ..write('probe: $probe, ')
          ..write('text_: $text_')
          ..write(')'))
        .toString();
  }
}

class $AlarmLogTable extends AlarmLog
    with TableInfo<$AlarmLogTable, AlarmLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlarmLogTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
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
  static const VerificationMeta _unixMsMeta = const VerificationMeta('unixMs');
  @override
  late final GeneratedColumn<int> unixMs = GeneratedColumn<int>(
    'unix_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ruleMeta = const VerificationMeta('rule');
  @override
  late final GeneratedColumn<String> rule = GeneratedColumn<String>(
    'rule',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _probeMeta = const VerificationMeta('probe');
  @override
  late final GeneratedColumn<int> probe = GeneratedColumn<int>(
    'probe',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _valueF10Meta = const VerificationMeta(
    'valueF10',
  );
  @override
  late final GeneratedColumn<int> valueF10 = GeneratedColumn<int>(
    'value_f10',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bridgeId,
    unixMs,
    rule,
    probe,
    valueF10,
    action,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alarm_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlarmLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('bridge_id')) {
      context.handle(
        _bridgeIdMeta,
        bridgeId.isAcceptableOrUnknown(data['bridge_id']!, _bridgeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bridgeIdMeta);
    }
    if (data.containsKey('unix_ms')) {
      context.handle(
        _unixMsMeta,
        unixMs.isAcceptableOrUnknown(data['unix_ms']!, _unixMsMeta),
      );
    }
    if (data.containsKey('rule')) {
      context.handle(
        _ruleMeta,
        rule.isAcceptableOrUnknown(data['rule']!, _ruleMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleMeta);
    }
    if (data.containsKey('probe')) {
      context.handle(
        _probeMeta,
        probe.isAcceptableOrUnknown(data['probe']!, _probeMeta),
      );
    }
    if (data.containsKey('value_f10')) {
      context.handle(
        _valueF10Meta,
        valueF10.isAcceptableOrUnknown(data['value_f10']!, _valueF10Meta),
      );
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlarmLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlarmLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bridgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bridge_id'],
      )!,
      unixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unix_ms'],
      ),
      rule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule'],
      )!,
      probe: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}probe'],
      )!,
      valueF10: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value_f10'],
      ),
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
    );
  }

  @override
  $AlarmLogTable createAlias(String alias) {
    return $AlarmLogTable(attachedDatabase, alias);
  }
}

class AlarmLogRow extends DataClass implements Insertable<AlarmLogRow> {
  final int id;
  final String bridgeId;
  final int? unixMs;
  final String rule;
  final int probe;
  final int? valueF10;
  final String action;
  const AlarmLogRow({
    required this.id,
    required this.bridgeId,
    this.unixMs,
    required this.rule,
    required this.probe,
    this.valueF10,
    required this.action,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['bridge_id'] = Variable<String>(bridgeId);
    if (!nullToAbsent || unixMs != null) {
      map['unix_ms'] = Variable<int>(unixMs);
    }
    map['rule'] = Variable<String>(rule);
    map['probe'] = Variable<int>(probe);
    if (!nullToAbsent || valueF10 != null) {
      map['value_f10'] = Variable<int>(valueF10);
    }
    map['action'] = Variable<String>(action);
    return map;
  }

  AlarmLogCompanion toCompanion(bool nullToAbsent) {
    return AlarmLogCompanion(
      id: Value(id),
      bridgeId: Value(bridgeId),
      unixMs: unixMs == null && nullToAbsent
          ? const Value.absent()
          : Value(unixMs),
      rule: Value(rule),
      probe: Value(probe),
      valueF10: valueF10 == null && nullToAbsent
          ? const Value.absent()
          : Value(valueF10),
      action: Value(action),
    );
  }

  factory AlarmLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlarmLogRow(
      id: serializer.fromJson<int>(json['id']),
      bridgeId: serializer.fromJson<String>(json['bridgeId']),
      unixMs: serializer.fromJson<int?>(json['unixMs']),
      rule: serializer.fromJson<String>(json['rule']),
      probe: serializer.fromJson<int>(json['probe']),
      valueF10: serializer.fromJson<int?>(json['valueF10']),
      action: serializer.fromJson<String>(json['action']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bridgeId': serializer.toJson<String>(bridgeId),
      'unixMs': serializer.toJson<int?>(unixMs),
      'rule': serializer.toJson<String>(rule),
      'probe': serializer.toJson<int>(probe),
      'valueF10': serializer.toJson<int?>(valueF10),
      'action': serializer.toJson<String>(action),
    };
  }

  AlarmLogRow copyWith({
    int? id,
    String? bridgeId,
    Value<int?> unixMs = const Value.absent(),
    String? rule,
    int? probe,
    Value<int?> valueF10 = const Value.absent(),
    String? action,
  }) => AlarmLogRow(
    id: id ?? this.id,
    bridgeId: bridgeId ?? this.bridgeId,
    unixMs: unixMs.present ? unixMs.value : this.unixMs,
    rule: rule ?? this.rule,
    probe: probe ?? this.probe,
    valueF10: valueF10.present ? valueF10.value : this.valueF10,
    action: action ?? this.action,
  );
  AlarmLogRow copyWithCompanion(AlarmLogCompanion data) {
    return AlarmLogRow(
      id: data.id.present ? data.id.value : this.id,
      bridgeId: data.bridgeId.present ? data.bridgeId.value : this.bridgeId,
      unixMs: data.unixMs.present ? data.unixMs.value : this.unixMs,
      rule: data.rule.present ? data.rule.value : this.rule,
      probe: data.probe.present ? data.probe.value : this.probe,
      valueF10: data.valueF10.present ? data.valueF10.value : this.valueF10,
      action: data.action.present ? data.action.value : this.action,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlarmLogRow(')
          ..write('id: $id, ')
          ..write('bridgeId: $bridgeId, ')
          ..write('unixMs: $unixMs, ')
          ..write('rule: $rule, ')
          ..write('probe: $probe, ')
          ..write('valueF10: $valueF10, ')
          ..write('action: $action')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, bridgeId, unixMs, rule, probe, valueF10, action);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlarmLogRow &&
          other.id == this.id &&
          other.bridgeId == this.bridgeId &&
          other.unixMs == this.unixMs &&
          other.rule == this.rule &&
          other.probe == this.probe &&
          other.valueF10 == this.valueF10 &&
          other.action == this.action);
}

class AlarmLogCompanion extends UpdateCompanion<AlarmLogRow> {
  final Value<int> id;
  final Value<String> bridgeId;
  final Value<int?> unixMs;
  final Value<String> rule;
  final Value<int> probe;
  final Value<int?> valueF10;
  final Value<String> action;
  const AlarmLogCompanion({
    this.id = const Value.absent(),
    this.bridgeId = const Value.absent(),
    this.unixMs = const Value.absent(),
    this.rule = const Value.absent(),
    this.probe = const Value.absent(),
    this.valueF10 = const Value.absent(),
    this.action = const Value.absent(),
  });
  AlarmLogCompanion.insert({
    this.id = const Value.absent(),
    required String bridgeId,
    this.unixMs = const Value.absent(),
    required String rule,
    this.probe = const Value.absent(),
    this.valueF10 = const Value.absent(),
    required String action,
  }) : bridgeId = Value(bridgeId),
       rule = Value(rule),
       action = Value(action);
  static Insertable<AlarmLogRow> custom({
    Expression<int>? id,
    Expression<String>? bridgeId,
    Expression<int>? unixMs,
    Expression<String>? rule,
    Expression<int>? probe,
    Expression<int>? valueF10,
    Expression<String>? action,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bridgeId != null) 'bridge_id': bridgeId,
      if (unixMs != null) 'unix_ms': unixMs,
      if (rule != null) 'rule': rule,
      if (probe != null) 'probe': probe,
      if (valueF10 != null) 'value_f10': valueF10,
      if (action != null) 'action': action,
    });
  }

  AlarmLogCompanion copyWith({
    Value<int>? id,
    Value<String>? bridgeId,
    Value<int?>? unixMs,
    Value<String>? rule,
    Value<int>? probe,
    Value<int?>? valueF10,
    Value<String>? action,
  }) {
    return AlarmLogCompanion(
      id: id ?? this.id,
      bridgeId: bridgeId ?? this.bridgeId,
      unixMs: unixMs ?? this.unixMs,
      rule: rule ?? this.rule,
      probe: probe ?? this.probe,
      valueF10: valueF10 ?? this.valueF10,
      action: action ?? this.action,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bridgeId.present) {
      map['bridge_id'] = Variable<String>(bridgeId.value);
    }
    if (unixMs.present) {
      map['unix_ms'] = Variable<int>(unixMs.value);
    }
    if (rule.present) {
      map['rule'] = Variable<String>(rule.value);
    }
    if (probe.present) {
      map['probe'] = Variable<int>(probe.value);
    }
    if (valueF10.present) {
      map['value_f10'] = Variable<int>(valueF10.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlarmLogCompanion(')
          ..write('id: $id, ')
          ..write('bridgeId: $bridgeId, ')
          ..write('unixMs: $unixMs, ')
          ..write('rule: $rule, ')
          ..write('probe: $probe, ')
          ..write('valueF10: $valueF10, ')
          ..write('action: $action')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BridgesTable bridges = $BridgesTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $SamplesTable samples = $SamplesTable(this);
  late final $MarksTable marks = $MarksTable(this);
  late final $AlarmLogTable alarmLog = $AlarmLogTable(this);
  late final SessionDao sessionDao = SessionDao(this as AppDatabase);
  late final SampleDao sampleDao = SampleDao(this as AppDatabase);
  late final MarkDao markDao = MarkDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    bridges,
    sessions,
    samples,
    marks,
    alarmLog,
  ];
}

typedef $$BridgesTableCreateCompanionBuilder =
    BridgesCompanion Function({
      required String id,
      Value<String> name,
      Value<int?> lastSeenUnixMs,
      Value<int> rowid,
    });
typedef $$BridgesTableUpdateCompanionBuilder =
    BridgesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int?> lastSeenUnixMs,
      Value<int> rowid,
    });

class $$BridgesTableFilterComposer
    extends Composer<_$AppDatabase, $BridgesTable> {
  $$BridgesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenUnixMs => $composableBuilder(
    column: $table.lastSeenUnixMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BridgesTableOrderingComposer
    extends Composer<_$AppDatabase, $BridgesTable> {
  $$BridgesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenUnixMs => $composableBuilder(
    column: $table.lastSeenUnixMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BridgesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BridgesTable> {
  $$BridgesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get lastSeenUnixMs => $composableBuilder(
    column: $table.lastSeenUnixMs,
    builder: (column) => column,
  );
}

class $$BridgesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BridgesTable,
          BridgeRow,
          $$BridgesTableFilterComposer,
          $$BridgesTableOrderingComposer,
          $$BridgesTableAnnotationComposer,
          $$BridgesTableCreateCompanionBuilder,
          $$BridgesTableUpdateCompanionBuilder,
          (BridgeRow, BaseReferences<_$AppDatabase, $BridgesTable, BridgeRow>),
          BridgeRow,
          PrefetchHooks Function()
        > {
  $$BridgesTableTableManager(_$AppDatabase db, $BridgesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BridgesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BridgesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BridgesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> lastSeenUnixMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BridgesCompanion(
                id: id,
                name: name,
                lastSeenUnixMs: lastSeenUnixMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> name = const Value.absent(),
                Value<int?> lastSeenUnixMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BridgesCompanion.insert(
                id: id,
                name: name,
                lastSeenUnixMs: lastSeenUnixMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BridgesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BridgesTable,
      BridgeRow,
      $$BridgesTableFilterComposer,
      $$BridgesTableOrderingComposer,
      $$BridgesTableAnnotationComposer,
      $$BridgesTableCreateCompanionBuilder,
      $$BridgesTableUpdateCompanionBuilder,
      (BridgeRow, BaseReferences<_$AppDatabase, $BridgesTable, BridgeRow>),
      BridgeRow,
      PrefetchHooks Function()
    >;
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
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
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
      Value<int> flags,
      Value<int> rssi,
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
      Value<int> flags,
      Value<int> rssi,
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

  ColumnFilters<int> get flags => $composableBuilder(
    column: $table.flags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rssi => $composableBuilder(
    column: $table.rssi,
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

  ColumnOrderings<int> get flags => $composableBuilder(
    column: $table.flags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rssi => $composableBuilder(
    column: $table.rssi,
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

  GeneratedColumn<int> get flags =>
      $composableBuilder(column: $table.flags, builder: (column) => column);

  GeneratedColumn<int> get rssi =>
      $composableBuilder(column: $table.rssi, builder: (column) => column);
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
                Value<int> flags = const Value.absent(),
                Value<int> rssi = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SamplesCompanion(
                bridgeId: bridgeId,
                sessionId: sessionId,
                t: t,
                p1: p1,
                p2: p2,
                p3: p3,
                p4: p4,
                flags: flags,
                rssi: rssi,
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
                Value<int> flags = const Value.absent(),
                Value<int> rssi = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SamplesCompanion.insert(
                bridgeId: bridgeId,
                sessionId: sessionId,
                t: t,
                p1: p1,
                p2: p2,
                p3: p3,
                p4: p4,
                flags: flags,
                rssi: rssi,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
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
typedef $$MarksTableCreateCompanionBuilder =
    MarksCompanion Function({
      Value<int> id,
      required String bridgeId,
      required int sessionId,
      required int t,
      required int kind,
      Value<int> probe,
      Value<String> text_,
    });
typedef $$MarksTableUpdateCompanionBuilder =
    MarksCompanion Function({
      Value<int> id,
      Value<String> bridgeId,
      Value<int> sessionId,
      Value<int> t,
      Value<int> kind,
      Value<int> probe,
      Value<String> text_,
    });

class $$MarksTableFilterComposer extends Composer<_$AppDatabase, $MarksTable> {
  $$MarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

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

  ColumnFilters<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get probe => $composableBuilder(
    column: $table.probe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get text_ => $composableBuilder(
    column: $table.text_,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MarksTableOrderingComposer
    extends Composer<_$AppDatabase, $MarksTable> {
  $$MarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

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

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get probe => $composableBuilder(
    column: $table.probe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get text_ => $composableBuilder(
    column: $table.text_,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $MarksTable> {
  $$MarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bridgeId =>
      $composableBuilder(column: $table.bridgeId, builder: (column) => column);

  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get t =>
      $composableBuilder(column: $table.t, builder: (column) => column);

  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get probe =>
      $composableBuilder(column: $table.probe, builder: (column) => column);

  GeneratedColumn<String> get text_ =>
      $composableBuilder(column: $table.text_, builder: (column) => column);
}

class $$MarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MarksTable,
          MarkRow,
          $$MarksTableFilterComposer,
          $$MarksTableOrderingComposer,
          $$MarksTableAnnotationComposer,
          $$MarksTableCreateCompanionBuilder,
          $$MarksTableUpdateCompanionBuilder,
          (MarkRow, BaseReferences<_$AppDatabase, $MarksTable, MarkRow>),
          MarkRow,
          PrefetchHooks Function()
        > {
  $$MarksTableTableManager(_$AppDatabase db, $MarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bridgeId = const Value.absent(),
                Value<int> sessionId = const Value.absent(),
                Value<int> t = const Value.absent(),
                Value<int> kind = const Value.absent(),
                Value<int> probe = const Value.absent(),
                Value<String> text_ = const Value.absent(),
              }) => MarksCompanion(
                id: id,
                bridgeId: bridgeId,
                sessionId: sessionId,
                t: t,
                kind: kind,
                probe: probe,
                text_: text_,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String bridgeId,
                required int sessionId,
                required int t,
                required int kind,
                Value<int> probe = const Value.absent(),
                Value<String> text_ = const Value.absent(),
              }) => MarksCompanion.insert(
                id: id,
                bridgeId: bridgeId,
                sessionId: sessionId,
                t: t,
                kind: kind,
                probe: probe,
                text_: text_,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MarksTable,
      MarkRow,
      $$MarksTableFilterComposer,
      $$MarksTableOrderingComposer,
      $$MarksTableAnnotationComposer,
      $$MarksTableCreateCompanionBuilder,
      $$MarksTableUpdateCompanionBuilder,
      (MarkRow, BaseReferences<_$AppDatabase, $MarksTable, MarkRow>),
      MarkRow,
      PrefetchHooks Function()
    >;
typedef $$AlarmLogTableCreateCompanionBuilder =
    AlarmLogCompanion Function({
      Value<int> id,
      required String bridgeId,
      Value<int?> unixMs,
      required String rule,
      Value<int> probe,
      Value<int?> valueF10,
      required String action,
    });
typedef $$AlarmLogTableUpdateCompanionBuilder =
    AlarmLogCompanion Function({
      Value<int> id,
      Value<String> bridgeId,
      Value<int?> unixMs,
      Value<String> rule,
      Value<int> probe,
      Value<int?> valueF10,
      Value<String> action,
    });

class $$AlarmLogTableFilterComposer
    extends Composer<_$AppDatabase, $AlarmLogTable> {
  $$AlarmLogTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bridgeId => $composableBuilder(
    column: $table.bridgeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unixMs => $composableBuilder(
    column: $table.unixMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rule => $composableBuilder(
    column: $table.rule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get probe => $composableBuilder(
    column: $table.probe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get valueF10 => $composableBuilder(
    column: $table.valueF10,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlarmLogTableOrderingComposer
    extends Composer<_$AppDatabase, $AlarmLogTable> {
  $$AlarmLogTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bridgeId => $composableBuilder(
    column: $table.bridgeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unixMs => $composableBuilder(
    column: $table.unixMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rule => $composableBuilder(
    column: $table.rule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get probe => $composableBuilder(
    column: $table.probe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get valueF10 => $composableBuilder(
    column: $table.valueF10,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlarmLogTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlarmLogTable> {
  $$AlarmLogTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bridgeId =>
      $composableBuilder(column: $table.bridgeId, builder: (column) => column);

  GeneratedColumn<int> get unixMs =>
      $composableBuilder(column: $table.unixMs, builder: (column) => column);

  GeneratedColumn<String> get rule =>
      $composableBuilder(column: $table.rule, builder: (column) => column);

  GeneratedColumn<int> get probe =>
      $composableBuilder(column: $table.probe, builder: (column) => column);

  GeneratedColumn<int> get valueF10 =>
      $composableBuilder(column: $table.valueF10, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);
}

class $$AlarmLogTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlarmLogTable,
          AlarmLogRow,
          $$AlarmLogTableFilterComposer,
          $$AlarmLogTableOrderingComposer,
          $$AlarmLogTableAnnotationComposer,
          $$AlarmLogTableCreateCompanionBuilder,
          $$AlarmLogTableUpdateCompanionBuilder,
          (
            AlarmLogRow,
            BaseReferences<_$AppDatabase, $AlarmLogTable, AlarmLogRow>,
          ),
          AlarmLogRow,
          PrefetchHooks Function()
        > {
  $$AlarmLogTableTableManager(_$AppDatabase db, $AlarmLogTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlarmLogTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlarmLogTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlarmLogTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bridgeId = const Value.absent(),
                Value<int?> unixMs = const Value.absent(),
                Value<String> rule = const Value.absent(),
                Value<int> probe = const Value.absent(),
                Value<int?> valueF10 = const Value.absent(),
                Value<String> action = const Value.absent(),
              }) => AlarmLogCompanion(
                id: id,
                bridgeId: bridgeId,
                unixMs: unixMs,
                rule: rule,
                probe: probe,
                valueF10: valueF10,
                action: action,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String bridgeId,
                Value<int?> unixMs = const Value.absent(),
                required String rule,
                Value<int> probe = const Value.absent(),
                Value<int?> valueF10 = const Value.absent(),
                required String action,
              }) => AlarmLogCompanion.insert(
                id: id,
                bridgeId: bridgeId,
                unixMs: unixMs,
                rule: rule,
                probe: probe,
                valueF10: valueF10,
                action: action,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlarmLogTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlarmLogTable,
      AlarmLogRow,
      $$AlarmLogTableFilterComposer,
      $$AlarmLogTableOrderingComposer,
      $$AlarmLogTableAnnotationComposer,
      $$AlarmLogTableCreateCompanionBuilder,
      $$AlarmLogTableUpdateCompanionBuilder,
      (AlarmLogRow, BaseReferences<_$AppDatabase, $AlarmLogTable, AlarmLogRow>),
      AlarmLogRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BridgesTableTableManager get bridges =>
      $$BridgesTableTableManager(_db, _db.bridges);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$SamplesTableTableManager get samples =>
      $$SamplesTableTableManager(_db, _db.samples);
  $$MarksTableTableManager get marks =>
      $$MarksTableTableManager(_db, _db.marks);
  $$AlarmLogTableTableManager get alarmLog =>
      $$AlarmLogTableTableManager(_db, _db.alarmLog);
}

mixin _$SessionDaoMixin on DatabaseAccessor<AppDatabase> {
  $SessionsTable get sessions => attachedDatabase.sessions;
  $BridgesTable get bridges => attachedDatabase.bridges;
  SessionDaoManager get managers => SessionDaoManager(this);
}

class SessionDaoManager {
  final _$SessionDaoMixin _db;
  SessionDaoManager(this._db);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
  $$BridgesTableTableManager get bridges =>
      $$BridgesTableTableManager(_db.attachedDatabase, _db.bridges);
}

mixin _$SampleDaoMixin on DatabaseAccessor<AppDatabase> {
  $SamplesTable get samples => attachedDatabase.samples;
  SampleDaoManager get managers => SampleDaoManager(this);
}

class SampleDaoManager {
  final _$SampleDaoMixin _db;
  SampleDaoManager(this._db);
  $$SamplesTableTableManager get samples =>
      $$SamplesTableTableManager(_db.attachedDatabase, _db.samples);
}

mixin _$MarkDaoMixin on DatabaseAccessor<AppDatabase> {
  $MarksTable get marks => attachedDatabase.marks;
  MarkDaoManager get managers => MarkDaoManager(this);
}

class MarkDaoManager {
  final _$MarkDaoMixin _db;
  MarkDaoManager(this._db);
  $$MarksTableTableManager get marks =>
      $$MarksTableTableManager(_db.attachedDatabase, _db.marks);
}
