/// Adding and editing an alarm rule (newapp §G.2).
///
/// The taxonomy is MEATER's Add Alert grouping, because it is the one users
/// already know: **AMBIENT** falls below / rises above, **INTERNAL** falls below
/// / rises above, **TIME** elapsed / before the end — plus TempPro's pre-alarm
/// offset, which its reviewers love and which costs almost nothing, and this
/// device's own health rules.
///
/// Two rules the sheet holds:
///
///  * a type is only offered on a tier that can actually run it
///    ([AlarmRuleType.tiers]); offering `time before end` as a device rule
///    would be offering a rule the firmware has no ETA to evaluate;
///  * the threshold field's unit follows the type
///    ([AlarmRuleType.thresholdUnit]), so nothing ever renders "1650 seconds"
///    under a temperature rule.
library;

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../domain/alarms/alarm_rule.dart';
import '../../ui/ui.dart';

Future<AlarmRuleSpec?> showAddRuleSheet(
  BuildContext context, {
  required String bridgeId,
  bool celsius = false,
}) => showModalBottomSheet<AlarmRuleSpec>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => Theme(
    data: SmokeTheme.dark,
    child: _RuleSheet(bridgeId: bridgeId, celsius: celsius),
  ),
);

Future<AlarmRuleSpec?> showEditRuleSheet(
  BuildContext context, {
  required AlarmRuleSpec rule,
  bool celsius = false,
}) => showModalBottomSheet<AlarmRuleSpec>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => Theme(
    data: SmokeTheme.dark,
    child: _RuleSheet(bridgeId: rule.bridgeId, celsius: celsius, initial: rule),
  ),
);

class _RuleSheet extends StatefulWidget {
  const _RuleSheet({
    required this.bridgeId,
    required this.celsius,
    this.initial,
  });

  final String bridgeId;
  final bool celsius;
  final AlarmRuleSpec? initial;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late AlarmRuleType _type =
      widget.initial?.type ?? AlarmRuleType.internalAbove;
  late AlarmTier _tier = widget.initial?.tier ?? AlarmTier.device;
  late int? _jack = widget.initial?.jack ?? 1;
  late String _threshold = _initialThreshold();
  late String _window = widget.initial?.windowS == null
      ? ''
      : (widget.initial!.windowS! ~/ 60).toString();

  String _initialThreshold() {
    final v = widget.initial?.threshold;
    if (v == null) {
      return '';
    }
    return switch (widget.initial!.type.thresholdUnit) {
      AlarmThresholdUnit.temperatureF10 =>
        widget.celsius
            ? ((v / 10 - 32) * 5 / 9).round().toString()
            : (v / 10).round().toString(),
      AlarmThresholdUnit.degreesBelowTarget => (v / 10).round().toString(),
      AlarmThresholdUnit.seconds => (v ~/ 60).toString(),
      AlarmThresholdUnit.percent => v.toString(),
      null => '',
    };
  }

  /// Only the types this tier can actually run.
  List<AlarmRuleType> get _available =>
      AlarmRuleType.values.where((t) => t.tiers.contains(_tier)).toList();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final unit = _type.thresholdUnit;
    final grouped = <String, List<AlarmRuleType>>{};
    for (final type in _available) {
      grouped.putIfAbsent(type.group, () => []).add(type);
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SmokeTokens.radiusCard),
        ),
        border: Border.all(color: t.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(SmokeTokens.s4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.initial == null ? 'Add a rule' : 'Edit rule',
                    style: SmokeType.displayS.copyWith(color: t.textHi),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: SmokeTokens.s4),
              children: [
                Text(
                  'WHO WATCHES IT',
                  style: SmokeType.label.copyWith(color: t.textMuted),
                ),
                const SizedBox(height: SmokeTokens.s2),
                SegmentedChips<AlarmTier>(
                  options: [
                    for (final tier in AlarmTier.values)
                      ChipOption(tier, tier.label),
                  ],
                  value: _tier,
                  onChanged: (v) => setState(() {
                    _tier = v;
                    if (!_type.tiers.contains(v)) {
                      _type = _available.first;
                    }
                  }),
                ),
                const SizedBox(height: SmokeTokens.s2),
                Text(
                  _tier.promise,
                  style: SmokeType.bodySm.copyWith(color: t.textMuted),
                ),
                const SizedBox(height: SmokeTokens.s4),
                for (final entry in grouped.entries) ...[
                  Text(
                    entry.key.toUpperCase(),
                    style: SmokeType.label.copyWith(color: t.textMuted),
                  ),
                  const SizedBox(height: SmokeTokens.s2),
                  for (final type in entry.value) _typeCard(t, type),
                  const SizedBox(height: SmokeTokens.s3),
                ],
                if (_type.isPerProbe) ...[
                  Text(
                    'WHICH PROBE',
                    style: SmokeType.label.copyWith(color: t.textMuted),
                  ),
                  const SizedBox(height: SmokeTokens.s2),
                  SegmentedChips<int>(
                    options: [
                      for (var j = 1; j <= 4; j++) ChipOption(j, 'Probe $j'),
                    ],
                    value: _jack ?? 1,
                    onChanged: (v) => setState(() => _jack = v),
                  ),
                  const SizedBox(height: SmokeTokens.s4),
                ],
                if (unit != null)
                  TextFormField(
                    key: const Key('rule-threshold'),
                    initialValue: _threshold,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: SmokeType.body.copyWith(color: t.textHi),
                    decoration: InputDecoration(
                      labelText: _thresholdLabel(unit),
                      helperText: _type.blurb,
                      helperMaxLines: 3,
                      helperStyle: SmokeType.labelSm.copyWith(
                        color: t.textMuted,
                      ),
                    ),
                    onChanged: (v) => _threshold = v,
                  ),
                const SizedBox(height: SmokeTokens.s3),
                TextFormField(
                  key: const Key('rule-window'),
                  initialValue: _window,
                  keyboardType: TextInputType.number,
                  style: SmokeType.body.copyWith(color: t.textHi),
                  decoration: InputDecoration(
                    labelText: 'Hold for (minutes)',
                    // A pit band that fires on one noisy packet is a pit band
                    // nobody leaves switched on.
                    helperText:
                        'Leave blank to fire straight away. A short hold stops '
                        'one odd reading from waking you.',
                    helperMaxLines: 3,
                    helperStyle: SmokeType.labelSm.copyWith(color: t.textMuted),
                  ),
                  onChanged: (v) => _window = v,
                ),
                const SizedBox(height: SmokeTokens.s4),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              SmokeTokens.s4,
              SmokeTokens.s2,
              SmokeTokens.s4,
              SmokeTokens.s4 + MediaQuery.of(context).padding.bottom,
            ),
            child: PrimaryAction(
              key: const Key('rule-save'),
              label: widget.initial == null ? 'Add rule' : 'Save rule',
              icon: Icons.check_rounded,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }

  String _thresholdLabel(AlarmThresholdUnit unit) => switch (unit) {
    AlarmThresholdUnit.temperatureF10 =>
      'Temperature (°${widget.celsius ? 'C' : 'F'})',
    AlarmThresholdUnit.degreesBelowTarget =>
      'Degrees before target (°${widget.celsius ? 'C' : 'F'})',
    AlarmThresholdUnit.seconds => 'Minutes',
    AlarmThresholdUnit.percent => 'Percent',
  };

  Widget _typeCard(SmokeTokens t, AlarmRuleType type) {
    final selected = _type == type;
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
      child: SmokeCard(
        key: Key('rule-type-${type.name}'),
        raised: selected,
        accent: selected ? StatusPalette.pit : null,
        onTap: () => setState(() => _type = type),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(type.label, style: SmokeType.title.copyWith(color: t.textHi)),
            const SizedBox(height: 2),
            Text(
              type.blurb,
              style: SmokeType.bodySm.copyWith(color: t.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final unit = _type.thresholdUnit;
    final raw = double.tryParse(_threshold.trim());
    final threshold = unit == null || raw == null
        ? null
        : switch (unit) {
            AlarmThresholdUnit.temperatureF10 =>
              widget.celsius
                  ? ((raw * 9 / 5 + 32) * 10).round()
                  : (raw * 10).round(),
            AlarmThresholdUnit.degreesBelowTarget =>
              widget.celsius
                  // A *difference* in °C is 9/5 of a difference in °F — not the
                  // absolute conversion, which would offset a pre-alarm by 32°.
                  ? (raw * 9 / 5 * 10).round()
                  : (raw * 10).round(),
            AlarmThresholdUnit.seconds => (raw * 60).round(),
            AlarmThresholdUnit.percent => raw.round(),
          };
    final windowMinutes = int.tryParse(_window.trim());
    Navigator.of(context).pop(
      AlarmRuleSpec(
        id: widget.initial?.id ?? 0,
        bridgeId: widget.bridgeId,
        tier: _tier,
        type: _type,
        jack: _type.isPerProbe ? _jack : null,
        threshold: threshold,
        windowS: windowMinutes == null ? null : windowMinutes * 60,
        enabled: widget.initial?.enabled ?? true,
        cookId: widget.initial?.cookId,
      ),
    );
  }
}
