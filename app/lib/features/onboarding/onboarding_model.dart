/// N14 — the Riverpod seam for the onboarding wizard.
///
/// Kept out of [setup_format] so that stays Flutter-free and runnable under
/// `dart test`. This file imports Riverpod and is used by the shell (gating)
/// and the wizard widget.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/model/app_settings.dart';
import '../../data/providers.dart';
import '../../domain/domain.dart';
import 'setup_format.dart';

/// Holds the wizard's live value above the overlay so closing and reopening
/// the wizard resumes where the user left off (N14.11 "resume").
///
/// Riverpod 3 forbids writing `.state` from outside the notifier, so every
/// transition is an intent method here; the widget only calls these.
class SetupMachine extends Notifier<SetupState> {
  @override
  SetupState build() => const SetupState();

  /// Back to a factory-fresh wizard (after finish or skip).
  void reset() => state = const SetupState();

  void next() => state = state.next();
  void back() => state = state.back();
  void allow(OnboardPermission permission) => state = state.allow(permission);
  void findBridge() => state = state.foundBridge();
  void startTroubleshoot() => state = state.startTroubleshoot();
  void stopTroubleshoot() => state = state.stopTroubleshoot();

  /// Confirm the (masked) passkey and advance.
  void confirmPasskey() => state = state.confirmPasskey().next();

  /// The base station was heard, then advance.
  void heardBase() => state = state.heardBase().next();

  /// Set the base station up later, then advance.
  void skipBase() => state = state.skipBase().next();

  void selectMode(String id) => state = state.selectMode(id);
  void setName(String value) => state = state.setName(value);
  void setUnits(TempUnit value) => state = state.setUnits(value);

  /// Enter a named failure (I15) — used by the widget and tests.
  void fault(SetupFault value) => state = state.fail(value);

  /// Recover from the current named failure.
  void recoverFault() {
    final current = state;
    switch (current.fault) {
      case SetupFault.permissionDenied:
        final denied = kOnboardPermissions.firstWhere(
          (permission) =>
              current.permissionOf(permission) != PermissionState.granted,
          orElse: () => OnboardPermission.bluetooth,
        );
        state = current.allow(denied);
      case SetupFault.wifiFailed:
        state = current.selectMode('ble').copyWith(fault: SetupFault.none);
      case SetupFault.unsupported:
        state = current.copyWith(fault: SetupFault.none);
      default:
        state = current.copyWith(fault: SetupFault.none);
    }
  }
}

/// The wizard's current state.
final setupStateProvider = NotifierProvider<SetupMachine, SetupState>(
  SetupMachine.new,
);

/// N14.12 — the wizard owns the screen only while no bridge is known.
///
/// [OnboardStatus.paired] (the mock build's default, and every later launch)
/// launches straight to the shell; [OnboardStatus.skipped] keeps the shell but
/// shows its "connect a bridge" empty state (N14.13).
final onboardingRequiredProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider).value;
  return settings?.onboardStatus == OnboardStatus.fresh;
});

/// Whether the shell should surface the "connect a bridge" empty state because
/// the user skipped the wizard (N14.13).
final onboardingSkippedProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider).value;
  return settings?.onboardStatus == OnboardStatus.skipped;
});
