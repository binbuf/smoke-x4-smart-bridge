/// N11.11–N11.13 — what to post, on which channel, and whether it makes a
/// sound (design 09 §9.5, research notes §6.4).
///
/// A **pure** function: no plugin, no `BuildContext`, no clock of its own. The
/// wall time arrives as an argument, which is the only reason a
/// midnight-spanning quiet-hours window is testable at all. Lives in the data
/// layer because the alarm it reasons about is the [Alarm] model; it imports no
/// Flutter and runs under `dart test`.
///
/// **The app tier MIRRORS; it does not decide.** The device owns alarm state
/// (§9.1) and runs with no phone in existence. An alarm the bridge reports as
/// raised-and-unacknowledged at 07:00 must produce a notification even though it
/// fired at 03:40 while the phone was face-down — and it must not produce a
/// second one every time `/status` is polled (I2).
library;

import 'dart:math' as math;

import '../model/alarm.dart';

/// §9.5's four channels. Importance cannot be changed after an Android channel
/// is created, which is why they are a closed set created up front rather than
/// invented at post time.
enum NotificationChannel {
  /// HIGH: sound + vibration + heads-up, full-screen intent, optional DND
  /// bypass. Survives quiet hours.
  critical,

  /// DEFAULT: sound, heads-up. Silenced during quiet hours.
  warning,

  /// LOW: silent, in the shade.
  info,

  /// MIN: the foreground-service notification — silent, non-dismissible while
  /// cooking.
  ongoing,
}

/// The advisory app-tier findings of §9.3, as things worth telling someone
/// about. Everything that must fire reliably is a device rule.
enum AppFinding {
  etaSoon,
  stallStarted,
  stallEnded,
  lidOpen,
  bridgeUnreachable,
  phoneOffline,
}

/// Quiet hours: warnings and info go silent, **critical still sounds**.
/// Overcooking a brisket at 3 a.m. is precisely the thing worth waking up for,
/// which is why `target_reached` is critical.
///
/// Evaluated in the PHONE's local time, deliberately. The bridge's clock can be
/// stale or absent entirely, and quiet hours exist to protect a sleeping human
/// who is next to the phone.
class QuietHours {
  const QuietHours({
    this.enabled = true,
    this.startHour = 22,
    this.endHour = 6,
  });

  final bool enabled;
  final int startHour;
  final int endHour;

  bool contains(DateTime local) {
    if (!enabled) {
      return false;
    }
    final h = local.hour;
    if (startHour == endHour) {
      return false;
    }
    // A window that wraps midnight is the default and the common case.
    return startHour < endHour
        ? h >= startHour && h < endHour
        : h >= startHour || h < endHour;
  }
}

/// One thing to show the user.
class PendingNotification {
  const PendingNotification({
    required this.key,
    required this.channel,
    required this.title,
    required this.body,
    required this.silent,
    this.alarmId,
    this.fullScreen = false,
    this.repost = false,
    this.escalation = 0,
  });

  /// Stable across polls, so "already told them" is decidable. Device alarms key
  /// on their id; findings key on their kind.
  final String key;
  final NotificationChannel channel;
  final String title;
  final String body;

  /// Quiet hours turned the sound off. The notification still appears —
  /// silencing is not suppressing.
  final bool silent;
  final String? alarmId;

  /// Light the screen. Only ever true for a critical alarm that has gone
  /// unacknowledged past [kEscalateToFullScreen]; the first post of even a
  /// critical alarm is a heads-up, because a full-screen takeover for something
  /// the user is already looking at is how an app teaches people to revoke the
  /// permission that makes it possible.
  final bool fullScreen;

  /// This key is **already on screen** and is being posted again deliberately
  /// (the escalation ladder's repeat). The sink must replace rather than stack.
  final bool repost;

  /// Which rung of the ladder: 0 = first post, 1 = repeat, 2 = full screen.
  final int escalation;

  @override
  String toString() =>
      'PendingNotification($key, ${channel.name}, silent: $silent'
      '${escalation > 0 ? ', escalation: $escalation' : ''}'
      '${fullScreen ? ', fullScreen' : ''})';
}

/// What the policy decided this pass.
class NotificationPlan {
  const NotificationPlan({this.post = const [], this.withdraw = const []});

  final List<PendingNotification> post;

  /// Keys whose notification should be cancelled: the device says the alarm is
  /// acknowledged or gone, or the user turned monitoring off.
  final List<String> withdraw;

  bool get isEmpty => post.isEmpty && withdraw.isEmpty;
}

/// Severity → channel. The mapping is §9.5's, and it is one-way: an `info`
/// device alarm does not exist, but the enum permits one and the mapping must
/// not throw if firmware grows one.
NotificationChannel channelFor(AlarmSeverity s) => switch (s) {
  AlarmSeverity.critical => NotificationChannel.critical,
  AlarmSeverity.warning => NotificationChannel.warning,
  AlarmSeverity.info || AlarmSeverity.positive => NotificationChannel.info,
};

/// Human copy for a device rule. An unknown rule falls through to its raw name
/// rather than being dropped — a rule the bridge can raise and the phone stays
/// silent about is the worst possible outcome.
String alarmTitle(String rule) => switch (rule) {
  'smoke_x_alarm' => 'Base station alarm',
  'target_reached' => 'Target reached',
  'pit_out_of_band' => 'Pit out of band',
  'pit_crash' => 'The fire is dying',
  'probe_detached' => 'Probe unplugged',
  'base_lost' => 'Base station lost',
  'battery_low' => 'Bridge battery low',
  'storage_low' => 'Bridge storage nearly full',
  'system_fault' => 'Bridge restarted unexpectedly',
  _ => rule,
};

String findingTitle(AppFinding f) => switch (f) {
  AppFinding.etaSoon => 'Nearly done',
  AppFinding.stallStarted => 'The stall has started',
  AppFinding.stallEnded => 'Out of the stall',
  AppFinding.lidOpen => 'Lid opened',
  AppFinding.bridgeUnreachable => 'Cannot reach the bridge',
  AppFinding.phoneOffline => 'This phone is offline',
};

String findingBody(AppFinding f) => switch (f) {
  AppFinding.etaSoon => 'Under 30 minutes to go — start getting ready.',
  // The single most useful thing an app can say at hour six of a first brisket
  // (09 §9.4).
  AppFinding.stallStarted =>
    'This is normal. Your cook is fine — do not raise the pit temperature.',
  AppFinding.stallEnded => 'Temperature is climbing again.',
  AppFinding.lidOpen => 'Pit alarms are paused while it recovers.',
  AppFinding.bridgeUnreachable =>
    'No data for a while. The bridge is still recording.',
  AppFinding.phoneOffline => 'Reconnecting when the network comes back.',
};

/// Findings are advisory (§9.3) and never critical.
NotificationChannel channelForFinding(AppFinding f) => switch (f) {
  AppFinding.bridgeUnreachable ||
  AppFinding.phoneOffline => NotificationChannel.warning,
  _ => NotificationChannel.info,
};

String alarmKey(Alarm a) => 'alarm:${a.id}';
String findingKey(AppFinding f) => 'finding:${f.name}';

// ── The escalation ladder ──────────────────────────────────────────────
//
// "For critical rules, escalate: silent → heads-up → full-screen intent +
// repeat sound if unacknowledged after N minutes."
//
// The rungs are deliberately far apart. A brisket alarm that a user has seen and
// is walking towards must not turn into a full-screen takeover thirty seconds
// later; and a phone face-down on a bedside table at 3 a.m. must not take twenty
// minutes to reach the rung that actually lights the screen. Five and ten
// minutes is the span that covers both.
//
// **Only critical escalates.** A warning that repeated itself every five minutes
// is an app nobody leaves notifications on for, which costs the critical rung
// too.

/// N15.17 — §9.6: "`bridge_unreachable` warning after 3 min". Lives here (not
/// in `features/monitor/`) because the presentation layer bans `Duration`
/// literals: motion comes from `SmokeMotion`, but policy windows are data.
const Duration kUnreachableAfter = Duration(minutes: 3);

/// §9.5: "The ongoing notification is a live readout, updated every 30 s".
const Duration kOngoingUpdateEvery = Duration(seconds: 30);

/// §9.6: "stops … 10 min after the last successful connection when no session
/// is active".
const Duration kIdleStopAfter = Duration(minutes: 10);

/// Repeat the sound once the alarm has gone unacknowledged this long.
const Duration kEscalateToRepeat = Duration(minutes: 5);

/// Light the screen. This is the rung the whole `USE_FULL_SCREEN_INTENT`
/// declaration exists for.
const Duration kEscalateToFullScreen = Duration(minutes: 10);

/// Which rung an unacknowledged critical alarm has reached.
///
/// Pure over [sinceUnixMs] and [now]; a null `since` (a device that reported an
/// alarm without a timestamp) stays at rung 0 rather than being assumed old.
int escalationRung(DateTime now, int? sinceUnixMs) {
  if (sinceUnixMs == null) {
    return 0;
  }
  final age = now.difference(DateTime.fromMillisecondsSinceEpoch(sinceUnixMs));
  if (age >= kEscalateToFullScreen) {
    return 2;
  }
  if (age >= kEscalateToRepeat) {
    return 1;
  }
  return 0;
}

/// The whole policy, as one pure function.
///
/// [alreadyPosted] is the set of keys the caller has live on screen — mirroring,
/// not re-deciding, is what stops a poll loop from posting the same alarm every
/// 30 seconds.
///
/// [preferManualAlarm] is N11.10: the user's own (app-tier) insights win the
/// *notification*, so a non-critical device alarm goes silent while an insight
/// or app alarm is also active. The device alarm stays authoritative in the
/// list (it is still posted and still unacknowledged); **a critical device alarm
/// never defers** — that is the promise the whole device tier exists to keep.
NotificationPlan planNotifications({
  required List<Alarm> alarms,
  required Set<String> alreadyPosted,
  required DateTime now,
  List<AppFinding> findings = const [],
  QuietHours quiet = const QuietHours(),
  bool monitoringEnabled = true,
  bool preferManualAlarm = false,

  /// The rung each live key was last posted at, so an alarm climbs the ladder
  /// exactly once per rung rather than re-posting on every 30 s poll. The caller
  /// owns this map for the same reason it owns [alreadyPosted]: this function
  /// stays pure, and "what have I already done" is state.
  Map<String, int> escalatedTo = const {},
}) {
  if (!monitoringEnabled) {
    // Everything comes down: the user turned monitoring off, and leaving stale
    // notifications behind would imply it is still running.
    return NotificationPlan(withdraw: alreadyPosted.toList()..sort());
  }

  // N11.10 — "prefer my own alarms". An active insight (or app-tier alarm) makes
  // the user's own choice the one that sounds, but only for non-critical device
  // rules.
  final hasAppSignal =
      findings.isNotEmpty ||
      alarms.any((a) => a.tier == AlarmTier.app && !a.acked);
  final manualWins = preferManualAlarm && hasAppSignal;

  final post = <PendingNotification>[];
  final live = <String>{};

  for (final a in alarms) {
    final key = alarmKey(a);
    // Acknowledging silences; it does not resolve (§9.2). The alarm stays in
    // `/status` with acked: true, and the notification comes down — the user has
    // seen it, which is what acknowledging means.
    if (a.acked) {
      continue;
    }
    // Snooze (N11.8) is also app-side and silences delivery without acking; the
    // alarm is still raised, so it stays in `live`.
    live.add(key);
    if (a.snoozedAt(now.millisecondsSinceEpoch)) {
      continue;
    }
    final channel = channelFor(a.severity);

    // The escalation ladder. Only critical climbs it.
    final rung = channel == NotificationChannel.critical
        ? escalationRung(now, a.atMs)
        : 0;
    final onScreen = alreadyPosted.contains(key);
    final lastRung = escalatedTo[key] ?? 0;

    if (onScreen && rung <= lastRung) {
      // Already on screen at this rung or higher: do NOT re-post on every poll.
      continue;
    }

    final quietNow = quiet.contains(now);
    final silent =
        channel != NotificationChannel.critical &&
        (quietNow || (manualWins && a.tier == AlarmTier.device));
    post.add(
      PendingNotification(
        key: key,
        channel: channel,
        title: alarmTitle(a.rule),
        body: _alarmBody(a),
        silent: silent,
        alarmId: a.id,
        // Rung 2 is the one that lights the screen — and it is never the first
        // post, even for a critical alarm.
        fullScreen: rung >= 2,
        repost: onScreen,
        escalation: rung,
      ),
    );
  }

  for (final f in findings) {
    final key = findingKey(f);
    live.add(key);
    if (alreadyPosted.contains(key)) {
      continue;
    }
    post.add(
      PendingNotification(
        key: key,
        channel: channelForFinding(f),
        title: findingTitle(f),
        body: findingBody(f),
        // Every finding is advisory, so quiet hours silence all of them.
        silent: quiet.contains(now),
      ),
    );
  }

  final withdraw = <String>[
    for (final k in alreadyPosted)
      if (!live.contains(k)) k,
  ]..sort();

  return NotificationPlan(post: post, withdraw: withdraw);
}

String _alarmBody(Alarm a) {
  final detail = a.detail.trim();
  if (a.valueF10 == null) {
    return detail;
  }
  final temp = '${(a.valueF10! / 10).toStringAsFixed(1)}°F';
  return detail.isEmpty ? temp : '$detail · $temp';
}

/// Whether [a] is an alarm the app should show as active right now: raised and
/// not acknowledged. Snoozing suppresses delivery, not the list (N11.8).
bool isActiveAlarm(Alarm a, int nowMs) => !a.acked;

/// Severity ordering, highest first, for the strips and the sheet.
int severityRank(AlarmSeverity s) => switch (s) {
  AlarmSeverity.critical => 0,
  AlarmSeverity.warning => 1,
  AlarmSeverity.info => 2,
  AlarmSeverity.positive => 3,
};

/// The active alarms, highest severity first, then most recent.
List<Alarm> orderedActiveAlarms(List<Alarm> alarms, {required int nowMs}) {
  final out = <Alarm>[
    for (final a in alarms)
      if (isActiveAlarm(a, nowMs)) a,
  ];
  out.sort((a, b) {
    final bySeverity = severityRank(
      a.severity,
    ).compareTo(severityRank(b.severity));
    return bySeverity != 0 ? bySeverity : b.atMs.compareTo(a.atMs);
  });
  return out;
}

/// The longest a snooze may run (clamped so a bad value cannot silence a cook).
const int kMaxSnoozeMinutes = 60;

/// The snooze expiry for a 10-minute snooze, or any clamp of it.
int snoozeUntilMs({required int nowMs, int minutes = 10}) =>
    nowMs + math.min(math.max(minutes, 1), kMaxSnoozeMinutes) * 60 * 1000;
