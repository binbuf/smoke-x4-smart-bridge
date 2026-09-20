/// The delivery verdict, as a banner (newapp §B.2, §C.1).
///
/// `/alerts` was a primary destination for a verdict and a test button. §B.1's
/// judgement is that a verdict is not a place you live — so it became this: a
/// strip that appears on `/live` and `/device` **only while something is
/// actually wrong**, says what, and offers the one action that fixes it.
///
/// Two rules it inherits and must not break:
///
///  * **A control that cannot work is absent.** The banner is not rendered at
///    all when delivery is fine, rather than rendered green — a permanent strip
///    saying everything is well is how a user learns to stop reading strips.
///  * **Never spend a permission prompt to render.** Android stops showing the
///    notifications dialog after two refusals, forever. The banner *checks*
///    (`hasPermission`); only the button *requests*.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_env.dart';
import '../../design/design.dart';
import 'delivery.dart';

class DeliveryBanner extends StatefulWidget {
  const DeliveryBanner({super.key, this.status, this.onChanged});

  /// Injected by tests and by the Lab. Null in production, where it is probed
  /// through the platform seams at mount.
  final DeliveryStatus? status;

  /// Called after a fix attempt, so a host screen can re-read anything of its
  /// own that depends on the verdict.
  final VoidCallback? onChanged;

  @override
  State<DeliveryBanner> createState() => _DeliveryBannerState();
}

class _DeliveryBannerState extends State<DeliveryBanner> {
  DeliveryStatus? _status;
  bool _busy = false;

  /// Dismissed **until fixed**, not dismissed forever: §B.2 is explicit that
  /// this is "dismissible-until-fixed". Re-probing after a fix clears it; a
  /// dismissal only silences the current sitting.
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _status = widget.status;
    if (widget.status == null) {
      unawaited(_probe());
    }
  }

  Future<void> _probe() async {
    final next = await probeDelivery();
    if (mounted) {
      setState(() => _status = next);
    }
  }

  Future<void> _fix(DeliveryBlocker blocker) async {
    setState(() => _busy = true);
    final env = AppEnv.instance;
    try {
      switch (blocker) {
        case DeliveryBlocker.permission:
          await env?.notifications?.requestPermission();
        case DeliveryBlocker.monitoringOff:
          await env?.prefs.setMonitoringEnabled(true);
        case DeliveryBlocker.batteryOptimised:
          await env?.foregroundService?.requestIgnoreBatteryOptimizations();
      }
    } on Object {
      // The verdict re-probe below is what reports the outcome — a thrown
      // platform call is just "it did not change".
    }
    await _probe();
    if (mounted) {
      setState(() {
        _busy = false;
        _dismissed = false;
      });
    }
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    // Absent, not green: nothing is wrong, so there is nothing to say.
    if (status == null || !status.needsAttention || _dismissed) {
      return const SizedBox.shrink();
    }
    final t = context.tokens;
    final blocker = status.worst!;
    final role = StatusRole.critical;
    return Container(
      key: const Key('delivery-banner'),
      margin: const EdgeInsets.fromLTRB(
        SmokeTokens.s4,
        SmokeTokens.s2,
        SmokeTokens.s4,
        0,
      ),
      padding: const EdgeInsets.all(SmokeTokens.s3),
      decoration: BoxDecoration(
        color: StatusPalette.fill(role),
        borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
        border: Border.all(color: StatusPalette.border(role)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_off_rounded,
            size: 18,
            color: StatusPalette.hue(role),
          ),
          const SizedBox(width: SmokeTokens.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The hue is carried by the icon and the border; the words are
                // carried by contrast (§14.6.5).
                Text(
                  status.headline,
                  style: SmokeType.title.copyWith(color: t.textHi),
                ),
                const SizedBox(height: 2),
                Text(
                  status.detail,
                  style: SmokeType.bodySm.copyWith(color: t.textBody),
                ),
                const SizedBox(height: SmokeTokens.s2),
                // `Wrap`, not `Row`: two buttons plus a 200 % text scale is
                // wider than a 360 dp phone, and §H.2's accessibility pass
                // requires large text to reflow rather than overflow.
                Wrap(
                  spacing: SmokeTokens.s2,
                  runSpacing: SmokeTokens.s1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonal(
                      key: const Key('delivery-banner-fix'),
                      onPressed: _busy ? null : () => unawaited(_fix(blocker)),
                      child: Text(status.actionLabel),
                    ),
                    TextButton(
                      key: const Key('delivery-banner-dismiss'),
                      onPressed: () => setState(() => _dismissed = true),
                      child: const Text('Not now'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
