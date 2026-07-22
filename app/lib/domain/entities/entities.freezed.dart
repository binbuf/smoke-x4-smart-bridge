// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'entities.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Probe {

/// 1..4 — the physical jack on the base station.
 int get n; String get name; ProbeRole get role;/// Tenths °F; null = no target set.
 int? get targetF10; bool get alarmEnabled;
/// Create a copy of Probe
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProbeCopyWith<Probe> get copyWith => _$ProbeCopyWithImpl<Probe>(this as Probe, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Probe&&(identical(other.n, n) || other.n == n)&&(identical(other.name, name) || other.name == name)&&(identical(other.role, role) || other.role == role)&&(identical(other.targetF10, targetF10) || other.targetF10 == targetF10)&&(identical(other.alarmEnabled, alarmEnabled) || other.alarmEnabled == alarmEnabled));
}


@override
int get hashCode => Object.hash(runtimeType,n,name,role,targetF10,alarmEnabled);

@override
String toString() {
  return 'Probe(n: $n, name: $name, role: $role, targetF10: $targetF10, alarmEnabled: $alarmEnabled)';
}


}

/// @nodoc
abstract mixin class $ProbeCopyWith<$Res>  {
  factory $ProbeCopyWith(Probe value, $Res Function(Probe) _then) = _$ProbeCopyWithImpl;
@useResult
$Res call({
 int n, String name, ProbeRole role, int? targetF10, bool alarmEnabled
});




}
/// @nodoc
class _$ProbeCopyWithImpl<$Res>
    implements $ProbeCopyWith<$Res> {
  _$ProbeCopyWithImpl(this._self, this._then);

  final Probe _self;
  final $Res Function(Probe) _then;

/// Create a copy of Probe
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? n = null,Object? name = null,Object? role = null,Object? targetF10 = freezed,Object? alarmEnabled = null,}) {
  return _then(_self.copyWith(
n: null == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ProbeRole,targetF10: freezed == targetF10 ? _self.targetF10 : targetF10 // ignore: cast_nullable_to_non_nullable
as int?,alarmEnabled: null == alarmEnabled ? _self.alarmEnabled : alarmEnabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [Probe].
extension ProbePatterns on Probe {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Probe value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Probe() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Probe value)  $default,){
final _that = this;
switch (_that) {
case _Probe():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Probe value)?  $default,){
final _that = this;
switch (_that) {
case _Probe() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int n,  String name,  ProbeRole role,  int? targetF10,  bool alarmEnabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Probe() when $default != null:
return $default(_that.n,_that.name,_that.role,_that.targetF10,_that.alarmEnabled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int n,  String name,  ProbeRole role,  int? targetF10,  bool alarmEnabled)  $default,) {final _that = this;
switch (_that) {
case _Probe():
return $default(_that.n,_that.name,_that.role,_that.targetF10,_that.alarmEnabled);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int n,  String name,  ProbeRole role,  int? targetF10,  bool alarmEnabled)?  $default,) {final _that = this;
switch (_that) {
case _Probe() when $default != null:
return $default(_that.n,_that.name,_that.role,_that.targetF10,_that.alarmEnabled);case _:
  return null;

}
}

}

/// @nodoc


class _Probe implements Probe {
  const _Probe({required this.n, this.name = '', this.role = ProbeRole.unused, this.targetF10, this.alarmEnabled = false});
  

/// 1..4 — the physical jack on the base station.
@override final  int n;
@override@JsonKey() final  String name;
@override@JsonKey() final  ProbeRole role;
/// Tenths °F; null = no target set.
@override final  int? targetF10;
@override@JsonKey() final  bool alarmEnabled;

/// Create a copy of Probe
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProbeCopyWith<_Probe> get copyWith => __$ProbeCopyWithImpl<_Probe>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Probe&&(identical(other.n, n) || other.n == n)&&(identical(other.name, name) || other.name == name)&&(identical(other.role, role) || other.role == role)&&(identical(other.targetF10, targetF10) || other.targetF10 == targetF10)&&(identical(other.alarmEnabled, alarmEnabled) || other.alarmEnabled == alarmEnabled));
}


@override
int get hashCode => Object.hash(runtimeType,n,name,role,targetF10,alarmEnabled);

@override
String toString() {
  return 'Probe(n: $n, name: $name, role: $role, targetF10: $targetF10, alarmEnabled: $alarmEnabled)';
}


}

/// @nodoc
abstract mixin class _$ProbeCopyWith<$Res> implements $ProbeCopyWith<$Res> {
  factory _$ProbeCopyWith(_Probe value, $Res Function(_Probe) _then) = __$ProbeCopyWithImpl;
@override @useResult
$Res call({
 int n, String name, ProbeRole role, int? targetF10, bool alarmEnabled
});




}
/// @nodoc
class __$ProbeCopyWithImpl<$Res>
    implements _$ProbeCopyWith<$Res> {
  __$ProbeCopyWithImpl(this._self, this._then);

  final _Probe _self;
  final $Res Function(_Probe) _then;

/// Create a copy of Probe
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? n = null,Object? name = null,Object? role = null,Object? targetF10 = freezed,Object? alarmEnabled = null,}) {
  return _then(_Probe(
n: null == n ? _self.n : n // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ProbeRole,targetF10: freezed == targetF10 ? _self.targetF10 : targetF10 // ignore: cast_nullable_to_non_nullable
as int?,alarmEnabled: null == alarmEnabled ? _self.alarmEnabled : alarmEnabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$Sample {

/// Seconds since session start (monotonic, never wall-clock).
 int get t;/// Length 4; tenths °F; null = detached or invalid.
 List<int?> get tempsF10; bool get billows; bool get newAlarm;/// Provenance only — the values are already canonical °F.
 bool get sourceCelsius; int get rssi;
/// Create a copy of Sample
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SampleCopyWith<Sample> get copyWith => _$SampleCopyWithImpl<Sample>(this as Sample, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Sample&&(identical(other.t, t) || other.t == t)&&const DeepCollectionEquality().equals(other.tempsF10, tempsF10)&&(identical(other.billows, billows) || other.billows == billows)&&(identical(other.newAlarm, newAlarm) || other.newAlarm == newAlarm)&&(identical(other.sourceCelsius, sourceCelsius) || other.sourceCelsius == sourceCelsius)&&(identical(other.rssi, rssi) || other.rssi == rssi));
}


@override
int get hashCode => Object.hash(runtimeType,t,const DeepCollectionEquality().hash(tempsF10),billows,newAlarm,sourceCelsius,rssi);

@override
String toString() {
  return 'Sample(t: $t, tempsF10: $tempsF10, billows: $billows, newAlarm: $newAlarm, sourceCelsius: $sourceCelsius, rssi: $rssi)';
}


}

/// @nodoc
abstract mixin class $SampleCopyWith<$Res>  {
  factory $SampleCopyWith(Sample value, $Res Function(Sample) _then) = _$SampleCopyWithImpl;
@useResult
$Res call({
 int t, List<int?> tempsF10, bool billows, bool newAlarm, bool sourceCelsius, int rssi
});




}
/// @nodoc
class _$SampleCopyWithImpl<$Res>
    implements $SampleCopyWith<$Res> {
  _$SampleCopyWithImpl(this._self, this._then);

  final Sample _self;
  final $Res Function(Sample) _then;

/// Create a copy of Sample
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? t = null,Object? tempsF10 = null,Object? billows = null,Object? newAlarm = null,Object? sourceCelsius = null,Object? rssi = null,}) {
  return _then(_self.copyWith(
t: null == t ? _self.t : t // ignore: cast_nullable_to_non_nullable
as int,tempsF10: null == tempsF10 ? _self.tempsF10 : tempsF10 // ignore: cast_nullable_to_non_nullable
as List<int?>,billows: null == billows ? _self.billows : billows // ignore: cast_nullable_to_non_nullable
as bool,newAlarm: null == newAlarm ? _self.newAlarm : newAlarm // ignore: cast_nullable_to_non_nullable
as bool,sourceCelsius: null == sourceCelsius ? _self.sourceCelsius : sourceCelsius // ignore: cast_nullable_to_non_nullable
as bool,rssi: null == rssi ? _self.rssi : rssi // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [Sample].
extension SamplePatterns on Sample {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Sample value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Sample() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Sample value)  $default,){
final _that = this;
switch (_that) {
case _Sample():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Sample value)?  $default,){
final _that = this;
switch (_that) {
case _Sample() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int t,  List<int?> tempsF10,  bool billows,  bool newAlarm,  bool sourceCelsius,  int rssi)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Sample() when $default != null:
return $default(_that.t,_that.tempsF10,_that.billows,_that.newAlarm,_that.sourceCelsius,_that.rssi);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int t,  List<int?> tempsF10,  bool billows,  bool newAlarm,  bool sourceCelsius,  int rssi)  $default,) {final _that = this;
switch (_that) {
case _Sample():
return $default(_that.t,_that.tempsF10,_that.billows,_that.newAlarm,_that.sourceCelsius,_that.rssi);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int t,  List<int?> tempsF10,  bool billows,  bool newAlarm,  bool sourceCelsius,  int rssi)?  $default,) {final _that = this;
switch (_that) {
case _Sample() when $default != null:
return $default(_that.t,_that.tempsF10,_that.billows,_that.newAlarm,_that.sourceCelsius,_that.rssi);case _:
  return null;

}
}

}

/// @nodoc


class _Sample implements Sample {
  const _Sample({required this.t, required final  List<int?> tempsF10, this.billows = false, this.newAlarm = false, this.sourceCelsius = false, this.rssi = 0}): _tempsF10 = tempsF10;
  

/// Seconds since session start (monotonic, never wall-clock).
@override final  int t;
/// Length 4; tenths °F; null = detached or invalid.
 final  List<int?> _tempsF10;
/// Length 4; tenths °F; null = detached or invalid.
@override List<int?> get tempsF10 {
  if (_tempsF10 is EqualUnmodifiableListView) return _tempsF10;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tempsF10);
}

@override@JsonKey() final  bool billows;
@override@JsonKey() final  bool newAlarm;
/// Provenance only — the values are already canonical °F.
@override@JsonKey() final  bool sourceCelsius;
@override@JsonKey() final  int rssi;

/// Create a copy of Sample
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SampleCopyWith<_Sample> get copyWith => __$SampleCopyWithImpl<_Sample>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Sample&&(identical(other.t, t) || other.t == t)&&const DeepCollectionEquality().equals(other._tempsF10, _tempsF10)&&(identical(other.billows, billows) || other.billows == billows)&&(identical(other.newAlarm, newAlarm) || other.newAlarm == newAlarm)&&(identical(other.sourceCelsius, sourceCelsius) || other.sourceCelsius == sourceCelsius)&&(identical(other.rssi, rssi) || other.rssi == rssi));
}


@override
int get hashCode => Object.hash(runtimeType,t,const DeepCollectionEquality().hash(_tempsF10),billows,newAlarm,sourceCelsius,rssi);

@override
String toString() {
  return 'Sample(t: $t, tempsF10: $tempsF10, billows: $billows, newAlarm: $newAlarm, sourceCelsius: $sourceCelsius, rssi: $rssi)';
}


}

/// @nodoc
abstract mixin class _$SampleCopyWith<$Res> implements $SampleCopyWith<$Res> {
  factory _$SampleCopyWith(_Sample value, $Res Function(_Sample) _then) = __$SampleCopyWithImpl;
@override @useResult
$Res call({
 int t, List<int?> tempsF10, bool billows, bool newAlarm, bool sourceCelsius, int rssi
});




}
/// @nodoc
class __$SampleCopyWithImpl<$Res>
    implements _$SampleCopyWith<$Res> {
  __$SampleCopyWithImpl(this._self, this._then);

  final _Sample _self;
  final $Res Function(_Sample) _then;

/// Create a copy of Sample
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? t = null,Object? tempsF10 = null,Object? billows = null,Object? newAlarm = null,Object? sourceCelsius = null,Object? rssi = null,}) {
  return _then(_Sample(
t: null == t ? _self.t : t // ignore: cast_nullable_to_non_nullable
as int,tempsF10: null == tempsF10 ? _self._tempsF10 : tempsF10 // ignore: cast_nullable_to_non_nullable
as List<int?>,billows: null == billows ? _self.billows : billows // ignore: cast_nullable_to_non_nullable
as bool,newAlarm: null == newAlarm ? _self.newAlarm : newAlarm // ignore: cast_nullable_to_non_nullable
as bool,sourceCelsius: null == sourceCelsius ? _self.sourceCelsius : sourceCelsius // ignore: cast_nullable_to_non_nullable
as bool,rssi: null == rssi ? _self.rssi : rssi // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$CookSession {

 int get id; String get name;/// Unix ms; null while the bridge had no clock (clock_valid unset).
 int? get startedUnixMs;/// Unix ms; null while the session is open.
 int? get endedUnixMs; int get samplePeriodS; int get sampleCount; int get numProbes; List<Probe> get probes; bool get closed; bool get pinned;
/// Create a copy of CookSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CookSessionCopyWith<CookSession> get copyWith => _$CookSessionCopyWithImpl<CookSession>(this as CookSession, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CookSession&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.startedUnixMs, startedUnixMs) || other.startedUnixMs == startedUnixMs)&&(identical(other.endedUnixMs, endedUnixMs) || other.endedUnixMs == endedUnixMs)&&(identical(other.samplePeriodS, samplePeriodS) || other.samplePeriodS == samplePeriodS)&&(identical(other.sampleCount, sampleCount) || other.sampleCount == sampleCount)&&(identical(other.numProbes, numProbes) || other.numProbes == numProbes)&&const DeepCollectionEquality().equals(other.probes, probes)&&(identical(other.closed, closed) || other.closed == closed)&&(identical(other.pinned, pinned) || other.pinned == pinned));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,startedUnixMs,endedUnixMs,samplePeriodS,sampleCount,numProbes,const DeepCollectionEquality().hash(probes),closed,pinned);

@override
String toString() {
  return 'CookSession(id: $id, name: $name, startedUnixMs: $startedUnixMs, endedUnixMs: $endedUnixMs, samplePeriodS: $samplePeriodS, sampleCount: $sampleCount, numProbes: $numProbes, probes: $probes, closed: $closed, pinned: $pinned)';
}


}

/// @nodoc
abstract mixin class $CookSessionCopyWith<$Res>  {
  factory $CookSessionCopyWith(CookSession value, $Res Function(CookSession) _then) = _$CookSessionCopyWithImpl;
@useResult
$Res call({
 int id, String name, int? startedUnixMs, int? endedUnixMs, int samplePeriodS, int sampleCount, int numProbes, List<Probe> probes, bool closed, bool pinned
});




}
/// @nodoc
class _$CookSessionCopyWithImpl<$Res>
    implements $CookSessionCopyWith<$Res> {
  _$CookSessionCopyWithImpl(this._self, this._then);

  final CookSession _self;
  final $Res Function(CookSession) _then;

/// Create a copy of CookSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? startedUnixMs = freezed,Object? endedUnixMs = freezed,Object? samplePeriodS = null,Object? sampleCount = null,Object? numProbes = null,Object? probes = null,Object? closed = null,Object? pinned = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,startedUnixMs: freezed == startedUnixMs ? _self.startedUnixMs : startedUnixMs // ignore: cast_nullable_to_non_nullable
as int?,endedUnixMs: freezed == endedUnixMs ? _self.endedUnixMs : endedUnixMs // ignore: cast_nullable_to_non_nullable
as int?,samplePeriodS: null == samplePeriodS ? _self.samplePeriodS : samplePeriodS // ignore: cast_nullable_to_non_nullable
as int,sampleCount: null == sampleCount ? _self.sampleCount : sampleCount // ignore: cast_nullable_to_non_nullable
as int,numProbes: null == numProbes ? _self.numProbes : numProbes // ignore: cast_nullable_to_non_nullable
as int,probes: null == probes ? _self.probes : probes // ignore: cast_nullable_to_non_nullable
as List<Probe>,closed: null == closed ? _self.closed : closed // ignore: cast_nullable_to_non_nullable
as bool,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [CookSession].
extension CookSessionPatterns on CookSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CookSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CookSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CookSession value)  $default,){
final _that = this;
switch (_that) {
case _CookSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CookSession value)?  $default,){
final _that = this;
switch (_that) {
case _CookSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String name,  int? startedUnixMs,  int? endedUnixMs,  int samplePeriodS,  int sampleCount,  int numProbes,  List<Probe> probes,  bool closed,  bool pinned)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CookSession() when $default != null:
return $default(_that.id,_that.name,_that.startedUnixMs,_that.endedUnixMs,_that.samplePeriodS,_that.sampleCount,_that.numProbes,_that.probes,_that.closed,_that.pinned);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String name,  int? startedUnixMs,  int? endedUnixMs,  int samplePeriodS,  int sampleCount,  int numProbes,  List<Probe> probes,  bool closed,  bool pinned)  $default,) {final _that = this;
switch (_that) {
case _CookSession():
return $default(_that.id,_that.name,_that.startedUnixMs,_that.endedUnixMs,_that.samplePeriodS,_that.sampleCount,_that.numProbes,_that.probes,_that.closed,_that.pinned);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String name,  int? startedUnixMs,  int? endedUnixMs,  int samplePeriodS,  int sampleCount,  int numProbes,  List<Probe> probes,  bool closed,  bool pinned)?  $default,) {final _that = this;
switch (_that) {
case _CookSession() when $default != null:
return $default(_that.id,_that.name,_that.startedUnixMs,_that.endedUnixMs,_that.samplePeriodS,_that.sampleCount,_that.numProbes,_that.probes,_that.closed,_that.pinned);case _:
  return null;

}
}

}

/// @nodoc


class _CookSession implements CookSession {
  const _CookSession({required this.id, this.name = '', this.startedUnixMs, this.endedUnixMs, this.samplePeriodS = 30, this.sampleCount = 0, this.numProbes = 4, final  List<Probe> probes = const <Probe>[], this.closed = false, this.pinned = false}): _probes = probes;
  

@override final  int id;
@override@JsonKey() final  String name;
/// Unix ms; null while the bridge had no clock (clock_valid unset).
@override final  int? startedUnixMs;
/// Unix ms; null while the session is open.
@override final  int? endedUnixMs;
@override@JsonKey() final  int samplePeriodS;
@override@JsonKey() final  int sampleCount;
@override@JsonKey() final  int numProbes;
 final  List<Probe> _probes;
@override@JsonKey() List<Probe> get probes {
  if (_probes is EqualUnmodifiableListView) return _probes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_probes);
}

@override@JsonKey() final  bool closed;
@override@JsonKey() final  bool pinned;

/// Create a copy of CookSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CookSessionCopyWith<_CookSession> get copyWith => __$CookSessionCopyWithImpl<_CookSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CookSession&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.startedUnixMs, startedUnixMs) || other.startedUnixMs == startedUnixMs)&&(identical(other.endedUnixMs, endedUnixMs) || other.endedUnixMs == endedUnixMs)&&(identical(other.samplePeriodS, samplePeriodS) || other.samplePeriodS == samplePeriodS)&&(identical(other.sampleCount, sampleCount) || other.sampleCount == sampleCount)&&(identical(other.numProbes, numProbes) || other.numProbes == numProbes)&&const DeepCollectionEquality().equals(other._probes, _probes)&&(identical(other.closed, closed) || other.closed == closed)&&(identical(other.pinned, pinned) || other.pinned == pinned));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,startedUnixMs,endedUnixMs,samplePeriodS,sampleCount,numProbes,const DeepCollectionEquality().hash(_probes),closed,pinned);

@override
String toString() {
  return 'CookSession(id: $id, name: $name, startedUnixMs: $startedUnixMs, endedUnixMs: $endedUnixMs, samplePeriodS: $samplePeriodS, sampleCount: $sampleCount, numProbes: $numProbes, probes: $probes, closed: $closed, pinned: $pinned)';
}


}

/// @nodoc
abstract mixin class _$CookSessionCopyWith<$Res> implements $CookSessionCopyWith<$Res> {
  factory _$CookSessionCopyWith(_CookSession value, $Res Function(_CookSession) _then) = __$CookSessionCopyWithImpl;
@override @useResult
$Res call({
 int id, String name, int? startedUnixMs, int? endedUnixMs, int samplePeriodS, int sampleCount, int numProbes, List<Probe> probes, bool closed, bool pinned
});




}
/// @nodoc
class __$CookSessionCopyWithImpl<$Res>
    implements _$CookSessionCopyWith<$Res> {
  __$CookSessionCopyWithImpl(this._self, this._then);

  final _CookSession _self;
  final $Res Function(_CookSession) _then;

/// Create a copy of CookSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? startedUnixMs = freezed,Object? endedUnixMs = freezed,Object? samplePeriodS = null,Object? sampleCount = null,Object? numProbes = null,Object? probes = null,Object? closed = null,Object? pinned = null,}) {
  return _then(_CookSession(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,startedUnixMs: freezed == startedUnixMs ? _self.startedUnixMs : startedUnixMs // ignore: cast_nullable_to_non_nullable
as int?,endedUnixMs: freezed == endedUnixMs ? _self.endedUnixMs : endedUnixMs // ignore: cast_nullable_to_non_nullable
as int?,samplePeriodS: null == samplePeriodS ? _self.samplePeriodS : samplePeriodS // ignore: cast_nullable_to_non_nullable
as int,sampleCount: null == sampleCount ? _self.sampleCount : sampleCount // ignore: cast_nullable_to_non_nullable
as int,numProbes: null == numProbes ? _self.numProbes : numProbes // ignore: cast_nullable_to_non_nullable
as int,probes: null == probes ? _self._probes : probes // ignore: cast_nullable_to_non_nullable
as List<Probe>,closed: null == closed ? _self.closed : closed // ignore: cast_nullable_to_non_nullable
as bool,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$Mark {

/// Seconds since session start.
 int get t; MarkKind get kind;/// 0 = whole cook, 1..4 = a specific probe.
 int get probe; String get text;
/// Create a copy of Mark
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MarkCopyWith<Mark> get copyWith => _$MarkCopyWithImpl<Mark>(this as Mark, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Mark&&(identical(other.t, t) || other.t == t)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.probe, probe) || other.probe == probe)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,t,kind,probe,text);

@override
String toString() {
  return 'Mark(t: $t, kind: $kind, probe: $probe, text: $text)';
}


}

/// @nodoc
abstract mixin class $MarkCopyWith<$Res>  {
  factory $MarkCopyWith(Mark value, $Res Function(Mark) _then) = _$MarkCopyWithImpl;
@useResult
$Res call({
 int t, MarkKind kind, int probe, String text
});




}
/// @nodoc
class _$MarkCopyWithImpl<$Res>
    implements $MarkCopyWith<$Res> {
  _$MarkCopyWithImpl(this._self, this._then);

  final Mark _self;
  final $Res Function(Mark) _then;

/// Create a copy of Mark
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? t = null,Object? kind = null,Object? probe = null,Object? text = null,}) {
  return _then(_self.copyWith(
t: null == t ? _self.t : t // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as MarkKind,probe: null == probe ? _self.probe : probe // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Mark].
extension MarkPatterns on Mark {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Mark value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Mark() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Mark value)  $default,){
final _that = this;
switch (_that) {
case _Mark():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Mark value)?  $default,){
final _that = this;
switch (_that) {
case _Mark() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int t,  MarkKind kind,  int probe,  String text)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Mark() when $default != null:
return $default(_that.t,_that.kind,_that.probe,_that.text);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int t,  MarkKind kind,  int probe,  String text)  $default,) {final _that = this;
switch (_that) {
case _Mark():
return $default(_that.t,_that.kind,_that.probe,_that.text);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int t,  MarkKind kind,  int probe,  String text)?  $default,) {final _that = this;
switch (_that) {
case _Mark() when $default != null:
return $default(_that.t,_that.kind,_that.probe,_that.text);case _:
  return null;

}
}

}

/// @nodoc


class _Mark implements Mark {
  const _Mark({required this.t, required this.kind, this.probe = 0, this.text = ''});
  

/// Seconds since session start.
@override final  int t;
@override final  MarkKind kind;
/// 0 = whole cook, 1..4 = a specific probe.
@override@JsonKey() final  int probe;
@override@JsonKey() final  String text;

/// Create a copy of Mark
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MarkCopyWith<_Mark> get copyWith => __$MarkCopyWithImpl<_Mark>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Mark&&(identical(other.t, t) || other.t == t)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.probe, probe) || other.probe == probe)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,t,kind,probe,text);

@override
String toString() {
  return 'Mark(t: $t, kind: $kind, probe: $probe, text: $text)';
}


}

/// @nodoc
abstract mixin class _$MarkCopyWith<$Res> implements $MarkCopyWith<$Res> {
  factory _$MarkCopyWith(_Mark value, $Res Function(_Mark) _then) = __$MarkCopyWithImpl;
@override @useResult
$Res call({
 int t, MarkKind kind, int probe, String text
});




}
/// @nodoc
class __$MarkCopyWithImpl<$Res>
    implements _$MarkCopyWith<$Res> {
  __$MarkCopyWithImpl(this._self, this._then);

  final _Mark _self;
  final $Res Function(_Mark) _then;

/// Create a copy of Mark
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? t = null,Object? kind = null,Object? probe = null,Object? text = null,}) {
  return _then(_Mark(
t: null == t ? _self.t : t // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as MarkKind,probe: null == probe ? _self.probe : probe // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$Alarm {

 int get id; String get rule;/// 0 = whole cook, 1..4 = a specific probe.
 int get probe; int? get valueF10; int? get sinceUnixMs; AlarmSeverity get severity; bool get acked;
/// Create a copy of Alarm
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AlarmCopyWith<Alarm> get copyWith => _$AlarmCopyWithImpl<Alarm>(this as Alarm, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Alarm&&(identical(other.id, id) || other.id == id)&&(identical(other.rule, rule) || other.rule == rule)&&(identical(other.probe, probe) || other.probe == probe)&&(identical(other.valueF10, valueF10) || other.valueF10 == valueF10)&&(identical(other.sinceUnixMs, sinceUnixMs) || other.sinceUnixMs == sinceUnixMs)&&(identical(other.severity, severity) || other.severity == severity)&&(identical(other.acked, acked) || other.acked == acked));
}


@override
int get hashCode => Object.hash(runtimeType,id,rule,probe,valueF10,sinceUnixMs,severity,acked);

@override
String toString() {
  return 'Alarm(id: $id, rule: $rule, probe: $probe, valueF10: $valueF10, sinceUnixMs: $sinceUnixMs, severity: $severity, acked: $acked)';
}


}

/// @nodoc
abstract mixin class $AlarmCopyWith<$Res>  {
  factory $AlarmCopyWith(Alarm value, $Res Function(Alarm) _then) = _$AlarmCopyWithImpl;
@useResult
$Res call({
 int id, String rule, int probe, int? valueF10, int? sinceUnixMs, AlarmSeverity severity, bool acked
});




}
/// @nodoc
class _$AlarmCopyWithImpl<$Res>
    implements $AlarmCopyWith<$Res> {
  _$AlarmCopyWithImpl(this._self, this._then);

  final Alarm _self;
  final $Res Function(Alarm) _then;

/// Create a copy of Alarm
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? rule = null,Object? probe = null,Object? valueF10 = freezed,Object? sinceUnixMs = freezed,Object? severity = null,Object? acked = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,rule: null == rule ? _self.rule : rule // ignore: cast_nullable_to_non_nullable
as String,probe: null == probe ? _self.probe : probe // ignore: cast_nullable_to_non_nullable
as int,valueF10: freezed == valueF10 ? _self.valueF10 : valueF10 // ignore: cast_nullable_to_non_nullable
as int?,sinceUnixMs: freezed == sinceUnixMs ? _self.sinceUnixMs : sinceUnixMs // ignore: cast_nullable_to_non_nullable
as int?,severity: null == severity ? _self.severity : severity // ignore: cast_nullable_to_non_nullable
as AlarmSeverity,acked: null == acked ? _self.acked : acked // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [Alarm].
extension AlarmPatterns on Alarm {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Alarm value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Alarm() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Alarm value)  $default,){
final _that = this;
switch (_that) {
case _Alarm():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Alarm value)?  $default,){
final _that = this;
switch (_that) {
case _Alarm() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String rule,  int probe,  int? valueF10,  int? sinceUnixMs,  AlarmSeverity severity,  bool acked)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Alarm() when $default != null:
return $default(_that.id,_that.rule,_that.probe,_that.valueF10,_that.sinceUnixMs,_that.severity,_that.acked);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String rule,  int probe,  int? valueF10,  int? sinceUnixMs,  AlarmSeverity severity,  bool acked)  $default,) {final _that = this;
switch (_that) {
case _Alarm():
return $default(_that.id,_that.rule,_that.probe,_that.valueF10,_that.sinceUnixMs,_that.severity,_that.acked);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String rule,  int probe,  int? valueF10,  int? sinceUnixMs,  AlarmSeverity severity,  bool acked)?  $default,) {final _that = this;
switch (_that) {
case _Alarm() when $default != null:
return $default(_that.id,_that.rule,_that.probe,_that.valueF10,_that.sinceUnixMs,_that.severity,_that.acked);case _:
  return null;

}
}

}

/// @nodoc


class _Alarm implements Alarm {
  const _Alarm({required this.id, required this.rule, this.probe = 0, this.valueF10, this.sinceUnixMs, this.severity = AlarmSeverity.warning, this.acked = false});
  

@override final  int id;
@override final  String rule;
/// 0 = whole cook, 1..4 = a specific probe.
@override@JsonKey() final  int probe;
@override final  int? valueF10;
@override final  int? sinceUnixMs;
@override@JsonKey() final  AlarmSeverity severity;
@override@JsonKey() final  bool acked;

/// Create a copy of Alarm
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AlarmCopyWith<_Alarm> get copyWith => __$AlarmCopyWithImpl<_Alarm>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Alarm&&(identical(other.id, id) || other.id == id)&&(identical(other.rule, rule) || other.rule == rule)&&(identical(other.probe, probe) || other.probe == probe)&&(identical(other.valueF10, valueF10) || other.valueF10 == valueF10)&&(identical(other.sinceUnixMs, sinceUnixMs) || other.sinceUnixMs == sinceUnixMs)&&(identical(other.severity, severity) || other.severity == severity)&&(identical(other.acked, acked) || other.acked == acked));
}


@override
int get hashCode => Object.hash(runtimeType,id,rule,probe,valueF10,sinceUnixMs,severity,acked);

@override
String toString() {
  return 'Alarm(id: $id, rule: $rule, probe: $probe, valueF10: $valueF10, sinceUnixMs: $sinceUnixMs, severity: $severity, acked: $acked)';
}


}

/// @nodoc
abstract mixin class _$AlarmCopyWith<$Res> implements $AlarmCopyWith<$Res> {
  factory _$AlarmCopyWith(_Alarm value, $Res Function(_Alarm) _then) = __$AlarmCopyWithImpl;
@override @useResult
$Res call({
 int id, String rule, int probe, int? valueF10, int? sinceUnixMs, AlarmSeverity severity, bool acked
});




}
/// @nodoc
class __$AlarmCopyWithImpl<$Res>
    implements _$AlarmCopyWith<$Res> {
  __$AlarmCopyWithImpl(this._self, this._then);

  final _Alarm _self;
  final $Res Function(_Alarm) _then;

/// Create a copy of Alarm
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? rule = null,Object? probe = null,Object? valueF10 = freezed,Object? sinceUnixMs = freezed,Object? severity = null,Object? acked = null,}) {
  return _then(_Alarm(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,rule: null == rule ? _self.rule : rule // ignore: cast_nullable_to_non_nullable
as String,probe: null == probe ? _self.probe : probe // ignore: cast_nullable_to_non_nullable
as int,valueF10: freezed == valueF10 ? _self.valueF10 : valueF10 // ignore: cast_nullable_to_non_nullable
as int?,sinceUnixMs: freezed == sinceUnixMs ? _self.sinceUnixMs : sinceUnixMs // ignore: cast_nullable_to_non_nullable
as int?,severity: null == severity ? _self.severity : severity // ignore: cast_nullable_to_non_nullable
as AlarmSeverity,acked: null == acked ? _self.acked : acked // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$LiveState {

/// Seconds into the active session; 0 when none.
 int get t;/// Wall clock, when the bridge knows it.
 int? get unixMs;/// Length 4; tenths °F; null = detached — never 0.
 List<int?> get tempsF10; bool get billows; List<Sample> get recent;
/// Create a copy of LiveState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiveStateCopyWith<LiveState> get copyWith => _$LiveStateCopyWithImpl<LiveState>(this as LiveState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveState&&(identical(other.t, t) || other.t == t)&&(identical(other.unixMs, unixMs) || other.unixMs == unixMs)&&const DeepCollectionEquality().equals(other.tempsF10, tempsF10)&&(identical(other.billows, billows) || other.billows == billows)&&const DeepCollectionEquality().equals(other.recent, recent));
}


@override
int get hashCode => Object.hash(runtimeType,t,unixMs,const DeepCollectionEquality().hash(tempsF10),billows,const DeepCollectionEquality().hash(recent));

@override
String toString() {
  return 'LiveState(t: $t, unixMs: $unixMs, tempsF10: $tempsF10, billows: $billows, recent: $recent)';
}


}

/// @nodoc
abstract mixin class $LiveStateCopyWith<$Res>  {
  factory $LiveStateCopyWith(LiveState value, $Res Function(LiveState) _then) = _$LiveStateCopyWithImpl;
@useResult
$Res call({
 int t, int? unixMs, List<int?> tempsF10, bool billows, List<Sample> recent
});




}
/// @nodoc
class _$LiveStateCopyWithImpl<$Res>
    implements $LiveStateCopyWith<$Res> {
  _$LiveStateCopyWithImpl(this._self, this._then);

  final LiveState _self;
  final $Res Function(LiveState) _then;

/// Create a copy of LiveState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? t = null,Object? unixMs = freezed,Object? tempsF10 = null,Object? billows = null,Object? recent = null,}) {
  return _then(_self.copyWith(
t: null == t ? _self.t : t // ignore: cast_nullable_to_non_nullable
as int,unixMs: freezed == unixMs ? _self.unixMs : unixMs // ignore: cast_nullable_to_non_nullable
as int?,tempsF10: null == tempsF10 ? _self.tempsF10 : tempsF10 // ignore: cast_nullable_to_non_nullable
as List<int?>,billows: null == billows ? _self.billows : billows // ignore: cast_nullable_to_non_nullable
as bool,recent: null == recent ? _self.recent : recent // ignore: cast_nullable_to_non_nullable
as List<Sample>,
  ));
}

}


/// Adds pattern-matching-related methods to [LiveState].
extension LiveStatePatterns on LiveState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LiveState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LiveState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LiveState value)  $default,){
final _that = this;
switch (_that) {
case _LiveState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LiveState value)?  $default,){
final _that = this;
switch (_that) {
case _LiveState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int t,  int? unixMs,  List<int?> tempsF10,  bool billows,  List<Sample> recent)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LiveState() when $default != null:
return $default(_that.t,_that.unixMs,_that.tempsF10,_that.billows,_that.recent);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int t,  int? unixMs,  List<int?> tempsF10,  bool billows,  List<Sample> recent)  $default,) {final _that = this;
switch (_that) {
case _LiveState():
return $default(_that.t,_that.unixMs,_that.tempsF10,_that.billows,_that.recent);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int t,  int? unixMs,  List<int?> tempsF10,  bool billows,  List<Sample> recent)?  $default,) {final _that = this;
switch (_that) {
case _LiveState() when $default != null:
return $default(_that.t,_that.unixMs,_that.tempsF10,_that.billows,_that.recent);case _:
  return null;

}
}

}

/// @nodoc


class _LiveState implements LiveState {
  const _LiveState({required this.t, this.unixMs, required final  List<int?> tempsF10, this.billows = false, final  List<Sample> recent = const <Sample>[]}): _tempsF10 = tempsF10,_recent = recent;
  

/// Seconds into the active session; 0 when none.
@override final  int t;
/// Wall clock, when the bridge knows it.
@override final  int? unixMs;
/// Length 4; tenths °F; null = detached — never 0.
 final  List<int?> _tempsF10;
/// Length 4; tenths °F; null = detached — never 0.
@override List<int?> get tempsF10 {
  if (_tempsF10 is EqualUnmodifiableListView) return _tempsF10;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tempsF10);
}

@override@JsonKey() final  bool billows;
 final  List<Sample> _recent;
@override@JsonKey() List<Sample> get recent {
  if (_recent is EqualUnmodifiableListView) return _recent;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_recent);
}


/// Create a copy of LiveState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LiveStateCopyWith<_LiveState> get copyWith => __$LiveStateCopyWithImpl<_LiveState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LiveState&&(identical(other.t, t) || other.t == t)&&(identical(other.unixMs, unixMs) || other.unixMs == unixMs)&&const DeepCollectionEquality().equals(other._tempsF10, _tempsF10)&&(identical(other.billows, billows) || other.billows == billows)&&const DeepCollectionEquality().equals(other._recent, _recent));
}


@override
int get hashCode => Object.hash(runtimeType,t,unixMs,const DeepCollectionEquality().hash(_tempsF10),billows,const DeepCollectionEquality().hash(_recent));

@override
String toString() {
  return 'LiveState(t: $t, unixMs: $unixMs, tempsF10: $tempsF10, billows: $billows, recent: $recent)';
}


}

/// @nodoc
abstract mixin class _$LiveStateCopyWith<$Res> implements $LiveStateCopyWith<$Res> {
  factory _$LiveStateCopyWith(_LiveState value, $Res Function(_LiveState) _then) = __$LiveStateCopyWithImpl;
@override @useResult
$Res call({
 int t, int? unixMs, List<int?> tempsF10, bool billows, List<Sample> recent
});




}
/// @nodoc
class __$LiveStateCopyWithImpl<$Res>
    implements _$LiveStateCopyWith<$Res> {
  __$LiveStateCopyWithImpl(this._self, this._then);

  final _LiveState _self;
  final $Res Function(_LiveState) _then;

/// Create a copy of LiveState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? t = null,Object? unixMs = freezed,Object? tempsF10 = null,Object? billows = null,Object? recent = null,}) {
  return _then(_LiveState(
t: null == t ? _self.t : t // ignore: cast_nullable_to_non_nullable
as int,unixMs: freezed == unixMs ? _self.unixMs : unixMs // ignore: cast_nullable_to_non_nullable
as int?,tempsF10: null == tempsF10 ? _self._tempsF10 : tempsF10 // ignore: cast_nullable_to_non_nullable
as List<int?>,billows: null == billows ? _self.billows : billows // ignore: cast_nullable_to_non_nullable
as bool,recent: null == recent ? _self._recent : recent // ignore: cast_nullable_to_non_nullable
as List<Sample>,
  ));
}


}

/// @nodoc
mixin _$BridgeStatus {

 String get deviceId; String get model; String get fw; int get uptimeS; bool get paired; int get numProbes;/// Seconds since the last valid state message; null = never.
 int? get lastPacketSAgo; bool get baseLost; bool get sessionActive; int? get activeSessionId; int get storageFreePct;/// 0–100; null when battery reporting is unavailable (R6).
 int? get socPct; bool get charging; List<Alarm> get alarms;
/// Create a copy of BridgeStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeStatusCopyWith<BridgeStatus> get copyWith => _$BridgeStatusCopyWithImpl<BridgeStatus>(this as BridgeStatus, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeStatus&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.model, model) || other.model == model)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.uptimeS, uptimeS) || other.uptimeS == uptimeS)&&(identical(other.paired, paired) || other.paired == paired)&&(identical(other.numProbes, numProbes) || other.numProbes == numProbes)&&(identical(other.lastPacketSAgo, lastPacketSAgo) || other.lastPacketSAgo == lastPacketSAgo)&&(identical(other.baseLost, baseLost) || other.baseLost == baseLost)&&(identical(other.sessionActive, sessionActive) || other.sessionActive == sessionActive)&&(identical(other.activeSessionId, activeSessionId) || other.activeSessionId == activeSessionId)&&(identical(other.storageFreePct, storageFreePct) || other.storageFreePct == storageFreePct)&&(identical(other.socPct, socPct) || other.socPct == socPct)&&(identical(other.charging, charging) || other.charging == charging)&&const DeepCollectionEquality().equals(other.alarms, alarms));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,model,fw,uptimeS,paired,numProbes,lastPacketSAgo,baseLost,sessionActive,activeSessionId,storageFreePct,socPct,charging,const DeepCollectionEquality().hash(alarms));

@override
String toString() {
  return 'BridgeStatus(deviceId: $deviceId, model: $model, fw: $fw, uptimeS: $uptimeS, paired: $paired, numProbes: $numProbes, lastPacketSAgo: $lastPacketSAgo, baseLost: $baseLost, sessionActive: $sessionActive, activeSessionId: $activeSessionId, storageFreePct: $storageFreePct, socPct: $socPct, charging: $charging, alarms: $alarms)';
}


}

/// @nodoc
abstract mixin class $BridgeStatusCopyWith<$Res>  {
  factory $BridgeStatusCopyWith(BridgeStatus value, $Res Function(BridgeStatus) _then) = _$BridgeStatusCopyWithImpl;
@useResult
$Res call({
 String deviceId, String model, String fw, int uptimeS, bool paired, int numProbes, int? lastPacketSAgo, bool baseLost, bool sessionActive, int? activeSessionId, int storageFreePct, int? socPct, bool charging, List<Alarm> alarms
});




}
/// @nodoc
class _$BridgeStatusCopyWithImpl<$Res>
    implements $BridgeStatusCopyWith<$Res> {
  _$BridgeStatusCopyWithImpl(this._self, this._then);

  final BridgeStatus _self;
  final $Res Function(BridgeStatus) _then;

/// Create a copy of BridgeStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? deviceId = null,Object? model = null,Object? fw = null,Object? uptimeS = null,Object? paired = null,Object? numProbes = null,Object? lastPacketSAgo = freezed,Object? baseLost = null,Object? sessionActive = null,Object? activeSessionId = freezed,Object? storageFreePct = null,Object? socPct = freezed,Object? charging = null,Object? alarms = null,}) {
  return _then(_self.copyWith(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,uptimeS: null == uptimeS ? _self.uptimeS : uptimeS // ignore: cast_nullable_to_non_nullable
as int,paired: null == paired ? _self.paired : paired // ignore: cast_nullable_to_non_nullable
as bool,numProbes: null == numProbes ? _self.numProbes : numProbes // ignore: cast_nullable_to_non_nullable
as int,lastPacketSAgo: freezed == lastPacketSAgo ? _self.lastPacketSAgo : lastPacketSAgo // ignore: cast_nullable_to_non_nullable
as int?,baseLost: null == baseLost ? _self.baseLost : baseLost // ignore: cast_nullable_to_non_nullable
as bool,sessionActive: null == sessionActive ? _self.sessionActive : sessionActive // ignore: cast_nullable_to_non_nullable
as bool,activeSessionId: freezed == activeSessionId ? _self.activeSessionId : activeSessionId // ignore: cast_nullable_to_non_nullable
as int?,storageFreePct: null == storageFreePct ? _self.storageFreePct : storageFreePct // ignore: cast_nullable_to_non_nullable
as int,socPct: freezed == socPct ? _self.socPct : socPct // ignore: cast_nullable_to_non_nullable
as int?,charging: null == charging ? _self.charging : charging // ignore: cast_nullable_to_non_nullable
as bool,alarms: null == alarms ? _self.alarms : alarms // ignore: cast_nullable_to_non_nullable
as List<Alarm>,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeStatus].
extension BridgeStatusPatterns on BridgeStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BridgeStatus value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BridgeStatus() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BridgeStatus value)  $default,){
final _that = this;
switch (_that) {
case _BridgeStatus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BridgeStatus value)?  $default,){
final _that = this;
switch (_that) {
case _BridgeStatus() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String deviceId,  String model,  String fw,  int uptimeS,  bool paired,  int numProbes,  int? lastPacketSAgo,  bool baseLost,  bool sessionActive,  int? activeSessionId,  int storageFreePct,  int? socPct,  bool charging,  List<Alarm> alarms)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BridgeStatus() when $default != null:
return $default(_that.deviceId,_that.model,_that.fw,_that.uptimeS,_that.paired,_that.numProbes,_that.lastPacketSAgo,_that.baseLost,_that.sessionActive,_that.activeSessionId,_that.storageFreePct,_that.socPct,_that.charging,_that.alarms);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String deviceId,  String model,  String fw,  int uptimeS,  bool paired,  int numProbes,  int? lastPacketSAgo,  bool baseLost,  bool sessionActive,  int? activeSessionId,  int storageFreePct,  int? socPct,  bool charging,  List<Alarm> alarms)  $default,) {final _that = this;
switch (_that) {
case _BridgeStatus():
return $default(_that.deviceId,_that.model,_that.fw,_that.uptimeS,_that.paired,_that.numProbes,_that.lastPacketSAgo,_that.baseLost,_that.sessionActive,_that.activeSessionId,_that.storageFreePct,_that.socPct,_that.charging,_that.alarms);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String deviceId,  String model,  String fw,  int uptimeS,  bool paired,  int numProbes,  int? lastPacketSAgo,  bool baseLost,  bool sessionActive,  int? activeSessionId,  int storageFreePct,  int? socPct,  bool charging,  List<Alarm> alarms)?  $default,) {final _that = this;
switch (_that) {
case _BridgeStatus() when $default != null:
return $default(_that.deviceId,_that.model,_that.fw,_that.uptimeS,_that.paired,_that.numProbes,_that.lastPacketSAgo,_that.baseLost,_that.sessionActive,_that.activeSessionId,_that.storageFreePct,_that.socPct,_that.charging,_that.alarms);case _:
  return null;

}
}

}

/// @nodoc


class _BridgeStatus implements BridgeStatus {
  const _BridgeStatus({required this.deviceId, this.model = '', this.fw = '', this.uptimeS = 0, this.paired = false, this.numProbes = 0, this.lastPacketSAgo, this.baseLost = false, this.sessionActive = false, this.activeSessionId, this.storageFreePct = 0, this.socPct, this.charging = false, final  List<Alarm> alarms = const <Alarm>[]}): _alarms = alarms;
  

@override final  String deviceId;
@override@JsonKey() final  String model;
@override@JsonKey() final  String fw;
@override@JsonKey() final  int uptimeS;
@override@JsonKey() final  bool paired;
@override@JsonKey() final  int numProbes;
/// Seconds since the last valid state message; null = never.
@override final  int? lastPacketSAgo;
@override@JsonKey() final  bool baseLost;
@override@JsonKey() final  bool sessionActive;
@override final  int? activeSessionId;
@override@JsonKey() final  int storageFreePct;
/// 0–100; null when battery reporting is unavailable (R6).
@override final  int? socPct;
@override@JsonKey() final  bool charging;
 final  List<Alarm> _alarms;
@override@JsonKey() List<Alarm> get alarms {
  if (_alarms is EqualUnmodifiableListView) return _alarms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_alarms);
}


/// Create a copy of BridgeStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BridgeStatusCopyWith<_BridgeStatus> get copyWith => __$BridgeStatusCopyWithImpl<_BridgeStatus>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BridgeStatus&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.model, model) || other.model == model)&&(identical(other.fw, fw) || other.fw == fw)&&(identical(other.uptimeS, uptimeS) || other.uptimeS == uptimeS)&&(identical(other.paired, paired) || other.paired == paired)&&(identical(other.numProbes, numProbes) || other.numProbes == numProbes)&&(identical(other.lastPacketSAgo, lastPacketSAgo) || other.lastPacketSAgo == lastPacketSAgo)&&(identical(other.baseLost, baseLost) || other.baseLost == baseLost)&&(identical(other.sessionActive, sessionActive) || other.sessionActive == sessionActive)&&(identical(other.activeSessionId, activeSessionId) || other.activeSessionId == activeSessionId)&&(identical(other.storageFreePct, storageFreePct) || other.storageFreePct == storageFreePct)&&(identical(other.socPct, socPct) || other.socPct == socPct)&&(identical(other.charging, charging) || other.charging == charging)&&const DeepCollectionEquality().equals(other._alarms, _alarms));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,model,fw,uptimeS,paired,numProbes,lastPacketSAgo,baseLost,sessionActive,activeSessionId,storageFreePct,socPct,charging,const DeepCollectionEquality().hash(_alarms));

@override
String toString() {
  return 'BridgeStatus(deviceId: $deviceId, model: $model, fw: $fw, uptimeS: $uptimeS, paired: $paired, numProbes: $numProbes, lastPacketSAgo: $lastPacketSAgo, baseLost: $baseLost, sessionActive: $sessionActive, activeSessionId: $activeSessionId, storageFreePct: $storageFreePct, socPct: $socPct, charging: $charging, alarms: $alarms)';
}


}

/// @nodoc
abstract mixin class _$BridgeStatusCopyWith<$Res> implements $BridgeStatusCopyWith<$Res> {
  factory _$BridgeStatusCopyWith(_BridgeStatus value, $Res Function(_BridgeStatus) _then) = __$BridgeStatusCopyWithImpl;
@override @useResult
$Res call({
 String deviceId, String model, String fw, int uptimeS, bool paired, int numProbes, int? lastPacketSAgo, bool baseLost, bool sessionActive, int? activeSessionId, int storageFreePct, int? socPct, bool charging, List<Alarm> alarms
});




}
/// @nodoc
class __$BridgeStatusCopyWithImpl<$Res>
    implements _$BridgeStatusCopyWith<$Res> {
  __$BridgeStatusCopyWithImpl(this._self, this._then);

  final _BridgeStatus _self;
  final $Res Function(_BridgeStatus) _then;

/// Create a copy of BridgeStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? model = null,Object? fw = null,Object? uptimeS = null,Object? paired = null,Object? numProbes = null,Object? lastPacketSAgo = freezed,Object? baseLost = null,Object? sessionActive = null,Object? activeSessionId = freezed,Object? storageFreePct = null,Object? socPct = freezed,Object? charging = null,Object? alarms = null,}) {
  return _then(_BridgeStatus(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,fw: null == fw ? _self.fw : fw // ignore: cast_nullable_to_non_nullable
as String,uptimeS: null == uptimeS ? _self.uptimeS : uptimeS // ignore: cast_nullable_to_non_nullable
as int,paired: null == paired ? _self.paired : paired // ignore: cast_nullable_to_non_nullable
as bool,numProbes: null == numProbes ? _self.numProbes : numProbes // ignore: cast_nullable_to_non_nullable
as int,lastPacketSAgo: freezed == lastPacketSAgo ? _self.lastPacketSAgo : lastPacketSAgo // ignore: cast_nullable_to_non_nullable
as int?,baseLost: null == baseLost ? _self.baseLost : baseLost // ignore: cast_nullable_to_non_nullable
as bool,sessionActive: null == sessionActive ? _self.sessionActive : sessionActive // ignore: cast_nullable_to_non_nullable
as bool,activeSessionId: freezed == activeSessionId ? _self.activeSessionId : activeSessionId // ignore: cast_nullable_to_non_nullable
as int?,storageFreePct: null == storageFreePct ? _self.storageFreePct : storageFreePct // ignore: cast_nullable_to_non_nullable
as int,socPct: freezed == socPct ? _self.socPct : socPct // ignore: cast_nullable_to_non_nullable
as int?,charging: null == charging ? _self.charging : charging // ignore: cast_nullable_to_non_nullable
as bool,alarms: null == alarms ? _self._alarms : alarms // ignore: cast_nullable_to_non_nullable
as List<Alarm>,
  ));
}


}

// dart format on
