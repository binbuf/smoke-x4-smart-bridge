/// §F Probes and §F Alarms — the two pages that decide what the app shows big
/// and what it wakes you for.
///
/// **A probe is a subject, so a probe gets a card** (16 §16.5). Four cards,
/// each holding the three things that are true of one jack: what it is called,
/// what it is *for*, and what temperature it is aiming at. The old page was a
/// flat column of twelve fields with a hairline between probes, which made
/// "probe 2's target" and "probe 3's name" look like peers of each other.
///
/// The role field is the one that earns its explanation. Roles are not
/// decoration: they decide which tile is large on `/live`, which rules the
/// bridge applies, and whether an ETA is even computed. A user who leaves
/// everything on "Not used" gets a working app that quietly does none of that,
/// so the page says what a role buys before it asks for one.
///
/// The alarms page carries the one claim a settings screen can most easily get
/// wrong. §9.1: **the device tier is authoritative and runs with no phone in
/// existence; the app tier is advisory.** Listing them as one list of switches
/// implies the phone can be switched off, and it cannot. They are two cards
/// with two different promises, said out loud on screen and not only here.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart';
import '../../ui/ui.dart';
import 'settings_kit.dart';
import 'settings_screen.dart' show probeRoleLabel;

/// The lowest and highest target a form will accept, in tenths °F. The probes
/// are K-type thermocouples on a 32–572 °F base station; a target outside that
/// is a typo, and it is refused in the form rather than on the wire.
const int probeTargetMinF10 = 320;
const int probeTargetMaxF10 = 5720;

class ProbeSettingsView extends StatefulWidget {
  const ProbeSettingsView({
    required this.probes,
    required this.probesKnown,
    required this.onSave,
    this.unsupportedReason = '',
    this.celsius = false,
    this.onOpenAlarmRules,
    super.key,
  });

  final List<Probe> probes;

  /// **False until `live()` has actually answered**, and the reason this form
  /// is gated rather than merely seeded.
  ///
  /// The route hands this view `const []` on its first build and the bridge's
  /// four probes a round trip later. A form seeded from that first build shows
  /// four empty names, no roles and no targets — and "Save to the bridge" then
  /// writes those blanks over a configuration somebody spent a cook getting
  /// right, reads the blanks back, finds they match, and reports "Saved to the
  /// bridge." Every part of that is working as designed except the premise.
  ///
  /// So: nothing is editable until a read lands (16 §16.6 — never a
  /// constructor default as a device fact), and [didUpdateWidget] adopts a
  /// later read for every jack the user has not typed in.
  final bool probesKnown;

  /// Writes through the shared transport and **verifies by read-back**.
  /// Throwing is expected — a lane that cannot configure probes says so with
  /// A6's typed condition, and the form keeps the user's edits.
  final Future<void> Function(List<Probe>) onSave;

  /// Non-empty when the active lane cannot write probe configuration
  /// (Bluetooth, today) or when there is no link at all.
  final String unsupportedReason;
  final bool celsius;

  /// Alarm bands are rules, and rules live in the rule editor. This page links
  /// there rather than growing a second, competing editor for the same field.
  final VoidCallback? onOpenAlarmRules;

  @override
  State<ProbeSettingsView> createState() => _ProbeSettingsViewState();
}

class _ProbeSettingsViewState extends State<ProbeSettingsView> {
  /// Four jacks, always — the hardware has four whether the bridge has
  /// described them or not.
  static List<Probe> _fourJacks(List<Probe> from) => [
    for (var n = 1; n <= 4; n++)
      from.where((p) => p.n == n).firstOrNull ?? Probe(n: n),
  ];

  late List<Probe> _draft = _fourJacks(widget.probes);

  /// The jacks somebody has actually typed in. A jack in here is **never**
  /// re-seeded by a later read: the bridge answering a second time must not
  /// take back what a user is halfway through writing.
  final _edited = <int>{};

  /// One controller per field, because a re-seed has to reach the *text* and
  /// not only the draft. `TextFormField.initialValue` is read once, when the
  /// field is first built, and silently ignored on every rebuild after that —
  /// so the draft and the boxes would have drifted apart.
  final _names = <int, TextEditingController>{};
  final _targets = <int, TextEditingController>{};

  final _errors = <int, String>{};
  String _saveError = '';
  bool _saving = false;

  bool get _disabled => widget.unsupportedReason.isNotEmpty;

  /// Why the form is not there yet. Says the consequence as well as the cause:
  /// "not read" is a state, "not read, and saving would overwrite" is a reason.
  static const String _unreadReason =
      'The bridge hasn’t sent its probe settings yet. Saving now would write '
      'four blank names over whatever it is actually running, so there is '
      'nothing to edit until it answers.';

  @override
  void initState() {
    super.initState();
    for (final p in _draft) {
      _names[p.n] = TextEditingController(text: p.name);
      _targets[p.n] = TextEditingController(text: _targetText(p));
    }
  }

  @override
  void dispose() {
    for (final c in [..._names.values, ..._targets.values]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Adopts a later read for every jack nobody has edited.
  ///
  /// Without this the form would keep the four blank probes it was born with
  /// for the whole life of the screen, and the read that finally arrived would
  /// change nothing but the rows above it.
  @override
  void didUpdateWidget(covariant ProbeSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.probesKnown) {
      return;
    }
    final reported = _fourJacks(widget.probes);
    _draft = [
      for (final p in _draft)
        if (_edited.contains(p.n))
          p
        else
          reported.firstWhere((x) => x.n == p.n),
    ];
    for (final p in _draft) {
      if (_edited.contains(p.n)) {
        continue;
      }
      _seed(_names[p.n]!, p.name);
      _seed(_targets[p.n]!, _targetText(p));
    }
  }

  /// Assigns only when the text actually differs. The setter rebuilds the whole
  /// [TextEditingValue] and collapses the selection, so an unconditional write
  /// on every parent rebuild would jump the caret in a box somebody had just
  /// tapped into.
  static void _seed(TextEditingController c, String value) {
    if (c.text != value) {
      c.text = value;
    }
  }

  static String _targetText(Probe p) =>
      p.targetF10 == null ? '' : (p.targetF10! / 10).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SettingsPage(
      key: const Key('settings-probes'),
      lead:
          'A probe’s role decides what the app shows large, which of the '
          'bridge’s alarms apply to it, and whether it gets a finish estimate. '
          'One probe should be the pit.',
      children: [
        if (_disabled)
          Padding(
            padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
            child: CapabilityNotice(
              key: const Key('probes-unsupported'),
              message: widget.unsupportedReason,
            ),
          ),
        if (!widget.probesKnown) ...[
          const SettingsSectionLabel('The four jacks'),
          SettingsGroup(
            key: const Key('probes-unread'),
            reason: _unreadReason,
            children: [
              for (var n = 1; n <= 4; n++)
                SettingsRow(key: Key('probe-unread-$n'), label: 'Probe $n'),
            ],
          ),
        ],
        if (widget.probesKnown)
          for (final p in _draft) ...[
            SettingsSectionLabel(_cardTitle(p)),
            SettingsGroup(
              key: Key('probe-editor-${p.n}'),
              reason: widget.unsupportedReason,
              children: [
                SettingsFieldRow(
                  label: 'Name',
                  subtitle: 'What this jack is called everywhere in the app',
                  fieldKey: Key('probe-name-${p.n}'),
                  controller: _names[p.n],
                  hintText: 'Probe ${p.n}',
                  onChanged: (v) => _update(p.n, (x) => x.copyWith(name: v)),
                ),
                SettingsChoiceRow<ProbeRole>(
                  key: Key('probe-role-row-${p.n}'),
                  label: 'Used for',
                  subtitle: _roleBlurb(p.role),
                  options: [
                    for (final r in ProbeRole.values)
                      ChipOption(r, probeRoleLabel(r)),
                  ],
                  value: p.role,
                  onChanged: (r) => _update(p.n, (x) => x.copyWith(role: r)),
                ),
                SettingsFieldRow(
                  label: 'Target',
                  subtitle: p.role == ProbeRole.food
                      ? 'The bridge sounds its alarm here, and the app '
                            'estimates when it will arrive'
                      : 'Leave this empty unless you want an alarm at a set '
                            'temperature',
                  fieldKey: Key('probe-target-${p.n}'),
                  controller: _targets[p.n],
                  hintText: widget.celsius ? '°C' : '°F',
                  errorText: _errors[p.n] ?? '',
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _setTarget(p.n, v),
                ),
                SettingsRow(
                  key: Key('probe-doneness-${p.n}'),
                  label: 'Doneness',
                  subtitle:
                      'A named finish — 203°F for pulled pork, 135°F for '
                      'medium rare',
                  reason:
                      'The bridge stores a target in degrees and nothing else, '
                      'so a doneness would only be a label this phone kept to '
                      'itself. Set the temperature above.',
                ),
                SettingsRow(
                  key: Key('probe-band-${p.n}'),
                  label: 'Alarm band',
                  subtitle: p.alarmMinF10 == null && p.alarmMaxF10 == null
                      ? 'No band set — the bridge is not watching a range on '
                            'this probe'
                      : 'The bridge alarms outside this range',
                  value: p.alarmMinF10 == null && p.alarmMaxF10 == null
                      ? null
                      : '${formatSetpoint(p.alarmMinF10, celsius: widget.celsius)}'
                            ' – '
                            '${formatSetpoint(p.alarmMaxF10, celsius: widget.celsius)}',
                  onTap: widget.onOpenAlarmRules,
                ),
              ],
            ),
          ],
        const SettingsSectionLabel('Not set from here'),
        const SettingsGroup(
          children: [
            SettingsRow(
              key: Key('probe-pull-offset'),
              label: 'Pull early by',
              subtitle:
                  'How far below target to call it, so carry-over finishes '
                  'the job',
              reason:
                  'The bridge doesn’t store a pull offset. Set the target a '
                  'few degrees low instead, and the app’s finish estimate '
                  'follows it.',
            ),
            SettingsRow(
              key: Key('probe-calibration'),
              label: 'Calibration offset',
              subtitle: 'Correct a probe that reads consistently high or low',
              reason:
                  'Calibration lives on the Smoke X base station, not on the '
                  'bridge, so the app has nothing to write it to.',
            ),
          ],
        ),
        if (_saveError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: SmokeTokens.s3),
            // The hue rides the icon and the border; the sentence stays
            // readable ink (§14.6.5). Red words on this surface measure
            // 3.19:1 — an error nobody can read is not an error message.
            child: CapabilityNotice(
              key: const Key('probes-save-error'),
              message: _saveError,
              icon: Icons.error_outline_rounded,
              role: StatusRole.critical,
            ),
          ),
        PrimaryAction(
          key: const Key('probes-save'),
          label: 'Save to the bridge',
          busy: _saving,
          onPressed: _disabled || !widget.probesKnown || _errors.isNotEmpty
              ? null
              : _save,
        ),
        const SizedBox(height: SmokeTokens.s2),
        Text(
          'Nothing is saved until you tap that. The app then reads the bridge '
          'back and shows you what it actually kept.',
          style: SmokeType.bodySm.copyWith(color: t.textMuted),
        ),
      ],
    );
  }

  String _cardTitle(Probe p) {
    final name = p.name.trim();
    return name.isEmpty ? 'Probe ${p.n}' : 'Probe ${p.n} · $name';
  }

  static String _roleBlurb(ProbeRole role) => switch (role) {
    ProbeRole.unused =>
      'Recorded, but never shown large and never given an alarm',
    ProbeRole.pit => 'The cooker itself. Shown large, and watched for a crash.',
    ProbeRole.food =>
      'What you are cooking. Gets the target, the alarm and the estimate.',
    ProbeRole.ambient => 'The air around the cooker. Recorded for context.',
  };

  void _update(int n, Probe Function(Probe) f) => setState(() {
    // Touching a jack takes it out of the re-seed: from here on the user's
    // draft wins over anything the bridge says next.
    _edited.add(n);
    _draft = [for (final p in _draft) p.n == n ? f(p) : p];
  });

  void _setTarget(int n, String raw) {
    if (raw.trim().isEmpty) {
      setState(() => _errors.remove(n));
      _update(n, (x) => x.copyWith(targetF10: null));
      return;
    }
    final parsed = double.tryParse(raw.trim());
    final f10 = parsed == null ? null : (parsed * 10).round();
    if (f10 == null || f10 < probeTargetMinF10 || f10 > probeTargetMaxF10) {
      // Refused in the form, not on the wire: the device would take it, and
      // then every rule downstream would be nonsense.
      setState(() {
        _edited.add(n);
        _errors[n] =
            'Between ${formatTempPrecise(probeTargetMinF10)} and '
            '${formatTempPrecise(probeTargetMaxF10)}';
      });
      return;
    }
    setState(() => _errors.remove(n));
    _update(n, (x) => x.copyWith(targetF10: f10));
  }

  Future<void> _save() async {
    setState(() {
      _saveError = '';
      _saving = true;
    });
    try {
      await widget.onSave(_draft);
    } on Object catch (e) {
      // The form keeps its edits. Clearing it on failure is how a user loses
      // ten minutes of typing to one dropped packet.
      setState(() => _saveError = '$e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

/// §F Alarms — delivery, in two tiers that are visibly, deliberately different.
///
/// The *rules* live at `/device/alarms`; this page is about **whether a rule
/// that fires ever reaches you**, which is a different question with different
/// answers and a different failure mode. Conflating them is how an app ends up
/// with a beautifully edited rule set and a phone that stays silent at 3 a.m.
class AlarmSettingsView extends StatelessWidget {
  const AlarmSettingsView({
    required this.deviceRules,
    required this.alarms,
    this.onAck,
    this.ackReason = '',
    this.onOpenRules,
    this.quietHours = true,
    this.onQuietHours,
    this.monitoring = true,
    this.onMonitoring,
    this.batteryExempt = false,
    this.onRequestBatteryExempt,
    super.key,
  });

  /// `{rule: enabled}` from `GET /config/alarms` (09 §9.2). Summarised here;
  /// edited in the rule editor.
  ///
  /// **Null until the bridge answers, and the worst default-as-fact left on
  /// this screen when it was found.** This was a `const` map of six rules, all
  /// on, handed in from the route — so a phone that had never met a bridge, on
  /// any lane, connected or not, printed "6 of 6 on" as a statement about a
  /// device. §G.1 names nine rules, not six, which is how the fabrication was
  /// spotted.
  final Map<String, bool>? deviceRules;

  /// What the device says is latched right now. The app mirrors; it never
  /// re-decides.
  final List<Alarm> alarms;
  final ValueChanged<Alarm>? onAck;

  /// Why an alarm cannot be silenced on this lane, or `''`. Silencing is a
  /// write to the bridge; with no link the button is disabled and says so
  /// rather than looking live and doing nothing.
  final String ackReason;

  final VoidCallback? onOpenRules;

  final bool quietHours;
  final ValueChanged<bool>? onQuietHours;

  /// A13.5 — background monitoring. Off means the foreground service stops and
  /// every posted notification comes down: leaving them behind would imply it
  /// is still running.
  final bool monitoring;
  final ValueChanged<bool>? onMonitoring;

  /// True once the OS has been asked to exempt us from battery optimisation.
  /// Several OEM builds kill long-running foreground services regardless of
  /// type (§9.6), and this is the one-tap mitigation — offered, never demanded.
  final bool batteryExempt;
  final VoidCallback? onRequestBatteryExempt;

  /// The bridge's rules, or null when it has not said. An empty map is the
  /// same absence: a bridge that answered with no rules at all has told us
  /// nothing worth counting.
  Map<String, bool>? get _rules =>
      (deviceRules?.isEmpty ?? true) ? null : deviceRules;

  /// What is *off*, named. A count alone ("7 of 9 on") makes somebody open the
  /// editor to find out which two, at the exact moment they are asking whether
  /// they are covered.
  String get _deviceRuleSubtitle {
    final rules = _rules;
    if (rules == null) {
      return 'The bridge hasn’t reported its rules yet';
    }
    final off =
        rules.entries
            .where((e) => !e.value)
            .map((e) => _ruleLabel(e.key))
            .toList()
          ..sort();
    return off.isEmpty
        ? 'Every rule the bridge has is switched on'
        : 'Switched off: ${off.join(', ')}';
  }

  @override
  Widget build(BuildContext context) => SettingsPage(
    key: const Key('settings-alarms'),
    lead:
        'Two different things have to work for an alarm to reach you: the '
        'bridge has to raise it, and this phone has to make a noise. They fail '
        'separately, so they are set separately.',
    children: [
      const SettingsSectionLabel('On the bridge'),
      SettingsGroup(
        key: const Key('alarms-device-tier'),
        footer: const Text(
          'These run on the bridge itself. They keep working with your phone '
          'switched off, out of range, or flat — that is the safety net, and '
          'nothing on this phone can turn it off.',
        ),
        children: [
          SettingsRow(
            key: const Key('alarms-device-count'),
            label: 'Rules the bridge is running',
            subtitle: _deviceRuleSubtitle,
            value: _rules == null
                ? null
                : '${_rules!.values.where((v) => v).length} of '
                      '${_rules!.length} on',
          ),
          SettingsActionRow(
            key: const Key('alarms-open-rules'),
            label: 'Edit the rules',
            subtitle:
                'Thresholds, pre-alarms, and whether the bridge or this phone '
                'watches for it',
            buttonLabel: 'Open rules',
            onPressed: onOpenRules,
          ),
        ],
      ),
      const SettingsSectionLabel('On this phone'),
      SettingsGroup(
        key: const Key('alarms-app-tier'),
        footer: const Text(
          'These decide whether this phone makes a noise. They need the app '
          'running, and they never replace the bridge’s own alarms.',
        ),
        children: [
          SettingsSwitchRow(
            key: const Key('alarm-quiet-hours'),
            label: 'Quiet hours, 22:00 to 06:00',
            subtitle:
                'Warnings go silent. Critical alarms still sound — overcooking '
                'a brisket at 3 a.m. is exactly what is worth waking for.',
            value: quietHours,
            onChanged: onQuietHours,
          ),
          SettingsSwitchRow(
            key: const Key('alarm-monitoring'),
            label: 'Keep watching in the background',
            subtitle:
                'Carries on with the app closed, and writes every reading to '
                'this phone',
            value: monitoring,
            onChanged: onMonitoring,
          ),
          if (!batteryExempt)
            SettingsActionRow(
              key: const Key('alarms-battery-optimisation'),
              label: 'Allow background running',
              subtitle:
                  'Some phones stop background monitoring to save battery. If '
                  'yours does, notifications arrive late or not at all. '
                  'Declining is fine — the app catches up when you open it, '
                  'and the bridge never stops recording.',
              buttonLabel: 'Allow',
              onPressed: onRequestBatteryExempt,
            ),
        ],
      ),
      const SettingsNote(
        'Even with everything on this page switched off, the bridge keeps '
        'logging and keeps sounding its own alarms.',
      ),
      const SettingsSectionLabel('What has fired'),
      SettingsGroup(
        key: const Key('alarms-log'),
        // The reason sits once, at the foot of the card, rather than under
        // every entry: the entries themselves are still real facts and must
        // stay at full contrast. Only the verb is unavailable.
        footer: Text(
          ackReason.isEmpty
              ? 'Acknowledging silences an alarm. It does not resolve it — one '
                    'that fired at 03:40 is still listed at 07:00.'
              : 'Acknowledging silences an alarm on the bridge, so it needs a '
                    'link. $ackReason',
        ),
        children: [
          if (alarms.isEmpty)
            const SettingsRow(
              key: Key('alarms-log-empty'),
              label: 'Nothing has fired',
              subtitle:
                  'Alarms the bridge raises show up here, acknowledged '
                  'or not',
            )
          else
            for (final a in alarms)
              SettingsRow(
                key: Key('alarm-entry-${a.id}'),
                label: _ruleLabel(a.rule),
                subtitle: [
                  if (a.probe > 0) 'Probe ${a.probe}',
                  if (a.valueF10 != null) formatTempPrecise(a.valueF10),
                  if (a.sinceUnixMs != null) formatSessionDate(a.sinceUnixMs),
                  if (a.acked) 'Acknowledged' else 'Not acknowledged yet',
                ].join(' · '),
                trailing: a.acked || onAck == null
                    ? null
                    : OutlinedButton(
                        key: Key('alarm-ack-${a.id}'),
                        // Disabled, not absent, and not enabled-and-inert:
                        // this used to be a fully live button behind a
                        // null-aware call that did nothing with no link.
                        onPressed: ackReason.isEmpty ? () => onAck!(a) : null,
                        child: const Text('Silence'),
                      ),
                value: a.acked ? 'Silenced' : null,
              ),
        ],
      ),
    ],
  );
}

String _ruleLabel(String rule) => switch (rule) {
  'smoke_x_alarm' => 'Base station alarm',
  'target_reached' => 'Target reached',
  'pit_out_of_band' => 'Pit out of band',
  'pit_crash' => 'The fire is dying',
  'probe_detached' => 'Probe unplugged',
  'base_lost' => 'Base station went quiet',
  'battery_low' => 'Bridge battery low',
  'storage_low' => 'Bridge storage nearly full',
  'system_fault' => 'Bridge restarted unexpectedly',
  _ => rule,
};
