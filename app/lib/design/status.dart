/// N3.20, N3.22–N3.23 — chrome: `TransportChip`, `InsightBanner`,
/// `CapabilityNotice`, `AlarmBar`.
///
/// **Status hue is chrome only, and always carries an icon *and* a word.**
/// Every banner here states its severity in words; the tint is decoration. The
/// banner's copy is always [SmokeTokens.textHi] so it stays readable on the
/// tint. Green appears only where it describes transport health.
library;

import 'package:flutter/material.dart';

import 'atoms.dart';
import 'haptics.dart';
import 'icons.dart';
import 'pulse.dart';
import 'text.dart';
import 'tokens.dart';

/// Where a link is in its lifecycle.
enum TransportPhase { offline, connecting, provisioning, rollback, connected }

/// Which link carries data.
enum TransportPrimary { none, bt, wifi }

/// The dual-link status chip.
class TransportChip extends StatelessWidget {
  const TransportChip({
    super.key,
    required this.label,
    required this.phase,
    this.primary = TransportPrimary.none,
    this.btConnected = false,
    this.wifiConnected = false,
    this.wifiAp = false,
    this.onTap,
  });

  final String label;
  final TransportPhase phase;
  final TransportPrimary primary;
  final bool btConnected;
  final bool wifiConnected;

  /// Whether Wi-Fi is in AP (hotspot) mode, which changes its glyph.
  final bool wifiAp;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final offline = phase == TransportPhase.offline;
    final busy =
        phase == TransportPhase.connecting ||
        phase == TransportPhase.provisioning ||
        phase == TransportPhase.rollback;
    final border = offline
        ? tokens.tint(tokens.critical, 0.35)
        : busy
        ? tokens.tint(tokens.warning, 0.35)
        : tokens.hairline;
    final background = offline
        ? tokens.tint(tokens.critical, 0.10)
        : busy
        ? tokens.tint(tokens.warning, 0.10)
        : tokens.cardSubtle;
    final live = phase == TransportPhase.connected;

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radii.pill),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radii.pill),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 5, 10, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PulseDot(
                state: live
                    ? PulseState.live
                    : busy
                    ? PulseState.warn
                    : PulseState.idle,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: SmokeText.label.copyWith(color: tokens.textHi),
              ),
              const SizedBox(width: 6),
              Container(width: 1, height: 14, color: tokens.hairlineStrong),
              const SizedBox(width: 6),
              _Radio(
                glyph: SmokeGlyph.bluetooth,
                connected: btConnected,
                primary: primary == TransportPrimary.bt,
              ),
              const SizedBox(width: 4),
              _Radio(
                glyph: wifiAp ? SmokeGlyph.wifi : SmokeGlyph.router,
                connected: wifiConnected,
                primary: primary == TransportPrimary.wifi,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({
    required this.glyph,
    required this.connected,
    required this.primary,
  });

  final SmokeGlyph glyph;
  final bool connected;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final color = primary
        ? tokens.positive
        : connected
        ? tokens.textHi
        : tokens.textMuted;
    return SmokeIcon(glyph, size: 13, color: color);
  }
}

/// How loud a banner is.
enum BannerSeverity { info, warn, critical }

/// A slim status strip: icon + word + message.
class InsightBanner extends StatelessWidget {
  const InsightBanner({
    super.key,
    required this.message,
    this.severity = BannerSeverity.info,
    this.icon,
    this.word,
  });

  final String message;
  final BannerSeverity severity;
  final SmokeGlyph? icon;

  /// Overrides the severity's default word.
  final String? word;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final hue = switch (severity) {
      BannerSeverity.info => tokens.info,
      BannerSeverity.warn => tokens.warning,
      BannerSeverity.critical => tokens.critical,
    };
    final defaultIcon = switch (severity) {
      BannerSeverity.info => SmokeGlyph.info,
      BannerSeverity.warn => SmokeGlyph.alertTriangle,
      BannerSeverity.critical => SmokeGlyph.alertCircle,
    };
    final defaultWord = switch (severity) {
      BannerSeverity.info => 'Note',
      BannerSeverity.warn => 'Warning',
      BannerSeverity.critical => 'Critical',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: tokens.statusFill(hue, alpha: 0.10),
        borderRadius: BorderRadius.circular(tokens.radii.control),
        border: Border.all(color: tokens.statusBorder(hue, alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SmokeIcon(icon ?? defaultIcon, size: 17, color: hue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  word ?? defaultWord,
                  style: SmokeText.labelSm.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: tokens.textHi,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  message,
                  style: SmokeText.label.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: tokens.textHi,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A capability notice (copy over error, I13).
class CapabilityNotice extends StatelessWidget {
  const CapabilityNotice({
    super.key,
    required this.message,
    this.icon = SmokeGlyph.info,
    this.severity = BannerSeverity.info,
  });

  final String message;
  final SmokeGlyph icon;
  final BannerSeverity severity;

  @override
  Widget build(BuildContext context) {
    return InsightBanner(
      message: message,
      severity: severity,
      icon: icon,
      word: 'Note',
    );
  }
}

/// The global alarm bar: highest-severity unacknowledged alarm, inline ack.
class AlarmBar extends StatelessWidget {
  const AlarmBar({
    super.key,
    required this.title,
    required this.severity,
    required this.tier,
    this.detail,
    this.onAcknowledge,
    this.onTap,
  });

  final String title;
  final BannerSeverity severity;
  final AlarmTier tier;
  final String? detail;

  /// Inline acknowledge. Fires the advisory haptic.
  final VoidCallback? onAcknowledge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final hue = switch (severity) {
      BannerSeverity.info => tokens.info,
      BannerSeverity.warn => tokens.warning,
      BannerSeverity.critical => tokens.critical,
    };
    final icon = switch (severity) {
      BannerSeverity.info => SmokeGlyph.info,
      BannerSeverity.warn => SmokeGlyph.alertTriangle,
      BannerSeverity.critical => SmokeGlyph.alertCircle,
    };

    return Material(
      color: tokens.statusFill(hue),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radii.control),
        side: BorderSide(color: tokens.statusBorder(hue, alpha: 0.35)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radii.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              SmokeIcon(icon, size: 22, color: hue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            style: SmokeText.label.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: tokens.textHi,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        TierTag(tier: tier),
                      ],
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: SmokeText.labelSm.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: tokens.textBody,
                        ),
                      ),
                  ],
                ),
              ),
              if (onAcknowledge != null)
                Material(
                  color: tokens.cardSubtle,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      SmokeHaptics.fire(SmokeHaptic.advisory);
                      onAcknowledge!();
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: tokens.hairlineStrong),
                      ),
                      child: SmokeIcon(
                        SmokeGlyph.check,
                        size: 17,
                        color: tokens.textHi,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
