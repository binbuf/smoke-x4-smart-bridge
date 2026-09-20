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
/// **The custom cook used to walk straight past the food-safety gate**, which
/// is the one bug in this file that could have hurt somebody. "Something else"
/// cleared the preset, nothing else on the sheet could set a hazard class, and
/// the fallback was whole-muscle red meat — the single class with no floor. So
/// chicken thighs at 140 °F built without a word. Three things close it, and
/// they are deliberately three rather than one:
///
///  1. every food jack carries **its own hazard picker** (§D.4 asks for
///     "arbitrary per-jack role + target + pull offset + doneness, subject to
///     the gate"), and until a jack with a target has been answered the primary
///     action is disabled with its reason on screen;
///  2. a jack that reaches a plan without an answer is written as
///     [HazardClass.unstated], which carries the 160 °F ground-meat floor —
///     so no path that skips this sheet inherits the permissive default either;
///  3. the gate in [CookPlan]'s constructor still runs on every exit.
///
/// A refusal surfaces as copy on the sheet rather than as a thrown error the
/// user has to interpret.
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

  /// The target field's text. A controller rather than an `initialValue`
  /// because a preset *writes* this field: `initialValue` is read once, so
  /// picking "Texas brisket" used to leave the box empty while the draft
  /// carried 203 °F, and an empty box is a target the user believes is unset.
  final TextEditingController target = TextEditingController();

  /// What is on this jack.
  ///
  /// **Null is "not answered yet"**, which is a different thing from
  /// [HazardClass.unstated] ("asked, and declined to say"): the first disables
  /// the primary action, the second is an answer that costs the 160 °F floor.
  /// Null never reaches a plan — `_start` writes [HazardClass.unstated].
  HazardClass? hazard;

  /// How much mass the cut has, which is the only thing carryover depends on
  /// (§D.4). Null means "keep whatever offset this cook was saved with" — the
  /// state an edited plan opens in, because a stored offset is a fact and
  /// re-deriving it from a guessed thickness would silently move a pull
  /// temperature the user chose.
  CutThickness? thickness = CutThickness.thin;

  /// The offset an edited plan arrived with, tenths °F. Only consulted while
  /// [thickness] is null.
  int storedOffsetF10 = 0;

  bool isIntact = true;
  String label = '';

  /// The carry-over in force for this jack, tenths °F.
  int get carryoverF10 {
    final t = thickness;
    return t == null
        ? storedOffsetF10
        : carryoverF10For(hazard: hazard ?? HazardClass.unstated, thickness: t);
  }
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
        _setTarget(draft, p.targetF10);
        // Restore the offset verbatim and leave the thickness unanswered: the
        // stored pull was clamped against a floor, so reading a thickness back
        // out of it would be a guess, and a wrong guess here moves a real
        // temperature.
        draft.storedOffsetF10 = p.carryoverF10;
        draft.thickness = null;
        draft.isIntact = p.isIntact;
        draft.label = p.name;
        // A plan built before per-jack hazards existed has null here. It
        // inherits the plan's class only where it actually had a target —
        // that is the class it was gated under, and re-gating a saved cook
        // under a different one would be the app changing its mind. A jack
        // that never had a target was never gated at all, so it stays
        // unanswered and the primary action waits for an answer.
        draft.hazard =
            p.hazard ??
            (p.role == ProbeRole.food && p.targetF10 != null
                ? initial.hazard
                : null);
      }
      for (final d in _jacks) {
        if (initial.probes.every((p) => p.jack != d.jack)) {
          d.role = ProbeRole.unused;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final d in _jacks) {
      d.target.dispose();
    }
    super.dispose();
  }

  /// The plan-level class: the preset's, else the first food jack that has been
  /// answered, else [HazardClass.unstated].
  ///
  /// It used to fall back to [HazardClass.wholeMuscleRedMeat], which is the one
  /// class with no floor — so an unanswered custom cook was gated as steak.
  /// Every jack carries its own class now, and this is only the backstop for a
  /// jack that has none.
  HazardClass get _hazard {
    final preset = _preset?.hazard;
    if (preset != null) {
      return preset;
    }
    for (final d in _jacks) {
      if (d.role == ProbeRole.food && d.hazard != null) {
        return d.hazard!;
      }
    }
    return HazardClass.unstated;
  }

  /// The first food jack that has a target but no answer about what it is.
  /// Non-null means the primary action stays disabled, with this jack named.
  _JackDraft? get _unanswered {
    for (final d in _jacks) {
      if (d.role == ProbeRole.food &&
          d.targetF10 != null &&
          d.hazard == null) {
        return d;
      }
    }
    return null;
  }

  /// Every food jack that is claimed to be an intact whole-muscle cut — the one
  /// case where the app is trusting a fact about the meat it cannot measure,
  /// and so the only case where the mode picker changes an outcome.
  bool get _anyIntactRedMeat => _jacks.any(
    (d) =>
        d.role == ProbeRole.food &&
        d.hazard == HazardClass.wholeMuscleRedMeat &&
        d.isIntact,
  );

  String _jackName(_JackDraft d) =>
      widget.probeNames[d.jack] ?? 'Probe ${d.jack}';

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
                  ],
                  // Nothing is a category while the custom card is chosen, and
                  // a lit chip that does not describe the sheet is a lie.
                  value: _custom ? '' : _category,
                  onChanged: (c) => setState(() {
                    _refusal = '';
                    _custom = false;
                    _category = c;
                    _preset = null;
                    _doneness = null;
                  }),
                ),
                const SizedBox(height: SmokeTokens.s3),
                if (!_custom)
                  for (final p in Presets.inCategory(_category))
                    _presetCard(context, p),
                _customCard(t),
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
                    key: const Key('cook-setup-refusal'),
                    kind: InsightKind.stall,
                    icon: Icons.shield_outlined,
                    label: _refusal,
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
        // Expanded rather than a Spacer: at 200% text scale on a 360 dp phone
        // the title is wider than the row, and a title that overflows takes
        // the close button off the screen with it.
        Expanded(
          child: Text(
            _editing ? 'Edit this cook' : 'Set up a cook',
            overflow: TextOverflow.ellipsis,
            style: SmokeType.displayS.copyWith(color: t.textHi),
          ),
        ),
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

  Widget _fieldLabel(SmokeTokens t, String text) =>
      Text(text, style: SmokeType.label.copyWith(color: t.textMuted));

  Widget _note(SmokeTokens t, String text, {Key? key}) => Text(
    text,
    key: key,
    style: SmokeType.labelSm.copyWith(color: t.textMuted),
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

  /// The custom cook, as a card rather than a sixth chip.
  ///
  /// It was a chip in the category row until eggs joined the table (§D.4's
  /// sixth class), and six categories plus "Something else" is a row whose
  /// labels wrap at 360 dp — a chip you cannot read is a choice you cannot
  /// make. A card also matches what it is: a way out of the preset list, not
  /// another kind of meat.
  Widget _customCard(SmokeTokens t) => Padding(
    padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
    child: SmokeCard(
      key: const Key('cook-setup-custom'),
      accent: _custom ? StatusPalette.pit : null,
      onTap: () => setState(() {
        _refusal = '';
        _custom = true;
        _preset = null;
        _doneness = null;
      }),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, color: t.textBody),
          const SizedBox(width: SmokeTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Something else',
                  style: SmokeType.title.copyWith(color: t.textHi),
                ),
                const SizedBox(height: 2),
                Text(
                  'Set each probe yourself — what is on it, the target, and '
                  'how thick the cut is.',
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
        key: Key('preset-${p.id}'),
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
        _setTarget(j, null);
      }
    }
    if (target != null) {
      _setTarget(target, d.targetF10);
      target.thickness = p.thickness;
      target.isIntact = p.isIntact;
      target.label = p.name;
      target.hazard = p.hazard;
    }
  }

  /// Writes a target into both the draft and the box the user reads it in.
  void _setTarget(_JackDraft d, int? f10) {
    d.targetF10 = f10;
    final text = f10 == null ? '' : _plainSetpoint(f10);
    if (d.target.text != text) {
      d.target.text = text;
    }
  }

  Widget _donenessCard(BuildContext context, Doneness d) {
    final selected = _doneness?.id == d.id;
    final t = context.tokens;
    final preset = _preset!;
    final pull = preset.pullF10For(d, mode: _mode);
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
      child: SmokeCard(
        key: Key('doneness-${d.id}'),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: SmokeTokens.s2),
      child: SmokeCard(
        key: Key('jack-${d.jack}'),
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
                    _jackName(d),
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
                  _setTarget(d, null);
                }
              }),
            ),
            if (d.role == ProbeRole.food) ...[
              const SizedBox(height: SmokeTokens.s3),
              _hazardPicker(context, d),
              const SizedBox(height: SmokeTokens.s3),
              _targetField(context, d),
              // Thickness only once the class is known: until then there is no
              // floor to clamp the offset against, so the control could not
              // tell the truth about where the food would come off.
              if (d.hazard != null) ...[
                const SizedBox(height: SmokeTokens.s3),
                _carryoverPicker(context, d),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// §D.4 — the per-jack hazard class, which is what the gate actually reads.
  ///
  /// Every class is offered, including "Not stated": a custom cook may be
  /// something the table has no row for, and the honest answer to that is a
  /// floor, not a refusal to proceed. Choosing it costs the 160 °F ground-meat
  /// minimum, and the line underneath says so before it is chosen.
  Widget _hazardPicker(BuildContext context, _JackDraft d) {
    final t = context.tokens;
    final h = d.hazard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(t, 'What is on this probe?'),
        const SizedBox(height: SmokeTokens.s2),
        Wrap(
          spacing: SmokeTokens.s2,
          runSpacing: SmokeTokens.s2,
          children: [
            for (final c in HazardClass.values)
              ChoiceChip(
                key: Key('hazard-${d.jack}-${c.name}'),
                label: Text(c.label),
                selected: h == c,
                onSelected: (_) => setState(() {
                  _refusal = '';
                  d.hazard = c;
                }),
              ),
          ],
        ),
        const SizedBox(height: SmokeTokens.s2),
        _note(t, _floorLine(d), key: Key('floor-${d.jack}')),
        if (h == HazardClass.wholeMuscleRedMeat) ...[
          const SizedBox(height: SmokeTokens.s2),
          // The switch's own explanation, not the strip's sentence — the strip
          // owns `intactCutAdvisory` and prints it once, lower down.
          Row(
            children: [
              Expanded(
                child: _note(
                  t,
                  'Intact means whole-muscle and un-needled. If this cut was '
                  'tenderized or injected, turn this off: it then takes the '
                  '160°F ground-meat minimum.',
                ),
              ),
              const SizedBox(width: SmokeTokens.s3),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Intact cut',
                    style: SmokeType.labelSm.copyWith(color: t.textMuted),
                  ),
                  Switch(
                    key: Key('intact-${d.jack}'),
                    value: d.isIntact,
                    onChanged: (v) => setState(() {
                      _refusal = '';
                      d.isIntact = v;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The sentence under the hazard chips: what minimum is now in force, and
  /// where it comes from.
  String _floorLine(_JackDraft d) {
    final h = d.hazard;
    if (h == null) {
      return 'Pick one. The safe minimum for this probe depends on it.';
    }
    final floor = SafetyFloor.forClass(h, isIntact: d.isIntact, mode: _mode);
    if (floor == null) {
      return 'No fixed minimum on an intact cut — its interior is sterile, so '
          'doneness is yours to choose.';
    }
    final rest = floor.restMinutes > 0
        ? ' Rest it ${floor.restMinutes} minutes after it comes off.'
        : '';
    return 'Safe minimum '
        '${formatSetpoint(floor.minF10, celsius: widget.celsius)}'
        '${floor.source == null ? '' : ' — ${floor.source}'}.$rest';
  }

  /// The number the field starts with, with no unit suffix — a text input
  /// pre-filled with "203°F" is a text input the next keystroke corrupts.
  String _plainSetpoint(int f10) {
    final v = widget.celsius ? (f10 / 10 - 32) * 5 / 9 : f10 / 10;
    return v.round().toString();
  }

  Widget _targetField(BuildContext context, _JackDraft d) {
    final t = context.tokens;
    return TextFormField(
      key: Key('target-${d.jack}'),
      controller: d.target,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: SmokeType.body.copyWith(color: t.textHi),
      decoration: InputDecoration(
        labelText: 'Target (°${widget.celsius ? 'C' : 'F'})',
        // Empty is a real answer, not an incomplete form: §D.3 makes
        // "no target yet" a state the cook is allowed to live in.
        helperText: 'Leave blank to set it later',
        helperStyle: SmokeType.labelSm.copyWith(color: t.textMuted),
      ),
      onChanged: (v) => setState(() {
        _refusal = '';
        final parsed = double.tryParse(v.trim());
        // Not `_setTarget`: writing the controller back mid-keystroke would
        // fight the cursor. The draft follows the box here, not the other way.
        d.targetF10 = parsed == null
            ? null
            : (widget.celsius
                  ? ((parsed * 9 / 5 + 32) * 10).round()
                  : (parsed * 10).round());
      }),
    );
  }

  /// §D.4's pull offset, asked as the question that has an answer.
  ///
  /// The user is never asked "how many degrees early?" — carryover is a
  /// property of the mass, and AmazingRibs measures it that way (a 1″ steak
  /// gains "a degree or two", a 4–6″ prime rib gains 5–10 °F). So the control
  /// is thickness, and the degrees are derived. Poultry has no control at all,
  /// with the reason on screen: USDA is explicit that carryover cannot be
  /// relied on to finish an under-cooked bird, so 165 °F is read, not predicted.
  Widget _carryoverPicker(BuildContext context, _JackDraft d) {
    final t = context.tokens;
    if (d.hazard == HazardClass.poultry) {
      return _note(
        t,
        'Poultry does not come off early. Carryover cannot be relied on to '
        'finish an under-cooked bird, so the app waits for the probe to read '
        'the target.',
        key: Key('carryover-${d.jack}'),
      );
    }
    return Column(
      key: Key('carryover-${d.jack}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(t, 'How thick is the cut?'),
        const SizedBox(height: SmokeTokens.s2),
        SegmentedChips<CutThickness?>(
          options: [
            for (final c in CutThickness.values) ChipOption(c, c.label),
          ],
          value: d.thickness,
          onChanged: (c) => setState(() {
            _refusal = '';
            d.thickness = c;
          }),
        ),
        const SizedBox(height: SmokeTokens.s2),
        _note(t, _carryoverLine(d)),
      ],
    );
  }

  String _carryoverLine(_JackDraft d) {
    final thickness = d.thickness;
    final target = d.targetF10;
    final blurb = thickness == null
        ? 'Keeping the pull temperature this cook was saved with.'
        : thickness.blurb;
    if (target == null) {
      return '$blurb Set a target and the pull temperature follows.';
    }
    final pull = _pullF10(d);
    if (pull >= target) {
      return '$blurb It comes off at '
          '${formatSetpoint(target, celsius: widget.celsius)}, with nothing '
          'held back.';
    }
    return '$blurb Pull at '
        '${formatSetpoint(pull, celsius: widget.celsius)}, '
        '${((target - pull) / 10).round()}°F early.';
  }

  /// The pull temperature for a draft — floor-clamped, so an offset can never
  /// take a cut off the heat below its own safe minimum.
  int _pullF10(_JackDraft d) => safePullF10(
    targetF10: d.targetF10 ?? 0,
    carryoverF10: d.carryoverF10,
    hazard: d.hazard ?? HazardClass.unstated,
    isIntact: d.isIntact,
    mode: _mode,
  );

  /// §D.4's two labelled modes plus the raw-meat strip MEATER carries. The
  /// mode picker only appears where it can actually change an outcome — on
  /// poultry, ground, pork, fish and eggs the two modes are identical, and
  /// offering a choice that does nothing is a dead control.
  Widget _safetySection(SmokeTokens t) {
    final intactRedMeat = _anyIntactRedMeat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (intactRedMeat) ...[
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
        ],
        const SizedBox(height: SmokeTokens.s3),
        // The strip, from the one place that owns its words (§D.4, §J3).
        // `/live`'s guided overlay and `/cooks/:id` render the same list.
        Column(
          key: const Key('cook-setup-safety-strip'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in safetyStripFor(intactRedMeat: intactRedMeat))
              Padding(
                padding: const EdgeInsets.only(bottom: SmokeTokens.s1),
                child: _note(t, line),
              ),
          ],
        ),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    final t = context.tokens;
    final blocked = _unanswered;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SmokeTokens.s4,
        SmokeTokens.s2,
        SmokeTokens.s4,
        SmokeTokens.s4 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // §16.7: no dead control. The button is disabled *and* says why, on
          // screen, naming the jack that is still unanswered.
          if (blocked != null) ...[
            _note(
              t,
              'Say what is on ${_jackName(blocked)} before you start — its '
              'safe minimum depends on it.',
              key: const Key('cook-setup-blocked'),
            ),
            const SizedBox(height: SmokeTokens.s2),
          ],
          PrimaryAction(
            key: const Key('cook-setup-start'),
            label: _editing ? 'Save changes' : 'Start the cook',
            icon: _editing ? Icons.check_rounded : Icons.play_arrow_rounded,
            onPressed: blocked == null ? _start : null,
          ),
        ],
      ),
    );
  }

  /// The "start it now, decide later" exit: a cook with roles and no targets.
  void _startBlank() {
    final plan = CookPlan(
      presetId: 'custom',
      title: 'Cook',
      // Nothing has been said about the food yet, and the class that says so
      // is [HazardClass.unstated] — not red meat, which would hand a later
      // retarget the one class with no floor.
      hazard: HazardClass.unstated,
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
                pullF10: d.targetF10 == null ? null : _pullF10(d),
                // A food jack always states a class. Null would fall back to
                // the plan's, and the plan's is the value this bug rode in on.
                hazard: d.role == ProbeRole.food
                    ? (d.hazard ?? HazardClass.unstated)
                    : d.hazard,
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
