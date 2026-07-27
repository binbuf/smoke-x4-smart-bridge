/// Branch 2 — Alerts (design 13 §13.5.5).
///
/// This replaces a branded placeholder that shipped in a quarter of the primary
/// navigation. It was also the wrong tab to stub: §13.5.7 names banner 11 —
/// *"Alerts are off — you won't be woken"* — as the load-bearing one, because a
/// fourteen-hour cook running with notifications denied, battery optimisation
/// on, or monitoring off is a **silent total failure**. The user finds out at
/// breakfast.
///
/// So the tab leads with **delivery**, not configuration, and delivery leads
/// with a verdict rather than a checklist: one card that says *You'll be woken*
/// or *You won't be woken*, the specific reason when it is the latter, and the
/// fix. Under it sits **[ Send a test alarm ]**, which posts through the real
/// sink on the real channel — the only way anyone verifies delivery before
/// committing a night to it.
///
/// §13.5.5's other two tiers (the bridge's nine rules, and this phone's own
/// stall/ETA/lid rules) are named honestly as still to come rather than
/// rendered as switches that do nothing — the discipline
/// `settings_screen.dart:1-11` set for the whole settings epic, and the reason
/// its six always-on `onChanged: null` switches are not reproduced here.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_env.dart';
import '../../design/design.dart';
import '../../domain/alarms/notification_policy.dart';
import '../../ui/ui.dart';

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
  });

  final bool permissionGranted;
  final bool monitoringEnabled;
  final bool batteryExempt;
  final bool quietHours;

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
}

class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key, this.status, this.onSendTest});

  /// Injected by tests. Null in production, where it is read from the
  /// platform seams at mount.
  final DeliveryStatus? status;

  /// Test seam for the "send a test alarm" button.
  final Future<void> Function()? onSendTest;

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  DeliveryStatus? _status;
  bool _sending = false;
  String _testResult = '';

  @override
  void initState() {
    super.initState();
    _status = widget.status;
    if (widget.status == null) {
      unawaited(_probe());
    }
  }

  /// Reads the three facts through the seams that already exist. Every one of
  /// them degrades to "assume the worst and say so" rather than throwing: a
  /// tab that cannot check whether it can wake you must not claim it can.
  Future<void> _probe() async {
    final env = AppEnv.instance;
    var granted = false;
    var exempt = false;
    try {
      granted = await env?.notifications?.requestPermission() ?? false;
    } on Object {
      granted = false;
    }
    try {
      exempt =
          await env?.foregroundService?.isIgnoringBatteryOptimizations() ??
          false;
    } on Object {
      exempt = false;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _status = DeliveryStatus(
        permissionGranted: granted,
        monitoringEnabled: env?.prefs.monitoringEnabled ?? true,
        batteryExempt: exempt,
        quietHours: env?.prefs.quietHoursEnabled ?? true,
      );
    });
  }

  /// Posts a real notification on the real critical channel. Anything less —
  /// an in-app toast, a mocked path — proves nothing about the thing being
  /// tested, which is the OS delivering a sound at 3 a.m.
  Future<void> _sendTest() async {
    setState(() {
      _sending = true;
      _testResult = '';
    });
    try {
      final custom = widget.onSendTest;
      if (custom != null) {
        await custom();
      } else {
        final sink = AppEnv.instance?.notifications;
        if (sink == null) {
          setState(
            () =>
                _testResult = 'This build has no notification support to test.',
          );
          return;
        }
        await sink.ensureChannels();
        await sink.post(
          const PendingNotification(
            key: 'test',
            channel: NotificationChannel.critical,
            title: 'Test alert',
            body: 'If you can see and hear this, your cook can wake you.',
            // Never silent, whatever quiet hours say: the one thing being
            // tested is whether this phone makes a noise.
            silent: false,
          ),
        );
      }
      if (mounted) {
        setState(
          () => _testResult =
              'Sent. Check your notification shade — and if your phone is '
              'silent, check its volume and Do Not Disturb.',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _testResult = 'Couldn’t send it. Alerts may be blocked.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = _status;
    return SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: _probe,
        child: ListView(
          key: const Key('alerts-tab'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(SmokeTokens.s4),
          children: [
            // Prose and cards read at prose width; on a tablet this keeps the
            // verdict a card rather than a banner spanning the window.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: SmokeWindow.readableMax,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (status == null)
                      const Padding(
                        padding: EdgeInsets.all(SmokeTokens.s6),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      _verdictCard(t, status),
                      const SizedBox(height: SmokeTokens.s4),
                      _testCard(t),
                      const SizedBox(height: SmokeTokens.s4),
                      _comingCard(t),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── tier 1: will this phone wake you ─────────────────────────────────

  Widget _verdictCard(SmokeTokens t, DeliveryStatus s) {
    final ok = s.willWake;
    final accent = ok ? StatusPalette.positive : StatusPalette.critical;
    return SmokeCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('DELIVERY', style: SmokeType.label.copyWith(color: t.textMuted)),
          const SizedBox(height: SmokeTokens.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                ok
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_rounded,
                size: 26,
                color: accent,
              ),
              const SizedBox(width: SmokeTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ok ? 'You’ll be woken' : 'You won’t be woken',
                      key: const Key('alerts-verdict'),
                      style: SmokeType.title.copyWith(color: t.textHi),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _verdictCaption(s),
                      key: const Key('alerts-verdict-caption'),
                      style: SmokeType.bodySm.copyWith(color: t.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final b in s.blockers) ...[
            const SizedBox(height: SmokeTokens.s3),
            _blockerRow(t, b),
          ],
        ],
      ),
    );
  }

  String _verdictCaption(DeliveryStatus s) => switch (s.worst) {
    DeliveryBlocker.permission =>
      'This phone is blocking notifications from the app, so a dying fire '
          'or a finished brisket will pass in silence.',
    DeliveryBlocker.monitoringOff =>
      'Background monitoring is off, so the app only notices things while '
          'you have it open.',
    DeliveryBlocker.batteryOptimised =>
      'Alerts will reach you, but this phone may pause the app in the '
          'background — so one could arrive late.',
    null =>
      s.quietHours
          ? 'Critical alarms will sound, including during quiet hours.'
          : 'Critical alarms will sound.',
  };

  Widget _blockerRow(SmokeTokens t, DeliveryBlocker b) {
    final (String title, String body, String action) = switch (b) {
      DeliveryBlocker.permission => (
        'Notifications are blocked',
        'Allow notifications so the app can reach you.',
        'Allow notifications',
      ),
      DeliveryBlocker.monitoringOff => (
        'Background monitoring is off',
        'Turn it on so alarms are noticed while the app is closed.',
        'Turn on monitoring',
      ),
      DeliveryBlocker.batteryOptimised => (
        'Battery optimisation is on',
        'Exempt the app so a long cook is not paused in the background.',
        'Allow background use',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(SmokeTokens.s3),
      decoration: BoxDecoration(
        color: t.cardSubtle,
        borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: SmokeType.body.copyWith(color: t.textHi)),
          Text(body, style: SmokeType.bodySm.copyWith(color: t.textMuted)),
          const SizedBox(height: SmokeTokens.s2),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              key: Key('alerts-fix-${b.name}'),
              onPressed: () => unawaited(_fix(b)),
              child: Text(action),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fix(DeliveryBlocker b) async {
    final env = AppEnv.instance;
    switch (b) {
      case DeliveryBlocker.permission:
        await env?.notifications?.requestPermission();
      case DeliveryBlocker.monitoringOff:
        await env?.prefs.setMonitoringEnabled(true);
      case DeliveryBlocker.batteryOptimised:
        await env?.foregroundService?.requestIgnoreBatteryOptimizations();
    }
    await _probe();
  }

  // ── the proof ────────────────────────────────────────────────────────

  Widget _testCard(SmokeTokens t) => SmokeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('PROOF', style: SmokeType.label.copyWith(color: t.textMuted)),
        const SizedBox(height: SmokeTokens.s2),
        Text(
          'Send yourself a real alarm on the real channel. It is the only way '
          'to know before you commit fourteen hours.',
          style: SmokeType.bodySm.copyWith(color: t.textMuted),
        ),
        const SizedBox(height: SmokeTokens.s3),
        FilledButton.tonalIcon(
          key: const Key('alerts-send-test'),
          onPressed: _sending ? null : () => unawaited(_sendTest()),
          icon: const Icon(Icons.notifications_active_outlined, size: 18),
          label: Text(_sending ? 'Sending…' : 'Send a test alarm'),
        ),
        if (_testResult.isNotEmpty) ...[
          const SizedBox(height: SmokeTokens.s2),
          Text(
            _testResult,
            key: const Key('alerts-test-result'),
            style: SmokeType.bodySm.copyWith(color: t.textBody),
          ),
        ],
      ],
    ),
  );

  // ── tiers 2 and 3, named rather than faked ───────────────────────────

  Widget _comingCard(SmokeTokens t) => SmokeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RULES', style: SmokeType.label.copyWith(color: t.textMuted)),
        const SizedBox(height: SmokeTokens.s2),
        Text(
          'The bridge’s own alarm rules and this phone’s stall, ETA and lid '
          'alerts are not editable yet. The bridge’s defaults are all on, so '
          'a target reached, a dying fire and a detached probe already alarm.',
          style: SmokeType.bodySm.copyWith(color: t.textMuted),
        ),
        const SizedBox(height: SmokeTokens.s2),
        Text(
          'To silence one that is ringing, use the bar at the top of any tab.',
          style: SmokeType.bodySm.copyWith(color: t.textMuted),
        ),
      ],
    ),
  );
}
