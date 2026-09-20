/// The chrome the cook sheets share (16 §16.5).
///
/// Lifted out of `cook_edit_sheets.dart` when the backdate sheet grew into its
/// own file. Nothing here decides anything — it is a titled surface and a date
/// picker, both in the design system, so two sheets cannot drift into looking
/// like two apps.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';

/// A titled bottom sheet with a close affordance and a scrolling body.
Widget cookSheetShell(
  BuildContext context, {
  required String title,
  required List<Widget> children,
  Key? key,
}) {
  final t = context.tokens;
  return Container(
    key: key,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    decoration: BoxDecoration(
      color: t.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(SmokeTokens.radiusCard),
      ),
      border: Border.all(color: t.hairline),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SmokeTokens.s4,
              SmokeTokens.s4,
              SmokeTokens.s2,
              SmokeTokens.s2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: SmokeType.displayS.copyWith(color: t.textHi),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                SmokeTokens.s4,
                0,
                SmokeTokens.s4,
                SmokeTokens.s4,
              ),
              children: children,
            ),
          ),
        ],
      ),
    ),
  );
}

/// A tappable row: icon, title, an explaining subtitle, an optional value.
/// 52 dp minimum, like every other row in the app (§16.5).
///
/// A row that cannot run **renders anyway**, dimmed, with [reason] directly
/// beneath it — never absent, never silently inert.
class CookSheetRow extends StatelessWidget {
  const CookSheetRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leadingDot,
    this.iconColor,
    this.enabled = true,
    this.reason,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// The right-hand value — usually the time this row would set.
  final String? trailing;

  /// A ≤12 dp series-hue dot, tying a row to the probe it came from. The only
  /// place a series hue is allowed to appear here.
  final Color? leadingDot;

  /// Overrides the icon ink. Used once, for delete.
  final Color? iconColor;

  final bool enabled;

  /// Why the row cannot run. Required in spirit whenever [enabled] is false —
  /// a dimmed row with no explanation is the failure §16.5 names.
  final String? reason;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              horizontal: SmokeTokens.s4,
              vertical: SmokeTokens.s3,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(icon, size: 20, color: iconColor ?? t.textBody),
                      if (leadingDot != null)
                        Positioned(
                          right: -2,
                          bottom: -1,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: leadingDot,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: SmokeTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: SmokeType.title.copyWith(color: t.textHi),
                            ),
                          ),
                          if (trailing != null) ...[
                            const SizedBox(width: SmokeTokens.s2),
                            Flexible(
                              child: Text(
                                trailing!,
                                textAlign: TextAlign.end,
                                style: SmokeType.body.copyWith(
                                  color: t.textHi,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: SmokeType.bodySm.copyWith(
                              color: t.textMuted,
                            ),
                          ),
                        ),
                      if (!enabled && reason != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            reason!,
                            style: SmokeType.bodySm.copyWith(
                              color: t.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A date then a time, both seeded from [seedUnixMs].
///
/// Both directions are open: a cook can be backdated a long way (the bridge may
/// have been recording for weeks before anyone opened the app) and scheduled
/// forward.
Future<int?> pickCookDateTime(BuildContext context, int seedUnixMs) async {
  final seed = DateTime.fromMillisecondsSinceEpoch(seedUnixMs);
  final date = await showDatePicker(
    context: context,
    initialDate: seed,
    firstDate: seed.subtract(const Duration(days: 400)),
    lastDate: seed.add(const Duration(days: 30)),
  );
  if (date == null || !context.mounted) {
    return null;
  }
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(seed),
  );
  if (time == null) {
    return null;
  }
  return DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  ).millisecondsSinceEpoch;
}
