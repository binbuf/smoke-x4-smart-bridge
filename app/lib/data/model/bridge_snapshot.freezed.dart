// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bridge_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeSnapshot {

 ConnectionState get connection; CookState get cook; List<ProbeState> get probes; List<Alarm> get alarms; List<Mark> get marks; PendingSession? get pendingSession;/// A one-line banner ("Bridge restarted — recording resumed.").
 String? get notice;
/// Create a copy of BridgeSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSnapshotCopyWith<BridgeSnapshot> get copyWith => _$BridgeSnapshotCopyWithImpl<BridgeSnapshot>(this as BridgeSnapshot, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSnapshot&&(identical(other.connection, connection) || other.connection == connection)&&(identical(other.cook, cook) || other.cook == cook)&&const DeepCollectionEquality().equals(other.probes, probes)&&const DeepCollectionEquality().equals(other.alarms, alarms)&&const DeepCollectionEquality().equals(other.marks, marks)&&(identical(other.pendingSession, pendingSession) || other.pendingSession == pendingSession)&&(identical(other.notice, notice) || other.notice == notice));
}


@override
int get hashCode => Object.hash(runtimeType,connection,cook,const DeepCollectionEquality().hash(probes),const DeepCollectionEquality().hash(alarms),const DeepCollectionEquality().hash(marks),pendingSession,notice);

@override
String toString() {
  return 'BridgeSnapshot(connection: $connection, cook: $cook, probes: $probes, alarms: $alarms, marks: $marks, pendingSession: $pendingSession, notice: $notice)';
}


}

/// @nodoc
abstract mixin class $BridgeSnapshotCopyWith<$Res>  {
  factory $BridgeSnapshotCopyWith(BridgeSnapshot value, $Res Function(BridgeSnapshot) _then) = _$BridgeSnapshotCopyWithImpl;
@useResult
$Res call({
 ConnectionState connection, CookState cook, List<ProbeState> probes, List<Alarm> alarms, List<Mark> marks, PendingSession? pendingSession, String? notice
});




}
/// @nodoc
class _$BridgeSnapshotCopyWithImpl<$Res>
    implements $BridgeSnapshotCopyWith<$Res> {
  _$BridgeSnapshotCopyWithImpl(this._self, this._then);

  final BridgeSnapshot _self;
  final $Res Function(BridgeSnapshot) _then;

/// Create a copy of BridgeSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? connection = null,Object? cook = null,Object? probes = null,Object? alarms = null,Object? marks = null,Object? pendingSession = freezed,Object? notice = freezed,}) {
  return _then(_self.copyWith(
connection: null == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as ConnectionState,cook: null == cook ? _self.cook : cook // ignore: cast_nullable_to_non_nullable
as CookState,probes: null == probes ? _self.probes : probes // ignore: cast_nullable_to_non_nullable
as List<ProbeState>,alarms: null == alarms ? _self.alarms : alarms // ignore: cast_nullable_to_non_nullable
as List<Alarm>,marks: null == marks ? _self.marks : marks // ignore: cast_nullable_to_non_nullable
as List<Mark>,pendingSession: freezed == pendingSession ? _self.pendingSession : pendingSession // ignore: cast_nullable_to_non_nullable
as PendingSession?,notice: freezed == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeSnapshot].
extension BridgeSnapshotPatterns on BridgeSnapshot {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BridgeSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BridgeSnapshot() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BridgeSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _BridgeSnapshot():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BridgeSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _BridgeSnapshot() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConnectionState connection,  CookState cook,  List<ProbeState> probes,  List<Alarm> alarms,  List<Mark> marks,  PendingSession? pendingSession,  String? notice)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BridgeSnapshot() when $default != null:
return $default(_that.connection,_that.cook,_that.probes,_that.alarms,_that.marks,_that.pendingSession,_that.notice);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConnectionState connection,  CookState cook,  List<ProbeState> probes,  List<Alarm> alarms,  List<Mark> marks,  PendingSession? pendingSession,  String? notice)  $default,) {final _that = this;
switch (_that) {
case _BridgeSnapshot():
return $default(_that.connection,_that.cook,_that.probes,_that.alarms,_that.marks,_that.pendingSession,_that.notice);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConnectionState connection,  CookState cook,  List<ProbeState> probes,  List<Alarm> alarms,  List<Mark> marks,  PendingSession? pendingSession,  String? notice)?  $default,) {final _that = this;
switch (_that) {
case _BridgeSnapshot() when $default != null:
return $default(_that.connection,_that.cook,_that.probes,_that.alarms,_that.marks,_that.pendingSession,_that.notice);case _:
  return null;

}
}

}

/// @nodoc


class _BridgeSnapshot implements BridgeSnapshot {
  const _BridgeSnapshot({required this.connection, required this.cook, final  List<ProbeState> probes = const <ProbeState>[], final  List<Alarm> alarms = const <Alarm>[], final  List<Mark> marks = const <Mark>[], this.pendingSession, this.notice}): _probes = probes,_alarms = alarms,_marks = marks;
  

@override final  ConnectionState connection;
@override final  CookState cook;
 final  List<ProbeState> _probes;
@override@JsonKey() List<ProbeState> get probes {
  if (_probes is EqualUnmodifiableListView) return _probes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_probes);
}

 final  List<Alarm> _alarms;
@override@JsonKey() List<Alarm> get alarms {
  if (_alarms is EqualUnmodifiableListView) return _alarms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_alarms);
}

 final  List<Mark> _marks;
@override@JsonKey() List<Mark> get marks {
  if (_marks is EqualUnmodifiableListView) return _marks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_marks);
}

@override final  PendingSession? pendingSession;
/// A one-line banner ("Bridge restarted — recording resumed.").
@override final  String? notice;

/// Create a copy of BridgeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BridgeSnapshotCopyWith<_BridgeSnapshot> get copyWith => __$BridgeSnapshotCopyWithImpl<_BridgeSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BridgeSnapshot&&(identical(other.connection, connection) || other.connection == connection)&&(identical(other.cook, cook) || other.cook == cook)&&const DeepCollectionEquality().equals(other._probes, _probes)&&const DeepCollectionEquality().equals(other._alarms, _alarms)&&const DeepCollectionEquality().equals(other._marks, _marks)&&(identical(other.pendingSession, pendingSession) || other.pendingSession == pendingSession)&&(identical(other.notice, notice) || other.notice == notice));
}


@override
int get hashCode => Object.hash(runtimeType,connection,cook,const DeepCollectionEquality().hash(_probes),const DeepCollectionEquality().hash(_alarms),const DeepCollectionEquality().hash(_marks),pendingSession,notice);

@override
String toString() {
  return 'BridgeSnapshot(connection: $connection, cook: $cook, probes: $probes, alarms: $alarms, marks: $marks, pendingSession: $pendingSession, notice: $notice)';
}


}

/// @nodoc
abstract mixin class _$BridgeSnapshotCopyWith<$Res> implements $BridgeSnapshotCopyWith<$Res> {
  factory _$BridgeSnapshotCopyWith(_BridgeSnapshot value, $Res Function(_BridgeSnapshot) _then) = __$BridgeSnapshotCopyWithImpl;
@override @useResult
$Res call({
 ConnectionState connection, CookState cook, List<ProbeState> probes, List<Alarm> alarms, List<Mark> marks, PendingSession? pendingSession, String? notice
});




}
/// @nodoc
class __$BridgeSnapshotCopyWithImpl<$Res>
    implements _$BridgeSnapshotCopyWith<$Res> {
  __$BridgeSnapshotCopyWithImpl(this._self, this._then);

  final _BridgeSnapshot _self;
  final $Res Function(_BridgeSnapshot) _then;

/// Create a copy of BridgeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? connection = null,Object? cook = null,Object? probes = null,Object? alarms = null,Object? marks = null,Object? pendingSession = freezed,Object? notice = freezed,}) {
  return _then(_BridgeSnapshot(
connection: null == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as ConnectionState,cook: null == cook ? _self.cook : cook // ignore: cast_nullable_to_non_nullable
as CookState,probes: null == probes ? _self._probes : probes // ignore: cast_nullable_to_non_nullable
as List<ProbeState>,alarms: null == alarms ? _self._alarms : alarms // ignore: cast_nullable_to_non_nullable
as List<Alarm>,marks: null == marks ? _self._marks : marks // ignore: cast_nullable_to_non_nullable
as List<Mark>,pendingSession: freezed == pendingSession ? _self.pendingSession : pendingSession // ignore: cast_nullable_to_non_nullable
as PendingSession?,notice: freezed == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
