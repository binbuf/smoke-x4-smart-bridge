/// The settings layout system (16 §16.5) and the two rules that make a
/// settings row honest (16 §16.4, §16.6).
///
/// **Why this file exists.** The settings tree was the last part of the app
/// built out of raw `ListTile`s on a bare `ListView`: one flat, undifferentiated
/// list per page, every row weighted the same, nothing grouped by subject, and
/// a disabled control indistinguishable from an enabled one that happened to do
/// nothing. Restyling it through the theme changed the colours and left the
/// information design exactly where it was. This is the information design.
///
/// Four elements, and nothing else on a settings page:
///
///  * [SettingsPage] — the scroll frame, one lead sentence, sections beneath;
///  * [SettingsSectionLabel] — `label`, upper case, `textMuted`, s5/s2;
///  * [SettingsGroup] — a [SmokeCard] holding rows that **share a subject**.
///    Never one card per row, and never a card of unrelated rows;
///  * [SettingsRow] and its variants — 52 dp minimum, label left, value right,
///    a subtitle that *explains* rather than repeating the label.
///
/// And the two rules the row type enforces structurally, because prose in a
/// design document has never once stopped anybody:
///
///  1. **Absent is `—`.** [SettingsRow.value] is a `String?` and null renders
///     the em dash. There is no way to spell "unknown" as `0`, as `false`, or
///     as a constructor default, because the only way to render a value is to
///     have one.
///  2. **A row the active lane cannot write is rendered, dimmed, with its
///     reason directly beneath it** ([SettingsRow.reason]). Not hidden — a user
///     hunting for a control needs to find it and be told why it is not
///     available. Not enabled-and-inert — that is the lie this whole epic was
///     opened to kill.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../ui/ui.dart';

/// The scroll frame every settings section renders into.
///
/// [lead] is the one sentence that says what the page is *for*. It is optional
/// and it is never a restatement of the title: "Probes" does not need "these
/// are your probes", it needs "roles decide what the app shows big".
class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.children, this.lead = '', super.key});

  final List<Widget> children;
  final String lead;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SmokeTokens.s4,
        SmokeTokens.s3,
        SmokeTokens.s4,
        SmokeTokens.s7,
      ),
      children: [
        if (lead.isNotEmpty) ...[
          Text(lead, style: SmokeType.body.copyWith(color: t.textBody)),
          const SizedBox(height: SmokeTokens.s2),
        ],
        ...children,
      ],
    );
  }
}

/// A section heading: `label`, upper case, `textMuted`, s5 above / s2 below.
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SmokeTokens.s2,
      SmokeTokens.s5,
      SmokeTokens.s2,
      SmokeTokens.s2,
    ),
    child: Text(
      label.toUpperCase(),
      style: SmokeType.label.copyWith(color: context.tokens.textMuted),
    ),
  );
}

/// A card of rows that share a subject, hairline-divided.
///
/// The subject test is the whole point: "Temperature" is a subject; "Settings"
/// is not. If the rows in a group do not answer the same question, they belong
/// in two groups with two labels.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    required this.children,
    this.footer,
    this.reason = '',
    super.key,
  });

  final List<Widget> children;

  /// Prose beneath the rows, inside the card — for the paragraph that explains
  /// a policy the rows can only state ("nothing expires on its own").
  final Widget? footer;

  /// Non-empty: every row in the card is dimmed and inert, and the sentence is
  /// printed **once**, at the foot of the card.
  ///
  /// The per-row [SettingsRow.reason] is right when one row in a group cannot
  /// be written. This is right when the whole subject cannot — a probe card on
  /// a Bluetooth link, the broker form with no Wi-Fi. Repeating one identical
  /// sentence under nine rows is not honesty, it is noise, and noise is what
  /// people stop reading.
  final String reason;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rows = <Widget>[
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) Divider(height: 1, color: t.hairline),
        children[i],
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
      child: SmokeCard(
        padding: const EdgeInsets.symmetric(vertical: SmokeTokens.s1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (reason.isEmpty)
              ...rows
            else
              Opacity(
                opacity: 0.45,
                child: IgnorePointer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  ),
                ),
              ),
            if (reason.isNotEmpty) ...[
              Divider(height: 1, color: t.hairline),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SmokeTokens.s4,
                  SmokeTokens.s3,
                  SmokeTokens.s4,
                  SmokeTokens.s3,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 15,
                      color: t.textMuted,
                    ),
                    const SizedBox(width: SmokeTokens.s2),
                    Expanded(
                      child: Text(
                        reason,
                        style: SmokeType.bodySm.copyWith(color: t.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (footer != null) ...[
              Divider(height: 1, color: t.hairline),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SmokeTokens.s4,
                  SmokeTokens.s3,
                  SmokeTokens.s4,
                  SmokeTokens.s3,
                ),
                child: DefaultTextStyle(
                  style: SmokeType.bodySm.copyWith(color: t.textMuted),
                  child: footer!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One settings row. 52 dp minimum; label left, value right.
///
/// [value] is nullable **on purpose**: null is the only way to say "the bridge
/// has not told us", and it renders as `—`. A caller that wants to render a
/// zero has to mean it.
///
/// [reason] non-empty dims the row, removes its interaction, and prints the
/// sentence directly beneath — 16 §16.5's disabled row, which is the shape
/// every "this lane can't write that" case in §F takes.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.label,
    this.value,
    this.subtitle = '',
    this.trailing,
    this.control,
    this.reason = '',
    this.onTap,
    this.danger = false,
    super.key,
  });

  final String label;

  /// The device's own answer. Null renders `—`; never a default, never 0.
  final String? value;

  /// Explains — never repeats the label.
  final String subtitle;

  /// Rendered on the right instead of [value].
  final Widget? trailing;

  /// Rendered full width beneath the label — a segmented control, a field.
  final Widget? control;

  /// Non-empty: dimmed, inert, and this sentence renders beneath the row.
  final String reason;

  final VoidCallback? onTap;

  /// Destructive framing: the label takes the critical hue. The row still
  /// carries an icon-free layout, so the colour is never the only signal —
  /// the copy says what is lost.
  final bool danger;

  bool get _disabled => reason.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // A destructive row's *title* stays ink. §16.5: the
                    // status hue is chrome, never a word — and this is the
                    // shared row every settings page builds on, so tinting
                    // the label here propagated the break across the tree.
                    // The weight is carried by the icon, the button and the
                    // cost sheet that runs before anything happens.
                    Text(
                      label,
                      style: SmokeType.title.copyWith(color: t.textHi),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: SmokeTokens.s1),
                      Text(
                        subtitle,
                        style: SmokeType.bodySm.copyWith(color: t.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              // Both branches are [Flexible]: at 360 dp with 200% text scale a
              // long value ("smokebridge-8274.local") or a two-word verb would
              // otherwise overflow the row rather than wrap inside it.
              if (trailing != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: SmokeTokens.s3),
                    child: trailing,
                  ),
                )
              else ...[
                const SizedBox(width: SmokeTokens.s3),
                Flexible(
                  child: Text(
                    value ?? noValue,
                    textAlign: TextAlign.right,
                    style: SmokeType.body.copyWith(color: t.textHi),
                  ),
                ),
              ],
              if (onTap != null && !_disabled)
                Padding(
                  padding: const EdgeInsets.only(left: SmokeTokens.s1),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: t.textMuted,
                  ),
                ),
            ],
          ),
        ),
        if (control != null)
          Padding(
            padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
            child: control,
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SmokeTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_disabled)
            // Dimmed, not hidden. The reason below stays at full contrast —
            // it is the only part of a disabled row anyone needs to read.
            Opacity(opacity: 0.45, child: IgnorePointer(child: body))
          else if (onTap != null)
            InkWell(onTap: onTap, child: body)
          else
            body,
          if (_disabled)
            Padding(
              padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 15,
                    color: t.textMuted,
                  ),
                  const SizedBox(width: SmokeTokens.s2),
                  Expanded(
                    child: Text(
                      reason,
                      style: SmokeType.bodySm.copyWith(color: t.textMuted),
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

/// A switch row. [value] null means the bridge has not reported it — the switch
/// is then off *and* inert, and the subtitle says which.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    required this.label,
    required this.value,
    this.onChanged,
    this.subtitle = '',
    this.reason = '',
    this.unknownNote = 'The bridge hasn’t reported this yet.',
    super.key,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final String subtitle;
  final String reason;

  /// Shown as the reason when [value] is null and no [reason] was given.
  final String unknownNote;

  @override
  Widget build(BuildContext context) {
    final unknown = value == null;
    final why = reason.isNotEmpty ? reason : (unknown ? unknownNote : '');
    return SettingsRow(
      label: label,
      subtitle: subtitle,
      reason: why,
      trailing: Switch(
        value: value ?? false,
        onChanged: why.isEmpty ? onChanged : null,
      ),
    );
  }
}

/// A row whose value is one of a short, named set — the shape battery saver,
/// units and the theme all wanted and none of them had.
///
/// Nothing is selected until [value] is non-null, so a segmented control can
/// never pre-select a guess and pass it off as the device's answer.
class SettingsChoiceRow<T> extends StatelessWidget {
  const SettingsChoiceRow({
    required this.label,
    required this.options,
    required this.value,
    this.onChanged,
    this.subtitle = '',
    this.reason = '',
    this.valueLabel,
    this.reportsValue = false,
    super.key,
  });

  final String label;
  final List<ChipOption<T>> options;

  /// Null selects nothing.
  final T? value;
  final ValueChanged<T>? onChanged;
  final String subtitle;
  final String reason;

  /// What the device actually reports, rendered on the right.
  ///
  /// The chips are shortcuts, not the whole domain: a bridge clamped to 45
  /// seconds, or one running a retention limit somebody set over USB, has a
  /// real value that matches no chip. Without this the row would show nothing
  /// selected and read as broken; with it the row states the fact and offers
  /// the shortcuts underneath.
  final String? valueLabel;

  /// Whether this row's value is a **device fact**, so its absence must be
  /// rendered as `—` rather than left blank.
  ///
  /// Off for the rows whose value is always known and always visible in the
  /// selection itself — the units, the app's theme. On for anything read from
  /// the bridge, where "nothing selected" and "the bridge has not said" look
  /// identical and only the em dash tells them apart.
  final bool reportsValue;

  @override
  Widget build(BuildContext context) {
    final inert = reason.isNotEmpty || onChanged == null;
    final chips = SegmentedChips<T?>(
      options: [for (final o in options) ChipOption<T?>(o.value, o.label)],
      value: value,
      onChanged: (v) {
        if (!inert && v != null) {
          onChanged!(v);
        }
      },
    );
    return SettingsRow(
      label: label,
      subtitle: subtitle,
      reason: reason,
      value: valueLabel,
      trailing: reportsValue ? null : const SizedBox.shrink(),
      control: inert ? IgnorePointer(child: chips) : chips,
    );
  }
}

/// A row whose value is typed in. The label stays a label — it does not become
/// a floating hint that disappears the moment somebody starts typing, which is
/// how a half-filled form stops saying what its fields are.
class SettingsFieldRow extends StatelessWidget {
  const SettingsFieldRow({
    required this.label,
    required this.fieldKey,
    this.subtitle = '',
    this.initialValue,
    this.controller,
    this.onChanged,
    this.hintText = '',
    this.errorText = '',
    this.keyboardType,
    this.obscure = false,
    this.reason = '',
    super.key,
  });

  final String label;
  final String subtitle;

  /// The field's own key, so a test can type into it by name.
  final Key fieldKey;

  final String? initialValue;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final String errorText;
  final TextInputType? keyboardType;
  final bool obscure;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SettingsRow(
      label: label,
      subtitle: subtitle,
      reason: reason,
      trailing: const SizedBox.shrink(),
      control: TextFormField(
        key: fieldKey,
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        enabled: reason.isEmpty,
        obscureText: obscure,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: SmokeType.body.copyWith(color: t.textHi),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText.isEmpty ? null : hintText,
          hintStyle: SmokeType.body.copyWith(color: t.chromeDim),
          errorText: errorText.isEmpty ? null : errorText,
          filled: true,
          fillColor: t.cardSubtle,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
            borderSide: BorderSide(color: t.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
            borderSide: BorderSide(color: t.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
            borderSide: BorderSide(color: t.hairlineStrong),
          ),
        ),
      ),
    );
  }
}

/// A row that *is* an action: one verb that names its outcome.
class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    required this.label,
    required this.buttonLabel,
    required this.onPressed,
    this.subtitle = '',
    this.reason = '',
    this.danger = false,
    super.key,
  });

  final String label;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final String reason;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SettingsRow(
      label: label,
      subtitle: subtitle,
      reason: reason,
      danger: danger,
      trailing: OutlinedButton(
        onPressed: reason.isEmpty ? onPressed : null,
        style: OutlinedButton.styleFrom(
          // The word stays ink; the hue rides the border, which is the
          // chrome §16.5 allows it on.
          foregroundColor: t.textHi,
          side: BorderSide(
            color: danger ? StatusPalette.border(StatusRole.critical) : t.hairlineStrong,
          ),
          minimumSize: const Size(64, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SmokeTokens.radiusControl),
          ),
        ),
        child: Text(buttonLabel, style: SmokeType.bodySm),
      ),
    );
  }
}

/// A paragraph between cards — a policy that no single row can carry.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SmokeTokens.s2,
      0,
      SmokeTokens.s2,
      SmokeTokens.s3,
    ),
    child: Text(
      text,
      style: SmokeType.bodySm.copyWith(color: context.tokens.textMuted),
    ),
  );
}

// ── §F's transport column, as data ──────────────────────────────────────

/// Which lane is carrying settings right now.
///
/// §F's table has a column per lane and a "what the UI does when the active
/// transport can't" column; this enum plus the getters below **are** that
/// table, so the reason a row is disabled is one testable value rather than a
/// string typed out at nine call sites.
enum SettingsLane {
  /// No shared link. Every device row is disabled — not silently inert.
  none,

  /// `BleTransport`. Live readings and the safe verbs; no probe config, no
  /// broker, no firmware image.
  bluetooth,

  /// `HttpTransport`, hosted or joined. Everything.
  wifi,
}

/// The reason each §F subject cannot be written on this lane, or `''`.
///
/// Every sentence names the lane and the outcome — "connect over Wi-Fi to
/// rename probes", not "unsupported operation".
extension SettingsLaneReasons on SettingsLane {
  static const String _offline =
      'The app isn’t connected to your bridge right now, so nothing here can '
      'be saved. It keeps trying on its own.';

  /// Probe names, roles and targets. §F: not over Bluetooth today.
  String get probes => switch (this) {
    SettingsLane.none => _offline,
    SettingsLane.bluetooth =>
      'Connect over Wi-Fi to rename probes, change their roles or set targets. '
          'Bluetooth carries the readings, not these.',
    SettingsLane.wifi => '',
  };

  /// The broker lives on the LAN; Bluetooth cannot reach it at all.
  String get mqtt => switch (this) {
    SettingsLane.none => _offline,
    SettingsLane.bluetooth =>
      'Home Assistant needs Wi-Fi. Your broker is on your network, and a '
          'Bluetooth link to the bridge cannot reach it.',
    SettingsLane.wifi => '',
  };

  /// A firmware image is far too large for the GATT path.
  String get firmware => switch (this) {
    SettingsLane.none => _offline,
    SettingsLane.bluetooth =>
      'Updating needs Wi-Fi. A firmware image is far too big to send over '
          'Bluetooth.',
    SettingsLane.wifi => '',
  };

  /// Units and the battery saver — both lanes carry these.
  String get deviceConfig => this == SettingsLane.none ? _offline : '';

  /// The bridge's **own hardware**: its screen timeout, its status light, and
  /// how many cooks it keeps.
  ///
  /// §F marks these ✅ on every lane, and §F is wrong about Bluetooth today:
  /// `BleTransport.configure` carries the units and the battery saver and
  /// **silently drops the other three** — no throw, no result frame, nothing.
  /// A row that looked live on that lane would be the exact defect this whole
  /// column exists to prevent, so it is disabled with the sentence below.
  /// Bluetooth also answers `DeviceConfig.unknown`, so the same sentence
  /// explains the `—` beside it.
  String get deviceHardware => switch (this) {
    SettingsLane.none => _offline,
    SettingsLane.bluetooth =>
      'Connect over Wi-Fi to change the bridge’s screen, its light, or how '
          'many cooks it keeps. Bluetooth carries the readings, the units and '
          'the battery saver — not these.',
    SettingsLane.wifi => '',
  };

  /// Restart, power off, factory reset, pair, unpair. Both lanes.
  String get control => this == SettingsLane.none ? _offline : '';

  /// The mode switch itself. §E.3: Bluetooth is the lane that carries it
  /// *safely*, so it is never the blocked one.
  String get network => this == SettingsLane.none ? _offline : '';

  /// How the lane names itself in a readout.
  String get title => switch (this) {
    SettingsLane.none => 'Not connected',
    SettingsLane.bluetooth => 'Bluetooth',
    SettingsLane.wifi => 'Wi-Fi',
  };
}

// ── verify-by-read-back, as a result ────────────────────────────────────

/// What actually happened to a settings write (16 §16.4 rule 10, §16.6).
///
/// A `Future<void>` that completes is not a saved setting. Every write in this
/// tree resolves to one of these, and the copy differs for every one — most of
/// all for [unverified], which is the case the old code reported as success:
/// the device took the request and has no way to tell us it kept it.
enum WriteOutcome {
  /// Written, read back, and the read-back matched.
  verified,

  /// Written and accepted, but **this connection cannot read the setting
  /// back**, so the app cannot confirm it. Said out loud, never dressed up.
  ///
  /// Bluetooth is the case: it carries the units and the battery saver and
  /// answers `DeviceConfig.unknown` to the read. The same change over Wi-Fi is
  /// compared field by field and comes back [verified]. This is deliberately
  /// *not* a catch-all for "we did not look" — every write in this tree looks.
  unverified,

  /// Written, read back, and the device is running something else — it
  /// clamped, refused a name, or ignored a field.
  changedByDevice,

  /// The transport said it cannot carry this at all.
  refused,

  /// No shared link.
  noLink,

  /// The write threw. Nothing was saved.
  failed,
}

/// One sentence per outcome. [what] names the setting in the user's words.
///
/// [WriteOutcome.refused] deliberately does **not** interpolate [what]. The
/// names are noun phrases written to sit inside "It doesn't report … back" —
/// "probe names and targets" — and a sentence built as "$what needs a Wi-Fi
/// connection" turned that into "probe names and targets needs a Wi-Fi
/// connection", printed to a real user on a real save. The refusal always
/// arrives on the screen that caused it, so "That" is never ambiguous.
String writeOutcomeMessage(WriteOutcome outcome, String what) =>
    switch (outcome) {
      WriteOutcome.verified => 'Saved to the bridge.',
      WriteOutcome.unverified =>
        'Sent to the bridge. It doesn’t report $what back, so the app can’t '
            'confirm it stuck.',
      WriteOutcome.changedByDevice =>
        'The bridge kept its own values for some of that. What you see now is '
            'what it actually has.',
      WriteOutcome.refused => 'That needs a Wi-Fi connection to the bridge.',
      WriteOutcome.noLink => 'Not connected to the bridge — nothing was saved.',
      WriteOutcome.failed => 'The bridge didn’t take that. Nothing was saved.',
    };
