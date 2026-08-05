/// What phone is this, and what will it let us do (newapp §G.4, J1).
///
/// J1 names Samsung, Xiaomi and OnePlus specifically as the OEMs whose
/// background killers behave differently from stock Android. Without the model
/// and the OS version in the field report, a foreground-service failure is
/// unattributable — and "the monitor died on someone's phone" is not a bug
/// anyone can act on.
///
/// A seam, like every other platform touch here, so the harness runs in a
/// widget test against a fixed map.
library;

import 'dart:io';

/// Everything worth recording about the host.
///
/// Deliberately a plain map: this is diagnostic data whose shape will change
/// as questions change, and a typed record would make adding a field a
/// migration.
Map<String, Object?> deviceFacts() {
  try {
    return {
      'platform': Platform.operatingSystem,
      // On Android this is the full build string — API level, build id,
      // fingerprint — which is what tells an Android 15 dataSync cap from an
      // Android 16 Live Update opportunity.
      'os version': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'processors': Platform.numberOfProcessors,
    };
  } on Object {
    // A platform that will not answer is not a failure; the rest of the
    // report is still worth having.
    return const {'platform': '(unavailable)'};
  }
}
