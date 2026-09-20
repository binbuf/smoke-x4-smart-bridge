/// The lead card of `/device` — **the card IS the situation** (design 16 §16.6).
///
/// One card, one cause, one action. Never a list: a list of problems is a
/// triage job handed to a tired person at 3 a.m., and the reconciler upstream
/// has already done the triage.
///
/// The colour rule, which is the one most easily broken on a card like this
/// (§16.5):
///
///  * the hue is **chrome** — a 10–14% fill and a 22–35% border — and it is
///    carried by the icon and the border, never by the words. Every string here
///    is `textHi` (13:1) or `textBody`; on `critical`'s fill the hue itself
///    would be 3.2:1;
///  * there is always an **icon *and* a word**, so the state survives a
///    colour-blind reader and a phone in direct sun;
///  * **green means transport health and nothing else** — so "Reconnected" is
///    green and "Set your bridge's clock" is not.
///
/// It is a `Container` rather than a [SmokeCard] on purpose: `SmokeCard`'s
/// `accent` is the *series*-hue treatment (a 35% border plus a bloom over a
/// neutral fill), and a status shape wants the opposite proportion and no glow
/// at all.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../domain/situation/situation.dart';
import '../../ui/ui.dart';
import '../shell/situation_resolver.dart';

/// Renders [situation] and its single action.
///
/// [onAct] is null when the action is one nothing can currently perform; the
/// button is then rendered **disabled with its reason beneath**, never hidden
/// and never live-but-inert.
class SituationCard extends StatelessWidget {
  const SituationCard({
    required this.situation,
    this.onAct,
    this.disabledReason = '',
    this.busy = false,
    super.key,
  });

  final Situation situation;
  final VoidCallback? onAct;

  /// Why [onAct] is null, in the user's terms. Shown under the button.
  final String disabledReason;

  /// A remedy is running right now.
  final bool busy;

  StatusRole get role {
    if (situation.resolvedAutomatically) {
      // A fix that restored the link is transport health, and that is the one
      // thing green is allowed to mean. A fix that set a clock or learned an
      // address is not, however pleasing it is.
      return switch (situation.kind) {
        SituationKind.phoneForgotBridge ||
        SituationKind.bridgeHostingOwnNetwork ||
        SituationKind.bridgeOutOfRange => StatusRole.positive,
        _ => StatusRole.info,
      };
    }
    return switch (situation.kind) {
      SituationKind.bridgeWasReset ||
      SituationKind.bridgeOutOfRange => StatusRole.critical,
      SituationKind.bluetoothOff ||
      SituationKind.permissionMissing ||
      SituationKind.bridgeHostingOwnNetwork ||
      SituationKind.bridgeNotPairedToBase ||
      SituationKind.staleCook => StatusRole.warning,
      SituationKind.neverSetUp ||
      SituationKind.phoneForgotBridge ||
      SituationKind.bridgeMovedAddress ||
      SituationKind.deviceClockUnset ||
      SituationKind.firmwareTooOld ||
      SituationKind.healthy => StatusRole.info,
    };
  }

  IconData get icon {
    if (situation.resolvedAutomatically) {
      return Icons.check_circle_rounded;
    }
    return switch (situation.kind) {
      SituationKind.bluetoothOff => Icons.bluetooth_disabled_rounded,
      SituationKind.permissionMissing => Icons.lock_outline_rounded,
      SituationKind.neverSetUp => Icons.add_link_rounded,
      SituationKind.phoneForgotBridge => Icons.link_rounded,
      SituationKind.bridgeHostingOwnNetwork => Icons.wifi_tethering_rounded,
      SituationKind.bridgeMovedAddress => Icons.moving_rounded,
      SituationKind.bridgeWasReset => Icons.help_outline_rounded,
      SituationKind.bridgeNotPairedToBase => Icons.sensors_off_rounded,
      SituationKind.deviceClockUnset => Icons.schedule_rounded,
      SituationKind.firmwareTooOld => Icons.system_update_alt_rounded,
      SituationKind.bridgeOutOfRange => Icons.cloud_off_rounded,
      SituationKind.staleCook => Icons.outdoor_grill_rounded,
      SituationKind.healthy => Icons.check_circle_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = role;
    final label = situation.actionLabel;
    final showsAction = label.isNotEmpty;
    return Semantics(
      container: true,
      label: '${situation.headline}. ${situation.detail}',
      child: Container(
        key: const Key('situation-card'),
        width: double.infinity,
        padding: const EdgeInsets.all(SmokeTokens.s4),
        decoration: BoxDecoration(
          color: StatusPalette.fill(r),
          borderRadius: BorderRadius.circular(SmokeTokens.radiusCard),
          border: Border.all(color: StatusPalette.border(r)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 24, color: StatusPalette.hue(r)),
                const SizedBox(width: SmokeTokens.s3),
                Expanded(
                  child: Text(
                    situation.headline,
                    key: const Key('situation-headline'),
                    style: SmokeType.title.copyWith(color: t.textHi),
                  ),
                ),
              ],
            ),
            if (situation.detail.isNotEmpty) ...[
              const SizedBox(height: SmokeTokens.s2),
              Text(
                situation.detail,
                key: const Key('situation-detail'),
                style: SmokeType.body.copyWith(color: t.textBody),
              ),
            ],
            if (busy) ...[
              const SizedBox(height: SmokeTokens.s3),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: SmokeTokens.s2),
                  Text(
                    'Working on it…',
                    key: const Key('situation-busy'),
                    style: SmokeType.bodySm.copyWith(color: t.textMuted),
                  ),
                ],
              ),
            ],
            if (showsAction) ...[
              const SizedBox(height: SmokeTokens.s4),
              PrimaryAction(
                key: const Key('situation-action'),
                label: label,
                busy: busy,
                onPressed: onAct,
              ),
              if (onAct == null && disabledReason.isNotEmpty) ...[
                const SizedBox(height: SmokeTokens.s2),
                Text(
                  disabledReason,
                  key: const Key('situation-action-reason'),
                  style: SmokeType.bodySm.copyWith(color: t.textMuted),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The one-line description of what each [SituationAct] will do, for the
/// screen that has to route it. Kept beside the card so the copy and the
/// destination cannot drift apart.
String actDescription(SituationAct act) => switch (act) {
  SituationAct.none => '',
  SituationAct.openBluetooth => 'Opens your phone’s Bluetooth settings.',
  SituationAct.grantPermission => 'Asks for the permission the app needs.',
  SituationAct.runSetup => 'Walks through setting a bridge up.',
  SituationAct.pairBase => 'Walks through introducing the two devices.',
  SituationAct.adoptBridge => 'Makes this bridge the one this phone uses.',
  SituationAct.switchNetwork => 'Changes which network the bridge is on.',
  SituationAct.updateFirmware => 'Opens the firmware page.',
  SituationAct.endCook => 'Ends the cook this phone is carrying.',
};
