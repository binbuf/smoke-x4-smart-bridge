/// A23.1 — hop 0, the preflight gate (design 13 §13.2.0).
///
/// WHY: `grep -rn "adapterState|isSupported|turnOn"` returns zero hits today
/// (§13.2.0), which is precisely why failure #5 exists — Bluetooth-off,
/// permission-denied and adapter-unsupported all collapse into
/// "No bridges found". This file restores the gate the product never had.
///
/// It calls **no platform APIs**. Every real check (adapter state, runtime
/// permission, location services) is read through the injected
/// [PreflightProbe], so the whole §13.2.0 truth table is exercisable against a
/// fake with no phone. The concrete probe — one `FlutterBluePlus` seam plus
/// `permission_handler` plus the `system_settings` MethodChannel — is A23.2's
/// to wire; this file only defines the shape and the ordering.
///
/// [SetupPreflight.evaluate] runs the checks *in order and stops at the first
/// failure* (§13.2.0 table), returning the preflight [SetupState] to show, or
/// null when the gate is clear and hop 1 may begin.
library;

import 'setup_machine.dart';
import 'setup_stage.dart';

/// The adapter's power/authorization state (§13.2.0): the five values
/// `FlutterBluePlus.adapterState` can report, named so the machine never
/// touches the plugin enum.
enum SetupAdapterState {
  /// Radio is off. Recoverable — `requestEnable()` or Bluetooth settings.
  off,

  /// Radio is on and usable.
  on,

  /// The OS denied this app Bluetooth access (iOS authorization; some
  /// Android OEM states). Routed through the permission path, not "off".
  unauthorized,

  /// No BLE hardware at all. **Terminal** (§13.2.0) — the honest instruction
  /// is to read the SSID/PSK off the OLED, not a button that leads nowhere.
  unsupported,

  /// Not yet known (the plugin reports this briefly at startup). Never a
  /// failure on its own; the lifetime subscription resolves it.
  unknown,
}

/// The runtime-permission verdict for `bluetoothScan`/`bluetoothConnect`
/// (§13.2.0). `permission_handler` cannot distinguish first-denial from
/// permanent-denial *until it has prompted*, which is the entire reason the
/// primer (check 2) is not optional.
enum PreflightPermission {
  /// Both permissions granted.
  granted,

  /// Denied, but the OS will still show the dialog — retry is possible.
  denied,

  /// Denied twice / "don't ask again": the dialog will never show again, so
  /// the only route is app settings (§13.2.0).
  permanentlyDenied,
}

/// The injected seam for every §13.2.0 check. A fake implementing this drives
/// the entire preflight truth table with no radio and no OS prompts.
abstract interface class PreflightProbe {
  /// The adapter state right now (checks 0 and 4).
  SetupAdapterState get adapterStateNow;

  /// Adapter transitions for the **whole** setup lifetime (§13.2.0), not just
  /// preflight — Bluetooth switched off at hop 3 must resume, not dead-end.
  Stream<SetupAdapterState> get adapterStates;

  /// Android only: ask the OS to turn Bluetooth on (`FlutterBluePlus.turnOn`).
  /// Must not throw; a refusal simply leaves the adapter off.
  Future<void> requestEnable();

  /// Whether check 1 applies at all: true only on Android SDK ≤ 32, where a
  /// BLE scan needs location services on (§13.2.0). iOS / Android 13+ → false.
  bool get needsLocationServices;

  /// Check 1: are location services enabled? Only consulted when
  /// [needsLocationServices] is true.
  Future<bool> isLocationServicesOn();

  /// The current permission verdict, WITHOUT prompting (check 3 on entry).
  Future<PreflightPermission> permissionStatus();

  /// Triggers the OS permission prompt and returns the verdict. Driven by the
  /// primer's "Continue" (§13.2.0 check 2). Must not throw.
  Future<PreflightPermission> requestPermissions();
}

/// Produces the §13.2.0 preflight states from a [PreflightProbe].
///
/// Stateless beyond the probe: every method re-reads the world, so a "recheck"
/// after the user visits settings is just another [evaluate].
class SetupPreflight {
  const SetupPreflight(this.probe);

  final PreflightProbe probe;

  /// Runs checks 0 → 1 → 2/3 → 4 in order, stopping at the first failure
  /// (§13.2.0). Returns the preflight [SetupState] to render, or **null** when
  /// the gate is clear and hop 1 may begin.
  ///
  /// [resumeAt] is threaded into [SetupBluetoothOff] so a mid-flow adapter-off
  /// returns to the recorded stage rather than the top (§13.2.0).
  Future<SetupState?> evaluate({
    SetupStage resumeAt = SetupStage.findBridge,
  }) async {
    // Check 0 — supported. Terminal; nothing below it can matter.
    if (probe.adapterStateNow == SetupAdapterState.unsupported) {
      return const SetupBluetoothUnsupported();
    }

    // Check 1 — location services (Android SDK ≤ 32 only).
    if (probe.needsLocationServices && !await probe.isLocationServicesOn()) {
      return const SetupLocationServicesOff();
    }

    // Checks 2/3 — permission. Already-permanent skips straight to the
    // settings route (the primer's prompt would never appear); already-granted
    // skips the primer entirely for a returning user; anything else shows the
    // primer, whose "Continue" runs [continueFromPrimer].
    final perm = await probe.permissionStatus();
    switch (perm) {
      case PreflightPermission.permanentlyDenied:
        return const SetupPermissionDenied(permanent: true);
      case PreflightPermission.denied:
        return const SetupPermissionPrimer();
      case PreflightPermission.granted:
        break;
    }

    // Check 4 — adapter on.
    return _adapterGate(resumeAt: resumeAt);
  }

  /// The primer's "Continue" (§13.2.0 check 2): prompt, then evaluate the
  /// result against checks 3 and 4. Returns the state to show, or null to
  /// proceed to hop 1.
  Future<SetupState?> continueFromPrimer({
    SetupStage resumeAt = SetupStage.findBridge,
  }) async {
    final perm = await probe.requestPermissions();
    switch (perm) {
      case PreflightPermission.permanentlyDenied:
        return const SetupPermissionDenied(permanent: true);
      case PreflightPermission.denied:
        return const SetupPermissionDenied(permanent: false);
      case PreflightPermission.granted:
        return _adapterGate(resumeAt: resumeAt);
    }
  }

  /// Check 4 in isolation, reused by [evaluate], [continueFromPrimer] and the
  /// machine's mid-flow adapter watcher. `unknown` is not a failure — the
  /// lifetime subscription resolves it — so only a definite `off`/`unauthorized`
  /// blocks.
  SetupState? _adapterGate({required SetupStage resumeAt}) {
    return switch (probe.adapterStateNow) {
      SetupAdapterState.off => SetupBluetoothOff(resumeAt: resumeAt),
      SetupAdapterState.unauthorized => const SetupPermissionDenied(
        permanent: true,
      ),
      SetupAdapterState.unsupported => const SetupBluetoothUnsupported(),
      SetupAdapterState.on || SetupAdapterState.unknown => null,
    };
  }

  /// Public alias used by the machine when re-checking after the user turned
  /// Bluetooth on (§13.2.0). Same logic as check 4.
  SetupState? adapterGate({SetupStage resumeAt = SetupStage.findBridge}) =>
      _adapterGate(resumeAt: resumeAt);
}
