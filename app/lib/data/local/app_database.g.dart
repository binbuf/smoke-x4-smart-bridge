// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

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
    flags,
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
      flags: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}flags'],
      )!,
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
  final int flags;
  final int rssi;

  /// NULL when the bridge had no clock (I11).
  final int? unixMs;
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
    map['flags'] = Variable<int>(flags);
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
      flags: Value(flags),
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
      flags: serializer.fromJson<int>(json['flags']),
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
      'flags': serializer.toJson<int>(flags),
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
    int? flags,
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
    flags: flags ?? this.flags,
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
      flags: data.flags.present ? data.flags.value : this.flags,
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
          ..write('flags: $flags, ')
          ..write('rssi: $rssi, ')
          ..write('unixMs: $unixMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(bridgeId, sessionId, t, p1, p2, p3, p4, flags, rssi, unixMs);
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
  final Value<int> flags;
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
    this.flags = const Value.absent(),
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
    this.flags = const Value.absent(),
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
    Expression<int>? flags,
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
      if (flags != null) 'flags': flags,
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
    Value<int>? flags,
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
      flags: flags ?? this.flags,
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
    if (flags.present) {
      map['flags'] = Variable<int>(flags.value);
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
          ..write('flags: $flags, ')
          ..write('rssi: $rssi, ')
          ..write('unixMs: $unixMs, ')
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

class $CooksTable extends Cooks with TableInfo<$CooksTable, CookRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CooksTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _startUnixMsMeta = const VerificationMeta(
    'startUnixMs',
  );
  @override
  late final GeneratedColumn<int> startUnixMs = GeneratedColumn<int>(
    'start_unix_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endUnixMsMeta = const VerificationMeta(
    'endUnixMs',
  );
  @override
  late final GeneratedColumn<int> endUnixMs = GeneratedColumn<int>(
    'end_unix_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdUnixMsMeta = const VerificationMeta(
    'createdUnixMs',
  );
  @override
  late final GeneratedColumn<int> createdUnixMs = GeneratedColumn<int>(
    'created_unix_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _presetIdMeta = const VerificationMeta(
    'presetId',
  );
  @override
  late final GeneratedColumn<String> presetId = GeneratedColumn<String>(
    'preset_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hazardMeta = const VerificationMeta('hazard');
  @override
  late final GeneratedColumn<String> hazard = GeneratedColumn<String>(
    'hazard',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unstated'),
  );
  static const VerificationMeta _pitBandMinF10Meta = const VerificationMeta(
    'pitBandMinF10',
  );
  @override
  late final GeneratedColumn<int> pitBandMinF10 = GeneratedColumn<int>(
    'pit_band_min_f10',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pitBandMaxF10Meta = const VerificationMeta(
    'pitBandMaxF10',
  );
  @override
  late final GeneratedColumn<int> pitBandMaxF10 = GeneratedColumn<int>(
    'pit_band_max_f10',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _favouriteMeta = const VerificationMeta(
    'favourite',
  );
  @override
  late final GeneratedColumn<bool> favourite = GeneratedColumn<bool>(
    'favourite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favourite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _anchorSessionIdMeta = const VerificationMeta(
    'anchorSessionId',
  );
  @override
  late final GeneratedColumn<int> anchorSessionId = GeneratedColumn<int>(
    'anchor_session_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pulledAtUnixMsMeta = const VerificationMeta(
    'pulledAtUnixMs',
  );
  @override
  late final GeneratedColumn<int> pulledAtUnixMs = GeneratedColumn<int>(
    'pulled_at_unix_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bridgeId,
    name,
    startUnixMs,
    endUnixMs,
    createdUnixMs,
    notes,
    presetId,
    hazard,
    pitBandMinF10,
    pitBandMaxF10,
    favourite,
    anchorSessionId,
    pulledAtUnixMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cooks';
  @override
  VerificationContext validateIntegrity(
    Insertable<CookRow> instance, {
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
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('start_unix_ms')) {
      context.handle(
        _startUnixMsMeta,
        startUnixMs.isAcceptableOrUnknown(
          data['start_unix_ms']!,
          _startUnixMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startUnixMsMeta);
    }
    if (data.containsKey('end_unix_ms')) {
      context.handle(
        _endUnixMsMeta,
        endUnixMs.isAcceptableOrUnknown(data['end_unix_ms']!, _endUnixMsMeta),
      );
    }
    if (data.containsKey('created_unix_ms')) {
      context.handle(
        _createdUnixMsMeta,
        createdUnixMs.isAcceptableOrUnknown(
          data['created_unix_ms']!,
          _createdUnixMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdUnixMsMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('preset_id')) {
      context.handle(
        _presetIdMeta,
        presetId.isAcceptableOrUnknown(data['preset_id']!, _presetIdMeta),
      );
    }
    if (data.containsKey('hazard')) {
      context.handle(
        _hazardMeta,
        hazard.isAcceptableOrUnknown(data['hazard']!, _hazardMeta),
      );
    }
    if (data.containsKey('pit_band_min_f10')) {
      context.handle(
        _pitBandMinF10Meta,
        pitBandMinF10.isAcceptableOrUnknown(
          data['pit_band_min_f10']!,
          _pitBandMinF10Meta,
        ),
      );
    }
    if (data.containsKey('pit_band_max_f10')) {
      context.handle(
        _pitBandMaxF10Meta,
        pitBandMaxF10.isAcceptableOrUnknown(
          data['pit_band_max_f10']!,
          _pitBandMaxF10Meta,
        ),
      );
    }
    if (data.containsKey('favourite')) {
      context.handle(
        _favouriteMeta,
        favourite.isAcceptableOrUnknown(data['favourite']!, _favouriteMeta),
      );
    }
    if (data.containsKey('anchor_session_id')) {
      context.handle(
        _anchorSessionIdMeta,
        anchorSessionId.isAcceptableOrUnknown(
          data['anchor_session_id']!,
          _anchorSessionIdMeta,
        ),
      );
    }
    if (data.containsKey('pulled_at_unix_ms')) {
      context.handle(
        _pulledAtUnixMsMeta,
        pulledAtUnixMs.isAcceptableOrUnknown(
          data['pulled_at_unix_ms']!,
          _pulledAtUnixMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CookRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CookRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bridgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bridge_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      startUnixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_unix_ms'],
      )!,
      endUnixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_unix_ms'],
      ),
      createdUnixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_unix_ms'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      presetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preset_id'],
      ),
      hazard: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hazard'],
      )!,
      pitBandMinF10: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pit_band_min_f10'],
      ),
      pitBandMaxF10: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pit_band_max_f10'],
      ),
      favourite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favourite'],
      )!,
      anchorSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}anchor_session_id'],
      ),
      pulledAtUnixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pulled_at_unix_ms'],
      ),
    );
  }

  @override
  $CooksTable createAlias(String alias) {
    return $CooksTable(attachedDatabase, alias);
  }
}

class CookRow extends DataClass implements Insertable<CookRow> {
  final int id;
  final String bridgeId;
  final String name;
  final int startUnixMs;
  final int? endUnixMs;
  final int createdUnixMs;
  final String notes;
  final String? presetId;

  /// [HazardClass.name].
  final String hazard;
  final int? pitBandMinF10;
  final int? pitBandMaxF10;
  final bool favourite;

  /// Clockless fallback: pin to one device session when `samples.unixMs` is
  /// NULL for the whole cook.
  final int? anchorSessionId;

  /// When the user took the food off the heat. Never inferred.
  final int? pulledAtUnixMs;
  const CookRow({
    required this.id,
    required this.bridgeId,
    required this.name,
    required this.startUnixMs,
    this.endUnixMs,
    required this.createdUnixMs,
    required this.notes,
    this.presetId,
    required this.hazard,
    this.pitBandMinF10,
    this.pitBandMaxF10,
    required this.favourite,
    this.anchorSessionId,
    this.pulledAtUnixMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['bridge_id'] = Variable<String>(bridgeId);
    map['name'] = Variable<String>(name);
    map['start_unix_ms'] = Variable<int>(startUnixMs);
    if (!nullToAbsent || endUnixMs != null) {
      map['end_unix_ms'] = Variable<int>(endUnixMs);
    }
    map['created_unix_ms'] = Variable<int>(createdUnixMs);
    map['notes'] = Variable<String>(notes);
    if (!nullToAbsent || presetId != null) {
      map['preset_id'] = Variable<String>(presetId);
    }
    map['hazard'] = Variable<String>(hazard);
    if (!nullToAbsent || pitBandMinF10 != null) {
      map['pit_band_min_f10'] = Variable<int>(pitBandMinF10);
    }
    if (!nullToAbsent || pitBandMaxF10 != null) {
      map['pit_band_max_f10'] = Variable<int>(pitBandMaxF10);
    }
    map['favourite'] = Variable<bool>(favourite);
    if (!nullToAbsent || anchorSessionId != null) {
      map['anchor_session_id'] = Variable<int>(anchorSessionId);
    }
    if (!nullToAbsent || pulledAtUnixMs != null) {
      map['pulled_at_unix_ms'] = Variable<int>(pulledAtUnixMs);
    }
    return map;
  }

  CooksCompanion toCompanion(bool nullToAbsent) {
    return CooksCompanion(
      id: Value(id),
      bridgeId: Value(bridgeId),
      name: Value(name),
      startUnixMs: Value(startUnixMs),
      endUnixMs: endUnixMs == null && nullToAbsent
          ? const Value.absent()
          : Value(endUnixMs),
      createdUnixMs: Value(createdUnixMs),
      notes: Value(notes),
      presetId: presetId == null && nullToAbsent
          ? const Value.absent()
          : Value(presetId),
      hazard: Value(hazard),
      pitBandMinF10: pitBandMinF10 == null && nullToAbsent
          ? const Value.absent()
          : Value(pitBandMinF10),
      pitBandMaxF10: pitBandMaxF10 == null && nullToAbsent
          ? const Value.absent()
          : Value(pitBandMaxF10),
      favourite: Value(favourite),
      anchorSessionId: anchorSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(anchorSessionId),
      pulledAtUnixMs: pulledAtUnixMs == null && nullToAbsent
          ? const Value.absent()
          : Value(pulledAtUnixMs),
    );
  }

  factory CookRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CookRow(
      id: serializer.fromJson<int>(json['id']),
      bridgeId: serializer.fromJson<String>(json['bridgeId']),
      name: serializer.fromJson<String>(json['name']),
      startUnixMs: serializer.fromJson<int>(json['startUnixMs']),
      endUnixMs: serializer.fromJson<int?>(json['endUnixMs']),
      createdUnixMs: serializer.fromJson<int>(json['createdUnixMs']),
      notes: serializer.fromJson<String>(json['notes']),
      presetId: serializer.fromJson<String?>(json['presetId']),
      hazard: serializer.fromJson<String>(json['hazard']),
      pitBandMinF10: serializer.fromJson<int?>(json['pitBandMinF10']),
      pitBandMaxF10: serializer.fromJson<int?>(json['pitBandMaxF10']),
      favourite: serializer.fromJson<bool>(json['favourite']),
      anchorSessionId: serializer.fromJson<int?>(json['anchorSessionId']),
      pulledAtUnixMs: serializer.fromJson<int?>(json['pulledAtUnixMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bridgeId': serializer.toJson<String>(bridgeId),
      'name': serializer.toJson<String>(name),
      'startUnixMs': serializer.toJson<int>(startUnixMs),
      'endUnixMs': serializer.toJson<int?>(endUnixMs),
      'createdUnixMs': serializer.toJson<int>(createdUnixMs),
      'notes': serializer.toJson<String>(notes),
      'presetId': serializer.toJson<String?>(presetId),
      'hazard': serializer.toJson<String>(hazard),
      'pitBandMinF10': serializer.toJson<int?>(pitBandMinF10),
      'pitBandMaxF10': serializer.toJson<int?>(pitBandMaxF10),
      'favourite': serializer.toJson<bool>(favourite),
      'anchorSessionId': serializer.toJson<int?>(anchorSessionId),
      'pulledAtUnixMs': serializer.toJson<int?>(pulledAtUnixMs),
    };
  }

  CookRow copyWith({
    int? id,
    String? bridgeId,
    String? name,
    int? startUnixMs,
    Value<int?> endUnixMs = const Value.absent(),
    int? createdUnixMs,
    String? notes,
    Value<String?> presetId = const Value.absent(),
    String? hazard,
    Value<int?> pitBandMinF10 = const Value.absent(),
    Value<int?> pitBandMaxF10 = const Value.absent(),
    bool? favourite,
    Value<int?> anchorSessionId = const Value.absent(),
    Value<int?> pulledAtUnixMs = const Value.absent(),
  }) => CookRow(
    id: id ?? this.id,
    bridgeId: bridgeId ?? this.bridgeId,
    name: name ?? this.name,
    startUnixMs: startUnixMs ?? this.startUnixMs,
    endUnixMs: endUnixMs.present ? endUnixMs.value : this.endUnixMs,
    createdUnixMs: createdUnixMs ?? this.createdUnixMs,
    notes: notes ?? this.notes,
    presetId: presetId.present ? presetId.value : this.presetId,
    hazard: hazard ?? this.hazard,
    pitBandMinF10: pitBandMinF10.present
        ? pitBandMinF10.value
        : this.pitBandMinF10,
    pitBandMaxF10: pitBandMaxF10.present
        ? pitBandMaxF10.value
        : this.pitBandMaxF10,
    favourite: favourite ?? this.favourite,
    anchorSessionId: anchorSessionId.present
        ? anchorSessionId.value
        : this.anchorSessionId,
    pulledAtUnixMs: pulledAtUnixMs.present
        ? pulledAtUnixMs.value
        : this.pulledAtUnixMs,
  );
  CookRow copyWithCompanion(CooksCompanion data) {
    return CookRow(
      id: data.id.present ? data.id.value : this.id,
      bridgeId: data.bridgeId.present ? data.bridgeId.value : this.bridgeId,
      name: data.name.present ? data.name.value : this.name,
      startUnixMs: data.startUnixMs.present
          ? data.startUnixMs.value
          : this.startUnixMs,
      endUnixMs: data.endUnixMs.present ? data.endUnixMs.value : this.endUnixMs,
      createdUnixMs: data.createdUnixMs.present
          ? data.createdUnixMs.value
          : this.createdUnixMs,
      notes: data.notes.present ? data.notes.value : this.notes,
      presetId: data.presetId.present ? data.presetId.value : this.presetId,
      hazard: data.hazard.present ? data.hazard.value : this.hazard,
      pitBandMinF10: data.pitBandMinF10.present
          ? data.pitBandMinF10.value
          : this.pitBandMinF10,
      pitBandMaxF10: data.pitBandMaxF10.present
          ? data.pitBandMaxF10.value
          : this.pitBandMaxF10,
      favourite: data.favourite.present ? data.favourite.value : this.favourite,
      anchorSessionId: data.anchorSessionId.present
          ? data.anchorSessionId.value
          : this.anchorSessionId,
      pulledAtUnixMs: data.pulledAtUnixMs.present
          ? data.pulledAtUnixMs.value
          : this.pulledAtUnixMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CookRow(')
          ..write('id: $id, ')
          ..write('bridgeId: $bridgeId, ')
          ..write('name: $name, ')
          ..write('startUnixMs: $startUnixMs, ')
          ..write('endUnixMs: $endUnixMs, ')
          ..write('createdUnixMs: $createdUnixMs, ')
          ..write('notes: $notes, ')
          ..write('presetId: $presetId, ')
          ..write('hazard: $hazard, ')
          ..write('pitBandMinF10: $pitBandMinF10, ')
          ..write('pitBandMaxF10: $pitBandMaxF10, ')
          ..write('favourite: $favourite, ')
          ..write('anchorSessionId: $anchorSessionId, ')
          ..write('pulledAtUnixMs: $pulledAtUnixMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bridgeId,
    name,
    startUnixMs,
    endUnixMs,
    createdUnixMs,
    notes,
    presetId,
    hazard,
    pitBandMinF10,
    pitBandMaxF10,
    favourite,
    anchorSessionId,
    pulledAtUnixMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CookRow &&
          other.id == this.id &&
          other.bridgeId == this.bridgeId &&
          other.name == this.name &&
          other.startUnixMs == this.startUnixMs &&
          other.endUnixMs == this.endUnixMs &&
          other.createdUnixMs == this.createdUnixMs &&
          other.notes == this.notes &&
          other.presetId == this.presetId &&
          other.hazard == this.hazard &&
          other.pitBandMinF10 == this.pitBandMinF10 &&
          other.pitBandMaxF10 == this.pitBandMaxF10 &&
          other.favourite == this.favourite &&
          other.anchorSessionId == this.anchorSessionId &&
          other.pulledAtUnixMs == this.pulledAtUnixMs);
}

class CooksCompanion extends UpdateCompanion<CookRow> {
  final Value<int> id;
  final Value<String> bridgeId;
  final Value<String> name;
  final Value<int> startUnixMs;
  final Value<int?> endUnixMs;
  final Value<int> createdUnixMs;
  final Value<String> notes;
  final Value<String?> presetId;
  final Value<String> hazard;
  final Value<int?> pitBandMinF10;
  final Value<int?> pitBandMaxF10;
  final Value<bool> favourite;
  final Value<int?> anchorSessionId;
  final Value<int?> pulledAtUnixMs;
  const CooksCompanion({
    this.id = const Value.absent(),
    this.bridgeId = const Value.absent(),
    this.name = const Value.absent(),
    this.startUnixMs = const Value.absent(),
    this.endUnixMs = const Value.absent(),
    this.createdUnixMs = const Value.absent(),
    this.notes = const Value.absent(),
    this.presetId = const Value.absent(),
    this.hazard = const Value.absent(),
    this.pitBandMinF10 = const Value.absent(),
    this.pitBandMaxF10 = const Value.absent(),
    this.favourite = const Value.absent(),
    this.anchorSessionId = const Value.absent(),
    this.pulledAtUnixMs = const Value.absent(),
  });
  CooksCompanion.insert({
    this.id = const Value.absent(),
    required String bridgeId,
    this.name = const Value.absent(),
    required int startUnixMs,
    this.endUnixMs = const Value.absent(),
    required int createdUnixMs,
    this.notes = const Value.absent(),
    this.presetId = const Value.absent(),
    this.hazard = const Value.absent(),
    this.pitBandMinF10 = const Value.absent(),
    this.pitBandMaxF10 = const Value.absent(),
    this.favourite = const Value.absent(),
    this.anchorSessionId = const Value.absent(),
    this.pulledAtUnixMs = const Value.absent(),
  }) : bridgeId = Value(bridgeId),
       startUnixMs = Value(startUnixMs),
       createdUnixMs = Value(createdUnixMs);
  static Insertable<CookRow> custom({
    Expression<int>? id,
    Expression<String>? bridgeId,
    Expression<String>? name,
    Expression<int>? startUnixMs,
    Expression<int>? endUnixMs,
    Expression<int>? createdUnixMs,
    Expression<String>? notes,
    Expression<String>? presetId,
    Expression<String>? hazard,
    Expression<int>? pitBandMinF10,
    Expression<int>? pitBandMaxF10,
    Expression<bool>? favourite,
    Expression<int>? anchorSessionId,
    Expression<int>? pulledAtUnixMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bridgeId != null) 'bridge_id': bridgeId,
      if (name != null) 'name': name,
      if (startUnixMs != null) 'start_unix_ms': startUnixMs,
      if (endUnixMs != null) 'end_unix_ms': endUnixMs,
      if (createdUnixMs != null) 'created_unix_ms': createdUnixMs,
      if (notes != null) 'notes': notes,
      if (presetId != null) 'preset_id': presetId,
      if (hazard != null) 'hazard': hazard,
      if (pitBandMinF10 != null) 'pit_band_min_f10': pitBandMinF10,
      if (pitBandMaxF10 != null) 'pit_band_max_f10': pitBandMaxF10,
      if (favourite != null) 'favourite': favourite,
      if (anchorSessionId != null) 'anchor_session_id': anchorSessionId,
      if (pulledAtUnixMs != null) 'pulled_at_unix_ms': pulledAtUnixMs,
    });
  }

  CooksCompanion copyWith({
    Value<int>? id,
    Value<String>? bridgeId,
    Value<String>? name,
    Value<int>? startUnixMs,
    Value<int?>? endUnixMs,
    Value<int>? createdUnixMs,
    Value<String>? notes,
    Value<String?>? presetId,
    Value<String>? hazard,
    Value<int?>? pitBandMinF10,
    Value<int?>? pitBandMaxF10,
    Value<bool>? favourite,
    Value<int?>? anchorSessionId,
    Value<int?>? pulledAtUnixMs,
  }) {
    return CooksCompanion(
      id: id ?? this.id,
      bridgeId: bridgeId ?? this.bridgeId,
      name: name ?? this.name,
      startUnixMs: startUnixMs ?? this.startUnixMs,
      endUnixMs: endUnixMs ?? this.endUnixMs,
      createdUnixMs: createdUnixMs ?? this.createdUnixMs,
      notes: notes ?? this.notes,
      presetId: presetId ?? this.presetId,
      hazard: hazard ?? this.hazard,
      pitBandMinF10: pitBandMinF10 ?? this.pitBandMinF10,
      pitBandMaxF10: pitBandMaxF10 ?? this.pitBandMaxF10,
      favourite: favourite ?? this.favourite,
      anchorSessionId: anchorSessionId ?? this.anchorSessionId,
      pulledAtUnixMs: pulledAtUnixMs ?? this.pulledAtUnixMs,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (startUnixMs.present) {
      map['start_unix_ms'] = Variable<int>(startUnixMs.value);
    }
    if (endUnixMs.present) {
      map['end_unix_ms'] = Variable<int>(endUnixMs.value);
    }
    if (createdUnixMs.present) {
      map['created_unix_ms'] = Variable<int>(createdUnixMs.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (presetId.present) {
      map['preset_id'] = Variable<String>(presetId.value);
    }
    if (hazard.present) {
      map['hazard'] = Variable<String>(hazard.value);
    }
    if (pitBandMinF10.present) {
      map['pit_band_min_f10'] = Variable<int>(pitBandMinF10.value);
    }
    if (pitBandMaxF10.present) {
      map['pit_band_max_f10'] = Variable<int>(pitBandMaxF10.value);
    }
    if (favourite.present) {
      map['favourite'] = Variable<bool>(favourite.value);
    }
    if (anchorSessionId.present) {
      map['anchor_session_id'] = Variable<int>(anchorSessionId.value);
    }
    if (pulledAtUnixMs.present) {
      map['pulled_at_unix_ms'] = Variable<int>(pulledAtUnixMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CooksCompanion(')
          ..write('id: $id, ')
          ..write('bridgeId: $bridgeId, ')
          ..write('name: $name, ')
          ..write('startUnixMs: $startUnixMs, ')
          ..write('endUnixMs: $endUnixMs, ')
          ..write('createdUnixMs: $createdUnixMs, ')
          ..write('notes: $notes, ')
          ..write('presetId: $presetId, ')
          ..write('hazard: $hazard, ')
          ..write('pitBandMinF10: $pitBandMinF10, ')
          ..write('pitBandMaxF10: $pitBandMaxF10, ')
          ..write('favourite: $favourite, ')
          ..write('anchorSessionId: $anchorSessionId, ')
          ..write('pulledAtUnixMs: $pulledAtUnixMs')
          ..write(')'))
        .toString();
  }
}

class $CookProbeRolesTable extends CookProbeRoles
    with TableInfo<$CookProbeRolesTable, CookProbeRoleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CookProbeRolesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cookIdMeta = const VerificationMeta('cookId');
  @override
  late final GeneratedColumn<int> cookId = GeneratedColumn<int>(
    'cook_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES cooks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _jackMeta = const VerificationMeta('jack');
  @override
  late final GeneratedColumn<int> jack = GeneratedColumn<int>(
    'jack',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<int> role = GeneratedColumn<int>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _targetF10Meta = const VerificationMeta(
    'targetF10',
  );
  @override
  late final GeneratedColumn<int> targetF10 = GeneratedColumn<int>(
    'target_f10',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pullOffsetF10Meta = const VerificationMeta(
    'pullOffsetF10',
  );
  @override
  late final GeneratedColumn<int> pullOffsetF10 = GeneratedColumn<int>(
    'pull_offset_f10',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    cookId,
    jack,
    role,
    label,
    targetF10,
    pullOffsetF10,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cook_probe_roles';
  @override
  VerificationContext validateIntegrity(
    Insertable<CookProbeRoleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cook_id')) {
      context.handle(
        _cookIdMeta,
        cookId.isAcceptableOrUnknown(data['cook_id']!, _cookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cookIdMeta);
    }
    if (data.containsKey('jack')) {
      context.handle(
        _jackMeta,
        jack.isAcceptableOrUnknown(data['jack']!, _jackMeta),
      );
    } else if (isInserting) {
      context.missing(_jackMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('target_f10')) {
      context.handle(
        _targetF10Meta,
        targetF10.isAcceptableOrUnknown(data['target_f10']!, _targetF10Meta),
      );
    }
    if (data.containsKey('pull_offset_f10')) {
      context.handle(
        _pullOffsetF10Meta,
        pullOffsetF10.isAcceptableOrUnknown(
          data['pull_offset_f10']!,
          _pullOffsetF10Meta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cookId, jack};
  @override
  CookProbeRoleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CookProbeRoleRow(
      cookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cook_id'],
      )!,
      jack: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}jack'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}role'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      targetF10: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_f10'],
      ),
      pullOffsetF10: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pull_offset_f10'],
      )!,
    );
  }

  @override
  $CookProbeRolesTable createAlias(String alias) {
    return $CookProbeRolesTable(attachedDatabase, alias);
  }
}

class CookProbeRoleRow extends DataClass
    implements Insertable<CookProbeRoleRow> {
  final int cookId;
  final int jack;

  /// [ProbeRole] index.
  final int role;
  final String label;
  final int? targetF10;
  final int pullOffsetF10;
  const CookProbeRoleRow({
    required this.cookId,
    required this.jack,
    required this.role,
    required this.label,
    this.targetF10,
    required this.pullOffsetF10,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cook_id'] = Variable<int>(cookId);
    map['jack'] = Variable<int>(jack);
    map['role'] = Variable<int>(role);
    map['label'] = Variable<String>(label);
    if (!nullToAbsent || targetF10 != null) {
      map['target_f10'] = Variable<int>(targetF10);
    }
    map['pull_offset_f10'] = Variable<int>(pullOffsetF10);
    return map;
  }

  CookProbeRolesCompanion toCompanion(bool nullToAbsent) {
    return CookProbeRolesCompanion(
      cookId: Value(cookId),
      jack: Value(jack),
      role: Value(role),
      label: Value(label),
      targetF10: targetF10 == null && nullToAbsent
          ? const Value.absent()
          : Value(targetF10),
      pullOffsetF10: Value(pullOffsetF10),
    );
  }

  factory CookProbeRoleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CookProbeRoleRow(
      cookId: serializer.fromJson<int>(json['cookId']),
      jack: serializer.fromJson<int>(json['jack']),
      role: serializer.fromJson<int>(json['role']),
      label: serializer.fromJson<String>(json['label']),
      targetF10: serializer.fromJson<int?>(json['targetF10']),
      pullOffsetF10: serializer.fromJson<int>(json['pullOffsetF10']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cookId': serializer.toJson<int>(cookId),
      'jack': serializer.toJson<int>(jack),
      'role': serializer.toJson<int>(role),
      'label': serializer.toJson<String>(label),
      'targetF10': serializer.toJson<int?>(targetF10),
      'pullOffsetF10': serializer.toJson<int>(pullOffsetF10),
    };
  }

  CookProbeRoleRow copyWith({
    int? cookId,
    int? jack,
    int? role,
    String? label,
    Value<int?> targetF10 = const Value.absent(),
    int? pullOffsetF10,
  }) => CookProbeRoleRow(
    cookId: cookId ?? this.cookId,
    jack: jack ?? this.jack,
    role: role ?? this.role,
    label: label ?? this.label,
    targetF10: targetF10.present ? targetF10.value : this.targetF10,
    pullOffsetF10: pullOffsetF10 ?? this.pullOffsetF10,
  );
  CookProbeRoleRow copyWithCompanion(CookProbeRolesCompanion data) {
    return CookProbeRoleRow(
      cookId: data.cookId.present ? data.cookId.value : this.cookId,
      jack: data.jack.present ? data.jack.value : this.jack,
      role: data.role.present ? data.role.value : this.role,
      label: data.label.present ? data.label.value : this.label,
      targetF10: data.targetF10.present ? data.targetF10.value : this.targetF10,
      pullOffsetF10: data.pullOffsetF10.present
          ? data.pullOffsetF10.value
          : this.pullOffsetF10,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CookProbeRoleRow(')
          ..write('cookId: $cookId, ')
          ..write('jack: $jack, ')
          ..write('role: $role, ')
          ..write('label: $label, ')
          ..write('targetF10: $targetF10, ')
          ..write('pullOffsetF10: $pullOffsetF10')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(cookId, jack, role, label, targetF10, pullOffsetF10);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CookProbeRoleRow &&
          other.cookId == this.cookId &&
          other.jack == this.jack &&
          other.role == this.role &&
          other.label == this.label &&
          other.targetF10 == this.targetF10 &&
          other.pullOffsetF10 == this.pullOffsetF10);
}

class CookProbeRolesCompanion extends UpdateCompanion<CookProbeRoleRow> {
  final Value<int> cookId;
  final Value<int> jack;
  final Value<int> role;
  final Value<String> label;
  final Value<int?> targetF10;
  final Value<int> pullOffsetF10;
  final Value<int> rowid;
  const CookProbeRolesCompanion({
    this.cookId = const Value.absent(),
    this.jack = const Value.absent(),
    this.role = const Value.absent(),
    this.label = const Value.absent(),
    this.targetF10 = const Value.absent(),
    this.pullOffsetF10 = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CookProbeRolesCompanion.insert({
    required int cookId,
    required int jack,
    this.role = const Value.absent(),
    this.label = const Value.absent(),
    this.targetF10 = const Value.absent(),
    this.pullOffsetF10 = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : cookId = Value(cookId),
       jack = Value(jack);
  static Insertable<CookProbeRoleRow> custom({
    Expression<int>? cookId,
    Expression<int>? jack,
    Expression<int>? role,
    Expression<String>? label,
    Expression<int>? targetF10,
    Expression<int>? pullOffsetF10,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cookId != null) 'cook_id': cookId,
      if (jack != null) 'jack': jack,
      if (role != null) 'role': role,
      if (label != null) 'label': label,
      if (targetF10 != null) 'target_f10': targetF10,
      if (pullOffsetF10 != null) 'pull_offset_f10': pullOffsetF10,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CookProbeRolesCompanion copyWith({
    Value<int>? cookId,
    Value<int>? jack,
    Value<int>? role,
    Value<String>? label,
    Value<int?>? targetF10,
    Value<int>? pullOffsetF10,
    Value<int>? rowid,
  }) {
    return CookProbeRolesCompanion(
      cookId: cookId ?? this.cookId,
      jack: jack ?? this.jack,
      role: role ?? this.role,
      label: label ?? this.label,
      targetF10: targetF10 ?? this.targetF10,
      pullOffsetF10: pullOffsetF10 ?? this.pullOffsetF10,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cookId.present) {
      map['cook_id'] = Variable<int>(cookId.value);
    }
    if (jack.present) {
      map['jack'] = Variable<int>(jack.value);
    }
    if (role.present) {
      map['role'] = Variable<int>(role.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (targetF10.present) {
      map['target_f10'] = Variable<int>(targetF10.value);
    }
    if (pullOffsetF10.present) {
      map['pull_offset_f10'] = Variable<int>(pullOffsetF10.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CookProbeRolesCompanion(')
          ..write('cookId: $cookId, ')
          ..write('jack: $jack, ')
          ..write('role: $role, ')
          ..write('label: $label, ')
          ..write('targetF10: $targetF10, ')
          ..write('pullOffsetF10: $pullOffsetF10, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlarmRulesTable extends AlarmRules
    with TableInfo<$AlarmRulesTable, AlarmRuleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlarmRulesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<int> scope = GeneratedColumn<int>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jackMeta = const VerificationMeta('jack');
  @override
  late final GeneratedColumn<int> jack = GeneratedColumn<int>(
    'jack',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thresholdMeta = const VerificationMeta(
    'threshold',
  );
  @override
  late final GeneratedColumn<int> threshold = GeneratedColumn<int>(
    'threshold',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _windowSMeta = const VerificationMeta(
    'windowS',
  );
  @override
  late final GeneratedColumn<int> windowS = GeneratedColumn<int>(
    'window_s',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _pushedToDeviceMeta = const VerificationMeta(
    'pushedToDevice',
  );
  @override
  late final GeneratedColumn<bool> pushedToDevice = GeneratedColumn<bool>(
    'pushed_to_device',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pushed_to_device" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastConfirmedUnixMsMeta =
      const VerificationMeta('lastConfirmedUnixMs');
  @override
  late final GeneratedColumn<int> lastConfirmedUnixMs = GeneratedColumn<int>(
    'last_confirmed_unix_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cookIdMeta = const VerificationMeta('cookId');
  @override
  late final GeneratedColumn<int> cookId = GeneratedColumn<int>(
    'cook_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bridgeId,
    scope,
    jack,
    type,
    threshold,
    windowS,
    enabled,
    pushedToDevice,
    lastConfirmedUnixMs,
    cookId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alarm_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlarmRuleRow> instance, {
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
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('jack')) {
      context.handle(
        _jackMeta,
        jack.isAcceptableOrUnknown(data['jack']!, _jackMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('threshold')) {
      context.handle(
        _thresholdMeta,
        threshold.isAcceptableOrUnknown(data['threshold']!, _thresholdMeta),
      );
    }
    if (data.containsKey('window_s')) {
      context.handle(
        _windowSMeta,
        windowS.isAcceptableOrUnknown(data['window_s']!, _windowSMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('pushed_to_device')) {
      context.handle(
        _pushedToDeviceMeta,
        pushedToDevice.isAcceptableOrUnknown(
          data['pushed_to_device']!,
          _pushedToDeviceMeta,
        ),
      );
    }
    if (data.containsKey('last_confirmed_unix_ms')) {
      context.handle(
        _lastConfirmedUnixMsMeta,
        lastConfirmedUnixMs.isAcceptableOrUnknown(
          data['last_confirmed_unix_ms']!,
          _lastConfirmedUnixMsMeta,
        ),
      );
    }
    if (data.containsKey('cook_id')) {
      context.handle(
        _cookIdMeta,
        cookId.isAcceptableOrUnknown(data['cook_id']!, _cookIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlarmRuleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlarmRuleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bridgeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bridge_id'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scope'],
      )!,
      jack: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}jack'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      threshold: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}threshold'],
      ),
      windowS: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}window_s'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      pushedToDevice: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pushed_to_device'],
      )!,
      lastConfirmedUnixMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_confirmed_unix_ms'],
      ),
      cookId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cook_id'],
      ),
    );
  }

  @override
  $AlarmRulesTable createAlias(String alias) {
    return $AlarmRulesTable(attachedDatabase, alias);
  }
}

class AlarmRuleRow extends DataClass implements Insertable<AlarmRuleRow> {
  final int id;
  final String bridgeId;

  /// 0 = device tier, 1 = app tier.
  final int scope;

  /// NULL = whole cook; 1..4 = one jack.
  final int? jack;

  /// [AlarmRuleType.name].
  final String type;
  final int? threshold;
  final int? windowS;
  final bool enabled;
  final bool pushedToDevice;
  final int? lastConfirmedUnixMs;
  final int? cookId;
  const AlarmRuleRow({
    required this.id,
    required this.bridgeId,
    required this.scope,
    this.jack,
    required this.type,
    this.threshold,
    this.windowS,
    required this.enabled,
    required this.pushedToDevice,
    this.lastConfirmedUnixMs,
    this.cookId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['bridge_id'] = Variable<String>(bridgeId);
    map['scope'] = Variable<int>(scope);
    if (!nullToAbsent || jack != null) {
      map['jack'] = Variable<int>(jack);
    }
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || threshold != null) {
      map['threshold'] = Variable<int>(threshold);
    }
    if (!nullToAbsent || windowS != null) {
      map['window_s'] = Variable<int>(windowS);
    }
    map['enabled'] = Variable<bool>(enabled);
    map['pushed_to_device'] = Variable<bool>(pushedToDevice);
    if (!nullToAbsent || lastConfirmedUnixMs != null) {
      map['last_confirmed_unix_ms'] = Variable<int>(lastConfirmedUnixMs);
    }
    if (!nullToAbsent || cookId != null) {
      map['cook_id'] = Variable<int>(cookId);
    }
    return map;
  }

  AlarmRulesCompanion toCompanion(bool nullToAbsent) {
    return AlarmRulesCompanion(
      id: Value(id),
      bridgeId: Value(bridgeId),
      scope: Value(scope),
      jack: jack == null && nullToAbsent ? const Value.absent() : Value(jack),
      type: Value(type),
      threshold: threshold == null && nullToAbsent
          ? const Value.absent()
          : Value(threshold),
      windowS: windowS == null && nullToAbsent
          ? const Value.absent()
          : Value(windowS),
      enabled: Value(enabled),
      pushedToDevice: Value(pushedToDevice),
      lastConfirmedUnixMs: lastConfirmedUnixMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConfirmedUnixMs),
      cookId: cookId == null && nullToAbsent
          ? const Value.absent()
          : Value(cookId),
    );
  }

  factory AlarmRuleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlarmRuleRow(
      id: serializer.fromJson<int>(json['id']),
      bridgeId: serializer.fromJson<String>(json['bridgeId']),
      scope: serializer.fromJson<int>(json['scope']),
      jack: serializer.fromJson<int?>(json['jack']),
      type: serializer.fromJson<String>(json['type']),
      threshold: serializer.fromJson<int?>(json['threshold']),
      windowS: serializer.fromJson<int?>(json['windowS']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      pushedToDevice: serializer.fromJson<bool>(json['pushedToDevice']),
      lastConfirmedUnixMs: serializer.fromJson<int?>(
        json['lastConfirmedUnixMs'],
      ),
      cookId: serializer.fromJson<int?>(json['cookId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bridgeId': serializer.toJson<String>(bridgeId),
      'scope': serializer.toJson<int>(scope),
      'jack': serializer.toJson<int?>(jack),
      'type': serializer.toJson<String>(type),
      'threshold': serializer.toJson<int?>(threshold),
      'windowS': serializer.toJson<int?>(windowS),
      'enabled': serializer.toJson<bool>(enabled),
      'pushedToDevice': serializer.toJson<bool>(pushedToDevice),
      'lastConfirmedUnixMs': serializer.toJson<int?>(lastConfirmedUnixMs),
      'cookId': serializer.toJson<int?>(cookId),
    };
  }

  AlarmRuleRow copyWith({
    int? id,
    String? bridgeId,
    int? scope,
    Value<int?> jack = const Value.absent(),
    String? type,
    Value<int?> threshold = const Value.absent(),
    Value<int?> windowS = const Value.absent(),
    bool? enabled,
    bool? pushedToDevice,
    Value<int?> lastConfirmedUnixMs = const Value.absent(),
    Value<int?> cookId = const Value.absent(),
  }) => AlarmRuleRow(
    id: id ?? this.id,
    bridgeId: bridgeId ?? this.bridgeId,
    scope: scope ?? this.scope,
    jack: jack.present ? jack.value : this.jack,
    type: type ?? this.type,
    threshold: threshold.present ? threshold.value : this.threshold,
    windowS: windowS.present ? windowS.value : this.windowS,
    enabled: enabled ?? this.enabled,
    pushedToDevice: pushedToDevice ?? this.pushedToDevice,
    lastConfirmedUnixMs: lastConfirmedUnixMs.present
        ? lastConfirmedUnixMs.value
        : this.lastConfirmedUnixMs,
    cookId: cookId.present ? cookId.value : this.cookId,
  );
  AlarmRuleRow copyWithCompanion(AlarmRulesCompanion data) {
    return AlarmRuleRow(
      id: data.id.present ? data.id.value : this.id,
      bridgeId: data.bridgeId.present ? data.bridgeId.value : this.bridgeId,
      scope: data.scope.present ? data.scope.value : this.scope,
      jack: data.jack.present ? data.jack.value : this.jack,
      type: data.type.present ? data.type.value : this.type,
      threshold: data.threshold.present ? data.threshold.value : this.threshold,
      windowS: data.windowS.present ? data.windowS.value : this.windowS,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      pushedToDevice: data.pushedToDevice.present
          ? data.pushedToDevice.value
          : this.pushedToDevice,
      lastConfirmedUnixMs: data.lastConfirmedUnixMs.present
          ? data.lastConfirmedUnixMs.value
          : this.lastConfirmedUnixMs,
      cookId: data.cookId.present ? data.cookId.value : this.cookId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlarmRuleRow(')
          ..write('id: $id, ')
          ..write('bridgeId: $bridgeId, ')
          ..write('scope: $scope, ')
          ..write('jack: $jack, ')
          ..write('type: $type, ')
          ..write('threshold: $threshold, ')
          ..write('windowS: $windowS, ')
          ..write('enabled: $enabled, ')
          ..write('pushedToDevice: $pushedToDevice, ')
          ..write('lastConfirmedUnixMs: $lastConfirmedUnixMs, ')
          ..write('cookId: $cookId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bridgeId,
    scope,
    jack,
    type,
    threshold,
    windowS,
    enabled,
    pushedToDevice,
    lastConfirmedUnixMs,
    cookId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlarmRuleRow &&
          other.id == this.id &&
          other.bridgeId == this.bridgeId &&
          other.scope == this.scope &&
          other.jack == this.jack &&
          other.type == this.type &&
          other.threshold == this.threshold &&
          other.windowS == this.windowS &&
          other.enabled == this.enabled &&
          other.pushedToDevice == this.pushedToDevice &&
          other.lastConfirmedUnixMs == this.lastConfirmedUnixMs &&
          other.cookId == this.cookId);
}

class AlarmRulesCompanion extends UpdateCompanion<AlarmRuleRow> {
  final Value<int> id;
  final Value<String> bridgeId;
  final Value<int> scope;
  final Value<int?> jack;
  final Value<String> type;
  final Value<int?> threshold;
  final Value<int?> windowS;
  final Value<bool> enabled;
  final Value<bool> pushedToDevice;
  final Value<int?> lastConfirmedUnixMs;
  final Value<int?> cookId;
  const AlarmRulesCompanion({
    this.id = const Value.absent(),
    this.bridgeId = const Value.absent(),
    this.scope = const Value.absent(),
    this.jack = const Value.absent(),
    this.type = const Value.absent(),
    this.threshold = const Value.absent(),
    this.windowS = const Value.absent(),
    this.enabled = const Value.absent(),
    this.pushedToDevice = const Value.absent(),
    this.lastConfirmedUnixMs = const Value.absent(),
    this.cookId = const Value.absent(),
  });
  AlarmRulesCompanion.insert({
    this.id = const Value.absent(),
    required String bridgeId,
    required int scope,
    this.jack = const Value.absent(),
    required String type,
    this.threshold = const Value.absent(),
    this.windowS = const Value.absent(),
    this.enabled = const Value.absent(),
    this.pushedToDevice = const Value.absent(),
    this.lastConfirmedUnixMs = const Value.absent(),
    this.cookId = const Value.absent(),
  }) : bridgeId = Value(bridgeId),
       scope = Value(scope),
       type = Value(type);
  static Insertable<AlarmRuleRow> custom({
    Expression<int>? id,
    Expression<String>? bridgeId,
    Expression<int>? scope,
    Expression<int>? jack,
    Expression<String>? type,
    Expression<int>? threshold,
    Expression<int>? windowS,
    Expression<bool>? enabled,
    Expression<bool>? pushedToDevice,
    Expression<int>? lastConfirmedUnixMs,
    Expression<int>? cookId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bridgeId != null) 'bridge_id': bridgeId,
      if (scope != null) 'scope': scope,
      if (jack != null) 'jack': jack,
      if (type != null) 'type': type,
      if (threshold != null) 'threshold': threshold,
      if (windowS != null) 'window_s': windowS,
      if (enabled != null) 'enabled': enabled,
      if (pushedToDevice != null) 'pushed_to_device': pushedToDevice,
      if (lastConfirmedUnixMs != null)
        'last_confirmed_unix_ms': lastConfirmedUnixMs,
      if (cookId != null) 'cook_id': cookId,
    });
  }

  AlarmRulesCompanion copyWith({
    Value<int>? id,
    Value<String>? bridgeId,
    Value<int>? scope,
    Value<int?>? jack,
    Value<String>? type,
    Value<int?>? threshold,
    Value<int?>? windowS,
    Value<bool>? enabled,
    Value<bool>? pushedToDevice,
    Value<int?>? lastConfirmedUnixMs,
    Value<int?>? cookId,
  }) {
    return AlarmRulesCompanion(
      id: id ?? this.id,
      bridgeId: bridgeId ?? this.bridgeId,
      scope: scope ?? this.scope,
      jack: jack ?? this.jack,
      type: type ?? this.type,
      threshold: threshold ?? this.threshold,
      windowS: windowS ?? this.windowS,
      enabled: enabled ?? this.enabled,
      pushedToDevice: pushedToDevice ?? this.pushedToDevice,
      lastConfirmedUnixMs: lastConfirmedUnixMs ?? this.lastConfirmedUnixMs,
      cookId: cookId ?? this.cookId,
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
    if (scope.present) {
      map['scope'] = Variable<int>(scope.value);
    }
    if (jack.present) {
      map['jack'] = Variable<int>(jack.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (threshold.present) {
      map['threshold'] = Variable<int>(threshold.value);
    }
    if (windowS.present) {
      map['window_s'] = Variable<int>(windowS.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (pushedToDevice.present) {
      map['pushed_to_device'] = Variable<bool>(pushedToDevice.value);
    }
    if (lastConfirmedUnixMs.present) {
      map['last_confirmed_unix_ms'] = Variable<int>(lastConfirmedUnixMs.value);
    }
    if (cookId.present) {
      map['cook_id'] = Variable<int>(cookId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlarmRulesCompanion(')
          ..write('id: $id, ')
          ..write('bridgeId: $bridgeId, ')
          ..write('scope: $scope, ')
          ..write('jack: $jack, ')
          ..write('type: $type, ')
          ..write('threshold: $threshold, ')
          ..write('windowS: $windowS, ')
          ..write('enabled: $enabled, ')
          ..write('pushedToDevice: $pushedToDevice, ')
          ..write('lastConfirmedUnixMs: $lastConfirmedUnixMs, ')
          ..write('cookId: $cookId')
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
  @override
  List<GeneratedColumn> get $columns => [
    bridgeId,
    sessionId,
    highWaterT,
    deviceMinT,
    deviceMaxT,
    lastSyncUnixMs,
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
  const SyncStateRow({
    required this.bridgeId,
    required this.sessionId,
    required this.highWaterT,
    this.deviceMinT,
    this.deviceMaxT,
    this.lastSyncUnixMs,
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
    };
  }

  SyncStateRow copyWith({
    String? bridgeId,
    int? sessionId,
    int? highWaterT,
    Value<int?> deviceMinT = const Value.absent(),
    Value<int?> deviceMaxT = const Value.absent(),
    Value<int?> lastSyncUnixMs = const Value.absent(),
  }) => SyncStateRow(
    bridgeId: bridgeId ?? this.bridgeId,
    sessionId: sessionId ?? this.sessionId,
    highWaterT: highWaterT ?? this.highWaterT,
    deviceMinT: deviceMinT.present ? deviceMinT.value : this.deviceMinT,
    deviceMaxT: deviceMaxT.present ? deviceMaxT.value : this.deviceMaxT,
    lastSyncUnixMs: lastSyncUnixMs.present
        ? lastSyncUnixMs.value
        : this.lastSyncUnixMs,
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
          ..write('lastSyncUnixMs: $lastSyncUnixMs')
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
          other.lastSyncUnixMs == this.lastSyncUnixMs);
}

class SyncStatesCompanion extends UpdateCompanion<SyncStateRow> {
  final Value<String> bridgeId;
  final Value<int> sessionId;
  final Value<int> highWaterT;
  final Value<int?> deviceMinT;
  final Value<int?> deviceMaxT;
  final Value<int?> lastSyncUnixMs;
  final Value<int> rowid;
  const SyncStatesCompanion({
    this.bridgeId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.highWaterT = const Value.absent(),
    this.deviceMinT = const Value.absent(),
    this.deviceMaxT = const Value.absent(),
    this.lastSyncUnixMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStatesCompanion.insert({
    required String bridgeId,
    required int sessionId,
    this.highWaterT = const Value.absent(),
    this.deviceMinT = const Value.absent(),
    this.deviceMaxT = const Value.absent(),
    this.lastSyncUnixMs = const Value.absent(),
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
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bridgeId != null) 'bridge_id': bridgeId,
      if (sessionId != null) 'session_id': sessionId,
      if (highWaterT != null) 'high_water_t': highWaterT,
      if (deviceMinT != null) 'device_min_t': deviceMinT,
      if (deviceMaxT != null) 'device_max_t': deviceMaxT,
      if (lastSyncUnixMs != null) 'last_sync_unix_ms': lastSyncUnixMs,
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
    Value<int>? rowid,
  }) {
    return SyncStatesCompanion(
      bridgeId: bridgeId ?? this.bridgeId,
      sessionId: sessionId ?? this.sessionId,
      highWaterT: highWaterT ?? this.highWaterT,
      deviceMinT: deviceMinT ?? this.deviceMinT,
      deviceMaxT: deviceMaxT ?? this.deviceMaxT,
      lastSyncUnixMs: lastSyncUnixMs ?? this.lastSyncUnixMs,
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
          ..write('rowid: $rowid')
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
  late final $CooksTable cooks = $CooksTable(this);
  late final $CookProbeRolesTable cookProbeRoles = $CookProbeRolesTable(this);
  late final $AlarmRulesTable alarmRules = $AlarmRulesTable(this);
  late final $GapsTable gaps = $GapsTable(this);
  late final $SyncStatesTable syncStates = $SyncStatesTable(this);
  late final Index idxSamplesUnix = Index(
    'idx_samples_unix',
    'CREATE INDEX idx_samples_unix ON samples (bridge_id, unix_ms)',
  );
  late final Index idxCooksSpan = Index(
    'idx_cooks_span',
    'CREATE INDEX idx_cooks_span ON cooks (bridge_id, start_unix_ms)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    bridges,
    sessions,
    samples,
    marks,
    cooks,
    cookProbeRoles,
    alarmRules,
    gaps,
    syncStates,
    idxSamplesUnix,
    idxCooksSpan,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'cooks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('cook_probe_roles', kind: UpdateKind.delete)],
    ),
  ]);
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
      Value<int> flags,
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

  ColumnFilters<int> get flags => $composableBuilder(
    column: $table.flags,
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

  ColumnOrderings<int> get flags => $composableBuilder(
    column: $table.flags,
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

  GeneratedColumn<int> get flags =>
      $composableBuilder(column: $table.flags, builder: (column) => column);

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
                Value<int> flags = const Value.absent(),
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
                flags: flags,
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
                Value<int> flags = const Value.absent(),
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
                flags: flags,
                rssi: rssi,
                unixMs: unixMs,
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
typedef $$CooksTableCreateCompanionBuilder =
    CooksCompanion Function({
      Value<int> id,
      required String bridgeId,
      Value<String> name,
      required int startUnixMs,
      Value<int?> endUnixMs,
      required int createdUnixMs,
      Value<String> notes,
      Value<String?> presetId,
      Value<String> hazard,
      Value<int?> pitBandMinF10,
      Value<int?> pitBandMaxF10,
      Value<bool> favourite,
      Value<int?> anchorSessionId,
      Value<int?> pulledAtUnixMs,
    });
typedef $$CooksTableUpdateCompanionBuilder =
    CooksCompanion Function({
      Value<int> id,
      Value<String> bridgeId,
      Value<String> name,
      Value<int> startUnixMs,
      Value<int?> endUnixMs,
      Value<int> createdUnixMs,
      Value<String> notes,
      Value<String?> presetId,
      Value<String> hazard,
      Value<int?> pitBandMinF10,
      Value<int?> pitBandMaxF10,
      Value<bool> favourite,
      Value<int?> anchorSessionId,
      Value<int?> pulledAtUnixMs,
    });

final class $$CooksTableReferences
    extends BaseReferences<_$AppDatabase, $CooksTable, CookRow> {
  $$CooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CookProbeRolesTable, List<CookProbeRoleRow>>
  _cookProbeRolesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.cookProbeRoles,
    aliasName: 'cooks__id__cook_probe_roles__cook_id',
  );

  $$CookProbeRolesTableProcessedTableManager get cookProbeRolesRefs {
    final manager = $$CookProbeRolesTableTableManager(
      $_db,
      $_db.cookProbeRoles,
    ).filter((f) => f.cookId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_cookProbeRolesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CooksTableFilterComposer extends Composer<_$AppDatabase, $CooksTable> {
  $$CooksTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startUnixMs => $composableBuilder(
    column: $table.startUnixMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endUnixMs => $composableBuilder(
    column: $table.endUnixMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdUnixMs => $composableBuilder(
    column: $table.createdUnixMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hazard => $composableBuilder(
    column: $table.hazard,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pitBandMinF10 => $composableBuilder(
    column: $table.pitBandMinF10,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pitBandMaxF10 => $composableBuilder(
    column: $table.pitBandMaxF10,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favourite => $composableBuilder(
    column: $table.favourite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get anchorSessionId => $composableBuilder(
    column: $table.anchorSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pulledAtUnixMs => $composableBuilder(
    column: $table.pulledAtUnixMs,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> cookProbeRolesRefs(
    Expression<bool> Function($$CookProbeRolesTableFilterComposer f) f,
  ) {
    final $$CookProbeRolesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cookProbeRoles,
      getReferencedColumn: (t) => t.cookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CookProbeRolesTableFilterComposer(
            $db: $db,
            $table: $db.cookProbeRoles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CooksTableOrderingComposer
    extends Composer<_$AppDatabase, $CooksTable> {
  $$CooksTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startUnixMs => $composableBuilder(
    column: $table.startUnixMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endUnixMs => $composableBuilder(
    column: $table.endUnixMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdUnixMs => $composableBuilder(
    column: $table.createdUnixMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hazard => $composableBuilder(
    column: $table.hazard,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pitBandMinF10 => $composableBuilder(
    column: $table.pitBandMinF10,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pitBandMaxF10 => $composableBuilder(
    column: $table.pitBandMaxF10,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favourite => $composableBuilder(
    column: $table.favourite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get anchorSessionId => $composableBuilder(
    column: $table.anchorSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pulledAtUnixMs => $composableBuilder(
    column: $table.pulledAtUnixMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $CooksTable> {
  $$CooksTableAnnotationComposer({
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

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get startUnixMs => $composableBuilder(
    column: $table.startUnixMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endUnixMs =>
      $composableBuilder(column: $table.endUnixMs, builder: (column) => column);

  GeneratedColumn<int> get createdUnixMs => $composableBuilder(
    column: $table.createdUnixMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get presetId =>
      $composableBuilder(column: $table.presetId, builder: (column) => column);

  GeneratedColumn<String> get hazard =>
      $composableBuilder(column: $table.hazard, builder: (column) => column);

  GeneratedColumn<int> get pitBandMinF10 => $composableBuilder(
    column: $table.pitBandMinF10,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pitBandMaxF10 => $composableBuilder(
    column: $table.pitBandMaxF10,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get favourite =>
      $composableBuilder(column: $table.favourite, builder: (column) => column);

  GeneratedColumn<int> get anchorSessionId => $composableBuilder(
    column: $table.anchorSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pulledAtUnixMs => $composableBuilder(
    column: $table.pulledAtUnixMs,
    builder: (column) => column,
  );

  Expression<T> cookProbeRolesRefs<T extends Object>(
    Expression<T> Function($$CookProbeRolesTableAnnotationComposer a) f,
  ) {
    final $$CookProbeRolesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cookProbeRoles,
      getReferencedColumn: (t) => t.cookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CookProbeRolesTableAnnotationComposer(
            $db: $db,
            $table: $db.cookProbeRoles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CooksTable,
          CookRow,
          $$CooksTableFilterComposer,
          $$CooksTableOrderingComposer,
          $$CooksTableAnnotationComposer,
          $$CooksTableCreateCompanionBuilder,
          $$CooksTableUpdateCompanionBuilder,
          (CookRow, $$CooksTableReferences),
          CookRow,
          PrefetchHooks Function({bool cookProbeRolesRefs})
        > {
  $$CooksTableTableManager(_$AppDatabase db, $CooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bridgeId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> startUnixMs = const Value.absent(),
                Value<int?> endUnixMs = const Value.absent(),
                Value<int> createdUnixMs = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<String?> presetId = const Value.absent(),
                Value<String> hazard = const Value.absent(),
                Value<int?> pitBandMinF10 = const Value.absent(),
                Value<int?> pitBandMaxF10 = const Value.absent(),
                Value<bool> favourite = const Value.absent(),
                Value<int?> anchorSessionId = const Value.absent(),
                Value<int?> pulledAtUnixMs = const Value.absent(),
              }) => CooksCompanion(
                id: id,
                bridgeId: bridgeId,
                name: name,
                startUnixMs: startUnixMs,
                endUnixMs: endUnixMs,
                createdUnixMs: createdUnixMs,
                notes: notes,
                presetId: presetId,
                hazard: hazard,
                pitBandMinF10: pitBandMinF10,
                pitBandMaxF10: pitBandMaxF10,
                favourite: favourite,
                anchorSessionId: anchorSessionId,
                pulledAtUnixMs: pulledAtUnixMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String bridgeId,
                Value<String> name = const Value.absent(),
                required int startUnixMs,
                Value<int?> endUnixMs = const Value.absent(),
                required int createdUnixMs,
                Value<String> notes = const Value.absent(),
                Value<String?> presetId = const Value.absent(),
                Value<String> hazard = const Value.absent(),
                Value<int?> pitBandMinF10 = const Value.absent(),
                Value<int?> pitBandMaxF10 = const Value.absent(),
                Value<bool> favourite = const Value.absent(),
                Value<int?> anchorSessionId = const Value.absent(),
                Value<int?> pulledAtUnixMs = const Value.absent(),
              }) => CooksCompanion.insert(
                id: id,
                bridgeId: bridgeId,
                name: name,
                startUnixMs: startUnixMs,
                endUnixMs: endUnixMs,
                createdUnixMs: createdUnixMs,
                notes: notes,
                presetId: presetId,
                hazard: hazard,
                pitBandMinF10: pitBandMinF10,
                pitBandMaxF10: pitBandMaxF10,
                favourite: favourite,
                anchorSessionId: anchorSessionId,
                pulledAtUnixMs: pulledAtUnixMs,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$CooksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({cookProbeRolesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (cookProbeRolesRefs) db.cookProbeRoles,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (cookProbeRolesRefs)
                    await $_getPrefetchedData<
                      CookRow,
                      $CooksTable,
                      CookProbeRoleRow
                    >(
                      currentTable: table,
                      referencedTable: $$CooksTableReferences
                          ._cookProbeRolesRefsTable(db),
                      managerFromTypedResult: (p0) => $$CooksTableReferences(
                        db,
                        table,
                        p0,
                      ).cookProbeRolesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.cookId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CooksTable,
      CookRow,
      $$CooksTableFilterComposer,
      $$CooksTableOrderingComposer,
      $$CooksTableAnnotationComposer,
      $$CooksTableCreateCompanionBuilder,
      $$CooksTableUpdateCompanionBuilder,
      (CookRow, $$CooksTableReferences),
      CookRow,
      PrefetchHooks Function({bool cookProbeRolesRefs})
    >;
typedef $$CookProbeRolesTableCreateCompanionBuilder =
    CookProbeRolesCompanion Function({
      required int cookId,
      required int jack,
      Value<int> role,
      Value<String> label,
      Value<int?> targetF10,
      Value<int> pullOffsetF10,
      Value<int> rowid,
    });
typedef $$CookProbeRolesTableUpdateCompanionBuilder =
    CookProbeRolesCompanion Function({
      Value<int> cookId,
      Value<int> jack,
      Value<int> role,
      Value<String> label,
      Value<int?> targetF10,
      Value<int> pullOffsetF10,
      Value<int> rowid,
    });

final class $$CookProbeRolesTableReferences
    extends
        BaseReferences<_$AppDatabase, $CookProbeRolesTable, CookProbeRoleRow> {
  $$CookProbeRolesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CooksTable _cookIdTable(_$AppDatabase db) =>
      db.cooks.createAlias('cook_probe_roles__cook_id__cooks__id');

  $$CooksTableProcessedTableManager get cookId {
    final $_column = $_itemColumn<int>('cook_id')!;

    final manager = $$CooksTableTableManager(
      $_db,
      $_db.cooks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_cookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CookProbeRolesTableFilterComposer
    extends Composer<_$AppDatabase, $CookProbeRolesTable> {
  $$CookProbeRolesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get jack => $composableBuilder(
    column: $table.jack,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetF10 => $composableBuilder(
    column: $table.targetF10,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pullOffsetF10 => $composableBuilder(
    column: $table.pullOffsetF10,
    builder: (column) => ColumnFilters(column),
  );

  $$CooksTableFilterComposer get cookId {
    final $$CooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cookId,
      referencedTable: $db.cooks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CooksTableFilterComposer(
            $db: $db,
            $table: $db.cooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CookProbeRolesTableOrderingComposer
    extends Composer<_$AppDatabase, $CookProbeRolesTable> {
  $$CookProbeRolesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get jack => $composableBuilder(
    column: $table.jack,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetF10 => $composableBuilder(
    column: $table.targetF10,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pullOffsetF10 => $composableBuilder(
    column: $table.pullOffsetF10,
    builder: (column) => ColumnOrderings(column),
  );

  $$CooksTableOrderingComposer get cookId {
    final $$CooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cookId,
      referencedTable: $db.cooks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CooksTableOrderingComposer(
            $db: $db,
            $table: $db.cooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CookProbeRolesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CookProbeRolesTable> {
  $$CookProbeRolesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get jack =>
      $composableBuilder(column: $table.jack, builder: (column) => column);

  GeneratedColumn<int> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get targetF10 =>
      $composableBuilder(column: $table.targetF10, builder: (column) => column);

  GeneratedColumn<int> get pullOffsetF10 => $composableBuilder(
    column: $table.pullOffsetF10,
    builder: (column) => column,
  );

  $$CooksTableAnnotationComposer get cookId {
    final $$CooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.cookId,
      referencedTable: $db.cooks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CooksTableAnnotationComposer(
            $db: $db,
            $table: $db.cooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CookProbeRolesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CookProbeRolesTable,
          CookProbeRoleRow,
          $$CookProbeRolesTableFilterComposer,
          $$CookProbeRolesTableOrderingComposer,
          $$CookProbeRolesTableAnnotationComposer,
          $$CookProbeRolesTableCreateCompanionBuilder,
          $$CookProbeRolesTableUpdateCompanionBuilder,
          (CookProbeRoleRow, $$CookProbeRolesTableReferences),
          CookProbeRoleRow,
          PrefetchHooks Function({bool cookId})
        > {
  $$CookProbeRolesTableTableManager(
    _$AppDatabase db,
    $CookProbeRolesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CookProbeRolesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CookProbeRolesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CookProbeRolesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> cookId = const Value.absent(),
                Value<int> jack = const Value.absent(),
                Value<int> role = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int?> targetF10 = const Value.absent(),
                Value<int> pullOffsetF10 = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CookProbeRolesCompanion(
                cookId: cookId,
                jack: jack,
                role: role,
                label: label,
                targetF10: targetF10,
                pullOffsetF10: pullOffsetF10,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int cookId,
                required int jack,
                Value<int> role = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int?> targetF10 = const Value.absent(),
                Value<int> pullOffsetF10 = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CookProbeRolesCompanion.insert(
                cookId: cookId,
                jack: jack,
                role: role,
                label: label,
                targetF10: targetF10,
                pullOffsetF10: pullOffsetF10,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CookProbeRolesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({cookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (cookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.cookId,
                                referencedTable: $$CookProbeRolesTableReferences
                                    ._cookIdTable(db),
                                referencedColumn:
                                    $$CookProbeRolesTableReferences
                                        ._cookIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CookProbeRolesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CookProbeRolesTable,
      CookProbeRoleRow,
      $$CookProbeRolesTableFilterComposer,
      $$CookProbeRolesTableOrderingComposer,
      $$CookProbeRolesTableAnnotationComposer,
      $$CookProbeRolesTableCreateCompanionBuilder,
      $$CookProbeRolesTableUpdateCompanionBuilder,
      (CookProbeRoleRow, $$CookProbeRolesTableReferences),
      CookProbeRoleRow,
      PrefetchHooks Function({bool cookId})
    >;
typedef $$AlarmRulesTableCreateCompanionBuilder =
    AlarmRulesCompanion Function({
      Value<int> id,
      required String bridgeId,
      required int scope,
      Value<int?> jack,
      required String type,
      Value<int?> threshold,
      Value<int?> windowS,
      Value<bool> enabled,
      Value<bool> pushedToDevice,
      Value<int?> lastConfirmedUnixMs,
      Value<int?> cookId,
    });
typedef $$AlarmRulesTableUpdateCompanionBuilder =
    AlarmRulesCompanion Function({
      Value<int> id,
      Value<String> bridgeId,
      Value<int> scope,
      Value<int?> jack,
      Value<String> type,
      Value<int?> threshold,
      Value<int?> windowS,
      Value<bool> enabled,
      Value<bool> pushedToDevice,
      Value<int?> lastConfirmedUnixMs,
      Value<int?> cookId,
    });

class $$AlarmRulesTableFilterComposer
    extends Composer<_$AppDatabase, $AlarmRulesTable> {
  $$AlarmRulesTableFilterComposer({
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

  ColumnFilters<int> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get jack => $composableBuilder(
    column: $table.jack,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get threshold => $composableBuilder(
    column: $table.threshold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get windowS => $composableBuilder(
    column: $table.windowS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pushedToDevice => $composableBuilder(
    column: $table.pushedToDevice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastConfirmedUnixMs => $composableBuilder(
    column: $table.lastConfirmedUnixMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cookId => $composableBuilder(
    column: $table.cookId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlarmRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $AlarmRulesTable> {
  $$AlarmRulesTableOrderingComposer({
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

  ColumnOrderings<int> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get jack => $composableBuilder(
    column: $table.jack,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get threshold => $composableBuilder(
    column: $table.threshold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get windowS => $composableBuilder(
    column: $table.windowS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pushedToDevice => $composableBuilder(
    column: $table.pushedToDevice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastConfirmedUnixMs => $composableBuilder(
    column: $table.lastConfirmedUnixMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cookId => $composableBuilder(
    column: $table.cookId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlarmRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlarmRulesTable> {
  $$AlarmRulesTableAnnotationComposer({
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

  GeneratedColumn<int> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<int> get jack =>
      $composableBuilder(column: $table.jack, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get threshold =>
      $composableBuilder(column: $table.threshold, builder: (column) => column);

  GeneratedColumn<int> get windowS =>
      $composableBuilder(column: $table.windowS, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<bool> get pushedToDevice => $composableBuilder(
    column: $table.pushedToDevice,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastConfirmedUnixMs => $composableBuilder(
    column: $table.lastConfirmedUnixMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cookId =>
      $composableBuilder(column: $table.cookId, builder: (column) => column);
}

class $$AlarmRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlarmRulesTable,
          AlarmRuleRow,
          $$AlarmRulesTableFilterComposer,
          $$AlarmRulesTableOrderingComposer,
          $$AlarmRulesTableAnnotationComposer,
          $$AlarmRulesTableCreateCompanionBuilder,
          $$AlarmRulesTableUpdateCompanionBuilder,
          (
            AlarmRuleRow,
            BaseReferences<_$AppDatabase, $AlarmRulesTable, AlarmRuleRow>,
          ),
          AlarmRuleRow,
          PrefetchHooks Function()
        > {
  $$AlarmRulesTableTableManager(_$AppDatabase db, $AlarmRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlarmRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlarmRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlarmRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bridgeId = const Value.absent(),
                Value<int> scope = const Value.absent(),
                Value<int?> jack = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int?> threshold = const Value.absent(),
                Value<int?> windowS = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> pushedToDevice = const Value.absent(),
                Value<int?> lastConfirmedUnixMs = const Value.absent(),
                Value<int?> cookId = const Value.absent(),
              }) => AlarmRulesCompanion(
                id: id,
                bridgeId: bridgeId,
                scope: scope,
                jack: jack,
                type: type,
                threshold: threshold,
                windowS: windowS,
                enabled: enabled,
                pushedToDevice: pushedToDevice,
                lastConfirmedUnixMs: lastConfirmedUnixMs,
                cookId: cookId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String bridgeId,
                required int scope,
                Value<int?> jack = const Value.absent(),
                required String type,
                Value<int?> threshold = const Value.absent(),
                Value<int?> windowS = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> pushedToDevice = const Value.absent(),
                Value<int?> lastConfirmedUnixMs = const Value.absent(),
                Value<int?> cookId = const Value.absent(),
              }) => AlarmRulesCompanion.insert(
                id: id,
                bridgeId: bridgeId,
                scope: scope,
                jack: jack,
                type: type,
                threshold: threshold,
                windowS: windowS,
                enabled: enabled,
                pushedToDevice: pushedToDevice,
                lastConfirmedUnixMs: lastConfirmedUnixMs,
                cookId: cookId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AlarmRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlarmRulesTable,
      AlarmRuleRow,
      $$AlarmRulesTableFilterComposer,
      $$AlarmRulesTableOrderingComposer,
      $$AlarmRulesTableAnnotationComposer,
      $$AlarmRulesTableCreateCompanionBuilder,
      $$AlarmRulesTableUpdateCompanionBuilder,
      (
        AlarmRuleRow,
        BaseReferences<_$AppDatabase, $AlarmRulesTable, AlarmRuleRow>,
      ),
      AlarmRuleRow,
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
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
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
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion(
                bridgeId: bridgeId,
                sessionId: sessionId,
                highWaterT: highWaterT,
                deviceMinT: deviceMinT,
                deviceMaxT: deviceMaxT,
                lastSyncUnixMs: lastSyncUnixMs,
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
                Value<int> rowid = const Value.absent(),
              }) => SyncStatesCompanion.insert(
                bridgeId: bridgeId,
                sessionId: sessionId,
                highWaterT: highWaterT,
                deviceMinT: deviceMinT,
                deviceMaxT: deviceMaxT,
                lastSyncUnixMs: lastSyncUnixMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
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
  $$BridgesTableTableManager get bridges =>
      $$BridgesTableTableManager(_db, _db.bridges);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$SamplesTableTableManager get samples =>
      $$SamplesTableTableManager(_db, _db.samples);
  $$MarksTableTableManager get marks =>
      $$MarksTableTableManager(_db, _db.marks);
  $$CooksTableTableManager get cooks =>
      $$CooksTableTableManager(_db, _db.cooks);
  $$CookProbeRolesTableTableManager get cookProbeRoles =>
      $$CookProbeRolesTableTableManager(_db, _db.cookProbeRoles);
  $$AlarmRulesTableTableManager get alarmRules =>
      $$AlarmRulesTableTableManager(_db, _db.alarmRules);
  $$GapsTableTableManager get gaps => $$GapsTableTableManager(_db, _db.gaps);
  $$SyncStatesTableTableManager get syncStates =>
      $$SyncStatesTableTableManager(_db, _db.syncStates);
}
