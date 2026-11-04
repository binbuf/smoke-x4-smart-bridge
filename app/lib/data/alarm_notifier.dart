import 'dart:async';

import 'package:flutter/services.dart';

/// Delivery seam for the alarm alert. Production uses the Android notification
/// channel; tests and review builds use [NoopAlarmNotifier].
abstract interface class AlarmNotifier {
  /// Initialise the platform channel and register [onOpen]. [onOpen] receives
  /// the probe mask stored in the notification payload (0 = all active).
  Future<void> initialize({void Function(int probeMask)? onOpen});

  Future<void> showAlarm({
    required int probeMask,
    required String title,
    required String body,
  });

  Future<void> cancelAlarm();
}

/// No-op implementation for host tests and review builds.
class NoopAlarmNotifier implements AlarmNotifier {
  const NoopAlarmNotifier();

  @override
  Future<void> initialize({void Function(int probeMask)? onOpen}) async {}

  @override
  Future<void> showAlarm({
    required int probeMask,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancelAlarm() async {}
}

/// Android local-notification delivery over a narrow method channel.
///
/// This is the "app is backgrounded or not on screen" path. Android can still
/// suspend a background process; the Bridge keeps recording and the app
/// reconciles the latched alarm on the next connect. A foreground service is a
/// separate product decision and is not started here.
class LocalAlarmNotifier implements AlarmNotifier {
  LocalAlarmNotifier({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('smoke_bridge/alarm');

  static const int notificationId = 4100;

  final MethodChannel _channel;
  void Function(int probeMask)? _onOpen;

  @override
  Future<void> initialize({void Function(int probeMask)? onOpen}) async {
    _onOpen = onOpen;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'alarmOpened') return null;
      final mask = (call.arguments as num?)?.toInt() ?? 0;
      _onOpen?.call(mask & 0x0F);
      return null;
    });
    try {
      final pending = await _channel.invokeMethod<int>('initialize');
      if (pending != null && pending != 0) {
        _onOpen?.call(pending & 0x0F);
      }
    } on PlatformException {
      // A non-Android host has no notification service; alarms still work
      // in-app and the Bridge remains authoritative.
    } on MissingPluginException {
      // Host tests and review builds do not register the channel.
    }
  }

  @override
  Future<void> showAlarm({
    required int probeMask,
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<void>('showAlarm', <String, Object>{
        'id': notificationId,
        'title': title,
        'body': body,
        'probeMask': probeMask & 0x0F,
      });
    } on PlatformException {
      // Notification permission can be denied; the in-app dialog still fires.
    } on MissingPluginException {
      // Host tests and review builds do not register the channel.
    }
  }

  @override
  Future<void> cancelAlarm() async {
    try {
      await _channel.invokeMethod<void>('cancelAlarm', <String, Object>{
        'id': notificationId,
      });
    } on PlatformException {
      // Nothing to cancel.
    } on MissingPluginException {
      // Host tests and review builds do not register the channel.
    }
  }
}
