// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bridge_transport.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeCapabilities {

 bool get liveState; bool get fullHistory; bool get historyPreview; bool get config; bool get ota;/// Home Assistant / MQTT config (05 §5.7). HTTP-only: the broker lives on
/// the Wi-Fi LAN, so BLE reports false and its settings page explains it.
 bool get mqtt;
/// Create a copy of BridgeCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeCapabilitiesCopyWith<BridgeCapabilities> get copyWith => _$BridgeCapabilitiesCopyWithImpl<BridgeCapabilities>(this as BridgeCapabilities, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeCapabilities&&(identical(other.liveState, liveState) || other.liveState == liveState)&&(identical(other.fullHistory, fullHistory) || other.fullHistory == fullHistory)&&(identical(other.historyPreview, historyPreview) || other.historyPreview == historyPreview)&&(identical(other.config, config) || other.config == config)&&(identical(other.ota, ota) || other.ota == ota)&&(identical(other.mqtt, mqtt) || other.mqtt == mqtt));
}


@override
int get hashCode => Object.hash(runtimeType,liveState,fullHistory,historyPreview,config,ota,mqtt);

@override
String toString() {
  return 'BridgeCapabilities(liveState: $liveState, fullHistory: $fullHistory, historyPreview: $historyPreview, config: $config, ota: $ota, mqtt: $mqtt)';
}


}

/// @nodoc
abstract mixin class $BridgeCapabilitiesCopyWith<$Res>  {
  factory $BridgeCapabilitiesCopyWith(BridgeCapabilities value, $Res Function(BridgeCapabilities) _then) = _$BridgeCapabilitiesCopyWithImpl;
@useResult
$Res call({
 bool liveState, bool fullHistory, bool historyPreview, bool config, bool ota, bool mqtt
});




}
/// @nodoc
class _$BridgeCapabilitiesCopyWithImpl<$Res>
    implements $BridgeCapabilitiesCopyWith<$Res> {
  _$BridgeCapabilitiesCopyWithImpl(this._self, this._then);

  final BridgeCapabilities _self;
  final $Res Function(BridgeCapabilities) _then;

/// Create a copy of BridgeCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? liveState = null,Object? fullHistory = null,Object? historyPreview = null,Object? config = null,Object? ota = null,Object? mqtt = null,}) {
  return _then(_self.copyWith(
liveState: null == liveState ? _self.liveState : liveState // ignore: cast_nullable_to_non_nullable
as bool,fullHistory: null == fullHistory ? _self.fullHistory : fullHistory // ignore: cast_nullable_to_non_nullable
as bool,historyPreview: null == historyPreview ? _self.historyPreview : historyPreview // ignore: cast_nullable_to_non_nullable
as bool,config: null == config ? _self.config : config // ignore: cast_nullable_to_non_nullable
as bool,ota: null == ota ? _self.ota : ota // ignore: cast_nullable_to_non_nullable
as bool,mqtt: null == mqtt ? _self.mqtt : mqtt // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeCapabilities].
extension BridgeCapabilitiesPatterns on BridgeCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BridgeCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BridgeCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BridgeCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _BridgeCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BridgeCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _BridgeCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool liveState,  bool fullHistory,  bool historyPreview,  bool config,  bool ota,  bool mqtt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BridgeCapabilities() when $default != null:
return $default(_that.liveState,_that.fullHistory,_that.historyPreview,_that.config,_that.ota,_that.mqtt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool liveState,  bool fullHistory,  bool historyPreview,  bool config,  bool ota,  bool mqtt)  $default,) {final _that = this;
switch (_that) {
case _BridgeCapabilities():
return $default(_that.liveState,_that.fullHistory,_that.historyPreview,_that.config,_that.ota,_that.mqtt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool liveState,  bool fullHistory,  bool historyPreview,  bool config,  bool ota,  bool mqtt)?  $default,) {final _that = this;
switch (_that) {
case _BridgeCapabilities() when $default != null:
return $default(_that.liveState,_that.fullHistory,_that.historyPreview,_that.config,_that.ota,_that.mqtt);case _:
  return null;

}
}

}

/// @nodoc


class _BridgeCapabilities implements BridgeCapabilities {
  const _BridgeCapabilities({this.liveState = true, this.fullHistory = false, this.historyPreview = false, this.config = false, this.ota = false, this.mqtt = false});
  

@override@JsonKey() final  bool liveState;
@override@JsonKey() final  bool fullHistory;
@override@JsonKey() final  bool historyPreview;
@override@JsonKey() final  bool config;
@override@JsonKey() final  bool ota;
/// Home Assistant / MQTT config (05 §5.7). HTTP-only: the broker lives on
/// the Wi-Fi LAN, so BLE reports false and its settings page explains it.
@override@JsonKey() final  bool mqtt;

/// Create a copy of BridgeCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BridgeCapabilitiesCopyWith<_BridgeCapabilities> get copyWith => __$BridgeCapabilitiesCopyWithImpl<_BridgeCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BridgeCapabilities&&(identical(other.liveState, liveState) || other.liveState == liveState)&&(identical(other.fullHistory, fullHistory) || other.fullHistory == fullHistory)&&(identical(other.historyPreview, historyPreview) || other.historyPreview == historyPreview)&&(identical(other.config, config) || other.config == config)&&(identical(other.ota, ota) || other.ota == ota)&&(identical(other.mqtt, mqtt) || other.mqtt == mqtt));
}


@override
int get hashCode => Object.hash(runtimeType,liveState,fullHistory,historyPreview,config,ota,mqtt);

@override
String toString() {
  return 'BridgeCapabilities(liveState: $liveState, fullHistory: $fullHistory, historyPreview: $historyPreview, config: $config, ota: $ota, mqtt: $mqtt)';
}


}

/// @nodoc
abstract mixin class _$BridgeCapabilitiesCopyWith<$Res> implements $BridgeCapabilitiesCopyWith<$Res> {
  factory _$BridgeCapabilitiesCopyWith(_BridgeCapabilities value, $Res Function(_BridgeCapabilities) _then) = __$BridgeCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
 bool liveState, bool fullHistory, bool historyPreview, bool config, bool ota, bool mqtt
});




}
/// @nodoc
class __$BridgeCapabilitiesCopyWithImpl<$Res>
    implements _$BridgeCapabilitiesCopyWith<$Res> {
  __$BridgeCapabilitiesCopyWithImpl(this._self, this._then);

  final _BridgeCapabilities _self;
  final $Res Function(_BridgeCapabilities) _then;

/// Create a copy of BridgeCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? liveState = null,Object? fullHistory = null,Object? historyPreview = null,Object? config = null,Object? ota = null,Object? mqtt = null,}) {
  return _then(_BridgeCapabilities(
liveState: null == liveState ? _self.liveState : liveState // ignore: cast_nullable_to_non_nullable
as bool,fullHistory: null == fullHistory ? _self.fullHistory : fullHistory // ignore: cast_nullable_to_non_nullable
as bool,historyPreview: null == historyPreview ? _self.historyPreview : historyPreview // ignore: cast_nullable_to_non_nullable
as bool,config: null == config ? _self.config : config // ignore: cast_nullable_to_non_nullable
as bool,ota: null == ota ? _self.ota : ota // ignore: cast_nullable_to_non_nullable
as bool,mqtt: null == mqtt ? _self.mqtt : mqtt // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$BridgeEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BridgeEvent()';
}


}

/// @nodoc
class $BridgeEventCopyWith<$Res>  {
$BridgeEventCopyWith(BridgeEvent _, $Res Function(BridgeEvent) __);
}


/// Adds pattern-matching-related methods to [BridgeEvent].
extension BridgeEventPatterns on BridgeEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSampleEvent value)?  sample,TResult Function( BridgeAlarmEvent value)?  alarm,TResult Function( BridgeSessionEvent value)?  session,TResult Function( BridgeNetEvent value)?  net,TResult Function( BridgePowerEvent value)?  power,TResult Function( BridgePairingEvent value)?  pairing,TResult Function( BridgeOtaEvent value)?  ota,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSampleEvent() when sample != null:
return sample(_that);case BridgeAlarmEvent() when alarm != null:
return alarm(_that);case BridgeSessionEvent() when session != null:
return session(_that);case BridgeNetEvent() when net != null:
return net(_that);case BridgePowerEvent() when power != null:
return power(_that);case BridgePairingEvent() when pairing != null:
return pairing(_that);case BridgeOtaEvent() when ota != null:
return ota(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSampleEvent value)  sample,required TResult Function( BridgeAlarmEvent value)  alarm,required TResult Function( BridgeSessionEvent value)  session,required TResult Function( BridgeNetEvent value)  net,required TResult Function( BridgePowerEvent value)  power,required TResult Function( BridgePairingEvent value)  pairing,required TResult Function( BridgeOtaEvent value)  ota,}){
final _that = this;
switch (_that) {
case BridgeSampleEvent():
return sample(_that);case BridgeAlarmEvent():
return alarm(_that);case BridgeSessionEvent():
return session(_that);case BridgeNetEvent():
return net(_that);case BridgePowerEvent():
return power(_that);case BridgePairingEvent():
return pairing(_that);case BridgeOtaEvent():
return ota(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSampleEvent value)?  sample,TResult? Function( BridgeAlarmEvent value)?  alarm,TResult? Function( BridgeSessionEvent value)?  session,TResult? Function( BridgeNetEvent value)?  net,TResult? Function( BridgePowerEvent value)?  power,TResult? Function( BridgePairingEvent value)?  pairing,TResult? Function( BridgeOtaEvent value)?  ota,}){
final _that = this;
switch (_that) {
case BridgeSampleEvent() when sample != null:
return sample(_that);case BridgeAlarmEvent() when alarm != null:
return alarm(_that);case BridgeSessionEvent() when session != null:
return session(_that);case BridgeNetEvent() when net != null:
return net(_that);case BridgePowerEvent() when power != null:
return power(_that);case BridgePairingEvent() when pairing != null:
return pairing(_that);case BridgeOtaEvent() when ota != null:
return ota(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Sample sample)?  sample,TResult Function( Alarm alarm,  AlarmAction action)?  alarm,TResult Function( SessionAction action,  int sessionId,  String? name)?  session,TResult Function( String mode,  String state,  String? ip)?  net,TResult Function( int socPct,  bool charging,  bool saver)?  power,TResult Function( bool paired,  String? deviceId,  int numProbes)?  pairing,TResult Function( String phase,  int pct)?  ota,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSampleEvent() when sample != null:
return sample(_that.sample);case BridgeAlarmEvent() when alarm != null:
return alarm(_that.alarm,_that.action);case BridgeSessionEvent() when session != null:
return session(_that.action,_that.sessionId,_that.name);case BridgeNetEvent() when net != null:
return net(_that.mode,_that.state,_that.ip);case BridgePowerEvent() when power != null:
return power(_that.socPct,_that.charging,_that.saver);case BridgePairingEvent() when pairing != null:
return pairing(_that.paired,_that.deviceId,_that.numProbes);case BridgeOtaEvent() when ota != null:
return ota(_that.phase,_that.pct);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Sample sample)  sample,required TResult Function( Alarm alarm,  AlarmAction action)  alarm,required TResult Function( SessionAction action,  int sessionId,  String? name)  session,required TResult Function( String mode,  String state,  String? ip)  net,required TResult Function( int socPct,  bool charging,  bool saver)  power,required TResult Function( bool paired,  String? deviceId,  int numProbes)  pairing,required TResult Function( String phase,  int pct)  ota,}) {final _that = this;
switch (_that) {
case BridgeSampleEvent():
return sample(_that.sample);case BridgeAlarmEvent():
return alarm(_that.alarm,_that.action);case BridgeSessionEvent():
return session(_that.action,_that.sessionId,_that.name);case BridgeNetEvent():
return net(_that.mode,_that.state,_that.ip);case BridgePowerEvent():
return power(_that.socPct,_that.charging,_that.saver);case BridgePairingEvent():
return pairing(_that.paired,_that.deviceId,_that.numProbes);case BridgeOtaEvent():
return ota(_that.phase,_that.pct);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Sample sample)?  sample,TResult? Function( Alarm alarm,  AlarmAction action)?  alarm,TResult? Function( SessionAction action,  int sessionId,  String? name)?  session,TResult? Function( String mode,  String state,  String? ip)?  net,TResult? Function( int socPct,  bool charging,  bool saver)?  power,TResult? Function( bool paired,  String? deviceId,  int numProbes)?  pairing,TResult? Function( String phase,  int pct)?  ota,}) {final _that = this;
switch (_that) {
case BridgeSampleEvent() when sample != null:
return sample(_that.sample);case BridgeAlarmEvent() when alarm != null:
return alarm(_that.alarm,_that.action);case BridgeSessionEvent() when session != null:
return session(_that.action,_that.sessionId,_that.name);case BridgeNetEvent() when net != null:
return net(_that.mode,_that.state,_that.ip);case BridgePowerEvent() when power != null:
return power(_that.socPct,_that.charging,_that.saver);case BridgePairingEvent() when pairing != null:
return pairing(_that.paired,_that.deviceId,_that.numProbes);case BridgeOtaEvent() when ota != null:
return ota(_that.phase,_that.pct);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSampleEvent implements BridgeEvent {
  const BridgeSampleEvent(this.sample);
  

 final  Sample sample;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSampleEventCopyWith<BridgeSampleEvent> get copyWith => _$BridgeSampleEventCopyWithImpl<BridgeSampleEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSampleEvent&&(identical(other.sample, sample) || other.sample == sample));
}


@override
int get hashCode => Object.hash(runtimeType,sample);

@override
String toString() {
  return 'BridgeEvent.sample(sample: $sample)';
}


}

/// @nodoc
abstract mixin class $BridgeSampleEventCopyWith<$Res> implements $BridgeEventCopyWith<$Res> {
  factory $BridgeSampleEventCopyWith(BridgeSampleEvent value, $Res Function(BridgeSampleEvent) _then) = _$BridgeSampleEventCopyWithImpl;
@useResult
$Res call({
 Sample sample
});


$SampleCopyWith<$Res> get sample;

}
/// @nodoc
class _$BridgeSampleEventCopyWithImpl<$Res>
    implements $BridgeSampleEventCopyWith<$Res> {
  _$BridgeSampleEventCopyWithImpl(this._self, this._then);

  final BridgeSampleEvent _self;
  final $Res Function(BridgeSampleEvent) _then;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sample = null,}) {
  return _then(BridgeSampleEvent(
null == sample ? _self.sample : sample // ignore: cast_nullable_to_non_nullable
as Sample,
  ));
}

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SampleCopyWith<$Res> get sample {
  
  return $SampleCopyWith<$Res>(_self.sample, (value) {
    return _then(_self.copyWith(sample: value));
  });
}
}

/// @nodoc


class BridgeAlarmEvent implements BridgeEvent {
  const BridgeAlarmEvent({required this.alarm, required this.action});
  

 final  Alarm alarm;
 final  AlarmAction action;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAlarmEventCopyWith<BridgeAlarmEvent> get copyWith => _$BridgeAlarmEventCopyWithImpl<BridgeAlarmEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAlarmEvent&&(identical(other.alarm, alarm) || other.alarm == alarm)&&(identical(other.action, action) || other.action == action));
}


@override
int get hashCode => Object.hash(runtimeType,alarm,action);

@override
String toString() {
  return 'BridgeEvent.alarm(alarm: $alarm, action: $action)';
}


}

/// @nodoc
abstract mixin class $BridgeAlarmEventCopyWith<$Res> implements $BridgeEventCopyWith<$Res> {
  factory $BridgeAlarmEventCopyWith(BridgeAlarmEvent value, $Res Function(BridgeAlarmEvent) _then) = _$BridgeAlarmEventCopyWithImpl;
@useResult
$Res call({
 Alarm alarm, AlarmAction action
});


$AlarmCopyWith<$Res> get alarm;

}
/// @nodoc
class _$BridgeAlarmEventCopyWithImpl<$Res>
    implements $BridgeAlarmEventCopyWith<$Res> {
  _$BridgeAlarmEventCopyWithImpl(this._self, this._then);

  final BridgeAlarmEvent _self;
  final $Res Function(BridgeAlarmEvent) _then;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? alarm = null,Object? action = null,}) {
  return _then(BridgeAlarmEvent(
alarm: null == alarm ? _self.alarm : alarm // ignore: cast_nullable_to_non_nullable
as Alarm,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as AlarmAction,
  ));
}

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AlarmCopyWith<$Res> get alarm {
  
  return $AlarmCopyWith<$Res>(_self.alarm, (value) {
    return _then(_self.copyWith(alarm: value));
  });
}
}

/// @nodoc


class BridgeSessionEvent implements BridgeEvent {
  const BridgeSessionEvent({required this.action, required this.sessionId, this.name});
  

 final  SessionAction action;
 final  int sessionId;
 final  String? name;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSessionEventCopyWith<BridgeSessionEvent> get copyWith => _$BridgeSessionEventCopyWithImpl<BridgeSessionEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSessionEvent&&(identical(other.action, action) || other.action == action)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,action,sessionId,name);

@override
String toString() {
  return 'BridgeEvent.session(action: $action, sessionId: $sessionId, name: $name)';
}


}

/// @nodoc
abstract mixin class $BridgeSessionEventCopyWith<$Res> implements $BridgeEventCopyWith<$Res> {
  factory $BridgeSessionEventCopyWith(BridgeSessionEvent value, $Res Function(BridgeSessionEvent) _then) = _$BridgeSessionEventCopyWithImpl;
@useResult
$Res call({
 SessionAction action, int sessionId, String? name
});




}
/// @nodoc
class _$BridgeSessionEventCopyWithImpl<$Res>
    implements $BridgeSessionEventCopyWith<$Res> {
  _$BridgeSessionEventCopyWithImpl(this._self, this._then);

  final BridgeSessionEvent _self;
  final $Res Function(BridgeSessionEvent) _then;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? action = null,Object? sessionId = null,Object? name = freezed,}) {
  return _then(BridgeSessionEvent(
action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as SessionAction,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as int,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BridgeNetEvent implements BridgeEvent {
  const BridgeNetEvent({required this.mode, required this.state, this.ip});
  

 final  String mode;
 final  String state;
 final  String? ip;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeNetEventCopyWith<BridgeNetEvent> get copyWith => _$BridgeNetEventCopyWithImpl<BridgeNetEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeNetEvent&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.state, state) || other.state == state)&&(identical(other.ip, ip) || other.ip == ip));
}


@override
int get hashCode => Object.hash(runtimeType,mode,state,ip);

@override
String toString() {
  return 'BridgeEvent.net(mode: $mode, state: $state, ip: $ip)';
}


}

/// @nodoc
abstract mixin class $BridgeNetEventCopyWith<$Res> implements $BridgeEventCopyWith<$Res> {
  factory $BridgeNetEventCopyWith(BridgeNetEvent value, $Res Function(BridgeNetEvent) _then) = _$BridgeNetEventCopyWithImpl;
@useResult
$Res call({
 String mode, String state, String? ip
});




}
/// @nodoc
class _$BridgeNetEventCopyWithImpl<$Res>
    implements $BridgeNetEventCopyWith<$Res> {
  _$BridgeNetEventCopyWithImpl(this._self, this._then);

  final BridgeNetEvent _self;
  final $Res Function(BridgeNetEvent) _then;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? mode = null,Object? state = null,Object? ip = freezed,}) {
  return _then(BridgeNetEvent(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,ip: freezed == ip ? _self.ip : ip // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class BridgePowerEvent implements BridgeEvent {
  const BridgePowerEvent({required this.socPct, required this.charging, this.saver = false});
  

 final  int socPct;
 final  bool charging;
@JsonKey() final  bool saver;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePowerEventCopyWith<BridgePowerEvent> get copyWith => _$BridgePowerEventCopyWithImpl<BridgePowerEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePowerEvent&&(identical(other.socPct, socPct) || other.socPct == socPct)&&(identical(other.charging, charging) || other.charging == charging)&&(identical(other.saver, saver) || other.saver == saver));
}


@override
int get hashCode => Object.hash(runtimeType,socPct,charging,saver);

@override
String toString() {
  return 'BridgeEvent.power(socPct: $socPct, charging: $charging, saver: $saver)';
}


}

/// @nodoc
abstract mixin class $BridgePowerEventCopyWith<$Res> implements $BridgeEventCopyWith<$Res> {
  factory $BridgePowerEventCopyWith(BridgePowerEvent value, $Res Function(BridgePowerEvent) _then) = _$BridgePowerEventCopyWithImpl;
@useResult
$Res call({
 int socPct, bool charging, bool saver
});




}
/// @nodoc
class _$BridgePowerEventCopyWithImpl<$Res>
    implements $BridgePowerEventCopyWith<$Res> {
  _$BridgePowerEventCopyWithImpl(this._self, this._then);

  final BridgePowerEvent _self;
  final $Res Function(BridgePowerEvent) _then;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? socPct = null,Object? charging = null,Object? saver = null,}) {
  return _then(BridgePowerEvent(
socPct: null == socPct ? _self.socPct : socPct // ignore: cast_nullable_to_non_nullable
as int,charging: null == charging ? _self.charging : charging // ignore: cast_nullable_to_non_nullable
as bool,saver: null == saver ? _self.saver : saver // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgePairingEvent implements BridgeEvent {
  const BridgePairingEvent({required this.paired, this.deviceId, this.numProbes = 0});
  

 final  bool paired;
 final  String? deviceId;
@JsonKey() final  int numProbes;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePairingEventCopyWith<BridgePairingEvent> get copyWith => _$BridgePairingEventCopyWithImpl<BridgePairingEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePairingEvent&&(identical(other.paired, paired) || other.paired == paired)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.numProbes, numProbes) || other.numProbes == numProbes));
}


@override
int get hashCode => Object.hash(runtimeType,paired,deviceId,numProbes);

@override
String toString() {
  return 'BridgeEvent.pairing(paired: $paired, deviceId: $deviceId, numProbes: $numProbes)';
}


}

/// @nodoc
abstract mixin class $BridgePairingEventCopyWith<$Res> implements $BridgeEventCopyWith<$Res> {
  factory $BridgePairingEventCopyWith(BridgePairingEvent value, $Res Function(BridgePairingEvent) _then) = _$BridgePairingEventCopyWithImpl;
@useResult
$Res call({
 bool paired, String? deviceId, int numProbes
});




}
/// @nodoc
class _$BridgePairingEventCopyWithImpl<$Res>
    implements $BridgePairingEventCopyWith<$Res> {
  _$BridgePairingEventCopyWithImpl(this._self, this._then);

  final BridgePairingEvent _self;
  final $Res Function(BridgePairingEvent) _then;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? paired = null,Object? deviceId = freezed,Object? numProbes = null,}) {
  return _then(BridgePairingEvent(
paired: null == paired ? _self.paired : paired // ignore: cast_nullable_to_non_nullable
as bool,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,numProbes: null == numProbes ? _self.numProbes : numProbes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BridgeOtaEvent implements BridgeEvent {
  const BridgeOtaEvent({required this.phase, this.pct = 0});
  

 final  String phase;
@JsonKey() final  int pct;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeOtaEventCopyWith<BridgeOtaEvent> get copyWith => _$BridgeOtaEventCopyWithImpl<BridgeOtaEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeOtaEvent&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.pct, pct) || other.pct == pct));
}


@override
int get hashCode => Object.hash(runtimeType,phase,pct);

@override
String toString() {
  return 'BridgeEvent.ota(phase: $phase, pct: $pct)';
}


}

/// @nodoc
abstract mixin class $BridgeOtaEventCopyWith<$Res> implements $BridgeEventCopyWith<$Res> {
  factory $BridgeOtaEventCopyWith(BridgeOtaEvent value, $Res Function(BridgeOtaEvent) _then) = _$BridgeOtaEventCopyWithImpl;
@useResult
$Res call({
 String phase, int pct
});




}
/// @nodoc
class _$BridgeOtaEventCopyWithImpl<$Res>
    implements $BridgeOtaEventCopyWith<$Res> {
  _$BridgeOtaEventCopyWithImpl(this._self, this._then);

  final BridgeOtaEvent _self;
  final $Res Function(BridgeOtaEvent) _then;

/// Create a copy of BridgeEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? pct = null,}) {
  return _then(BridgeOtaEvent(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as String,pct: null == pct ? _self.pct : pct // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ControlCommand {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ControlCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ControlCommand()';
}


}

/// @nodoc
class $ControlCommandCopyWith<$Res>  {
$ControlCommandCopyWith(ControlCommand _, $Res Function(ControlCommand) __);
}


/// Adds pattern-matching-related methods to [ControlCommand].
extension ControlCommandPatterns on ControlCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StartSessionCommand value)?  sessionStart,TResult Function( StopSessionCommand value)?  sessionStop,TResult Function( MarkCommand value)?  mark,TResult Function( PairCommand value)?  pair,TResult Function( UnpairCommand value)?  unpair,TResult Function( SetTimeCommand value)?  setTime,TResult Function( AckAlarmCommand value)?  ackAlarm,TResult Function( RebootCommand value)?  reboot,TResult Function( FactoryResetCommand value)?  factoryReset,TResult Function( PowerOffCommand value)?  powerOff,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StartSessionCommand() when sessionStart != null:
return sessionStart(_that);case StopSessionCommand() when sessionStop != null:
return sessionStop(_that);case MarkCommand() when mark != null:
return mark(_that);case PairCommand() when pair != null:
return pair(_that);case UnpairCommand() when unpair != null:
return unpair(_that);case SetTimeCommand() when setTime != null:
return setTime(_that);case AckAlarmCommand() when ackAlarm != null:
return ackAlarm(_that);case RebootCommand() when reboot != null:
return reboot(_that);case FactoryResetCommand() when factoryReset != null:
return factoryReset(_that);case PowerOffCommand() when powerOff != null:
return powerOff(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StartSessionCommand value)  sessionStart,required TResult Function( StopSessionCommand value)  sessionStop,required TResult Function( MarkCommand value)  mark,required TResult Function( PairCommand value)  pair,required TResult Function( UnpairCommand value)  unpair,required TResult Function( SetTimeCommand value)  setTime,required TResult Function( AckAlarmCommand value)  ackAlarm,required TResult Function( RebootCommand value)  reboot,required TResult Function( FactoryResetCommand value)  factoryReset,required TResult Function( PowerOffCommand value)  powerOff,}){
final _that = this;
switch (_that) {
case StartSessionCommand():
return sessionStart(_that);case StopSessionCommand():
return sessionStop(_that);case MarkCommand():
return mark(_that);case PairCommand():
return pair(_that);case UnpairCommand():
return unpair(_that);case SetTimeCommand():
return setTime(_that);case AckAlarmCommand():
return ackAlarm(_that);case RebootCommand():
return reboot(_that);case FactoryResetCommand():
return factoryReset(_that);case PowerOffCommand():
return powerOff(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StartSessionCommand value)?  sessionStart,TResult? Function( StopSessionCommand value)?  sessionStop,TResult? Function( MarkCommand value)?  mark,TResult? Function( PairCommand value)?  pair,TResult? Function( UnpairCommand value)?  unpair,TResult? Function( SetTimeCommand value)?  setTime,TResult? Function( AckAlarmCommand value)?  ackAlarm,TResult? Function( RebootCommand value)?  reboot,TResult? Function( FactoryResetCommand value)?  factoryReset,TResult? Function( PowerOffCommand value)?  powerOff,}){
final _that = this;
switch (_that) {
case StartSessionCommand() when sessionStart != null:
return sessionStart(_that);case StopSessionCommand() when sessionStop != null:
return sessionStop(_that);case MarkCommand() when mark != null:
return mark(_that);case PairCommand() when pair != null:
return pair(_that);case UnpairCommand() when unpair != null:
return unpair(_that);case SetTimeCommand() when setTime != null:
return setTime(_that);case AckAlarmCommand() when ackAlarm != null:
return ackAlarm(_that);case RebootCommand() when reboot != null:
return reboot(_that);case FactoryResetCommand() when factoryReset != null:
return factoryReset(_that);case PowerOffCommand() when powerOff != null:
return powerOff(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  sessionStart,TResult Function()?  sessionStop,TResult Function( MarkKind kind,  int probe,  String text)?  mark,TResult Function()?  pair,TResult Function()?  unpair,TResult Function( int unixMs)?  setTime,TResult Function( int alarmId)?  ackAlarm,TResult Function()?  reboot,TResult Function()?  factoryReset,TResult Function()?  powerOff,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StartSessionCommand() when sessionStart != null:
return sessionStart();case StopSessionCommand() when sessionStop != null:
return sessionStop();case MarkCommand() when mark != null:
return mark(_that.kind,_that.probe,_that.text);case PairCommand() when pair != null:
return pair();case UnpairCommand() when unpair != null:
return unpair();case SetTimeCommand() when setTime != null:
return setTime(_that.unixMs);case AckAlarmCommand() when ackAlarm != null:
return ackAlarm(_that.alarmId);case RebootCommand() when reboot != null:
return reboot();case FactoryResetCommand() when factoryReset != null:
return factoryReset();case PowerOffCommand() when powerOff != null:
return powerOff();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  sessionStart,required TResult Function()  sessionStop,required TResult Function( MarkKind kind,  int probe,  String text)  mark,required TResult Function()  pair,required TResult Function()  unpair,required TResult Function( int unixMs)  setTime,required TResult Function( int alarmId)  ackAlarm,required TResult Function()  reboot,required TResult Function()  factoryReset,required TResult Function()  powerOff,}) {final _that = this;
switch (_that) {
case StartSessionCommand():
return sessionStart();case StopSessionCommand():
return sessionStop();case MarkCommand():
return mark(_that.kind,_that.probe,_that.text);case PairCommand():
return pair();case UnpairCommand():
return unpair();case SetTimeCommand():
return setTime(_that.unixMs);case AckAlarmCommand():
return ackAlarm(_that.alarmId);case RebootCommand():
return reboot();case FactoryResetCommand():
return factoryReset();case PowerOffCommand():
return powerOff();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  sessionStart,TResult? Function()?  sessionStop,TResult? Function( MarkKind kind,  int probe,  String text)?  mark,TResult? Function()?  pair,TResult? Function()?  unpair,TResult? Function( int unixMs)?  setTime,TResult? Function( int alarmId)?  ackAlarm,TResult? Function()?  reboot,TResult? Function()?  factoryReset,TResult? Function()?  powerOff,}) {final _that = this;
switch (_that) {
case StartSessionCommand() when sessionStart != null:
return sessionStart();case StopSessionCommand() when sessionStop != null:
return sessionStop();case MarkCommand() when mark != null:
return mark(_that.kind,_that.probe,_that.text);case PairCommand() when pair != null:
return pair();case UnpairCommand() when unpair != null:
return unpair();case SetTimeCommand() when setTime != null:
return setTime(_that.unixMs);case AckAlarmCommand() when ackAlarm != null:
return ackAlarm(_that.alarmId);case RebootCommand() when reboot != null:
return reboot();case FactoryResetCommand() when factoryReset != null:
return factoryReset();case PowerOffCommand() when powerOff != null:
return powerOff();case _:
  return null;

}
}

}

/// @nodoc


class StartSessionCommand implements ControlCommand {
  const StartSessionCommand();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartSessionCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ControlCommand.sessionStart()';
}


}




/// @nodoc


class StopSessionCommand implements ControlCommand {
  const StopSessionCommand();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StopSessionCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ControlCommand.sessionStop()';
}


}




/// @nodoc


class MarkCommand implements ControlCommand {
  const MarkCommand({required this.kind, this.probe = 0, this.text = ''});
  

 final  MarkKind kind;
@JsonKey() final  int probe;
@JsonKey() final  String text;

/// Create a copy of ControlCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MarkCommandCopyWith<MarkCommand> get copyWith => _$MarkCommandCopyWithImpl<MarkCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MarkCommand&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.probe, probe) || other.probe == probe)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,kind,probe,text);

@override
String toString() {
  return 'ControlCommand.mark(kind: $kind, probe: $probe, text: $text)';
}


}

/// @nodoc
abstract mixin class $MarkCommandCopyWith<$Res> implements $ControlCommandCopyWith<$Res> {
  factory $MarkCommandCopyWith(MarkCommand value, $Res Function(MarkCommand) _then) = _$MarkCommandCopyWithImpl;
@useResult
$Res call({
 MarkKind kind, int probe, String text
});




}
/// @nodoc
class _$MarkCommandCopyWithImpl<$Res>
    implements $MarkCommandCopyWith<$Res> {
  _$MarkCommandCopyWithImpl(this._self, this._then);

  final MarkCommand _self;
  final $Res Function(MarkCommand) _then;

/// Create a copy of ControlCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? probe = null,Object? text = null,}) {
  return _then(MarkCommand(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as MarkKind,probe: null == probe ? _self.probe : probe // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PairCommand implements ControlCommand {
  const PairCommand();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PairCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ControlCommand.pair()';
}


}




/// @nodoc


class UnpairCommand implements ControlCommand {
  const UnpairCommand();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UnpairCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ControlCommand.unpair()';
}


}




/// @nodoc


class SetTimeCommand implements ControlCommand {
  const SetTimeCommand({required this.unixMs});
  

 final  int unixMs;

/// Create a copy of ControlCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetTimeCommandCopyWith<SetTimeCommand> get copyWith => _$SetTimeCommandCopyWithImpl<SetTimeCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetTimeCommand&&(identical(other.unixMs, unixMs) || other.unixMs == unixMs));
}


@override
int get hashCode => Object.hash(runtimeType,unixMs);

@override
String toString() {
  return 'ControlCommand.setTime(unixMs: $unixMs)';
}


}

/// @nodoc
abstract mixin class $SetTimeCommandCopyWith<$Res> implements $ControlCommandCopyWith<$Res> {
  factory $SetTimeCommandCopyWith(SetTimeCommand value, $Res Function(SetTimeCommand) _then) = _$SetTimeCommandCopyWithImpl;
@useResult
$Res call({
 int unixMs
});




}
/// @nodoc
class _$SetTimeCommandCopyWithImpl<$Res>
    implements $SetTimeCommandCopyWith<$Res> {
  _$SetTimeCommandCopyWithImpl(this._self, this._then);

  final SetTimeCommand _self;
  final $Res Function(SetTimeCommand) _then;

/// Create a copy of ControlCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? unixMs = null,}) {
  return _then(SetTimeCommand(
unixMs: null == unixMs ? _self.unixMs : unixMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class AckAlarmCommand implements ControlCommand {
  const AckAlarmCommand({required this.alarmId});
  

 final  int alarmId;

/// Create a copy of ControlCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AckAlarmCommandCopyWith<AckAlarmCommand> get copyWith => _$AckAlarmCommandCopyWithImpl<AckAlarmCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AckAlarmCommand&&(identical(other.alarmId, alarmId) || other.alarmId == alarmId));
}


@override
int get hashCode => Object.hash(runtimeType,alarmId);

@override
String toString() {
  return 'ControlCommand.ackAlarm(alarmId: $alarmId)';
}


}

/// @nodoc
abstract mixin class $AckAlarmCommandCopyWith<$Res> implements $ControlCommandCopyWith<$Res> {
  factory $AckAlarmCommandCopyWith(AckAlarmCommand value, $Res Function(AckAlarmCommand) _then) = _$AckAlarmCommandCopyWithImpl;
@useResult
$Res call({
 int alarmId
});




}
/// @nodoc
class _$AckAlarmCommandCopyWithImpl<$Res>
    implements $AckAlarmCommandCopyWith<$Res> {
  _$AckAlarmCommandCopyWithImpl(this._self, this._then);

  final AckAlarmCommand _self;
  final $Res Function(AckAlarmCommand) _then;

/// Create a copy of ControlCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? alarmId = null,}) {
  return _then(AckAlarmCommand(
alarmId: null == alarmId ? _self.alarmId : alarmId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RebootCommand implements ControlCommand {
  const RebootCommand();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RebootCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ControlCommand.reboot()';
}


}




/// @nodoc


class FactoryResetCommand implements ControlCommand {
  const FactoryResetCommand();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FactoryResetCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ControlCommand.factoryReset()';
}


}




/// @nodoc


class PowerOffCommand implements ControlCommand {
  const PowerOffCommand();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PowerOffCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ControlCommand.powerOff()';
}


}




/// @nodoc
mixin _$BridgeConfig {

 String? get displayUnits; List<Probe>? get probes; BatterySaverMode? get batterySaver;/// The bridge's own OLED timeout, seconds. The firmware has taken this
/// since F13; nothing could send it.
 int? get displayTimeoutS;/// The status LED. Likewise.
 bool? get ledEnabled;/// How many cooks the bridge keeps before the oldest are dropped.
 int? get maxSessions;
/// Create a copy of BridgeConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConfigCopyWith<BridgeConfig> get copyWith => _$BridgeConfigCopyWithImpl<BridgeConfig>(this as BridgeConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConfig&&(identical(other.displayUnits, displayUnits) || other.displayUnits == displayUnits)&&const DeepCollectionEquality().equals(other.probes, probes)&&(identical(other.batterySaver, batterySaver) || other.batterySaver == batterySaver)&&(identical(other.displayTimeoutS, displayTimeoutS) || other.displayTimeoutS == displayTimeoutS)&&(identical(other.ledEnabled, ledEnabled) || other.ledEnabled == ledEnabled)&&(identical(other.maxSessions, maxSessions) || other.maxSessions == maxSessions));
}


@override
int get hashCode => Object.hash(runtimeType,displayUnits,const DeepCollectionEquality().hash(probes),batterySaver,displayTimeoutS,ledEnabled,maxSessions);

@override
String toString() {
  return 'BridgeConfig(displayUnits: $displayUnits, probes: $probes, batterySaver: $batterySaver, displayTimeoutS: $displayTimeoutS, ledEnabled: $ledEnabled, maxSessions: $maxSessions)';
}


}

/// @nodoc
abstract mixin class $BridgeConfigCopyWith<$Res>  {
  factory $BridgeConfigCopyWith(BridgeConfig value, $Res Function(BridgeConfig) _then) = _$BridgeConfigCopyWithImpl;
@useResult
$Res call({
 String? displayUnits, List<Probe>? probes, BatterySaverMode? batterySaver, int? displayTimeoutS, bool? ledEnabled, int? maxSessions
});




}
/// @nodoc
class _$BridgeConfigCopyWithImpl<$Res>
    implements $BridgeConfigCopyWith<$Res> {
  _$BridgeConfigCopyWithImpl(this._self, this._then);

  final BridgeConfig _self;
  final $Res Function(BridgeConfig) _then;

/// Create a copy of BridgeConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? displayUnits = freezed,Object? probes = freezed,Object? batterySaver = freezed,Object? displayTimeoutS = freezed,Object? ledEnabled = freezed,Object? maxSessions = freezed,}) {
  return _then(_self.copyWith(
displayUnits: freezed == displayUnits ? _self.displayUnits : displayUnits // ignore: cast_nullable_to_non_nullable
as String?,probes: freezed == probes ? _self.probes : probes // ignore: cast_nullable_to_non_nullable
as List<Probe>?,batterySaver: freezed == batterySaver ? _self.batterySaver : batterySaver // ignore: cast_nullable_to_non_nullable
as BatterySaverMode?,displayTimeoutS: freezed == displayTimeoutS ? _self.displayTimeoutS : displayTimeoutS // ignore: cast_nullable_to_non_nullable
as int?,ledEnabled: freezed == ledEnabled ? _self.ledEnabled : ledEnabled // ignore: cast_nullable_to_non_nullable
as bool?,maxSessions: freezed == maxSessions ? _self.maxSessions : maxSessions // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeConfig].
extension BridgeConfigPatterns on BridgeConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BridgeConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BridgeConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BridgeConfig value)  $default,){
final _that = this;
switch (_that) {
case _BridgeConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BridgeConfig value)?  $default,){
final _that = this;
switch (_that) {
case _BridgeConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? displayUnits,  List<Probe>? probes,  BatterySaverMode? batterySaver,  int? displayTimeoutS,  bool? ledEnabled,  int? maxSessions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BridgeConfig() when $default != null:
return $default(_that.displayUnits,_that.probes,_that.batterySaver,_that.displayTimeoutS,_that.ledEnabled,_that.maxSessions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? displayUnits,  List<Probe>? probes,  BatterySaverMode? batterySaver,  int? displayTimeoutS,  bool? ledEnabled,  int? maxSessions)  $default,) {final _that = this;
switch (_that) {
case _BridgeConfig():
return $default(_that.displayUnits,_that.probes,_that.batterySaver,_that.displayTimeoutS,_that.ledEnabled,_that.maxSessions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? displayUnits,  List<Probe>? probes,  BatterySaverMode? batterySaver,  int? displayTimeoutS,  bool? ledEnabled,  int? maxSessions)?  $default,) {final _that = this;
switch (_that) {
case _BridgeConfig() when $default != null:
return $default(_that.displayUnits,_that.probes,_that.batterySaver,_that.displayTimeoutS,_that.ledEnabled,_that.maxSessions);case _:
  return null;

}
}

}

/// @nodoc


class _BridgeConfig implements BridgeConfig {
  const _BridgeConfig({this.displayUnits, final  List<Probe>? probes, this.batterySaver, this.displayTimeoutS, this.ledEnabled, this.maxSessions}): _probes = probes;
  

@override final  String? displayUnits;
 final  List<Probe>? _probes;
@override List<Probe>? get probes {
  final value = _probes;
  if (value == null) return null;
  if (_probes is EqualUnmodifiableListView) return _probes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override final  BatterySaverMode? batterySaver;
/// The bridge's own OLED timeout, seconds. The firmware has taken this
/// since F13; nothing could send it.
@override final  int? displayTimeoutS;
/// The status LED. Likewise.
@override final  bool? ledEnabled;
/// How many cooks the bridge keeps before the oldest are dropped.
@override final  int? maxSessions;

/// Create a copy of BridgeConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BridgeConfigCopyWith<_BridgeConfig> get copyWith => __$BridgeConfigCopyWithImpl<_BridgeConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BridgeConfig&&(identical(other.displayUnits, displayUnits) || other.displayUnits == displayUnits)&&const DeepCollectionEquality().equals(other._probes, _probes)&&(identical(other.batterySaver, batterySaver) || other.batterySaver == batterySaver)&&(identical(other.displayTimeoutS, displayTimeoutS) || other.displayTimeoutS == displayTimeoutS)&&(identical(other.ledEnabled, ledEnabled) || other.ledEnabled == ledEnabled)&&(identical(other.maxSessions, maxSessions) || other.maxSessions == maxSessions));
}


@override
int get hashCode => Object.hash(runtimeType,displayUnits,const DeepCollectionEquality().hash(_probes),batterySaver,displayTimeoutS,ledEnabled,maxSessions);

@override
String toString() {
  return 'BridgeConfig(displayUnits: $displayUnits, probes: $probes, batterySaver: $batterySaver, displayTimeoutS: $displayTimeoutS, ledEnabled: $ledEnabled, maxSessions: $maxSessions)';
}


}

/// @nodoc
abstract mixin class _$BridgeConfigCopyWith<$Res> implements $BridgeConfigCopyWith<$Res> {
  factory _$BridgeConfigCopyWith(_BridgeConfig value, $Res Function(_BridgeConfig) _then) = __$BridgeConfigCopyWithImpl;
@override @useResult
$Res call({
 String? displayUnits, List<Probe>? probes, BatterySaverMode? batterySaver, int? displayTimeoutS, bool? ledEnabled, int? maxSessions
});




}
/// @nodoc
class __$BridgeConfigCopyWithImpl<$Res>
    implements _$BridgeConfigCopyWith<$Res> {
  __$BridgeConfigCopyWithImpl(this._self, this._then);

  final _BridgeConfig _self;
  final $Res Function(_BridgeConfig) _then;

/// Create a copy of BridgeConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? displayUnits = freezed,Object? probes = freezed,Object? batterySaver = freezed,Object? displayTimeoutS = freezed,Object? ledEnabled = freezed,Object? maxSessions = freezed,}) {
  return _then(_BridgeConfig(
displayUnits: freezed == displayUnits ? _self.displayUnits : displayUnits // ignore: cast_nullable_to_non_nullable
as String?,probes: freezed == probes ? _self._probes : probes // ignore: cast_nullable_to_non_nullable
as List<Probe>?,batterySaver: freezed == batterySaver ? _self.batterySaver : batterySaver // ignore: cast_nullable_to_non_nullable
as BatterySaverMode?,displayTimeoutS: freezed == displayTimeoutS ? _self.displayTimeoutS : displayTimeoutS // ignore: cast_nullable_to_non_nullable
as int?,ledEnabled: freezed == ledEnabled ? _self.ledEnabled : ledEnabled // ignore: cast_nullable_to_non_nullable
as bool?,maxSessions: freezed == maxSessions ? _self.maxSessions : maxSessions // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
