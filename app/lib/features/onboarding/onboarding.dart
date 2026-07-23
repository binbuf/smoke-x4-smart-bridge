/// Onboarding feature: BLE scan → bond → passkey → mode choice → handoff.
///
/// See design 08 §8.3, §8.6. Landed in M3 (A8): the logic is a pure state
/// machine in wizard.dart; onboarding_screens.dart projects it and holds
/// no decisions, which is what keeps M4's restyle cosmetic.
library;

export 'onboarding_route.dart';
export 'onboarding_screens.dart';
export 'wizard.dart';
