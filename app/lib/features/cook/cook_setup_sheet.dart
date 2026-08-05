/// The guided-cook setup sheet (design 13 §13.5.3; extended per newapp §D.3–§D.4).
///
/// **What changed, and why.** The first cut was presets-only: pick a category,
/// a cut, a doneness, done. That closed the common case and left three gaps the
/// spec names explicitly —
///
///  * *no custom cook.* TempPro proves the demand the hard way: its reviewers
///    complained the highest settable alarm was 175 °F when "pulled pork needs
///    to go to 193". A preset table is a starting point, not a ceiling.
///  * *no probe mapping.* Jack 1 was the pit and jack 2 the food **by
///    convention**, which is fine until someone plugs the brisket into jack 3.
///  * *no way to start without deciding.* §D.3's whole point is that a cook can
///    begin before its target exists.
///
/// So this sheet now has three ways out, and all three are first-class:
/// **a preset**, **a custom cook**, and **"start it now, decide later"**. The
/// last one is not a degraded path — it is the one that matches how the
/// hardware behaves, because the bridge was already recording before anybody
/// opened the app.
///
/// The plan is built through [CookPlan]'s constructor, so the food-safety gate
/// (§D.4, hardened with the intact-cut flag and the two labelled modes) runs on
/// every exit including the custom one. A refusal surfaces as copy on the
/// offending row rather than as a thrown error the user has to interpret.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/entities/entities.dart' show ProbeRole;
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';

/// Shows the sheet and returns the chosen plan, or null if dismissed.
///
/// [initial] pre-loads a **running** cook so its targets and name can be
/// edited mid-cook — §D.4 requires that, and it used to be impossible.
/// [probeNames] labels the jack rows with whatever the device calls them.
Future<CookPlan?> showCookSetupSheet(
  BuildContext context, {
  bool celsius = false,
  CookPlan? initial,
  Map<int, String> probeNames = const {},
}) {
  return showModalBottomSheet<CookPlan>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Theme(
      data: SmokeTheme.dark,
      child: _CookSetupSheet(
        celsius: celsius,
        initial: initial,
        probeNames: probeNames,
      ),
    ),
  );
}

/// One jack, as the mapping section edits it.
class _JackDraft {
  _JackDraft({required this.jack, required this.role});

  final int jack;
  ProbeRole role;
  int? targetF10;
  int pullOffsetF10 = 0;
  bool isIntact = true;
  String label = '';
  HazardClass? hazard;
}

class _CookSetupSheet extends StatefulWidget {
  const _CookSetupSheet({
    required this.celsius,
    required this.probeNames,
    this.initial,
  });

  final bool celsius;
  final CookPlan? initial;
  final Map<int, String> probeNames;

  @override
  State<_CookSetupSheet> createState() => _CookSetupSheetState();
}

class _CookSetupSheetState extends State<_CookSetupSheet> {
  String _category = Presets.categories.first;
  CookPreset? _preset;
  Doneness? _doneness;
  bool _custom = false;
  SafetyMode _mode = SafetyMode.enthusiast;
  late final List<_JackDraft> _jacks;
  String _refusal = '';

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _jacks = [
      for (var j = 1; j <= 4; j++)
        _JackDraft(
          jack: j,
          // Without a starting plan the device's own convention holds — jack 1
          // is the pit, the rest are food — because that is what the OLED
          // assumes and the two screens must not disagree.
          role: j == 1 ? ProbeRole.pit : ProbeRole.food,
        ),
    ];
    if (initial != null) {
      _mode = initial.safetyMode;
      _custom = initial.presetId == 'custom';
      _preset = Presets.byId(initial.presetId);
      _category = _preset?.category ?? _category;
      _doneness = _preset?.doneness
          .where((d) => d.label == initial.doneness)
          .firstOrNull;
      for (final p in initial.probes) {
        final draft = _jacks.where((d) => d.jack == p.jack).firstOrNull;
        if (draft == null) {
          continue;
        }
        draft.role = p.role;
        draft.targetF10 = p.targetF10;
        draft.pullOffsetF10 = p.carryoverF10;
        draft.isIntact = p.isIntact;
        draft.label = p.name;
        draft.hazard = p.hazard;
      }
      for (final d in _jacks) {
        if (initial.probes.every((p) => p.jack != d.jack)) {
          d.role = ProbeRole.unused;
        }
      }
    }
  }

  HazardClass get _hazard =>
      _preset?.hazard ?? widget.initial?.hazard ?? HazardClass.wholeMuscleRedMeat;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
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
          _header(t),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: SmokeTokens.s4),
              children: [
                if (!_editing) _startBlankCard(t),
                _sectionLabel(t, 'What are you cooking?'),
                SegmentedChips<String>(
                  options: [
                    for (final c in Presets.categories) ChipOption(c, c),
                    const ChipOption('custom', 'Something else'),
                  ],
                  value: _custom ? 'custom' : _category,
                  onChanged: (c) => setState(() {
                    _refusal = '';
                    if (c == 'custom') {
                      _custom = true;
                      _preset = null;
                      _doneness = null;
                    } else {
                      _custom = false;
                      _category = c;
                      _preset = null;
                      _doneness = null;
                    }
                  }),
                ),
                const SizedBox(height: SmokeTokens.s3),
                if (!_custom)
                  for (final p in Presets.inCategory(_category))
                    _presetCard(context, p),
                if (_preset != null) ...[
                  _sectionLabel(t, 'Doneness'),
                  for (final d in _preset!.doneness) _donenessCard(context, d),
                ],
                _sectionLabel(t, 'Probes'),
                for (final d in _jacks) _jackRow(context, d),
                _safetySection(t),
                if (_refusal.isNotEmpty) ...[
                  const SizedBox(height: SmokeTokens.s3),
                  InsightBanner(
                    kind: InsightKind.stall,
                    icon: Icons.shield_outlined,
                    label: 'Below the safe minimum — $_refusal',
                  ),
                ],
                const SizedBox(height: SmokeTokens.s4),
              ],
            ),
          ),
          _footer(context),
        ],
      ),
    );
  }

  Widget _header(SmokeTokens t) => Padding(
    padding: const EdgeInsets.all(SmokeTokens.s4),
    child: Row(
      children: [
        Icon(Icons.bolt_rounded, color: StatusPalette.pit),
        const SizedBox(width: SmokeTokens.s2),
        Text(
          _editing ? 'Edit this cook' : 'Set up a cook',
          style: SmokeType.displayS.copyWith(color: t.textHi),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  Widget _sectionLabel(SmokeTokens t, String text) => Padding(
    padding: const EdgeInsets.only(
      top: SmokeTokens.s4,
      bottom: SmokeTokens.s2,
    ),
    child: Text(text, style: SmokeType.label.copyWith(color: t.textMuted)),
  );

  /// §D.3 — the honest first option. The bridge has been recording since it was
  /// switched on; naming that window is a decision the user can make now and
  /// finish later, so it must not sit at the bottom behind two other choices.
  Widget _startBlankCard(SmokeTokens t) => Padding(
    padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
    child: SmokeCard(
      onTap: _startBlank,
      child: Row(
        children: [
          Icon(Icons.play_circle_outline_rounded, color: t.textBody),
          const SizedBox(width: SmokeTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start one now, decide later',
                  style: SmokeType.title.copyWith(color: t.textHi),
                ),
                const SizedBox(height: 2),
                Text(
                  'Names this stretch of the recording. You can set targets, '
                  'rename it, or move its start time whenever you like.',
                  style: SmokeType.bodySm.copyWith(color: t.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _presetCard(BuildContext context, CookPreset p) {
    final selected = _preset?.id == p.id;
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
      child: SmokeCard(
        accent: selected ? StatusPalette.pit : null,
        onTap: () => setState(() {
          _refusal = '';
          _preset = p;
          _doneness = p.defaultDoneness;
          _applyPresetToJacks(p, p.defaultDoneness);
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.name, style: SmokeType.title.copyWith(color: t.textHi)),
            const SizedBox(height: 2),
            Text(
              p.blurb,
              style: SmokeType.bodySm.copyWith(color: t.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _applyPresetToJacks(CookPreset p, Doneness d) {
    final food = _jacks.where((j) => j.role == ProbeRole.food).toList();
    final target = food.isEmpty ? null : food.first;
    for (final j in _jacks) {
      if (j.role == ProbeRole.pit) {
        j.targetF10 = null;
      }
    }
    if (target != null) {
      target.targetF10 = d.targetF10;
      target.pullOffsetF10 = p.carryoverF10;
      target.label = p.name;
      target.hazard = p.hazard;
    }
  }

  Widget _donenessCard(BuildContext context, Doneness d) {
    final selected = _doneness?.id == d.id;
    final t = context.tokens;
    final preset = _preset!;
    final pull = preset.pullF10For(d);
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
      child: SmokeCard(
        raised: selected,
        accent: selected ? StatusPalette.pit : null,
        onTap: () => setState(() {
          _refusal = '';
          _doneness = d;
          _applyPresetToJacks(preset, d);
        }),
        child: Row(
          children: [
            Expanded(
              child: Text(
                d.label,
                style: SmokeType.title.copyWith(color: t.textHi),
              ),
            ),
            Text(
              'Target ${formatSetpoint(d.targetF10, celsius: widget.celsius)}'
              '${pull < d.targetF10 ? ' · Pull ${formatSetpoint(pull, celsius: widget.celsius)}' : ''}',
              style: SmokeType.bodySm.copyWith(color: t.textBody),
            ),
          ],
        ),
      ),
    );
  }

  /// §D.4's probe mapping. Four rows, always — a jack that vanishes reads as an
  /// app bug rather than an empty socket, which is the same rule the reader
  /// holds for detached probes.
  Widget _jackRow(BuildContext context, _JackDraft d) {
    final t = context.tokens;
    final name = widget.probeNames[d.jack] ?? 'Probe ${d.jack}';
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
      child: SmokeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: ProbePalette.hue(d.jack),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: SmokeTokens.s2),
                Expanded(
                  child: Text(
                    name,
                    style: SmokeType.title.copyWith(color: t.textHi),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SmokeTokens.s2),
            SegmentedChips<ProbeRole>(
              options: const [
                ChipOption(ProbeRole.pit, 'Pit'),
                ChipOption(ProbeRole.food, 'Food'),
                ChipOption(ProbeRole.ambient, 'Ambient'),
                ChipOption(ProbeRole.unused, 'Not used'),
              ],
              value: d.role,
              onChanged: (r) => setState(() {
                _refusal = '';
                // At most one pit: a second one would make the band ambiguous
                // and the gauge pick arbitrarily.
                if (r == ProbeRole.pit) {
                  for (final other in _jacks) {
                    if (other.jack != d.jack && other.role == ProbeRole.pit) {
                      other.role = ProbeRole.food;
                    }
                  }
                }
                d.role = r;
                if (r != ProbeRole.food) {
                  d.targetF10 = null;
                }
              }),
            ),
            if (d.role == ProbeRole.food) ...[
              const SizedBox(height: SmokeTokens.s2),
              _targetField(context, d),
            ],
          ],
        ),
      ),
    );
  }

  /// The number the field starts with, with no unit suffix — a text input
  /// pre-filled with "203°F" is a text input the next keystroke corrupts.
  String _plainSetpoint(int f10) {
    final v = widget.celsius ? (f10 / 10 - 32) * 5 / 9 : f10 / 10;
    return v.round().toString();
  }

  Widget _targetField(BuildContext context, _JackDraft d) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            key: Key('target-${d.jack}'),
            initialValue: d.targetF10 == null
                ? ''
                : _plainSetpoint(d.targetF10!),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: SmokeType.body.copyWith(color: t.textHi),
            decoration: InputDecoration(
              labelText: 'Target (°${widget.celsius ? 'C' : 'F'})',
              // Empty is a real answer, not an incomplete form: §D.3 makes
              // "no target yet" a state the cook is allowed to live in.
              helperText: 'Leave blank to set it later',
              helperStyle: SmokeType.labelSm.copyWith(color: t.textMuted),
            ),
            onChanged: (v) {
              _refusal = '';
              final parsed = double.tryParse(v.trim());
              d.targetF10 = parsed == null
                  ? null
                  : (widget.celsius
                        ? ((parsed * 9 / 5 + 32) * 10).round()
                        : (parsed * 10).round());
            },
          ),
        ),
        if ((d.hazard ?? _hazard) == HazardClass.wholeMuscleRedMeat) ...[
          const SizedBox(width: SmokeTokens.s3),
          Tooltip(
            message: intactCutAdvisory,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Intact cut',
                  style: SmokeType.labelSm.copyWith(color: t.textMuted),
                ),
                Switch(
                  value: d.isIntact,
                  onChanged: (v) => setState(() {
                    _refusal = '';
                    d.isIntact = v;
                  }),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// §D.4's two labelled modes plus the raw-meat strip MEATER carries. The
  /// mode picker only appears where it can actually change an outcome — on
  /// poultry, ground, pork and fish the two modes are identical, and offering a
  /// choice that does nothing is a dead control.
  Widget _safetySection(SmokeTokens t) {
    final anyRedMeat = _jacks.any(
      (d) =>
          d.role == ProbeRole.food &&
          (d.hazard ?? _hazard) == HazardClass.wholeMuscleRedMeat,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (anyRedMeat) ...[
          _sectionLabel(t, 'Safe minimum'),
          SegmentedChips<SafetyMode>(
            options: [
              for (final m in SafetyMode.values) ChipOption(m, m.label),
            ],
            value: _mode,
            onChanged: (m) => setState(() {
              _refusal = '';
              _mode = m;
            }),
          ),
          const SizedBox(height: SmokeTokens.s2),
          Text(
            _mode.blurb,
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: SmokeTokens.s2),
          Text(
            intactCutAdvisory,
            style: SmokeType.labelSm.copyWith(color: t.textMuted),
          ),
        ],
        const SizedBox(height: SmokeTokens.s3),
        Text(
          rawMeatAdvisory,
          style: SmokeType.labelSm.copyWith(color: t.textMuted),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      SmokeTokens.s4,
      SmokeTokens.s2,
      SmokeTokens.s4,
      SmokeTokens.s4 + MediaQuery.of(context).padding.bottom,
    ),
    child: PrimaryAction(
      label: _editing ? 'Save changes' : 'Start the cook',
      icon: _editing ? Icons.check_rounded : Icons.play_arrow_rounded,
      onPressed: _start,
    ),
  );

  /// The "start it now, decide later" exit: a cook with roles and no targets.
  void _startBlank() {
    final plan = CookPlan(
      presetId: 'custom',
      title: 'Cook',
      hazard: HazardClass.wholeMuscleRedMeat,
      doneness: '',
      safetyMode: _mode,
      probes: [
        for (final d in _jacks)
          if (d.role != ProbeRole.unused)
            PlanProbe(
              jack: d.jack,
              isPit: d.role == ProbeRole.pit,
              role: d.role,
              name: widget.probeNames[d.jack] ?? '',
            ),
      ],
    );
    plan.startedUnixMs = DateTime.now().millisecondsSinceEpoch;
    Navigator.of(context).pop(plan);
  }

  void _start() {
    final preset = _preset;
    final doneness = _doneness;
    final title = preset != null && doneness != null
        ? '${preset.name} — ${doneness.label}'
        : (widget.initial?.title ?? 'Cook');
    try {
      final plan = CookPlan(
        presetId: preset?.id ?? 'custom',
        title: title,
        hazard: _hazard,
        doneness: doneness?.label ?? widget.initial?.doneness ?? '',
        safetyMode: _mode,
        pitBandMinF10: preset?.pitBandMinF10 ?? widget.initial?.pitBandMinF10,
        pitBandMaxF10: preset?.pitBandMaxF10 ?? widget.initial?.pitBandMaxF10,
        probes: [
          for (final d in _jacks)
            if (d.role != ProbeRole.unused)
              PlanProbe(
                jack: d.jack,
                isPit: d.role == ProbeRole.pit,
                role: d.role,
                name: d.label.isNotEmpty
                    ? d.label
                    : (widget.probeNames[d.jack] ??
                          (d.role == ProbeRole.pit ? 'Pit' : '')),
                targetF10: d.targetF10,
                pullF10: d.targetF10 == null
                    ? null
                    : d.targetF10! - d.pullOffsetF10,
                hazard: d.hazard,
                isIntact: d.isIntact,
                doneness: doneness?.label ?? '',
              ),
        ],
      );
      plan.startedUnixMs =
          widget.initial?.startedUnixMs != null &&
              widget.initial!.startedUnixMs > 0
          ? widget.initial!.startedUnixMs
          : DateTime.now().millisecondsSinceEpoch;
      plan.cookId = widget.initial?.cookId;
      Navigator.of(context).pop(plan);
    } on ArgumentError catch (e) {
      // The gate refused. Copy over error: the sheet stays open with the
      // reason on it, because "that chicken breast target is unsafe" is
      // information, and a dialog that dismisses it is not.
      setState(() => _refusal = e.message?.toString() ?? '');
    }
  }
}
