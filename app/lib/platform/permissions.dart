/// A24.2 — runtime BLE / notification permissions (design 13 §13.2.0, 05 §5.8.3).
///
/// WHY this exists: the manifest DECLARES `BLUETOOTH_SCAN`/`CONNECT`,
/// `NEARBY_WIFI_DEVICES`, `POST_NOTIFICATIONS` and the legacy location trio, but
/// nothing REQUESTS them at runtime — so on Android 12+ a scan silently returns
/// nothing until `flutter_blue_plus` happens to prompt at scan time, which is
/// exactly the "No bridges found" collapse the preflight gate (§13.2.0 check
/// 2/3) is meant to pre-empt. This file lets the primer prompt for real.
///
/// The plugin (`permission_handler`) lives behind [PermissionBackend] — the
/// same seam discipline `nsd`, `flutter_blue_plus` and the network binder use —
/// so the version-gated set selection and the granted/denied/permanentlyDenied
/// mapping are pure Dart, driven by a fake in `permissions_test.dart` with no OS
/// prompt. Only [PermissionHandlerBackend] touches the plugin, and nothing in
/// this file reaches a platform channel.
library;

import 'package:permission_handler/permission_handler.dart' as ph;

/// The runtime permissions this app asks for. Named rather than the plugin's
/// `Permission` so callers (and the fake) never import `permission_handler`.
enum AppPermission { bluetoothScan, bluetoothConnect, location, notification }

/// The subset of `permission_handler`'s `PermissionStatus` this app acts on,
/// re-declared at the seam so [AppPermissions]' reduction is exercisable with no
/// plugin. `restricted`/`limited`/`provisional` are iOS shapes kept for a total
/// mapping even though v1 is Android-only.
enum RawPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  limited,
  provisional,
}

/// The routing-relevant verdict: the three outcomes the setup gate branches on
/// (§13.2.0). `denied` can be retried/primed; `permanentlyDenied` has only the
/// app-settings route left.
enum PermissionResult { granted, denied, permanentlyDenied }

/// The injected plugin seam. A fake implementing this drives the whole set
/// selection + reduction with no radio and no OS dialogs.
abstract interface class PermissionBackend {
  /// Prompt for [p] and report the resulting status.
  Future<RawPermissionStatus> request(AppPermission p);

  /// The current status of [p] WITHOUT prompting.
  Future<RawPermissionStatus> status(AppPermission p);

  /// Android API level, or null off Android (iOS / desktop / test). The
  /// version thresholds (BLE needs location ≤ 30; the §13.2.0 location-services
  /// gate ≤ 32) are decided by the CALLERS, not here, so both stay testable
  /// against a fake that just names a level.
  int? get androidSdkInt;

  /// The device's location-services master toggle — a *service* status, not a
  /// permission (`permission_handler`'s `serviceStatus`). Consulted by the
  /// preflight location gate (§13.2.0 check 1).
  Future<bool> locationServicesEnabled();
}

/// Requests and reads the app's runtime permissions, reducing the plugin's
/// per-permission statuses to the single [PermissionResult] the setup gate acts
/// on. Const and backend-only: every method re-reads the world.
class AppPermissions {
  const AppPermissions(this._backend);

  /// Production wiring: `permission_handler` behind the seam, told the OS
  /// version so the Android ≤ 30 BLE-location leg is requested ONLY where it
  /// applies — requesting `ACCESS_FINE_LOCATION` on Android 12+ would prompt
  /// for the location the manifest's `neverForLocation` deliberately avoids
  /// (05 §5.8.3).
  factory AppPermissions.production({required int? androidSdkInt}) =>
      AppPermissions(PermissionHandlerBackend(androidSdkInt: androidSdkInt));

  final PermissionBackend _backend;

  static const List<AppPermission> _bleCore = [
    AppPermission.bluetoothScan,
    AppPermission.bluetoothConnect,
  ];

  /// The BLE permission set for THIS OS: scan + connect everywhere, plus
  /// location on Android ≤ 30 where a BLE scan still needs it.
  List<AppPermission> _bleSet() {
    final sdk = _backend.androidSdkInt;
    final needsLocation = sdk != null && sdk <= 30;
    return needsLocation
        ? const [..._bleCore, AppPermission.location]
        : _bleCore;
  }

  /// Prompt for the BLE set and return the combined verdict — the driver for
  /// the primer's "Continue" (§13.2.0 check 2). Never throws.
  Future<PermissionResult> ensureBleReady() async {
    final results = <PermissionResult>[];
    for (final p in _bleSet()) {
      results.add(_reduceOne(await _backend.request(p)));
    }
    return _combine(results);
  }

  /// The BLE verdict WITHOUT prompting — the gate's on-entry check 3.
  Future<PermissionResult> bleStatus() async {
    final results = <PermissionResult>[];
    for (final p in _bleSet()) {
      results.add(_reduceOne(await _backend.status(p)));
    }
    return _combine(results);
  }

  /// Prompt for `POST_NOTIFICATIONS` (Android 13+). A denial degrades the app
  /// to in-app surfacing (09 §9.5); it is never fatal.
  Future<PermissionResult> ensureNotifications() async =>
      _reduceOne(await _backend.request(AppPermission.notification));

  /// The notification verdict without prompting.
  Future<PermissionResult> notificationStatus() async =>
      _reduceOne(await _backend.status(AppPermission.notification));

  /// The device location-services toggle (not a permission), for the §13.2.0
  /// check-1 location gate.
  Future<bool> locationServicesEnabled() => _backend.locationServicesEnabled();

  /// One status → verdict. `limited`/`provisional` are usable grants;
  /// `restricted` (iOS parental / device policy) has no dialog, so it routes
  /// like `permanentlyDenied` — settings, not retry.
  static PermissionResult _reduceOne(RawPermissionStatus s) => switch (s) {
    RawPermissionStatus.granted ||
    RawPermissionStatus.limited ||
    RawPermissionStatus.provisional => PermissionResult.granted,
    RawPermissionStatus.denied => PermissionResult.denied,
    RawPermissionStatus.permanentlyDenied ||
    RawPermissionStatus.restricted => PermissionResult.permanentlyDenied,
  };

  /// The worst verdict wins, because BLE needs EVERY permission in the set: a
  /// single permanent denial sends the user to settings; any plain denial is
  /// retryable; only all-granted is ready.
  static PermissionResult _combine(List<PermissionResult> results) {
    if (results.contains(PermissionResult.permanentlyDenied)) {
      return PermissionResult.permanentlyDenied;
    }
    if (results.contains(PermissionResult.denied)) {
      return PermissionResult.denied;
    }
    return PermissionResult.granted;
  }
}

/// The production backend over `permission_handler`. Nothing above it imports
/// the plugin; the version thresholds live in [AppPermissions].
class PermissionHandlerBackend implements PermissionBackend {
  const PermissionHandlerBackend({required this.androidSdkInt});

  @override
  final int? androidSdkInt;

  ph.Permission _plugin(AppPermission p) => switch (p) {
    AppPermission.bluetoothScan => ph.Permission.bluetoothScan,
    AppPermission.bluetoothConnect => ph.Permission.bluetoothConnect,
    // The location group (fine + coarse) — what a legacy BLE scan needs.
    AppPermission.location => ph.Permission.location,
    AppPermission.notification => ph.Permission.notification,
  };

  RawPermissionStatus _mapStatus(ph.PermissionStatus s) => switch (s) {
    ph.PermissionStatus.granted => RawPermissionStatus.granted,
    ph.PermissionStatus.denied => RawPermissionStatus.denied,
    ph.PermissionStatus.permanentlyDenied =>
      RawPermissionStatus.permanentlyDenied,
    ph.PermissionStatus.restricted => RawPermissionStatus.restricted,
    ph.PermissionStatus.limited => RawPermissionStatus.limited,
    ph.PermissionStatus.provisional => RawPermissionStatus.provisional,
  };

  @override
  Future<RawPermissionStatus> request(AppPermission p) async =>
      _mapStatus(await _plugin(p).request());

  @override
  Future<RawPermissionStatus> status(AppPermission p) async =>
      _mapStatus(await _plugin(p).status);

  @override
  Future<bool> locationServicesEnabled() async =>
      (await ph.Permission.location.serviceStatus).isEnabled;
}
