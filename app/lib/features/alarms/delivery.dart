/// **Will this phone actually wake you** (design 13 §13.5.5; relocated per
/// newapp §B.2).
///
/// This used to be a whole primary destination — a quarter of the navigation
/// spent on a permissions verdict plus a test button. §B.1 is right that a
/// verdict is not a place you live: you need it told to you *where the
/// temperatures are*, once, while it is true, and then never again.
///
/// So the tab is gone and its three parts landed where each belongs:
///
///  * the **verdict** is now [DeliveryBanner] on `/live` and `/device`, and a
///    one-time gate in setup;
///  * the **test alarm** moved to `/device/alarms`, beside the rules it tests;
///  * the "rules aren't editable yet" card is obsolete — they are now (§G.2).
///
/// The verdict itself is unchanged, because it was right: §13.5.7 names *"Alerts
/// are off — you won't be woken"* as the load-bearing banner, since a fourteen-
/// hour cook running with notifications denied is a **silent total failure** the
/// user discovers at breakfast.
library;

import 'package:flutter/foundation.dart';

import '../../app/app_env.dart';
import '../../domain/alarms/notification_policy.dart';

/// Why alerts would not reach the user, in the order worth fixing them.
enum DeliveryBlocker {
  /// POST_NOTIFICATIONS denied. Nothing else matters until this is fixed.
  permission,

  /// The user turned background monitoring off in settings.
  monitoringOff,

  /// The OS may freeze the app in the background. Not fatal — the app still
  /// catches up when opened — so it is a caveat, not a failure.
  batteryOptimised,
}

/// The whole verdict, as a value, so the card is a pure render of it and the
/// truth table is testable without a phone.
@immutable
class DeliveryStatus {
  const DeliveryStatus({
    required this.permissionGranted,
    required this.monitoringEnabled,
    required this.batteryExempt,
    this.quietHours = false,
    this.fullScreenIntentGranted = true,
  });

  final bool permissionGranted;
  final bool monitoringEnabled;
  final bool batteryExempt;
  final bool quietHours;

  /// §G.4 — whether this phone will let the app light the screen.
  ///
  /// Since 22 January 2025 apps targeting Android 14+ only get
  /// `USE_FULL_SCREEN_INTENT` by default if they have calling or **alarm**
  /// functionality. This app qualifies as an alarm app and declares it, but the
  /// user can still revoke it, and `NotificationManager.canUseFullScreenIntent`
  /// is the only honest way to know. Defaults true so a platform that cannot
  /// answer (web, a test) does not cry wolf.
  final bool fullScreenIntentGranted;

  /// The blockers, worst first. Empty means the alerts will land.
  List<DeliveryBlocker> get blockers => [
    if (!permissionGranted) DeliveryBlocker.permission,
    if (!monitoringEnabled) DeliveryBlocker.monitoringOff,
    if (!batteryExempt) DeliveryBlocker.batteryOptimised,
  ];

  /// True only when nothing stands between an alarm and the user's attention.
  /// Battery optimisation alone does not clear this: it is the difference
  /// between "woken at 3 a.m." and "told at 7 a.m.", which is the difference
  /// the whole product exists for.
  bool get willWake => permissionGranted && monitoringEnabled;

  /// The single worst thing wrong, or null when nothing is.
  DeliveryBlocker? get worst => blockers.isEmpty ? null : blockers.first;

  /// Whether the banner should show at all. Battery optimisation on its own is
  /// a caveat worth stating on `/device` but not worth a permanent strip over
  /// the temperatures — a banner nobody can dismiss and nobody must act on is
  /// how a user learns to stop reading banners.
  bool get needsAttention => !willWake;

  /// The banner's sentence. Names the consequence, never the API.
  String get headline => switch (worst) {
    DeliveryBlocker.permission => 'Notifications are off — this phone can’t '
        'wake you',
    DeliveryBlocker.monitoringOff =>
      'Background monitoring is off — this phone can’t wake you',
    DeliveryBlocker.batteryOptimised =>
      'Battery saving may delay alerts until you open the app',
    null => 'You’ll be woken',
  };

  String get detail => switch (worst) {
    DeliveryBlocker.permission =>
      'The bridge still records and still alarms on its own — but nothing '
          'reaches this phone until you allow notifications.',
    DeliveryBlocker.monitoringOff =>
      'Alerts only arrive while the app is open. The bridge keeps its own '
          'alarms either way.',
    DeliveryBlocker.batteryOptimised =>
      'Android may freeze the app in the background. You would be told at '
          'breakfast rather than at 3 a.m.',
    null =>
      'Notifications are allowed and background monitoring is on. The bridge '
          'alarms on its own as well.',
  };

  /// The button's words. Never "Fix" — say what tapping does.
  String get actionLabel => switch (worst) {
    DeliveryBlocker.permission => 'Allow notifications',
    DeliveryBlocker.monitoringOff => 'Turn on monitoring',
    DeliveryBlocker.batteryOptimised => 'Allow background use',
    null => '',
  };
}

/// Reads the facts through the seams that already exist.
///
/// Every one degrades to **assume the worst and say so** rather than throwing:
/// a check that cannot run must not report that everything is fine.
Future<DeliveryStatus> probeDelivery({bool requestPermission = false}) async {
  final env = AppEnv.instance;
  var granted = false;
  var exempt = false;
  try {
    granted = requestPermission
        ? await env?.notifications?.requestPermission() ?? false
        : await env?.notifications?.hasPermission() ?? false;
  } on Object {
    granted = false;
  }
  try {
    exempt =
        await env?.foregroundService?.isIgnoringBatteryOptimizations() ?? false;
  } on Object {
    exempt = false;
  }
  return DeliveryStatus(
    permissionGranted: granted,
    monitoringEnabled: env?.prefs.monitoringEnabled ?? true,
    batteryExempt: exempt,
    quietHours: env?.prefs.quietHoursEnabled ?? true,
  );
}

/// The outcome of the test alarm, in the user's terms.
typedef TestAlarmResult = ({bool sent, String message});

/// Posts a real notification on the real critical channel.
///
/// Anything less — an in-app toast, a mocked path — proves nothing about the
/// thing being tested, which is the OS making a noise at 3 a.m. This is the one
/// control that has to touch the real plumbing.
Future<TestAlarmResult> postTestAlarm() async {
  final sink = AppEnv.instance?.notifications;
  if (sink == null) {
    return (sent: false, message: 'This build has no notification support to '
        'test.');
  }
  try {
    await sink.ensureChannels();
    await sink.post(
      const PendingNotification(
        key: 'test',
        channel: NotificationChannel.critical,
        title: 'Test alert',
        body: 'If you can see and hear this, your cook can wake you.',
        // Never silent, whatever quiet hours say: the one thing being tested
        // is whether this phone makes a noise.
        silent: false,
      ),
    );
    return (
      sent: true,
      message:
          'Sent. Check your notification shade — and if your phone is silent, '
          'check its volume and Do Not Disturb.',
    );
  } on Object {
    return (sent: false, message: 'Couldn’t send it. Alerts may be blocked.');
  }
}
