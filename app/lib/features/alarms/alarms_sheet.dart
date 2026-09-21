/// N11 — the Alerts sheet (`?overlay=alarms`) and its two-tier separation.
///
/// The prototype's `overlayAlarms`, completed:
///
/// * **Active now** — the unacknowledged alarms, severity first, each with its
///   Device/Insight tag and inline acknowledge, or the all-clear notice.
/// * **Delivery** — "will this phone wake you?" plus Send a test alarm (N11.3).
/// * **From the bridge — authoritative** — the nine device rules, toggled only
///   (I2). Never invented, never edited.
/// * **Insights from the app — never overrides the bridge** — the three app
///   rules, toggled and edited (N11.16).
/// * **Preferences** — prefer my own alarms, quiet hours, background monitoring
///   (N11.6).
///
/// The two tiers are never merged untagged (I2). The pure delivery policy is
/// [planNotifications]; this sheet is the surface that reads it and the
/// preferences.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/alarms/notification_policy.dart';
import '../../data/dev_panel.dart';
import '../../data/model/alarm.dart' as bridge;
import '../../data/model/alarm_rule.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../shell/shell.dart';
import 'alarms_format.dart';

/// The clock the Alerts sheet reads. Overridable so relative times are
/// deterministic in tests. No ticker is owned (a repeating clock would make
/// `pumpAndSettle` unusable); the page reads this once per build.
final alarmsNowProvider = Provider<DateTime>((ref) => DateTime.now());

/// The three app rules that ship with the catalogue; anything else in the list
/// is user-authored and may be deleted outright (N11.16).
const Set<String> kBuiltInAppRuleIds = <String>{
  'eta_soon',
  'stall',
  'bridge_unreachable',
};

class AlarmsSheetBody extends ConsumerStatefulWidget {
  const AlarmsSheetBody({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<AlarmsSheetBody> createState() => _AlarmsSheetBodyState();
}

class _AlarmsSheetBodyState extends ConsumerState<AlarmsSheetBody> {
  String? _editingId;
  late TextEditingController _name;
  bridge.AlarmSeverity _severity = bridge.AlarmSeverity.info;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _beginEdit(AlarmRule rule) {
    setState(() {
      _editingId = rule.id;
      _name.text = rule.name;
      _severity = rule.severity;
    });
  }

  void _beginAdd() {
    setState(() {
      _editingId = '__new__';
      _name.text = '';
      _severity = bridge.AlarmSeverity.info;
    });
  }

  Future<void> _save() async {
    final repo = ref.read(bridgeRepositoryProvider);
    final editing = _editingId;
    if (editing == null) {
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    if (editing == '__new__') {
      await repo.saveAppAlarmRule(
        AlarmRule(
          id: 'app_${DateTime.now().microsecondsSinceEpoch}',
          tier: bridge.AlarmTier.app,
          name: name,
          desc: 'Insight added on this phone.',
          severity: _severity,
          scope: bridge.AlarmScope.perProbe,
        ),
      );
    } else {
      final existing = repo.alarmRules.firstWhere((r) => r.id == editing);
      await repo.saveAppAlarmRule(
        existing.copyWith(name: name, severity: _severity),
      );
    }
    if (mounted) {
      setState(() => _editingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final snapshot = ref.watch(snapshotProvider).value;
    final settings = ref.watch(settingsProvider).value;
    final repo = ref.watch(bridgeRepositoryProvider);
    final now = ref.watch(alarmsNowProvider);
    final nowMs = now.millisecondsSinceEpoch;

    final alarms = snapshot?.alarms ?? const <bridge.Alarm>[];
    final active = orderedActiveAlarms(alarms, nowMs: nowMs);
    final findings = snapshot == null
        ? const <AppFinding>[]
        : deriveFindings(snapshot);
    final activeRuleIds = <String>{
      for (final a in active)
        if (a.ruleId.isNotEmpty) a.ruleId else a.id,
    };
    final visibleFindings = <AppFinding>[
      for (final f in findings)
        if (!activeRuleIds.contains(findingRuleId(f))) f,
    ];

    final monitoring = settings?.monitoring ?? true;
    final quietHours = settings?.quietHours ?? true;
    final preferManual = settings?.preferManualAlarm ?? false;
    final verdict = deliveryVerdict(
      monitoring: monitoring,
      quietHours: quietHours,
      preferManualAlarm: preferManual,
    );

    return Column(
      key: const ValueKey<String>('alarms-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ActiveNow(
          active: active,
          findings: visibleFindings,
          nowMs: nowMs,
          onOpen: (alarm) => _openDetail(alarm),
          onAcknowledge: (alarm) async {
            await repo.ackAlarm(alarm.id);
          },
          onAcknowledgeAll: () async {
            for (final alarm in active) {
              await repo.ackAlarm(alarm.id);
            }
          },
        ),
        const SectionLabel(label: 'Delivery'),
        SmokeCard(
          key: const ValueKey<String>('alarms-delivery'),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SmokeIcon(
                    verdict.wake ? SmokeGlyph.bell : SmokeGlyph.moon,
                    size: 20,
                    color: verdict.wake ? tokens.positive : tokens.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          verdict.title,
                          key: const ValueKey<String>(
                            'alarms-delivery-verdict',
                          ),
                          style: SmokeText.bodyStrong.copyWith(
                            color: tokens.textHi,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          verdict.detail,
                          style: SmokeText.labelSm.copyWith(
                            fontSize: 11.5,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SmokeButton(
                key: const ValueKey<String>('alarms-test'),
                label: 'Send a test alarm',
                icon: SmokeGlyph.zap,
                variant: SmokeButtonVariant.ghost,
                size: SmokeButtonSize.sm,
                onPressed: () => repo.sendTestAlarm(),
              ),
            ],
          ),
        ),
        const SectionLabel(
          label: 'From the bridge',
          trailing: _Authoritative(),
        ),
        SmokeCard(
          key: const ValueKey<String>('alarms-device-rules'),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final rule in deviceRules(repo.alarmRules))
                SettingsRow(
                  key: ValueKey<String>('alarms-device-rule-${rule.id}'),
                  icon: rule.severity == bridge.AlarmSeverity.critical
                      ? SmokeGlyph.alertCircle
                      : SmokeGlyph.alertTriangle,
                  name: rule.name,
                  sub: '${rule.desc} · ${scopeWord(rule.scope)}',
                  trailing: SmokeToggle(
                    key: ValueKey<String>('alarms-device-toggle-${rule.id}'),
                    value: rule.enabled,
                    onChanged: (v) async {
                      await repo.setAlarmRuleEnabled(rule.id, v);
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        const SectionLabel(
          label: 'Insights from the app',
          trailing: _NeverOverrides(),
        ),
        SmokeCard(
          key: const ValueKey<String>('alarms-app-rules'),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final rule in appRules(repo.alarmRules))
                _AppRuleRow(
                  rule: rule,
                  onToggle: (v) async {
                    await repo.setAlarmRuleEnabled(rule.id, v);
                    if (mounted) {
                      setState(() {});
                    }
                  },
                  onEdit: () => _beginEdit(rule),
                  onDelete: () async {
                    await repo.deleteAppAlarmRule(rule.id);
                    if (mounted) {
                      setState(() => _editingId = null);
                    }
                  },
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: SmokeButton(
                  key: const ValueKey<String>('alarms-app-add'),
                  label: 'Add an insight',
                  icon: SmokeGlyph.plus,
                  variant: SmokeButtonVariant.ghost,
                  size: SmokeButtonSize.sm,
                  onPressed: _beginAdd,
                ),
              ),
            ],
          ),
        ),
        if (_editingId != null) _buildEditor(context),
        const SectionLabel(label: 'Preferences'),
        SmokeCard(
          key: const ValueKey<String>('alarms-preferences'),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SettingsRow(
                icon: SmokeGlyph.key,
                name: 'Prefer my own alarms',
                sub:
                    'Your insights win the sound; device rules stay '
                    'authoritative in the list',
                trailing: SmokeToggle(
                  key: const ValueKey<String>('alarms-pref-prefer'),
                  value: preferManual,
                  onChanged: (v) => ref
                      .read(prefsProvider)
                      .update((s) => s.copyWith(preferManualAlarm: v)),
                ),
              ),
              SettingsRow(
                icon: SmokeGlyph.moon,
                name: 'Quiet hours',
                sub: 'Silence warning & info 10pm–6am · critical always sounds',
                trailing: SmokeToggle(
                  key: const ValueKey<String>('alarms-pref-quiet'),
                  value: quietHours,
                  onChanged: (v) => ref
                      .read(prefsProvider)
                      .update((s) => s.copyWith(quietHours: v)),
                ),
              ),
              SettingsRow(
                icon: SmokeGlyph.bell,
                name: 'Background monitoring',
                sub: 'Check on the bridge and bubble up alarms',
                trailing: SmokeToggle(
                  key: const ValueKey<String>('alarms-pref-monitoring'),
                  value: monitoring,
                  onChanged: (v) => ref
                      .read(prefsProvider)
                      .update((s) => s.copyWith(monitoring: v)),
                ),
              ),
            ],
          ),
        ),
        const SectionLabel(label: 'Background monitoring'),
        SmokeCard(
          key: const ValueKey<String>('alarms-monitoring'),
          subtle: true,
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SmokeIcon(
                monitoring ? SmokeGlyph.activity : SmokeGlyph.moon,
                color: tokens.textBody,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  monitoring
                      ? 'This phone watches for alarms while the app is '
                            'backgrounded. The bridge keeps recording and '
                            'sounding its own alarms either way.'
                      : 'Background monitoring is off. Device alarms still '
                            'sound on the bridge; this phone stays quiet '
                            'until you open it.',
                  key: const ValueKey<String>('alarms-monitoring-copy'),
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 11.5,
                    color: tokens.textBody,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final adding = _editingId == '__new__';
    return SmokeCard(
      key: const ValueKey<String>('alarms-app-editor'),
      raised: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            adding ? 'Add an app insight' : 'Edit app insight',
            style: SmokeText.cardTitle.copyWith(color: tokens.textHi),
          ),
          const SizedBox(height: 4),
          Text(
            'App insights are advisory. They never override the bridge (I2).',
            style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey<String>('alarms-app-name'),
            controller: _name,
            onChanged: (_) => setState(() {}),
            style: SmokeText.body.copyWith(color: tokens.textHi),
            decoration: InputDecoration(
              labelText: 'Name',
              labelStyle: SmokeText.labelSm.copyWith(color: tokens.textMuted),
              filled: true,
              fillColor: tokens.well,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.radii.control),
                borderSide: BorderSide(color: tokens.hairlineStrong),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Severity',
            style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: 6),
          FilterChips<bridge.AlarmSeverity>(
            options: const <SmokeSegment<bridge.AlarmSeverity>>[
              SmokeSegment(value: bridge.AlarmSeverity.info, label: 'Info'),
              SmokeSegment(
                value: bridge.AlarmSeverity.warning,
                label: 'Warning',
              ),
              SmokeSegment(
                value: bridge.AlarmSeverity.critical,
                label: 'Critical',
              ),
            ],
            value: _severity,
            onChanged: (v) => setState(() => _severity = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('alarms-app-save'),
                  label: adding ? 'Add insight' : 'Save',
                  onPressed: _name.text.trim().isEmpty ? null : _save,
                  reason: _name.text.trim().isEmpty
                      ? 'Give the insight a name first.'
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmokeButton(
                  key: const ValueKey<String>('alarms-app-cancel'),
                  label: 'Cancel',
                  variant: SmokeButtonVariant.ghost,
                  onPressed: () => setState(() => _editingId = null),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openDetail(bridge.Alarm alarm) {
    final scope = ShellScope.maybeOf(context);
    if (scope == null) {
      return;
    }
    widget.onDone();
    scope.openOverlay(DevOverlay.alarmDetail, {
      'id': alarm.id,
      'tier': alarm.tier.name,
    });
  }
}

/// The `authoritative` trailing word on the device-rules section.
class _Authoritative extends StatelessWidget {
  const _Authoritative();

  @override
  Widget build(BuildContext context) => Text(
    'authoritative',
    key: const ValueKey<String>('alarms-device-authoritative'),
    style: SmokeText.labelSm.copyWith(
      fontSize: 10.5,
      color: SmokeTokens.of(context).textMuted,
    ),
  );
}

/// The `never overrides the bridge` trailing word on the app-rules section.
class _NeverOverrides extends StatelessWidget {
  const _NeverOverrides();

  @override
  Widget build(BuildContext context) => Text(
    'never overrides the bridge',
    key: const ValueKey<String>('alarms-app-never-overrides'),
    style: SmokeText.labelSm.copyWith(
      fontSize: 10.5,
      color: SmokeTokens.of(context).textMuted,
    ),
  );
}

class _ActiveNow extends StatelessWidget {
  const _ActiveNow({
    required this.active,
    required this.findings,
    required this.nowMs,
    required this.onOpen,
    required this.onAcknowledge,
    required this.onAcknowledgeAll,
  });

  final List<bridge.Alarm> active;
  final List<AppFinding> findings;
  final int nowMs;
  final ValueChanged<bridge.Alarm> onOpen;
  final ValueChanged<bridge.Alarm> onAcknowledge;
  final Future<void> Function() onAcknowledgeAll;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final empty = active.isEmpty && findings.isEmpty;
    return Column(
      key: const ValueKey<String>('alarms-active'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SectionLabel(label: 'Active now'),
        if (empty)
          CapabilityNotice(
            key: const ValueKey<String>('alarms-all-clear'),
            icon: SmokeGlyph.check,
            message:
                'No active alarms. The bridge is watching with or without '
                'this app.',
          )
        else ...<Widget>[
          if (active.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${active.length} active alerts',
                      key: const ValueKey<String>('alarms-active-count'),
                      style: SmokeText.labelSm.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey<String>('alarms-ack-all'),
                    onPressed: () => onAcknowledgeAll(),
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textHi,
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Acknowledge all',
                      style: SmokeText.label.copyWith(color: tokens.textHi),
                    ),
                  ),
                ],
              ),
            ),
          for (final alarm in active)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ActiveAlarmRow(
                alarm: alarm,
                nowMs: nowMs,
                onOpen: () => onOpen(alarm),
                onAcknowledge: () => onAcknowledge(alarm),
              ),
            ),
          for (final finding in findings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FindingRow(finding: finding),
            ),
        ],
      ],
    );
  }
}

class _ActiveAlarmRow extends StatelessWidget {
  const _ActiveAlarmRow({
    required this.alarm,
    required this.nowMs,
    required this.onOpen,
    required this.onAcknowledge,
  });

  final bridge.Alarm alarm;
  final int nowMs;
  final VoidCallback onOpen;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final severity = _bannerSeverity(alarm.severity);
    final hue = switch (severity) {
      BannerSeverity.info => tokens.info,
      BannerSeverity.warn => tokens.warning,
      BannerSeverity.critical => tokens.critical,
    };
    return Material(
      key: ValueKey<String>('alarms-active-${alarm.id}'),
      color: tokens.statusFill(hue),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radii.control),
        side: BorderSide(color: tokens.statusBorder(hue, alpha: 0.35)),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(tokens.radii.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              SmokeIcon(_severityGlyph(alarm.severity), size: 22, color: hue),
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
                            alarm.rule,
                            style: SmokeText.label.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: tokens.textHi,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        TierTag(tier: _designTier(alarm.tier)),
                      ],
                    ),
                    Text(
                      alarm.detail.isEmpty ? '—' : alarm.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SmokeText.labelSm.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: tokens.textBody,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: tokens.cardSubtle,
                shape: const CircleBorder(),
                child: InkWell(
                  key: ValueKey<String>('alarms-ack-${alarm.id}'),
                  customBorder: const CircleBorder(),
                  onTap: onAcknowledge,
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

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final AppFinding finding;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final channel = channelForFinding(finding);
    final severity = switch (channel) {
      NotificationChannel.critical => BannerSeverity.critical,
      NotificationChannel.warning => BannerSeverity.warn,
      NotificationChannel.info ||
      NotificationChannel.ongoing => BannerSeverity.info,
    };
    final hue = switch (severity) {
      BannerSeverity.info => tokens.info,
      BannerSeverity.warn => tokens.warning,
      BannerSeverity.critical => tokens.critical,
    };
    return Container(
      key: ValueKey<String>('alarms-finding-${finding.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.statusFill(hue),
        borderRadius: BorderRadius.circular(tokens.radii.control),
        border: Border.all(color: tokens.statusBorder(hue, alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          SmokeIcon(SmokeGlyph.info, size: 22, color: hue),
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
                        findingTitle(finding),
                        style: SmokeText.label.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: tokens.textHi,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    const TierTag(tier: AlarmTier.app),
                  ],
                ),
                Text(
                  findingBody(finding),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: tokens.textBody,
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

class _AppRuleRow extends StatelessWidget {
  const _AppRuleRow({
    required this.rule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final AlarmRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      key: ValueKey<String>('alarms-app-rule-${rule.id}'),
      icon: SmokeGlyph.info,
      name: rule.name,
      sub: rule.desc,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            key: ValueKey<String>('alarms-app-edit-${rule.id}'),
            onPressed: onEdit,
            iconSize: 17,
            visualDensity: VisualDensity.compact,
            tooltip: 'Edit ${rule.name}',
            icon: SmokeIcon(
              SmokeGlyph.edit,
              size: 17,
              color: SmokeTokens.of(context).textBody,
            ),
          ),
          IconButton(
            key: ValueKey<String>('alarms-app-delete-${rule.id}'),
            onPressed: onDelete,
            iconSize: 17,
            visualDensity: VisualDensity.compact,
            tooltip: 'Delete ${rule.name}',
            icon: SmokeIcon(
              SmokeGlyph.trash,
              size: 17,
              color: SmokeTokens.of(context).textMuted,
            ),
          ),
          SmokeToggle(
            key: ValueKey<String>('alarms-app-toggle-${rule.id}'),
            value: rule.enabled,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}

BannerSeverity _bannerSeverity(bridge.AlarmSeverity severity) =>
    switch (severity) {
      bridge.AlarmSeverity.critical => BannerSeverity.critical,
      bridge.AlarmSeverity.warning => BannerSeverity.warn,
      bridge.AlarmSeverity.info ||
      bridge.AlarmSeverity.positive => BannerSeverity.info,
    };

SmokeGlyph _severityGlyph(bridge.AlarmSeverity severity) => switch (severity) {
  bridge.AlarmSeverity.critical => SmokeGlyph.alertCircle,
  bridge.AlarmSeverity.warning => SmokeGlyph.alertTriangle,
  bridge.AlarmSeverity.info || bridge.AlarmSeverity.positive => SmokeGlyph.info,
};

AlarmTier _designTier(bridge.AlarmTier tier) =>
    tier == bridge.AlarmTier.device ? AlarmTier.device : AlarmTier.app;

/// The rule id an app finding maps to, so a finding is not shown twice when a
/// fixture alarm already carries it.
String findingRuleId(AppFinding finding) => switch (finding) {
  AppFinding.etaSoon => 'eta_soon',
  AppFinding.stallStarted || AppFinding.stallEnded => 'stall',
  AppFinding.bridgeUnreachable => 'bridge_unreachable',
  AppFinding.lidOpen => 'lid_open',
  AppFinding.phoneOffline => 'phone_offline',
};

/// `per probe` / `pit` / `cook` / `device` — the prototype's `scoped` word.
String scopeWord(bridge.AlarmScope scope) => switch (scope) {
  bridge.AlarmScope.perProbe => 'per probe',
  bridge.AlarmScope.pit => 'pit',
  bridge.AlarmScope.cook => 'cook',
  bridge.AlarmScope.device => 'device',
};
