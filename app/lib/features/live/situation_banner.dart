/// One named situation, above the temperatures (design 16 §16.3, §16.5).
///
/// The reconciliation layer answers *"what is actually wrong, and what is being
/// done about it"* with a single [Situation]. This renders it, and it renders
/// **one** — never a list. A list of problems is a triage job handed to a tired
/// person at 3 a.m., which is the failure mode §16.3 exists to end.
///
/// Four rules it enforces so no caller has to remember them:
///
///  * **It never covers the numbers.** It is a sibling above them in a column,
///    never an overlay, never a dialog, and it is absent — not collapsed to a
///    green "all well" strip — when there is nothing to say.
///  * **The status hue is chrome only**: a 12–16 % fill, a 22–35 % border, and
///    always an icon *and* a word. **The text is `textHi`**, because the hue
///    lands 3.2–7.0:1 on its own fill and the ink lands 13:1 (§16.5).
///  * **Green never appears.** Green is transport health; a resolved situation
///    is reported in the past tense, in words.
///  * **Automatic means no button.** §16.3: *act, then report.* A banner
///    offering to do a thing the app could simply have done is an app making
///    its problem into the user's decision — so an `automatic` situation gets
///    the sentence ("Reconnecting to it now") and no control at all.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../domain/situation/situation.dart';

class SituationBanner extends StatelessWidget {
  const SituationBanner({super.key, required this.situation, this.onAction});

  final Situation situation;

  /// The single action, wired. Absent (or absent on the situation) means the
  /// button is not rendered — never a control that looks live and is not.
  final VoidCallback? onAction;

  /// How loud. A situation the user cannot get past is `critical`; one the app
  /// is working around is `warning`; one that is merely news is `info`.
  static StatusRole roleFor(SituationKind kind) => switch (kind) {
    SituationKind.bluetoothOff ||
    SituationKind.permissionMissing ||
    SituationKind.bridgeWasReset ||
    SituationKind.staleCook => StatusRole.critical,
    SituationKind.bridgeHostingOwnNetwork ||
    SituationKind.bridgeMovedAddress ||
    SituationKind.bridgeNotPairedToBase ||
    SituationKind.deviceClockUnset ||
    SituationKind.firmwareTooOld ||
    SituationKind.bridgeOutOfRange => StatusRole.warning,
    SituationKind.neverSetUp ||
    SituationKind.phoneForgotBridge ||
    SituationKind.healthy => StatusRole.info,
  };

  /// The glyph names the cause, so the banner is legible before it is read.
  static IconData iconFor(SituationKind kind) => switch (kind) {
    SituationKind.bluetoothOff => Icons.bluetooth_disabled_rounded,
    SituationKind.permissionMissing => Icons.lock_outline_rounded,
    SituationKind.neverSetUp => Icons.add_circle_outline_rounded,
    SituationKind.phoneForgotBridge => Icons.link_rounded,
    SituationKind.bridgeHostingOwnNetwork => Icons.wifi_tethering_rounded,
    SituationKind.bridgeMovedAddress => Icons.swap_horiz_rounded,
    SituationKind.bridgeWasReset => Icons.restart_alt_rounded,
    SituationKind.bridgeNotPairedToBase => Icons.link_off_rounded,
    SituationKind.deviceClockUnset => Icons.schedule_rounded,
    SituationKind.firmwareTooOld => Icons.system_update_alt_rounded,
    SituationKind.bridgeOutOfRange => Icons.cloud_off_rounded,
    SituationKind.staleCook => Icons.outdoor_grill_rounded,
    SituationKind.healthy => Icons.check_rounded,
  };

  @override
  Widget build(BuildContext context) {
    if (!situation.showsBanner) {
      return const SizedBox.shrink();
    }
    final t = context.tokens;
    final role = roleFor(situation.kind);
    // The app is handling it: report, do not ask. The button is the remedy for
    // the situations only a human can resolve.
    final showAction =
        !situation.automatic &&
        situation.actionLabel.isNotEmpty &&
        onAction != null;

    return Container(
      key: Key('situation-${situation.kind.name}'),
      padding: const EdgeInsets.all(SmokeTokens.s3),
      decoration: BoxDecoration(
        color: StatusPalette.fill(role),
        borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
        border: Border.all(color: StatusPalette.border(role)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            iconFor(situation.kind),
            size: 20,
            color: StatusPalette.hue(role),
          ),
          const SizedBox(width: SmokeTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  situation.headline,
                  style: SmokeType.title.copyWith(color: t.textHi),
                ),
                if (situation.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    situation.detail,
                    style: SmokeType.bodySm.copyWith(color: t.textBody),
                  ),
                ],
                if (showAction) ...[
                  const SizedBox(height: SmokeTokens.s3),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      key: const Key('situation-action'),
                      onPressed: onAction,
                      child: Text(situation.actionLabel),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
