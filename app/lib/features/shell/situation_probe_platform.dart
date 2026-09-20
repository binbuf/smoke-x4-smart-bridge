/// The production [SituationProbe] — the observable middle column of §16.3.
///
/// Everything here is a *best-effort* read of the phone, and every one of them
/// can legitimately fail: the plugin may not have booted, the channel may not
/// exist (a desktop build, a widget test), the OEM may refuse. **A failure is
/// answered with null**, which the reconciler reads as "not known yet" and
/// steps over — never as a verdict. Telling somebody their Bluetooth is off
/// because a method channel was missing would be exactly the class of bug this
/// whole layer was written to end.
///
/// Two of the seven answers are deliberately narrower than they look:
///
///  * [visibleApSsid] is **always null on Android**. Naming the networks in
///    range needs the location permission the manifest promises never to take
///    (A6.6, `neverForLocation`), and no recovery path is worth breaking that
///    promise for — especially since the tell arrives anyway from the device
///    itself, over Bluetooth, as `net_status.mode == ap`.
///  * [joinNetwork] can only join a network whose key it holds, and the app
///    stores no Wi-Fi key by design (05 §5.9). It answers false rather than
///    prompting for something it cannot complete, and the resolver then names
///    the cause and offers the one action instead of reporting a fix.
library;

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../../platform/network_binder.dart';
import '../../platform/system_settings.dart';
import '../setup/preflight.dart';
import '../setup/preflight_platform.dart';
import 'situation_resolver.dart';

/// The `SmokeBridge-…` prefix the firmware advertises and hosts under. A bond
/// that does not match it belongs to somebody's headphones.
const String kBridgeNamePrefix = 'SmokeBridge';

class PlatformSituationProbe implements SituationProbe {
  PlatformSituationProbe({
    required this.preflight,
    SystemSettings? settings,
    this.binder,
  }) : _settings = settings ?? SystemSettings();

  /// Wires the real preflight (adapter + permissions, already bench-proven by
  /// setup) and the OS-settings deep links. Returns null when the platform
  /// will not answer at all, so a caller can fall back to
  /// [UnknownSituationProbe] rather than hold a probe that throws.
  static Future<PlatformSituationProbe?> create({
    SystemSettings? settings,
    NetworkBinder? binder,
  }) async {
    try {
      final resolved = settings ?? SystemSettings();
      return PlatformSituationProbe(
        preflight: await PlatformPreflightProbe.create(settings: resolved),
        settings: resolved,
        binder: binder,
      );
    } on Object {
      return null;
    }
  }

  /// The adapter + permission reads, shared verbatim with guided setup —
  /// the same seam the bench already proved.
  final PreflightProbe preflight;

  /// The phone half of the AP-routing mitigation. Null where nothing wired
  /// one, and [joinNetwork] then answers false rather than pretending.
  final NetworkBinder? binder;

  final SystemSettings _settings;

  /// Whether the last permission read said the OS will no longer prompt. It
  /// decides which of the two grant routes [requestMissingPermission] takes,
  /// because a prompt that can never appear is a dead button.
  bool _permissionPermanent = false;

  @override
  Future<bool?> bluetoothOn() async {
    try {
      return switch (preflight.adapterStateNow) {
        SetupAdapterState.on => true,
        SetupAdapterState.off => false,
        // Unauthorized is a permission problem wearing a radio's clothes, and
        // unsupported is not something a user can switch on. Both are handled
        // above this line, so neither may read as "the radio is off".
        SetupAdapterState.unauthorized ||
        SetupAdapterState.unsupported ||
        SetupAdapterState.unknown => null,
      };
    } on Object {
      return null;
    }
  }

  /// The one missing permission, in the OS's own words.
  ///
  /// Android 12+ groups `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` under **Nearby
  /// devices**, which is the name on the settings screen the user will be
  /// looking at; on Android ≤ 30 the same capability sits under **Location**.
  /// Naming the permission the way the OS names it is the difference between
  /// an instruction someone can follow and one they cannot.
  @override
  Future<String?> missingPermission() async {
    try {
      if (preflight.adapterStateNow == SetupAdapterState.unauthorized) {
        _permissionPermanent = true;
        return _permissionName;
      }
      final verdict = await preflight.permissionStatus();
      _permissionPermanent =
          verdict == PreflightPermission.permanentlyDenied;
      return verdict == PreflightPermission.granted ? null : _permissionName;
    } on Object {
      return null;
    }
  }

  String get _permissionName =>
      preflight.needsLocationServices ? 'Location' : 'Nearby devices';

  /// A bridge in the OS bond table — the tell that this phone was reset and
  /// the pairing survived on the device side.
  @override
  Future<BondedBridge?> bondedBridge() async {
    try {
      for (final d in await fbp.FlutterBluePlus.bondedDevices) {
        final name = d.platformName.isEmpty ? d.advName : d.platformName;
        if (name.startsWith(kBridgeNamePrefix)) {
          return BondedBridge(deviceId: d.remoteId.str, name: name);
        }
      }
      return null;
    } on Object {
      // No radio, no permission, not Android, or a widget test with no
      // channel. All four mean "cannot tell", which is not "no bond".
      return null;
    }
  }

  /// Always null — see the library comment. The promise not to take the
  /// location permission outranks this lane, and the device tells us anyway.
  @override
  Future<String?> visibleApSsid() async => null;

  @override
  Future<bool> joinNetwork(String ssid, {String psk = ''}) async {
    final joiner = binder;
    if (joiner == null || ssid.isEmpty || psk.isEmpty) {
      // No key means no join. Prompting the user to pick a network out of a
      // system dialog, mid-cook, is not "the app handled it".
      return false;
    }
    try {
      await joiner.joinAp(ssid, psk);
      return joiner.state == BinderState.bound;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> openBluetoothSettings() async {
    try {
      await _settings.openBluetoothSettings();
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> requestMissingPermission() async {
    try {
      if (_permissionPermanent) {
        // The dialog will never appear again; app settings is the only route
        // left, and offering the prompt would be a button that does nothing.
        await _settings.openAppSettings();
        return false;
      }
      return await preflight.requestPermissions() ==
          PreflightPermission.granted;
    } on Object {
      return false;
    }
  }
}
