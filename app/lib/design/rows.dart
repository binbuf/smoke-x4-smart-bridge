/// N3.17–N3.18 — the row primitives.
///
/// `SettingsRow` is the settings tree's one row shape: icon, name, sub,
/// trailing, and a disabled state that states its reason (I5). `LinkRow` is the
/// transport/health row (Bluetooth, Wi-Fi) with a trailing slot; `SignalBars`
/// draws the four neutral bars.
///
/// **Signal bars are neutral, never a status hue.** They describe link quality,
/// which is a property of the transport, not a critical/warning/positive
/// judgement; colouring them would make two hops look like two severities.
library;

import 'package:flutter/material.dart';

import 'icons.dart';
import 'text.dart';
import 'tokens.dart';

/// The uppercase section label (`.section-label`).
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(
        top: tokens.spacing.s5,
        bottom: tokens.spacing.s2,
      ),
      child: Row(
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: SmokeText.labelSm.copyWith(
              letterSpacing: 0.9,
              color: tokens.textMuted,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// One row in the settings tree.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.name,
    this.sub,
    this.trailing,
    this.onTap,
    this.disabledReason,
    this.danger = false,
  });

  final SmokeGlyph icon;
  final String name;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Why the row is disabled (I5). Null means it is not disabled.
  final String? disabledReason;

  /// Renders the name/icon in the critical hue.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final disabled = disabledReason != null;
    final accent = danger ? tokens.critical : tokens.textBody;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: danger
                  ? tokens.tint(tokens.critical, 0.10)
                  : tokens.cardSubtle,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SmokeIcon(icon, size: 17, color: accent),
          ),
          SizedBox(width: tokens.spacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  style: SmokeText.bodyStrong.copyWith(
                    fontSize: 13.5,
                    color: danger ? tokens.critical : tokens.textHi,
                  ),
                ),
                if (sub != null)
                  Text(
                    disabled && disabledReason != null ? disabledReason! : sub!,
                    style: SmokeText.labelSm.copyWith(
                      fontSize: 11.5,
                      color: tokens.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            SizedBox(width: tokens.spacing.s2),
            trailing!,
          ],
        ],
      ),
    );

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: disabled ? null : onTap, child: row),
      ),
    );
  }
}

/// A transport/health row.
class LinkRow extends StatelessWidget {
  const LinkRow({
    super.key,
    required this.icon,
    required this.name,
    this.sub,
    this.right,
    this.off = false,
    this.onTap,
  });

  final SmokeGlyph icon;
  final String name;
  final String? sub;
  final Widget? right;

  /// Dims the icon when the link is down.
  final bool off;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: <Widget>[
              Opacity(
                opacity: off ? 0.6 : 1,
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.cardSubtle,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: SmokeIcon(icon, color: tokens.textBody),
                ),
              ),
              SizedBox(width: tokens.spacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name,
                      style: SmokeText.bodyStrong.copyWith(
                        fontSize: 13.5,
                        color: tokens.textHi,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub!,
                        style: SmokeText.labelSm.copyWith(
                          fontSize: 11.5,
                          color: tokens.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (right != null) ...<Widget>[
                SizedBox(width: tokens.spacing.s2),
                right!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Four neutral signal bars.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.bars, this.maxBars = 4});

  /// How many bars are lit (0–[maxBars]).
  final int bars;
  final int maxBars;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Semantics(
      label: '$bars of $maxBars bars',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (var i = 0; i < maxBars; i++)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Container(
                width: 3,
                height: 5 + i * 3.0,
                decoration: BoxDecoration(
                  color: i < bars ? tokens.textHi : tokens.hairlineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
