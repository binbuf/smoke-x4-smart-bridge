/// A14.1 — the network binder: the phone half of the Android AP-routing
/// mitigation (design 05 §5.8.1–5.8.2, 08 §8.8).
///
/// The trap this exists for: the phone joins the bridge's AP, Android
/// probes connectivitycheck.gstatic.com, gets nothing (our AP has no
/// internet), marks the network unvalidated, and keeps the default route
/// on cellular — so requests to 192.168.4.1 leave the mobile interface
/// and vanish. `bind()` pins this app's process to the Wi-Fi network so
/// routing is explicit, not Android's guess.
///
/// The failure mode of forgetting to unbind is "the app has no internet
/// anywhere, forever" — hence the strict lifecycle: every bind path has
/// an owning unbind path, misuse is defined behaviour, and a lost network
/// unbinds implicitly (with the state stream saying so).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The binder's observable state.
enum BinderState {
  unbound,
  binding, // request filed, waiting for onAvailable
  bound,
  lost, // the network went away; the binding is already released
}

/// Thrown for misuse the platform would otherwise turn into
/// platform-dependent luck.
class BinderStateError extends StateError {
  BinderStateError(super.message);
}

/// The narrow platform seam. Production is [ChannelNetworkBinder];
/// tests and M2's no-device flows use [FakeNetworkBinder].
abstract interface class NetworkBinder {
  BinderState get state;
  Stream<BinderState> get states;

  /// Pins the app's process to the connected Wi-Fi network. Resolves on
  /// onAvailable. Throws [BinderStateError] when already bound/binding.
  Future<void> bind();

  /// Releases the pin. Safe exactly once per bind; unbinding while
  /// unbound throws [BinderStateError] (a double-release is a lifecycle
  /// bug worth failing loudly in development).
  Future<void> unbind();

  /// The WifiNetworkSpecifier one-tap join: credentials already known
  /// from provisioning, no Settings round-trip. Resolves when the AP is
  /// joined AND bound (the join implies the bind — a joined-but-unbound
  /// AP is exactly the trap).
  Future<void> joinAp(String ssid, String psk);

  Future<void> dispose();
}

/// Production implementation over the MethodChannel to A14.2's Kotlin.
class ChannelNetworkBinder implements NetworkBinder {
  ChannelNetworkBinder({@visibleForTesting MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('smokebridge/network_binder') {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  final MethodChannel _channel;
  final _states = StreamController<BinderState>.broadcast();
  BinderState _state = BinderState.unbound;

  @override
  BinderState get state => _state;

  @override
  Stream<BinderState> get states => _states.stream;

  void _setState(BinderState s) {
    _state = s;
    _states.add(s);
  }

  /// The Kotlin side pushes lifecycle callbacks (onAvailable → "bound",
  /// onLost → "lost").
  Future<Object?> _onPlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onBound':
        _setState(BinderState.bound);
      case 'onLost':
        // The platform already released the binding: reflect, don't act.
        _setState(BinderState.lost);
    }
    return null;
  }

  @override
  Future<void> bind() async {
    if (_state == BinderState.bound || _state == BinderState.binding) {
      throw BinderStateError('bind() while $_state');
    }
    _setState(BinderState.binding);
    try {
      await _channel.invokeMethod<void>('bind');
    } on PlatformException {
      _setState(BinderState.unbound);
      rethrow;
    }
  }

  @override
  Future<void> unbind() async {
    if (_state == BinderState.unbound) {
      throw BinderStateError('unbind() while unbound');
    }
    await _channel.invokeMethod<void>('unbind');
    _setState(BinderState.unbound);
  }

  @override
  Future<void> joinAp(String ssid, String psk) async {
    if (_state == BinderState.bound || _state == BinderState.binding) {
      throw BinderStateError('joinAp() while $_state');
    }
    _setState(BinderState.binding);
    try {
      await _channel.invokeMethod<void>('joinAp', {'ssid': ssid, 'psk': psk});
    } on PlatformException {
      _setState(BinderState.unbound);
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    // Dispose is a guaranteed-release path, never a thrower.
    if (_state == BinderState.bound || _state == BinderState.binding) {
      try {
        await _channel.invokeMethod<void>('unbind');
      } on PlatformException {
        // The process is going away; the platform side also unbinds on
        // activity destroy. Nothing useful to do.
      }
      _setState(BinderState.unbound);
    }
    await _states.close();
  }
}

/// The contract double: same state machine, no platform. A7 and the
/// onboarding logic test against this; A14.2's Kotlin must answer the
/// same call/response vectors.
class FakeNetworkBinder implements NetworkBinder {
  final _states = StreamController<BinderState>.broadcast();
  BinderState _state = BinderState.unbound;
  final calls = <String>[];

  /// Test hook: the fake's network drops (Android's onLost).
  void simulateLost() {
    if (_state == BinderState.bound) {
      _state = BinderState.lost;
      _states.add(_state);
    }
  }

  @override
  BinderState get state => _state;

  @override
  Stream<BinderState> get states => _states.stream;

  @override
  Future<void> bind() async {
    if (_state == BinderState.bound || _state == BinderState.binding) {
      throw BinderStateError('bind() while $_state');
    }
    calls.add('bind');
    _state = BinderState.bound;
    _states.add(_state);
  }

  @override
  Future<void> unbind() async {
    if (_state == BinderState.unbound) {
      throw BinderStateError('unbind() while unbound');
    }
    calls.add('unbind');
    _state = BinderState.unbound;
    _states.add(_state);
  }

  @override
  Future<void> joinAp(String ssid, String psk) async {
    if (_state == BinderState.bound || _state == BinderState.binding) {
      throw BinderStateError('joinAp() while $_state');
    }
    calls.add('joinAp:$ssid');
    _state = BinderState.bound;
    _states.add(_state);
  }

  @override
  Future<void> dispose() async {
    if (_state == BinderState.bound) {
      calls.add('unbind');
      _state = BinderState.unbound;
    }
    await _states.close();
  }
}
