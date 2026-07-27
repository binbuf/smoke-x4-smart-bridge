/// A22.3 — a minimal guided-cook setup sheet (design 13 §13.5.3).
///
/// The full three-page flow (cut → doneness → probe mapping) is W10. This is
/// the field-usable core: pick a category, a cut, a doneness, and it builds a
/// [CookPlan] that switches the Cook view into guided mode. Jack 1 is the pit
/// and jack 2 the primary food by convention — the probe-mapping page that
/// makes that configurable is deferred, not faked.
///
/// The plan is built through [CookPlan]'s constructor, so an unsafe target is a
/// thrown [ArgumentError] here too — but the presets never carry one, so a user
/// cannot reach that state from this sheet.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/plan/plan.dart';
import '../../ui/ui.dart';

/// Shows the sheet and returns the chosen plan, or null if dismissed.
Future<CookPlan?> showCookSetupSheet(
  BuildContext context, {
  bool celsius = false,
}) {
  return showModalBottomSheet<CookPlan>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Theme(
      data: SmokeTheme.dark,
      child: _CookSetupSheet(celsius: celsius),
    ),
  );
}

class _CookSetupSheet extends StatefulWidget {
  const _CookSetupSheet({required this.celsius});
  final bool celsius;

  @override
  State<_CookSetupSheet> createState() => _CookSetupSheetState();
}

class _CookSetupSheetState extends State<_CookSetupSheet> {
  String _category = Presets.categories.first;
  CookPreset? _preset;
  Doneness? _doneness;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final presets = Presets.inCategory(_category);
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
                Icon(Icons.bolt_rounded, color: StatusPalette.pit),
                const SizedBox(width: SmokeTokens.s2),
                Text(
                  'Set up a cook',
                  style: SmokeType.displayS.copyWith(color: t.textHi),
                ),
                const Spacer(),
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
                SegmentedChips<String>(
                  options: [
                    for (final c in Presets.categories) ChipOption(c, c),
                  ],
                  value: _category,
                  onChanged: (c) => setState(() {
                    _category = c;
                    _preset = null;
                    _doneness = null;
                  }),
                ),
                const SizedBox(height: SmokeTokens.s3),
                for (final p in presets) _presetCard(context, p),
                if (_preset != null) ...[
                  const SizedBox(height: SmokeTokens.s4),
                  Text(
                    'Doneness',
                    style: SmokeType.label.copyWith(color: t.textMuted),
                  ),
                  const SizedBox(height: SmokeTokens.s2),
                  for (final d in _preset!.doneness) _donenessCard(context, d),
                ],
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
              label: 'Start the cook',
              icon: Icons.play_arrow_rounded,
              onPressed: _preset != null && _doneness != null ? _start : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetCard(BuildContext context, CookPreset p) {
    final selected = _preset?.id == p.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
      child: SmokeCard(
        accent: selected ? StatusPalette.pit : null,
        onTap: () => setState(() {
          _preset = p;
          _doneness = p.defaultDoneness;
        }),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.name,
              style: SmokeType.title.copyWith(color: context.tokens.textHi),
            ),
            const SizedBox(height: 2),
            Text(
              p.blurb,
              style: SmokeType.bodySm.copyWith(color: context.tokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _donenessCard(BuildContext context, Doneness d) {
    final selected = _doneness?.id == d.id;
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
      child: SmokeCard(
        raised: selected,
        accent: selected ? StatusPalette.pit : null,
        onTap: () => setState(() => _doneness = d),
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
              '${d.restOffsetF10 > 0 ? ' · Pull ${formatSetpoint(d.pullF10, celsius: widget.celsius)}' : ''}',
              style: SmokeType.bodySm.copyWith(color: t.textBody),
            ),
          ],
        ),
      ),
    );
  }

  void _start() {
    final p = _preset!;
    final d = _doneness!;
    final plan = CookPlan(
      presetId: p.id,
      title: '${p.name} — ${d.label}',
      hazard: p.hazard,
      doneness: d.label,
      pitBandMinF10: p.pitBandMinF10,
      pitBandMaxF10: p.pitBandMaxF10,
      probes: [
        const PlanProbe(jack: 1, isPit: true, name: 'Pit'),
        PlanProbe(
          jack: 2,
          isPit: false,
          name: p.name,
          targetF10: d.targetF10,
          pullF10: d.pullF10,
        ),
      ],
    );
    Navigator.of(context).pop(plan);
  }
}
