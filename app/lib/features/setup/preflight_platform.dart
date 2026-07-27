/// A24.2 — the REAL [PreflightProbe] (design 13 §13.2.0), replacing the honest
/// stub `setup_route.dart`'s `_FbpPreflightProbe` describes.
///
/// WHY: `preflight.dart` calls no platform APIs on purpose — every §13.2.0 check
/// is read through an injected [PreflightProbe] so the truth table is testable
/// with no phone. Until this task the only production probe reported permission
/// `granted` and no location requirement, because `permission_handler` was not
/// in the package set and there was no platform-version seam. It is now: this
/// probe wires the adapter to `flutter_blue_plus` (as the stub already did) AND
/// the permission/location gates to [AppPermissions] + [SystemSettings], so the
/// primer (check 2/3) and the Android ≤ 32 location-services gate (check 1)
/// become real on device.
///
/// The adapter half calls `flutter_blue_plus` statics directly — the same
/// bench-proven seam the stub used; only a phone can exercise it, so there is no
/// value in a fake here. The permission half goes through [AppPermissions],
/// which IS fakeable (`permissions_test.dart`).
library;

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../../platform/permissions.dart';
import '../../platform/system_settings.dart';
import 'preflight.dart';

/// The production [PreflightProbe] (§13.2.0). Build it with [create], which
/// reads the OS version once so the sync [needsLocationServices] getter and the
/// [AppPermissions] set selection agree on the same level.
class PlatformPreflightProbe implements PreflightProbe {
  PlatformPreflightProbe({
    required AppPermissions permissions,
    required int? androidSdkInt,
  }) : _perms = permissions,
       _sdk = androidSdkInt;

  /// Reads `Build.VERSION.SDK_INT` from [SystemSettings], then wires a
  /// production [AppPermissions] told that level. Null off Android → every
  /// version-gated leg is skipped, which is correct for a modern OS.
  static Future<PlatformPreflightProbe> create({
    SystemSettings? settings,
  }) async {
    final sdk = await (settings ?? SystemSettings()).androidSdkInt();
    return PlatformPreflightProbe(
      permissions: AppPermissions.production(androidSdkInt: sdk),
      androidSdkInt: sdk,
    );
  }

  final AppPermissions _perms;
  final int? _sdk;

  @override
  SetupAdapterState get adapterStateNow =>
      _map(fbp.FlutterBluePlus.adapterStateNow);

  @override
  Stream<SetupAdapterState> get adapterStates =>
      fbp.FlutterBluePlus.adapterState.map(_map);

  @override
  Future<void> requestEnable() async {
    try {
      await fbp.FlutterBluePlus.turnOn();
    } on Object {
      // A refusal simply leaves the adapter off; the gate re-reads it.
    }
  }

  /// §13.2.0 check 1 applies on Android SDK ≤ 32, where a scan needs location
  /// services ON. Null (off Android) / 33+ → false.
  @override
  bool get needsLocationServices => _sdk != null && _sdk <= 32;

  @override
  Future<bool> isLocationServicesOn() => _perms.locationServicesEnabled();

  @override
  Future<PreflightPermission> permissionStatus() async =>
      _toPreflight(await _perms.bleStatus());

  @override
  Future<PreflightPermission> requestPermissions() async =>
      _toPreflight(await _perms.ensureBleReady());

  static PreflightPermission _toPreflight(PermissionResult r) => switch (r) {
    PermissionResult.granted => PreflightPermission.granted,
    PermissionResult.denied => PreflightPermission.denied,
    PermissionResult.permanentlyDenied => PreflightPermission.permanentlyDenied,
  };

  static SetupAdapterState _map(fbp.BluetoothAdapterState s) => switch (s) {
    fbp.BluetoothAdapterState.on => SetupAdapterState.on,
    fbp.BluetoothAdapterState.off ||
    fbp.BluetoothAdapterState.turningOff => SetupAdapterState.off,
    fbp.BluetoothAdapterState.unavailable => SetupAdapterState.unsupported,
    fbp.BluetoothAdapterState.unauthorized => SetupAdapterState.unauthorized,
    fbp.BluetoothAdapterState.turningOn ||
    fbp.BluetoothAdapterState.unknown => SetupAdapterState.unknown,
  };
}
