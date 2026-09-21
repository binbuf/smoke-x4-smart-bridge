/// N9.17/N9.18 — the custom-food form.
///
/// A user-defined cut: identity (name, category, glyph), food-safety class and
/// thickness, pit band, final target, rest and cook range, and the optional
/// wrap/spritz steps. On save the food is written to [AppSettings.customCatalog]
/// with its own [CookTimeline] (bypassing the catalog's timeline table) and the
/// setup sheet reopens on it.
///
/// **I12:** a target below its hazard's floor is refused before it is stored —
/// the same gate a catalog rung runs through, with the floor's own words.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/app_settings.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../shell/shell.dart';
import 'setup_format.dart';

class CustomFoodSheetBody extends ConsumerStatefulWidget {
  const CustomFoodSheetBody({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<CustomFoodSheetBody> createState() =>
      _CustomFoodSheetBodyState();
}

/// The thickness options the form offers (the prototype's three).
const List<CutThickness> _thicknesses = <CutThickness>[
  CutThickness.thin,
  CutThickness.medium,
  CutThickness.thick,
];

class _CustomFoodSheetBodyState extends ConsumerState<CustomFoodSheetBody> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _pitLo = TextEditingController(text: '225');
  final TextEditingController _pitHi = TextEditingController(text: '275');
  final TextEditingController _target = TextEditingController(text: '145');
  final TextEditingController _rest = TextEditingController(text: '10');
  final TextEditingController _totalLo = TextEditingController(text: '60');
  final TextEditingController _totalHi = TextEditingController(text: '120');
  final TextEditingController _wrap = TextEditingController(text: '0');
  final TextEditingController _spritz = TextEditingController(text: '0');

  String _category = 'Beef';
  String _glyph = 'beef';
  HazardClass _hazard = HazardClass.wholeMuscleRedMeat;
  CutThickness _thickness = CutThickness.medium;
  String? _error;

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _name,
      _pitLo,
      _pitHi,
      _target,
      _rest,
      _totalLo,
      _totalHi,
      _wrap,
      _spritz,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController controller, int fallback) =>
      int.tryParse(controller.text.trim()) ?? fallback;

  Future<void> _save() async {
    final scope = ShellScope.maybeOf(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give it a name');
      return;
    }
    final targetF10 = _int(_target, 145) * 10;
    final refusal = customTargetRefusal(
      hazard: _hazard,
      targetF10: targetF10,
      thickness: _thickness,
    );
    if (refusal != null) {
      setState(() => _error = refusal);
      return;
    }

    final now = ref.read(shellClockProvider).millisecondsSinceEpoch;
    final food = customFoodFromForm(
      id: 'custom_$now',
      name: name,
      category: _category,
      glyph: _glyph,
      hazard: _hazard,
      thickness: _thickness,
      pitLoF: _int(_pitLo, 225),
      pitHiF: _int(_pitHi, 275),
      targetF: _int(_target, 145),
      restMin: _int(_rest, 10),
      totalLoMin: _int(_totalLo, 60),
      totalHiMin: _int(_totalHi, 120),
      wrapF: _int(_wrap, 0),
      spritzMin: _int(_spritz, 0),
    );
    await ref
        .read(prefsProvider)
        .update(
          (settings) => settings.copyWith(
            customCatalog: <CustomFood>[...settings.customCatalog, food],
          ),
        );
    scope?.showToast('Added $name to the catalog');
    widget.onDone();
    scope?.openOverlay(DevOverlay.setup, <String, String>{'food': food.id});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final categories = ref.watch(bridgeRepositoryProvider).catalog.categories;

    return Column(
      key: const ValueKey<String>('custom-food-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CapabilityNotice(
          message:
              'Custom foods live alongside the built-in catalog. Give it a '
              'target and an expected timeline and the app will plan around it.',
        ),
        const SizedBox(height: 14),
        _FieldLabel(label: 'Name'),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey<String>('custom-food-name'),
          controller: _name,
          style: SmokeText.body.copyWith(color: tokens.textHi),
          decoration: _decoration(tokens, 'e.g. Smoked Lamb Ribs'),
        ),
        const SizedBox(height: 12),
        _FieldLabel(label: 'Category'),
        const SizedBox(height: 6),
        FilterChips<String>(
          key: const ValueKey<String>('custom-food-category'),
          options: <SmokeSegment<String>>[
            for (final category in categories)
              SmokeSegment<String>(value: category, label: category),
          ],
          value: _category,
          onChanged: (value) => setState(() => _category = value),
        ),
        const SizedBox(height: 12),
        _FieldLabel(label: 'Icon'),
        const SizedBox(height: 6),
        Wrap(
          key: const ValueKey<String>('custom-food-glyph'),
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final glyph in kCustomFoodGlyphs)
              _GlyphChip(
                key: ValueKey<String>('custom-food-glyph-$glyph'),
                glyph: glyph,
                selected: glyph == _glyph,
                onTap: () => setState(() => _glyph = glyph),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _FieldLabel(label: 'Hazard class'),
        const SizedBox(height: 6),
        FilterChips<HazardClass>(
          key: const ValueKey<String>('custom-food-hazard'),
          options: <SmokeSegment<HazardClass>>[
            for (final hazard in kCustomFoodHazards)
              SmokeSegment<HazardClass>(value: hazard, label: hazard.label),
          ],
          value: _hazard,
          onChanged: (value) => setState(() {
            _hazard = value;
            _error = null;
          }),
        ),
        const SizedBox(height: 12),
        _FieldLabel(label: 'Thickness'),
        const SizedBox(height: 6),
        FilterChips<CutThickness>(
          key: const ValueKey<String>('custom-food-thickness'),
          options: <SmokeSegment<CutThickness>>[
            for (final thickness in _thicknesses)
              SmokeSegment<CutThickness>(
                value: thickness,
                label: thickness.label,
              ),
          ],
          value: _thickness,
          onChanged: (value) => setState(() => _thickness = value),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _NumberField(
                key: const ValueKey<String>('custom-food-pit-lo'),
                label: 'Pit band low (°F)',
                controller: _pitLo,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _NumberField(
                key: const ValueKey<String>('custom-food-pit-hi'),
                label: 'Pit band high (°F)',
                controller: _pitHi,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _NumberField(
                key: const ValueKey<String>('custom-food-target'),
                label: 'Target final (°F)',
                controller: _target,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _NumberField(
                key: const ValueKey<String>('custom-food-rest'),
                label: 'Rest (min)',
                controller: _rest,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _NumberField(
                key: const ValueKey<String>('custom-food-total-lo'),
                label: 'Cook time low (min)',
                controller: _totalLo,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _NumberField(
                key: const ValueKey<String>('custom-food-total-hi'),
                label: 'Cook time high (min)',
                controller: _totalHi,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _NumberField(
                key: const ValueKey<String>('custom-food-wrap'),
                label: 'Wrap at (°F, 0 = never)',
                controller: _wrap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _NumberField(
                key: const ValueKey<String>('custom-food-spritz'),
                label: 'Spritz every (min, 0 = never)',
                controller: _spritz,
              ),
            ),
          ],
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const ValueKey<String>('custom-food-error'),
            style: SmokeText.label.copyWith(color: tokens.critical),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Expanded(
              child: PrimaryAction(
                key: const ValueKey<String>('custom-food-save'),
                label: 'Add to catalog',
                icon: SmokeGlyph.check,
                onPressed: _save,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SmokeButton(
                key: const ValueKey<String>('custom-food-cancel'),
                label: 'Cancel',
                variant: SmokeButtonVariant.ghost,
                onPressed: widget.onDone,
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _decoration(SmokeTokens tokens, String hint) =>
      InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: SmokeText.body.copyWith(color: tokens.textMuted),
        filled: true,
        fillColor: tokens.well,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radii.control),
          borderSide: BorderSide(color: tokens.hairlineStrong),
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Text(
      label,
      style: SmokeText.labelSm.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: tokens.textMuted,
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    super.key,
    required this.label,
    required this.controller,
  });

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _FieldLabel(label: label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: SmokeText.body.copyWith(color: tokens.textHi),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: tokens.well,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(tokens.radii.control),
              borderSide: BorderSide(color: tokens.hairlineStrong),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlyphChip extends StatelessWidget {
  const _GlyphChip({
    super.key,
    required this.glyph,
    required this.selected,
    required this.onTap,
  });

  final String glyph;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Material(
      color: selected ? tokens.tint(tokens.pit, 0.15) : tokens.cardSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radii.pill),
        side: BorderSide(
          color: selected ? tokens.tint(tokens.pit, 0.40) : tokens.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FoodAvatar(FoodGlyph.parse(glyph), size: FoodAvatarSize.sm),
              const SizedBox(width: 5),
              Text(
                glyph,
                style: SmokeText.label.copyWith(
                  fontSize: 11.5,
                  color: selected ? tokens.textHi : tokens.textBody,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
