/// A13.2 / A13.5 — the plugin-backed halves of the two seams in
/// `notifications.dart`.
///
/// **Nothing in this file is reachable from `flutter test`**, by
/// construction: `flutter_local_notifications` and
/// `flutter_foreground_task` are platform channels, and the service's
/// handler is a second isolate. That is exactly why the DECISIONS live in
/// `domain/alarms/notification_policy.dart` and
/// `features/monitor/cook_monitor.dart`, both of which are pure and
/// host-tested. This file is the plumbing the bench proves.
///
/// The same shape A7.4 gave `nsd` and A14 gave the network binder, for
/// the same reason.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/alarms/notification_policy.dart';
import 'notifications.dart';

/// The ongoing readout owns a fixed id so updating it replaces it rather
/// than stacking a new notification every 30 seconds.
const int _kOngoingId = 1;

class PluginNotificationSink implements NotificationSink {
  PluginNotificationSink([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _channelsReady = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Importance _importance(ChannelImportance i) => switch (i) {
    ChannelImportance.min => Importance.min,
    ChannelImportance.low => Importance.low,
    ChannelImportance.defaultImportance => Importance.defaultImportance,
    ChannelImportance.high => Importance.high,
  };

  @override
  Future<void> ensureChannels() async {
    if (_channelsReady) {
      return;
    }
    _channelsReady = true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    // Created UP FRONT with their §9.5 importances. Android will not let
    // a channel's importance change after creation, so a channel first
    // created as DEFAULT would stay DEFAULT for the life of the install
    // and "critical alarms stopped making a sound" would be unshippable.
    for (final spec in notificationChannels) {
      await _android?.createNotificationChannel(
        AndroidNotificationChannel(
          spec.id,
          spec.name,
          description: spec.description,
          importance: _importance(spec.importance),
          playSound:
              spec.importance.index >=
              ChannelImportance.defaultImportance.index,
        ),
      );
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } on Object catch (e) {
      // A denial degrades the app to in-app surfacing; it never throws
      // into the monitor loop.
      debugPrint('notification permission unavailable: $e');
      return false;
    }
  }

  /// Checks without prompting — Android stops showing the dialog after two
  /// refusals, forever, so the delivery banner must not spend one to render.
  @override
  Future<bool> hasPermission() async {
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } on Object catch (e) {
      debugPrint('notification permission check unavailable: $e');
      return false;
    }
  }

  /// §G.4 — the mechanism that lights the screen at 3 a.m.
  ///
  /// Since 22 January 2025 apps targeting Android 14+ only hold
  /// `USE_FULL_SCREEN_INTENT` by default if they have calling or **alarm**
  /// functionality. This app declares itself an alarm app (the manifest says
  /// so, and the Play Console declaration backs it), but the user can revoke
  /// it.
  ///
  /// **`flutter_local_notifications` 22 exposes no read-only check** — only
  /// `requestFullScreenIntentPermission`, which prompts. Prompting to render a
  /// verdict is exactly the mistake the notifications permission taught (two
  /// refusals and Android never shows the dialog again), so this returns the
  /// unknown answer rather than spending a prompt on it. Unknown is `true`
  /// deliberately: a warning nobody can act on is noise, and this permission is
  /// granted by default on every device that predates the change.
  @override
  Future<bool> canUseFullScreenIntent() async => true;

  @override
  Future<void> openFullScreenIntentSettings() async {
    try {
      await _android?.requestFullScreenIntentPermission();
    } on Object catch (e) {
      debugPrint('full-screen intent request unavailable: $e');
    }
  }

  /// §G.4 — exact alarms, so a time-based rule (elapsed, before-the-end) fires
  /// on time in Doze rather than whenever the OS next feels like it.
  Future<bool> canScheduleExactAlarms() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? true;
    } on Object catch (e) {
      debugPrint('exact alarm check unavailable: $e');
      return true;
    }
  }

  Future<void> requestExactAlarms() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } on Object catch (e) {
      debugPrint('exact alarm request unavailable: $e');
    }
  }

  int _idFor(String key) => key.hashCode & 0x7FFFFFFF;

  @override
  Future<void> post(PendingNotification n) async {
    final spec = notificationChannels.firstWhere((c) => c.channel == n.channel);
    final details = AndroidNotificationDetails(
      spec.id,
      spec.name,
      channelDescription: spec.description,
      importance: _importance(spec.importance),
      priority: n.channel == NotificationChannel.critical
          ? Priority.high
          : Priority.defaultPriority,
      // Quiet hours silence the DELIVERY, not the notification: it still
      // appears in the shade, and it is still there at 07:00 (§9.5).
      playSound: !n.silent,
      enableVibration: !n.silent,
      // §9.5's full-screen intent for critical, so it lights the screen
      // of a phone face-down on a bedside table.
      fullScreenIntent: n.channel == NotificationChannel.critical,
      category: n.channel == NotificationChannel.critical
          ? AndroidNotificationCategory.alarm
          : null,
    );
    await _plugin.show(
      id: _idFor(n.key),
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(android: details),
      payload: n.key,
    );
  }

  @override
  Future<void> cancel(String key) => _plugin.cancel(id: _idFor(key));

  @override
  Future<void> showOngoing(String title, String body) async {
    final spec = notificationChannels.firstWhere(
      (c) => c.channel == NotificationChannel.ongoing,
    );
    await _plugin.show(
      id: _kOngoingId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          spec.id,
          spec.name,
          channelDescription: spec.description,
          importance: Importance.min,
          priority: Priority.min,
          ongoing: true,
          autoCancel: false,
          playSound: false,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }

  @override
  Future<void> hideOngoing() => _plugin.cancel(id: _kOngoingId);
}

class PluginForegroundServiceHost implements ForegroundServiceHost {
  bool _running = false;

  @override
  bool get running => _running;

  @override
  Future<void> start() async {
    if (_running) {
      return;
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ongoing',
        channelName: 'Cook in progress',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
    await FlutterForegroundTask.startService(
      // Android 14 requires a TYPE, and omitting it is a CRASH rather
      // than a warning. Ours is connectedDevice because that is what the
      // service does (09 §9.6).
      serviceTypes: const [ForegroundServiceTypes.connectedDevice],
      notificationTitle: 'Smoke Bridge',
      notificationText: 'Monitoring your cook',
    );
    _running = true;
  }

  @override
  Future<void> stop() async {
    if (!_running) {
      return;
    }
    await FlutterForegroundTask.stopService();
    _running = false;
  }

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        return true;
      }
      // OPT-IN, offered once after the first cook starts. Declining is a
      // supported outcome: the app degrades to "reconnects and catches up
      // when you open it", which still works because sync is delta-based
      // and the DEVICE never stopped recording (04).
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } on Object catch (e) {
      debugPrint('battery optimisation request unavailable: $e');
      return false;
    }
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } on Object {
      return false;
    }
  }
}
