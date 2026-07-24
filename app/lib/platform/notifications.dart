/// A13.2 — the notification channels and the delivery seam
/// (design 09 §9.5, 08 §8.2).
///
/// `flutter_local_notifications` is a plugin, so it hides behind an
/// interface — the same seam discipline `nsd`, `flutter_blue_plus` and
/// `shared_preferences` already live under. The host suite drives
/// [RecordingNotificationSink]; the app installs the real one at
/// bootstrap. Nothing above this file knows which it has.
///
/// **Channel importance cannot be changed after an Android channel is
/// created.** That is a real platform constraint and it is why all four
/// channels are created up front with their §9.5 importances rather than
/// lazily with defaults — a channel first created as DEFAULT stays
/// DEFAULT for the install's lifetime, and "critical alarms stopped
/// making a sound" is not a bug you can ship a fix for.
library;

import '../domain/alarms/notification_policy.dart';

/// Android importance, named rather than numbered so the mapping to
/// §9.5's table is readable at the call site.
enum ChannelImportance { min, low, defaultImportance, high }

class ChannelSpec {
  const ChannelSpec({
    required this.channel,
    required this.id,
    required this.name,
    required this.description,
    required this.importance,
  });

  final NotificationChannel channel;
  final String id;
  final String name;
  final String description;
  final ChannelImportance importance;
}

/// §9.5's table, verbatim. The only copy.
const List<ChannelSpec> notificationChannels = [
  ChannelSpec(
    channel: NotificationChannel.critical,
    id: 'critical',
    name: 'Critical alarms',
    description:
        'Target reached, a dying fire, the base station alarming. Sounds '
        'even during quiet hours.',
    importance: ChannelImportance.high,
  ),
  ChannelSpec(
    channel: NotificationChannel.warning,
    id: 'warning',
    name: 'Warnings',
    description: 'Pit out of band, a probe unplugged, the bridge unreachable.',
    importance: ChannelImportance.defaultImportance,
  ),
  ChannelSpec(
    channel: NotificationChannel.info,
    id: 'info',
    name: 'Information',
    description: 'The stall, lid opens, "nearly done". Silent.',
    importance: ChannelImportance.low,
  ),
  ChannelSpec(
    channel: NotificationChannel.ongoing,
    id: 'ongoing',
    name: 'Cook in progress',
    description:
        'The live readout while a cook is running. Silent and cannot be '
        'swiped away.',
    importance: ChannelImportance.min,
  ),
];

/// Post, update, cancel. Deliberately small: everything interesting is in
/// [planNotifications], which is pure.
abstract interface class NotificationSink {
  /// Idempotent — a second call for the same channel set does nothing.
  Future<void> ensureChannels();

  /// Returns false when the user has denied POST_NOTIFICATIONS. A denial
  /// degrades the app to in-app surfacing; it never throws.
  Future<bool> requestPermission();

  Future<void> post(PendingNotification n);
  Future<void> cancel(String key);

  /// The §9.5 ongoing readout, updated every 30 s.
  Future<void> showOngoing(String title, String body);
  Future<void> hideOngoing();
}

/// What the host suite uses. Records in order, because "did it post
/// before it cancelled" is a real question.
class RecordingNotificationSink implements NotificationSink {
  RecordingNotificationSink({this.permissionGranted = true});

  bool permissionGranted;
  int channelSetups = 0;
  final List<PendingNotification> posted = [];
  final List<String> cancelled = [];
  final List<String> log = [];
  String? ongoingTitle;
  String? ongoingBody;
  int ongoingUpdates = 0;

  @override
  Future<void> ensureChannels() async {
    channelSetups++;
    log.add('channels');
  }

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> post(PendingNotification n) async {
    posted.add(n);
    log.add('post:${n.key}');
  }

  @override
  Future<void> cancel(String key) async {
    cancelled.add(key);
    log.add('cancel:$key');
  }

  @override
  Future<void> showOngoing(String title, String body) async {
    ongoingTitle = title;
    ongoingBody = body;
    ongoingUpdates++;
    log.add('ongoing');
  }

  @override
  Future<void> hideOngoing() async {
    ongoingTitle = null;
    ongoingBody = null;
    log.add('ongoing:hide');
  }
}

/// The seam the foreground service itself hides behind. The plugin's
/// handler runs in a separate isolate over platform channels, which
/// `flutter test` has neither of — so the LIFECYCLE is decided here and
/// the plumbing is proven at the bench.
abstract interface class ForegroundServiceHost {
  bool get running;

  /// Android 14 requires a foreground-service TYPE. Ours is
  /// `connectedDevice` (09 §9.6); omitting it is a crash, not a warning.
  Future<void> start();
  Future<void> stop();

  /// The opt-in §9.6 describes: offered after the FIRST cook starts, not
  /// at launch. Returns false when declined — which degrades the app to
  /// "reconnects and catches up when you open it", and that still works.
  Future<bool> requestIgnoreBatteryOptimizations();
  Future<bool> isIgnoringBatteryOptimizations();
}

class FakeForegroundServiceHost implements ForegroundServiceHost {
  FakeForegroundServiceHost({this.grantOptimizationExemption = true});

  bool grantOptimizationExemption;
  bool _running = false;
  int starts = 0;
  int stops = 0;
  int optimizationPrompts = 0;
  bool exempt = false;

  @override
  bool get running => _running;

  @override
  Future<void> start() async {
    if (!_running) {
      starts++;
    }
    _running = true;
  }

  @override
  Future<void> stop() async {
    if (_running) {
      stops++;
    }
    _running = false;
  }

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async {
    optimizationPrompts++;
    exempt = grantOptimizationExemption;
    return exempt;
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => exempt;
}
