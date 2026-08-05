/// `/device/alarms` — the alarm-rule editor, both tiers (newapp §G.2, §G.3).
///
/// **The biggest missing feature, and it had no entry point.** Not one rule was
/// editable: the bridge's nine ran with hard-coded thresholds, the app's
/// advisory ones were a `const` map behind a `null` callback, and the page that
/// showed them was reachable only by typing `/bridge/alarms` into a deep link.
/// The Alerts tab said so out loud, in a card, which is honest and is not a
/// feature.
///
/// Three things this screen has to get right:
///
///  1. **The two tiers stay visibly separate.** One list of switches would
///     imply the phone tier can be turned off and the device tier cannot. They
///     are two sections with two stated promises: the bridge's rules keep
///     working with the phone flat, and the app's are advisory.
///  2. **A device rule says "Saved to bridge" only after a read-back matched**
///     (§G.3). The settings tree's original sin was calling `configure()`
///     through a null-aware operator and reporting success it never had; this
///     screen writes, reads back, compares, and only then flips the badge.
///  3. **A rule the transport cannot push is disabled with its reason on
///     screen**, never rendered as a live control that silently writes nothing.
///
/// It also hosts the **test alarm** that used to live on `/alerts`, beside the
/// rules it tests, and the delivery verdict as a banner.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_env.dart';
import '../../core/format.dart';
import '../../data/local/database.dart';
import '../../data/transport/bridge_transport.dart';
import '../../design/design.dart';
import '../../domain/alarms/alarm_rule.dart';
import '../../ui/ui.dart';
import '../cooks/cook_actions.dart';
import '../shell/shell_scope.dart';
import 'alarm_rule_sheet.dart';
import 'delivery_banner.dart';

class AlarmRulesRoute extends StatefulWidget {
  const AlarmRulesRoute({super.key});

  @override
  State<AlarmRulesRoute> createState() => _AlarmRulesRouteState();
}

class _AlarmRulesRouteState extends State<AlarmRulesRoute> {
  AppDatabase? _db;
  String? _bridgeId;
  List<AlarmRuleSpec> _rules = const [];
  bool _loaded = false;
  final Set<int> _pushing = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final env = AppEnv.instance;
    final bridgeId = await env?.db.sessionDao.knownBridgeId();
    if (env == null || bridgeId == null) {
      if (mounted) {
        setState(() => _loaded = true);
      }
      return;
    }
    var rules = await env.db.alarmRuleDao.forBridge(bridgeId);
    if (rules.isEmpty) {
      // First run: seed the device's own nine and the app's advisory two, so
      // the editor has real rows to show. Every one is seeded **unpushed** —
      // the app does not get to claim the bridge agreed to something nobody
      // has asked it about yet.
      for (final r in [
        ...defaultDeviceRules(bridgeId),
        ...defaultAppRules(bridgeId),
      ]) {
        await env.db.alarmRuleDao.save(r);
      }
      rules = await env.db.alarmRuleDao.forBridge(bridgeId);
    }
    if (mounted) {
      setState(() {
        _db = env.db;
        _bridgeId = bridgeId;
        _rules = rules;
        _loaded = true;
      });
    }
  }

  BridgeTransport? get _transport =>
      ShellScope.maybeOf(context)?.bridge?.transport;

  /// §G.3 — write, read back, compare, and only then say it is saved.
  Future<void> _push(AlarmRuleSpec rule) async {
    final db = _db;
    final transport = _transport;
    if (db == null || rule.tier != AlarmTier.device) {
      return;
    }
    setState(() => _pushing.add(rule.id));
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (transport == null) {
        throw StateError('no transport');
      }
      final payload = rule.toDeviceJson();
      if (payload == null) {
        throw StateError('not a device rule');
      }
      await transport.setAlarmConfig(payload);
      // The read-back is the claim. A write that returned 200 and changed
      // nothing is the exact failure this whole pattern exists to catch.
      if (!rule.matchesReadBack(await transport.alarmConfig())) {
        throw StateError('read-back mismatch');
      }
      await db.alarmRuleDao.markConfirmed(
        rule.id,
        atUnixMs: DateTime.now().millisecondsSinceEpoch,
      );
    } on Object {
      await db.alarmRuleDao.markUnconfirmed(rule.id);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'The bridge didn’t confirm that change. It is saved on this phone '
            'and will be sent again when the bridge answers.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pushing.remove(rule.id));
      }
      await _reload();
    }
  }

  Future<void> _reload() async {
    final db = _db;
    final id = _bridgeId;
    if (db == null || id == null) {
      return;
    }
    final rules = await db.alarmRuleDao.forBridge(id);
    if (mounted) {
      setState(() => _rules = rules);
    }
  }

  Future<void> _save(AlarmRuleSpec rule) async {
    final db = _db;
    if (db == null) {
      return;
    }
    final id = await db.alarmRuleDao.save(rule);
    await _reload();
    if (rule.tier == AlarmTier.device) {
      await _push(rule.copyWith(id: id));
    }
  }

  Future<void> _add() async {
    final id = _bridgeId;
    if (id == null) {
      return;
    }
    final rule = await showAddRuleSheet(
      context,
      bridgeId: id,
      celsius: ShellScope.maybeOf(context)?.celsius ?? false,
    );
    if (rule != null) {
      await _save(rule);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canPush = _transport?.capabilities.config ?? false;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Alarms'),
        actions: [
          IconButton(
            key: const Key('alarm-rule-add'),
            tooltip: 'Add a rule',
            icon: const Icon(Icons.add_rounded),
            onPressed: _loaded ? () => unawaited(_add()) : null,
          ),
        ],
      ),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                key: const Key('alarm-rules'),
                padding: const EdgeInsets.all(SmokeTokens.s4),
                children: [
                  const DeliveryBanner(),
                  const SizedBox(height: SmokeTokens.s2),
                  _tierSection(t, AlarmTier.device, canPush: canPush),
                  const SizedBox(height: SmokeTokens.s5),
                  _tierSection(t, AlarmTier.app, canPush: true),
                  const SizedBox(height: SmokeTokens.s5),
                  _testCard(t),
                ],
              ),
      ),
    );
  }

  Widget _tierSection(
    SmokeTokens t,
    AlarmTier tier, {
    required bool canPush,
  }) {
    final rules = _rules.where((r) => r.tier == tier).toList()
      ..sort((a, b) => a.type.index.compareTo(b.type.index));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tier.label.toUpperCase(),
          style: SmokeType.label.copyWith(color: t.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          tier.promise,
          style: SmokeType.bodySm.copyWith(color: t.textBody),
        ),
        const SizedBox(height: SmokeTokens.s3),
        if (rules.isEmpty)
          Text(
            'No rules here yet.',
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          )
        else
          for (final rule in rules)
            _RuleRow(
              key: Key('alarm-rule-${rule.id}'),
              rule: rule,
              celsius: ShellScope.maybeOf(context)?.celsius ?? false,
              busy: _pushing.contains(rule.id),
              // A control that cannot work is disabled **with its reason**.
              disabledReason: tier == AlarmTier.device && !canPush
                  ? 'Connect over Wi-Fi to change the bridge’s own rules.'
                  : '',
              onToggle: (v) =>
                  unawaited(_save(rule.copyWith(enabled: v))),
              onEdit: () => unawaited(_edit(rule)),
              onDelete: () => unawaited(_delete(rule)),
            ),
      ],
    );
  }

  Future<void> _edit(AlarmRuleSpec rule) async {
    final next = await showEditRuleSheet(
      context,
      rule: rule,
      celsius: ShellScope.maybeOf(context)?.celsius ?? false,
    );
    if (next != null) {
      await _save(next);
    }
  }

  Future<void> _delete(AlarmRuleSpec rule) async {
    final db = _db;
    if (db == null) {
      return;
    }
    await db.alarmRuleDao.deleteRule(rule.id);
    await _reload();
  }

  /// The one control that has to touch the real plumbing, moved here from the
  /// deleted `/alerts` tab so it sits beside the rules it is testing.
  Widget _testCard(SmokeTokens t) => SmokeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PROVE IT',
          style: SmokeType.label.copyWith(color: t.textMuted),
        ),
        const SizedBox(height: SmokeTokens.s2),
        Text(
          'Posts a real alarm on the real channel. It is the only way to know '
          'this phone will make a noise at 3 a.m. before you spend a night '
          'finding out.',
          style: SmokeType.bodySm.copyWith(color: t.textBody),
        ),
        const SizedBox(height: SmokeTokens.s3),
        PrimaryAction(
          key: const Key('alarm-send-test'),
          label: 'Send a test alarm',
          icon: Icons.notifications_active_rounded,
          onPressed: () => unawaited(sendTestAlarm(context)),
        ),
      ],
    ),
  );
}

/// One rule row. Stateless over plain values, so the whole editor renders in a
/// widget test with no transport and no database.
class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.celsius,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.busy = false,
    this.disabledReason = '',
    super.key,
  });

  final AlarmRuleSpec rule;
  final bool celsius;
  final bool busy;
  final String disabledReason;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locked = disabledReason.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
      child: SmokeCard(
        onTap: locked ? null : onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rule.type.label,
                        style: SmokeType.title.copyWith(color: t.textHi),
                      ),
                      Text(
                        _summary(),
                        style: SmokeType.bodySm.copyWith(color: t.textMuted),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    key: Key('alarm-rule-toggle-${rule.id}'),
                    value: rule.enabled,
                    onChanged: locked ? null : onToggle,
                  ),
              ],
            ),
            if (locked)
              Padding(
                padding: const EdgeInsets.only(top: SmokeTokens.s2),
                child: Text(
                  disabledReason,
                  style: SmokeType.bodySm.copyWith(color: t.textMuted),
                ),
              )
            else if (rule.tier == AlarmTier.device)
              Padding(
                padding: const EdgeInsets.only(top: SmokeTokens.s2),
                child: Text(
                  // Never "Saved" on the strength of a return value.
                  rule.pushedToDevice
                      ? 'Saved to the bridge'
                      : 'Not saved to the bridge yet — it will be sent again '
                            'when the bridge answers.',
                  style: SmokeType.labelSm.copyWith(
                    color: rule.pushedToDevice ? t.textMuted : t.textBody,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _summary() {
    final unit = rule.type.thresholdUnit;
    final v = rule.threshold;
    final parts = <String>[
      if (rule.jack != null) 'Probe ${rule.jack}',
      if (v != null && unit != null)
        switch (unit) {
          AlarmThresholdUnit.temperatureF10 =>
            formatSetpoint(v, celsius: celsius),
          AlarmThresholdUnit.degreesBelowTarget =>
            '${(v / 10).round()}° before target',
          AlarmThresholdUnit.seconds => formatDuration(v),
          AlarmThresholdUnit.percent => '$v%',
        },
      if (rule.windowS != null) 'held ${formatDuration(rule.windowS!)}',
    ];
    return parts.isEmpty ? rule.type.blurb : parts.join(' · ');
  }
}
