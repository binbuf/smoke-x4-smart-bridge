/// A13.1 — what to post, on which channel, and whether it makes a sound
/// (design 09 §9.5).
///
/// A pure function. No plugin, no `BuildContext`, no clock of its own:
/// the wall time arrives as an argument, which is the only reason a
/// midnight-spanning quiet-hours window is testable at all.
///
/// **The app tier MIRRORS; it does not decide.** The device owns alarm
/// state (§9.1) and runs with no phone in existence. An alarm the bridge
/// reports as raised-and-unacknowledged at 07:00 must produce a
/// notification even though it fired at 03:40 while the phone was
/// face-down — and it must not produce a second one every time `/status`
/// is polled.
library;

import '../entities/entities.dart';

/// §9.5's four channels. Importance cannot be changed after an Android
/// channel is created, which is why they are a closed set created up
/// front rather than invented at post time.
enum NotificationChannel {
  /// HIGH: sound + vibration + heads-up, full-screen intent, optional
  /// DND bypass. Survives quiet hours.
  critical,

  /// DEFAULT: sound, heads-up. Silenced during quiet hours.
  warning,

  /// LOW: silent, in the shade.
  info,

  /// MIN: the foreground-service notification — silent, non-dismissible
  /// while cooking.
  ongoing,
}

/// The advisory app-tier findings of §9.3, as things worth telling
/// someone about. Everything that must fire reliably is a device rule.
enum AppFinding {
  etaSoon,
  stallStarted,
  stallEnded,
  lidOpen,
  bridgeUnreachable,
  phoneOffline,
}

/// Quiet hours: warnings and info go silent, **critical still sounds**.
/// Overcooking a brisket at 3 a.m. is precisely the thing worth waking up
/// for, which is why `target_reached` is critical.
///
/// Evaluated in the PHONE's local time, deliberately. The bridge's clock
/// can be stale or absent entirely (04 §4.4), and quiet hours exist to
/// protect a sleeping human who is next to the phone.
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

  /// Stable across polls, so "already told them" is decidable. Device
  /// alarms key on their id; findings key on their kind.
  final String key;
  final NotificationChannel channel;
  final String title;
  final String body;

  /// Quiet hours turned the sound off. The notification still appears —
  /// silencing is not suppressing.
  final bool silent;
  final int? alarmId;

  /// newapp §G.5 — light the screen. Only ever true for a critical alarm that
  /// has gone unacknowledged past [kEscalateToFullScreen]; the first post of
  /// even a critical alarm is a heads-up, because a full-screen takeover for
  /// something the user is already looking at is how an app teaches people to
  /// revoke the permission that makes it possible.
  final bool fullScreen;

  /// This key is **already on screen** and is being posted again deliberately
  /// (§G.5's "repeat sound if unacknowledged after N minutes"). The sink must
  /// replace rather than stack — the id is derived from [key], so it does.
  final bool repost;

  /// Which rung of the ladder: 0 = first post, 1 = repeat, 2 = full screen.
  /// Carried so the monitor can record what it actually did, and so the field
  /// report can show whether escalation ever fired on a real phone.
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

  /// Keys whose notification should be cancelled: the device says the
  /// alarm is acknowledged or gone.
  final List<String> withdraw;

  bool get isEmpty => post.isEmpty && withdraw.isEmpty;
}

/// Severity → channel. The mapping is §9.5's, and it is one-way: an
/// `info` device alarm does not exist, but the enum permits one and the
/// mapping must not throw if firmware grows one.
NotificationChannel channelFor(AlarmSeverity s) => switch (s) {
  AlarmSeverity.critical => NotificationChannel.critical,
  AlarmSeverity.warning => NotificationChannel.warning,
  AlarmSeverity.info => NotificationChannel.info,
};

/// Human copy for a device rule. The identifiers are the firmware's
/// generated `alarm_rule` spellings (`protocol/records.yaml`), so an
/// unknown one falls through to the raw name rather than being dropped —
/// a rule the bridge can raise and the phone stays silent about is the
/// worst possible outcome.
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
  // The single most useful thing an app can say at hour six of a first
  // brisket (09 §9.4).
  AppFinding.stallStarted =>
    'This is normal. Your cook is fine — do not raise the pit temperature.',
  AppFinding.stallEnded => 'Temperature is climbing again.',
  AppFinding.lidOpen => 'Pit alarms are paused while it recovers.',
  AppFinding.bridgeUnreachable =>
    'No data for 3 minutes. The bridge is still recording.',
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

// ── §G.5's escalation ladder ──────────────────────────────────────────
//
// "For critical rules, escalate: silent → heads-up → full-screen intent +
// repeat sound if unacknowledged after N minutes."
//
// The rungs are deliberately far apart. A brisket alarm that a user has seen
// and is walking towards must not turn into a full-screen takeover thirty
// seconds later; and a phone face-down on a bedside table at 3 a.m. must not
// take twenty minutes to reach the rung that actually lights the screen. Five
// and ten minutes is the span that covers both — long enough that anybody
// awake has already acted, short enough that the brisket is still a brisket.
//
// **Only critical escalates.** A warning that repeated itself every five
// minutes would be an app nobody leaves notifications on for, which costs the
// critical rung too.

/// Repeat the sound once the alarm has gone unacknowledged this long.
const Duration kEscalateToRepeat = Duration(minutes: 5);

/// Light the screen. This is the rung the whole `USE_FULL_SCREEN_INTENT`
/// declaration exists for (§G.4).
const Duration kEscalateToFullScreen = Duration(minutes: 10);

/// Which rung an unacknowledged critical alarm has reached.
///
/// Pure over [since] and [now]; a null [since] (a device that reported an
/// alarm without a timestamp) stays at rung 0 rather than being assumed old —
/// escalating on a missing field would let one firmware quirk light the screen.
int escalationRung(DateTime now, int? sinceUnixMs) {
  if (sinceUnixMs == null) {
    return 0;
  }
  final age = now.difference(
    DateTime.fromMillisecondsSinceEpoch(sinceUnixMs),
  );
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
/// [alreadyPosted] is the set of keys the caller has live on screen —
/// mirroring, not re-deciding, is what stops a poll loop from posting the
/// same alarm every 30 seconds.
NotificationPlan planNotifications({
  required List<Alarm> alarms,
  required Set<String> alreadyPosted,
  required DateTime now,
  List<AppFinding> findings = const [],
  QuietHours quiet = const QuietHours(),
  bool monitoringEnabled = true,
  String Function(int probe)? probeName,

  /// §G.5 — the rung each live key was last posted at, so an alarm climbs the
  /// ladder exactly once per rung rather than re-posting on every 30 s poll.
  /// The caller owns this map for the same reason it owns [alreadyPosted]:
  /// this function stays pure, and "what have I already done" is state.
  Map<String, int> escalatedTo = const {},
}) {
  if (!monitoringEnabled) {
    // Everything comes down: the user turned monitoring off, and leaving
    // stale notifications behind would imply it is still running.
    return NotificationPlan(withdraw: alreadyPosted.toList()..sort());
  }

  final post = <PendingNotification>[];
  final live = <String>{};

  for (final a in alarms) {
    final key = alarmKey(a);
    // Acknowledging silences; it does not resolve (§9.2). The alarm stays
    // in `/status` with acked: true, and the notification comes down —
    // the user has seen it, which is what acknowledging means.
    if (a.acked) {
      continue;
    }
    live.add(key);
    final channel = channelFor(a.severity);

    // §G.5 — the escalation ladder. Only critical climbs it: a warning that
    // repeated every five minutes is an app nobody leaves notifications on
    // for, which would cost the critical rung too.
    final rung = channel == NotificationChannel.critical
        ? escalationRung(now, a.sinceUnixMs)
        : 0;
    final onScreen = alreadyPosted.contains(key);
    final lastRung = escalatedTo[key] ?? 0;

    if (onScreen && rung <= lastRung) {
      // Already on screen at this rung or higher: do NOT re-post on every
      // poll. Re-posting an unchanged alarm every 30 seconds is how an app
      // gets its notifications turned off before the cook it matters for.
      continue;
    }

    final silent =
        channel != NotificationChannel.critical && quiet.contains(now);
    final who = a.probe > 0
        ? (probeName?.call(a.probe) ?? 'Probe ${a.probe}')
        : 'Bridge';
    post.add(
      PendingNotification(
        key: key,
        channel: channel,
        title: alarmTitle(a.rule),
        body: a.valueF10 != null
            ? '$who · ${(a.valueF10! / 10).toStringAsFixed(1)}°F'
            : who,
        silent: silent,
        alarmId: a.id,
        // Rung 2 is the one that lights the screen — and it is never the
        // first post, even for a critical alarm.
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

  final withdraw = [
    for (final k in alreadyPosted)
      if (!live.contains(k)) k,
  ]..sort();

  return NotificationPlan(post: post, withdraw: withdraw);
}
