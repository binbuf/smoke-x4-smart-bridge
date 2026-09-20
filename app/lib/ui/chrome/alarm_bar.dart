/// A19.6 — AlarmBar (design 14 §14.7, newapp §H.2).
///
/// The notice that carries the highest-severity unacked alarm — **including
/// device-scope alarms** (`probe == 0`), which the old dashboard filtered out
/// and rendered nowhere. It rides above every tab, and its `[Acknowledge]` is
/// inline: a 3 a.m. silence must never require a tab change (13 §13.3.3).
///
/// ## What changed in the §H.2 pass
///
/// **It is a slab, not a stripe.** It used to be a full-bleed band of status
/// fill with no border, butted against two other full-bleed bands, and three
/// edge-to-edge strips stacked is the single loudest "generic Material app"
/// tell the shell had. It is now an inset card on the 4 dp scale with the
/// 14 %/35 % chrome treatment §14.6.1 actually specifies — a fill *and* a
/// border, an icon *and* a word — which is both better looking and the rule.
///
/// **The buzz means something.** One `heavyImpact` for everything was a buzz
/// with no vocabulary: a target reached felt exactly like a pit crash. It now
/// fires [SmokeHaptics.forRole], so critical is a tap **and** a buzz, warning
/// is a single heavy tap, and an advisory is a light one — distinguishable
/// through a coat pocket, which is the only place this signal is ever read.
///
/// **It announces itself.** A newly-raised alarm calls
/// `SemanticsService.announce` assertively, once per alarm id (§14.10): a
/// screen-reader user must not have to find the bar to learn the fire is dying.
///
/// Both the buzz and the announcement are keyed to `alarm.id`, so a rebuild —
/// a tab change, a new reading, a rotation — is silent. The alarm demands
/// attention once.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../design/design.dart';
import '../../domain/alarms/notification_policy.dart' show alarmTitle;
import '../../domain/entities/entities.dart';
import 'chrome_slot.dart';

class AlarmBar extends StatefulWidget {
  const AlarmBar({
    super.key,
    required this.alarm,
    this.onAck,
    this.celsius = false,
    this.inset = false,
  });

  /// The highest-severity unacked alarm, or null when nothing is ringing.
  final Alarm? alarm;
  final VoidCallback? onAck;
  final bool celsius;

  /// Whether the slab supplies its own gutter (the shell, where it floats over
  /// `bg` beneath the bezel) or fills a content column that is already padded
  /// (the cook reader). Geometry only — the treatment is identical either way,
  /// and the default is the un-gutted one so a caller inside a padded column
  /// never ends up double-indented.
  final bool inset;

  @override
  State<AlarmBar> createState() => _AlarmBarState();
}

class _AlarmBarState extends State<AlarmBar> {
  int? _raisedFor;

  @override
  void didUpdateWidget(AlarmBar old) {
    super.didUpdateWidget(old);
    _onRaised();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // An alarm present on the very first build never passes through
    // didUpdateWidget, and used to arrive in total silence.
    _onRaised();
  }

  void _onRaised() {
    final alarm = widget.alarm;
    if (alarm == null) {
      _raisedFor = null;
      return;
    }
    if (alarm.id == _raisedFor) {
      return;
    }
    _raisedFor = alarm.id;
    final role = StatusPalette.roleOf(alarm.severity);
    SmokeHaptics.fireForRole(role);
    // Assertive, not polite: a polite announcement queues behind whatever the
    // reader is already saying, and "the fire is dying" does not queue. The
    // view-scoped form rather than the deprecated implicit-view one, so this
    // still lands on a foldable running two windows.
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        _semantics(alarm),
        Directionality.maybeOf(context) ?? TextDirection.ltr,
        assertiveness: Assertiveness.assertive,
      ),
    );
  }

  /// "The fire is dying. Probe 3." — cause first, location second, and never
  /// the rule id: `pit_out_of_band` must never reach a user (§14.7.1).
  static String _semantics(Alarm alarm) {
    final title = alarmTitle(alarm.rule);
    return alarm.probe == 0 ? title : '$title. Probe ${alarm.probe}.';
  }

  @override
  Widget build(BuildContext context) {
    final alarm = widget.alarm;
    return ChromeSlot(
      // 8 dp from the frame. Two simultaneous notices therefore sit 16 dp
      // apart — further from each other than from the bezel — so a stack of
      // two never reads as one two-line banner.
      padding: widget.inset
          ? const EdgeInsets.symmetric(
              horizontal: SmokeTokens.s3,
              vertical: SmokeTokens.s2,
            )
          : EdgeInsets.zero,
      child: alarm == null ? null : _slab(context, alarm),
    );
  }

  Widget _slab(BuildContext context, Alarm alarm) {
    final t = context.tokens;
    final role = StatusPalette.roleOf(alarm.severity);
    final hue = StatusPalette.hue(role);
    final where = alarm.probe == 0 ? null : 'Probe ${alarm.probe}';
    // At large text the button cannot share a row with two lines of prose
    // without one of them being clipped, so it moves under them instead.
    final stacked = SmokeTextScale.isLarge(context);
    final ack = widget.onAck == null
        ? null
        : _AckButton(hue: hue, onPressed: widget.onAck!, wide: stacked);

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          alarmTitle(alarm.rule),
          // The words are carried at 13:1 and never in the status hue — the
          // hue is the icon's job and the border's (§14.6.5).
          style: SmokeType.title.copyWith(color: t.textHi),
        ),
        if (where != null)
          Text(where, style: SmokeType.bodySm.copyWith(color: t.textBody)),
      ],
    );

    return Semantics(
      liveRegion: true,
      container: true,
      label: _semantics(alarm),
      child: DecoratedBox(
        // Keyed to match `refresh-banner`: the two notices are siblings, the
        // goldens are text, and a slab appearing or changing rank has to be a
        // line in a diff.
        key: const Key('alarm-bar'),
        decoration: BoxDecoration(
          color: StatusPalette.fill(role),
          borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
          border: Border.all(color: StatusPalette.border(role)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(SmokeTokens.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    StatusPalette.iconOf(alarm.severity),
                    color: hue,
                    size: 22,
                  ),
                  const SizedBox(width: SmokeTokens.s3),
                  Expanded(child: words),
                  if (!stacked && ack != null) ...[
                    const SizedBox(width: SmokeTokens.s2),
                    ack,
                  ],
                ],
              ),
              if (stacked && ack != null) ...[
                const SizedBox(height: SmokeTokens.s3),
                ack,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Deliberately not a bare `TextButton`: a 3 a.m. tap with a cold or greasy
/// finger gets a 48 dp target and a visible surface, not a word floating on a
/// coloured field (§14.10's touch-target row names this control by name).
class _AckButton extends StatelessWidget {
  const _AckButton({
    required this.hue,
    required this.onPressed,
    required this.wide,
  });

  final Color hue;
  final VoidCallback onPressed;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: t.textHi,
        backgroundColor: hue.withValues(alpha: 0.22),
        textStyle: SmokeType.bodySm.copyWith(fontWeight: FontWeight.w700),
        minimumSize: Size(wide ? double.infinity : 64, 44),
        padding: const EdgeInsets.symmetric(horizontal: SmokeTokens.s4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
          side: BorderSide(color: hue.withValues(alpha: 0.35)),
        ),
      ),
      // A verb that names the outcome (§16.4 rule 7). "OK" would not say what
      // stops.
      child: const Text('Acknowledge'),
    );
  }
}
