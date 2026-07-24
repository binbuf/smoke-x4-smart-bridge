/// A12.1 / A12.2 — the probe editor and the alarms page (design 08 §8.6,
/// 09 §9.1–§9.5).
///
/// **Roles drive which tile is large and which rules apply**, so the probe
/// editor is the screen that decides what the dashboard emphasises — which
/// is why A9.1's headline-slot choice reads the same configuration this
/// page writes.
///
/// The alarms page carries the one claim a settings screen can most easily
/// get wrong. §9.1: **the device tier is authoritative and runs with no
/// phone in existence; the app tier is advisory.** Listing them together
/// as one list of switches implies the phone can be switched off, and it
/// cannot. They are two sections with two different promises, said out
/// loud on screen and not only in this comment.
library;

import 'package:flutter/material.dart';

import '../../app/palette.dart';
import '../../core/format.dart';
import '../../domain/entities/entities.dart';
import 'settings_screen.dart' show probeRoleLabel;

/// The lowest and highest target a form will accept, in tenths °F. The
/// probes are K-type thermocouples on a 32–572 °F base station; a target
/// outside that is a typo, and it is refused in the form rather than on
/// the wire.
const int probeTargetMinF10 = 320;
const int probeTargetMaxF10 = 5720;

class ProbeSettingsView extends StatefulWidget {
  const ProbeSettingsView({
    required this.probes,
    required this.onSave,
    this.unsupportedReason = '',
    this.celsius = false,
    super.key,
  });

  final List<Probe> probes;

  /// Writes through `transport.configure()`. Throwing is expected — a
  /// transport that cannot configure probes says so with A6's typed
  /// condition, and the form keeps the user's edits.
  final Future<void> Function(List<Probe>) onSave;

  /// Non-empty when the current transport cannot do this at all
  /// (`BleTransport`, today: there is no `device_control` op for probe
  /// names or roles, and v1 leaves that surface HTTP-only).
  final String unsupportedReason;
  final bool celsius;

  @override
  State<ProbeSettingsView> createState() => _ProbeSettingsViewState();
}

class _ProbeSettingsViewState extends State<ProbeSettingsView> {
  late List<Probe> _draft = [
    for (var n = 1; n <= 4; n++)
      widget.probes.where((p) => p.n == n).firstOrNull ?? Probe(n: n),
  ];
  final _errors = <int, String>{};
  String _saveError = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = widget.unsupportedReason.isNotEmpty;
    return ListView(
      key: const Key('settings-probes'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (disabled)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.unsupportedReason,
              key: const Key('probes-unsupported'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final p in _draft)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              key: Key('probe-editor-${p.n}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 4,
                      color: ProbePalette.styleFor(
                        p.n,
                        theme.brightness,
                        role: p.role,
                      ).color,
                    ),
                    const SizedBox(width: 8),
                    Text('Probe ${p.n}', style: theme.textTheme.labelLarge),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: Key('probe-name-${p.n}'),
                  enabled: !disabled,
                  initialValue: p.name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (v) => _update(p.n, (x) => x.copyWith(name: v)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final r in ProbeRole.values)
                      ChoiceChip(
                        key: Key('probe-role-${p.n}-${r.name}'),
                        label: Text(probeRoleLabel(r)),
                        selected: p.role == r,
                        onSelected: disabled
                            ? null
                            : (_) => _update(p.n, (x) => x.copyWith(role: r)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: Key('probe-target-${p.n}'),
                  enabled: !disabled,
                  initialValue: p.targetF10 == null
                      ? ''
                      : (p.targetF10! / 10).toStringAsFixed(1),
                  decoration: InputDecoration(
                    labelText: 'Target (${widget.celsius ? '°C' : '°F'})',
                    errorText: _errors[p.n],
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _setTarget(p.n, v),
                ),
              ],
            ),
          ),
        if (_saveError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _saveError,
              key: const Key('probes-save-error'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const Key('probes-save'),
            onPressed: disabled || _errors.isNotEmpty ? null : _save,
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }

  void _update(int n, Probe Function(Probe) f) => setState(() {
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
      // Refused in the form, not on the wire: the device would take it,
      // and then every rule downstream would be nonsense.
      setState(
        () => _errors[n] =
            'Between ${formatTempPrecise(probeTargetMinF10)} and '
            '${formatTempPrecise(probeTargetMaxF10)}',
      );
      return;
    }
    setState(() => _errors.remove(n));
    _update(n, (x) => x.copyWith(targetF10: f10));
  }

  Future<void> _save() async {
    setState(() => _saveError = '');
    try {
      await widget.onSave(_draft);
    } on Object catch (e) {
      // The form keeps its edits. Clearing it on failure is how a user
      // loses ten minutes of typing to one dropped packet.
      setState(() => _saveError = '$e');
    }
  }
}

/// A12.2 — alarms, in two tiers that are visibly, deliberately different.
class AlarmSettingsView extends StatelessWidget {
  const AlarmSettingsView({
    required this.deviceRules,
    required this.alarms,
    this.onToggleRule,
    this.onAck,
    this.quietHours = true,
    this.onQuietHours,
    this.monitoring = true,
    this.onMonitoring,
    this.batteryExempt = false,
    this.onRequestBatteryExempt,
    super.key,
  });

  /// `{rule: enabled}` from `GET /config/alarms` (09 §9.2).
  final Map<String, bool> deviceRules;

  /// What the device says is latched right now. The app mirrors; it does
  /// not decide.
  final List<Alarm> alarms;
  final void Function(String rule, bool enabled)? onToggleRule;
  final ValueChanged<Alarm>? onAck;
  final bool quietHours;
  final ValueChanged<bool>? onQuietHours;

  /// A13.5 — background monitoring. Off means the foreground service
  /// stops and every posted notification comes down: leaving them behind
  /// would imply it is still running.
  final bool monitoring;
  final ValueChanged<bool>? onMonitoring;

  /// True once the OS has been asked to exempt us from battery
  /// optimisation. Several OEM builds kill long-running foreground
  /// services regardless of type (§9.6), and this is the one-tap
  /// mitigation — offered, never demanded.
  final bool batteryExempt;
  final VoidCallback? onRequestBatteryExempt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('settings-alarms'),
      children: [
        _Tier(
          key: const Key('alarms-device-tier'),
          title: 'On the bridge',
          // The promise that makes this tier different, said on screen.
          blurb:
              'These run on the bridge itself. They keep working with your '
              'phone switched off, out of range, or flat.',
        ),
        for (final e in deviceRules.entries)
          SwitchListTile(
            key: Key('alarm-rule-${e.key}'),
            title: Text(_ruleLabel(e.key)),
            subtitle: Text(_ruleBlurb(e.key)),
            value: e.value,
            onChanged: onToggleRule == null
                ? null
                : (v) => onToggleRule!(e.key, v),
          ),
        _Tier(
          key: const Key('alarms-app-tier'),
          title: 'On this phone',
          blurb:
              'Advisory only. They need the app running, and they never '
              'replace the bridge\'s own alarms.',
        ),
        const ListTile(
          key: Key('alarm-app-eta'),
          title: Text('Nearly done'),
          subtitle: Text('When a food probe is under 30 minutes away'),
        ),
        const ListTile(
          key: Key('alarm-app-stall'),
          title: Text('Stall started or ended'),
          subtitle: Text('The stall is normal — this is so you do not act'),
        ),
        SwitchListTile(
          key: const Key('alarm-quiet-hours'),
          title: const Text('Quiet hours (22:00–06:00)'),
          subtitle: const Text(
            'Warnings go silent. Critical alarms still sound — overcooking '
            'a brisket at 3 a.m. is exactly what is worth waking up for.',
          ),
          value: quietHours,
          onChanged: onQuietHours,
        ),
        SwitchListTile(
          // A12.2 shipped a caveat here reading "Background monitoring
          // arrives in a later release." This is that release, and the
          // switch below is what replaced it.
          key: const Key('alarm-monitoring'),
          title: const Text('Monitor in the background'),
          subtitle: const Text(
            'Keeps watching while the app is closed, and writes every '
            'reading to this phone.',
          ),
          value: monitoring,
          onChanged: onMonitoring,
        ),
        if (!batteryExempt)
          ListTile(
            key: const Key('alarms-battery-optimisation'),
            title: const Text('Allow background running'),
            subtitle: const Text(
              'Some phones stop background monitoring to save battery. If '
              'yours does, notifications arrive late or not at all. '
              'Declining is fine — the app catches up when you open it, '
              'and the bridge never stops recording.',
            ),
            trailing: TextButton(
              key: const Key('alarms-battery-optimisation-request'),
              onPressed: onRequestBatteryExempt,
              child: const Text('Allow'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Even with all of this switched off, the bridge keeps logging '
            'and keeps sounding its own alarms.',
            key: const Key('alarms-delivery-note'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _Tier(
          key: const Key('alarms-log'),
          title: 'Alarm log',
          blurb:
              'What the bridge raised, and whether anyone has seen it. An '
              'alarm that fired at 03:40 is still waiting at 07:00.',
        ),
        if (alarms.isEmpty)
          const ListTile(
            key: Key('alarms-log-empty'),
            subtitle: Text('Nothing has fired.'),
          )
        else
          for (final a in alarms)
            ListTile(
              key: Key('alarm-entry-${a.id}'),
              leading: Icon(
                AlarmPalette.iconOf(a.severity),
                color: AlarmPalette.of(a.severity),
              ),
              title: Text(_ruleLabel(a.rule)),
              subtitle: Text(
                [
                  if (a.probe > 0) 'probe ${a.probe}',
                  if (a.valueF10 != null) formatTempPrecise(a.valueF10),
                  if (a.sinceUnixMs != null) formatSessionDate(a.sinceUnixMs),
                  // Acknowledging silences; it does not resolve (§9.2).
                  if (a.acked) 'acknowledged' else 'not acknowledged',
                ].join(' · '),
              ),
              trailing: a.acked || onAck == null
                  ? null
                  : TextButton(
                      key: Key('alarm-ack-${a.id}'),
                      onPressed: () => onAck!(a),
                      child: const Text('Acknowledge'),
                    ),
            ),
      ],
    );
  }
}

class _Tier extends StatelessWidget {
  const _Tier({required this.title, required this.blurb, super.key});
  final String title;
  final String blurb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            blurb,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _ruleLabel(String rule) => switch (rule) {
  'smoke_x_alarm' => 'Base station alarm',
  'target_reached' => 'Target reached',
  'pit_out_of_band' => 'Pit out of band',
  'pit_crash' => 'Pit crashing',
  'probe_detached' => 'Probe unplugged',
  'base_lost' => 'Base station lost',
  'battery_low' => 'Bridge battery low',
  'storage_low' => 'Bridge storage nearly full',
  'system_fault' => 'Bridge restarted unexpectedly',
  _ => rule,
};

String _ruleBlurb(String rule) => switch (rule) {
  'target_reached' => 'A food probe crosses its target',
  'pit_out_of_band' => 'The pit sits outside its band for 10 minutes',
  'pit_crash' => 'The fire is dying',
  'probe_detached' => 'A probe is unplugged mid-cook',
  'base_lost' => 'No packet from the base station for 10 minutes',
  _ => '',
};
