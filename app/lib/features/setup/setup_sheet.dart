/// N9.1–N9.16, N9.19 — the catalog-as-setup flow.
///
/// This is the body behind `?overlay=setup`. It is one surface for the three
/// ways to start a cook (NOTES §5):
///
///  * **new** — pick category → cut → style → doneness → jack → reminders, then
///    start (or append, when a cook is already running — N9.19).
///  * **existing** — pick what is on the grill, confirm when it went on, and
///    pull the samples the bridge already recorded (N9.15).
///  * **watch** — instrument mode: no cook, no targets, no timers (N9.2).
///
/// It also owns the long-item guard (N9.14): an add whose expected finish is
/// more than 15 minutes after everything else asks first.
///
/// Invariants encoded here:
/// * **I5** — the primary is disabled with its reason on screen until a food is
///   picked; a busy jack states "(in use)".
/// * **I12** — a custom target below its hazard's floor is refused before it can
///   be started.
/// * **I14** — exactly one ember [PrimaryAction].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/model/app_settings.dart';
import '../../data/model/cook_state.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../../domain/domain.dart';
import '../live/live_format.dart';
import '../shell/overlay.dart';
import '../shell/shell.dart';
import '../shell/shell_screen.dart';
import '../temps/temps_format.dart';
import 'setup_format.dart';

/// The setup overlay body.
class SetupSheetBody extends ConsumerStatefulWidget {
  const SetupSheetBody({
    super.key,
    required this.onDone,
    this.addContext = false,
    this.initialJack,
    this.initialFoodId,
  });

  final VoidCallback onDone;

  /// True for `context=edit`: the copy reads "Add to cook" (N9.19).
  final bool addContext;

  /// The jack the caller already focused (N6's "Set a target").
  final ProbeJack? initialJack;

  /// A food to preselect — used when returning from the custom-food form.
  final String? initialFoodId;

  @override
  ConsumerState<SetupSheetBody> createState() => _SetupSheetBodyState();
}

/// Which anchor the `existing` mode uses for the backdated start.
enum _ExistingAnchor { bridge, custom }

/// The `I will set a time` offsets.
const List<({String label, int minutes})> _existingOffsets =
    <({String label, int minutes})>[
      (label: 'Just now', minutes: 0),
      (label: '30 min ago', minutes: 30),
      (label: '1 hour ago', minutes: 60),
      (label: '2 hours ago', minutes: 120),
    ];

class _SetupSheetBodyState extends ConsumerState<SetupSheetBody> {
  final TextEditingController _search = TextEditingController();

  SetupMode _mode = SetupMode.newCook;
  String _category = 'Beef';
  String _query = '';
  String? _selectedId;
  String? _styleId;
  String? _donenessId;
  late ProbeJack _jack;
  bool _wrap = false;
  bool _spritz = false;
  _ExistingAnchor _anchor = _ExistingAnchor.bridge;
  int _customOffsetMin = 0;

  @override
  void initState() {
    super.initState();
    _jack = widget.initialJack ?? ProbeJack.one;
    _selectedId = widget.initialFoodId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SetupFood> get _foods {
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    return setupFoods(
      catalog: ref.read(bridgeRepositoryProvider).catalog,
      customs: settings.customCatalog,
    );
  }

  SetupFood? get _selected => setupFoodById(_foods, _selectedId);

  List<CookStyle> _stylesFor(SetupFood? food) =>
      setupStylesFor(ref.read(bridgeRepositoryProvider).catalog, food);

  CookTimeline? _timelineFor(SetupFood food, CookStyle? style) =>
      style?.timeline ??
      food.customTimeline ??
      ref.read(bridgeRepositoryProvider).catalog.timelineFor(food.id);

  void _applySeed(SetupFood food, CookStyle? style) {
    final timeline = _timelineFor(food, style);
    _wrap = timeline?.wrap != null;
    _spritz = timeline?.spritzEveryMin != null;
  }

  void _pickFood(SetupFood food) {
    setState(() {
      _selectedId = food.id;
      _styleId = null;
      _donenessId = null;
      _applySeed(food, null);
    });
  }

  void _pickStyle(SetupFood food, CookStyle style) {
    setState(() {
      _styleId = style.id;
      _donenessId = null;
      _applySeed(food, style);
    });
  }

  Future<void> _start() async {
    final scope = ShellScope.maybeOf(context);
    final repo = ref.read(bridgeRepositoryProvider);
    final snapshot = ref.read(snapshotProvider).value;
    final cook = snapshot?.cook ?? const CookState();
    final now = ref.read(shellClockProvider).millisecondsSinceEpoch;

    if (_mode == SetupMode.watch) {
      scope?.showToast('Watching live — no cook set');
      widget.onDone();
      scope?.openScreen(ShellScreen.live);
      return;
    }

    final food = _selected;
    if (food == null) {
      return;
    }
    final style = setupStyleById(_stylesFor(food), _styleId);
    final timeline = _timelineFor(food, style);
    final summary = setupSummary(
      food: food,
      doneness: food.donenessById(_donenessId),
      style: style,
      timeline: timeline,
    );
    final explicitTimeline = food.isCustom
        ? food.customTimeline
        : style?.timeline;

    if (_mode == SetupMode.existing) {
      final pending = snapshot?.pendingSession;
      final adopting = pending != null;
      final startedAtMs = _anchor == _ExistingAnchor.custom
          ? now - _customOffsetMin * 60000
          : null;
      await repo.startCook(
        presetId: food.id,
        jack: _jack,
        styleId: _styleId,
        targetF10: summary.targetF10,
        pullF10: summary.pullF10,
        timeline: explicitTimeline,
        wrap: _wrap,
        spritz: _spritz,
        startedAtMs: startedAtMs,
        adoptPendingSession: adopting,
      );
      scope?.showToast(
        adopting
            ? 'Cook adopted · pulled ${pending.samples} samples'
            : '${food.name} added to the cook',
      );
      widget.onDone();
      scope?.openScreen(ShellScreen.live);
      return;
    }

    // new mode: the long-item guard asks first (N9.14).
    final delay = longItemDelayMin(
      cook: cook,
      food: food,
      nowMs: now,
      catalog: repo.catalog,
      timeline: timeline,
    );
    if (delay != null) {
      final go = await _confirmLongItem(food, summary, delay);
      if (go != true) {
        return;
      }
    }
    await repo.startCook(
      presetId: food.id,
      jack: _jack,
      styleId: _styleId,
      targetF10: summary.targetF10,
      pullF10: summary.pullF10,
      timeline: explicitTimeline,
      wrap: _wrap,
      spritz: _spritz,
    );
    scope?.showToast('${food.name} added to the cook');
    widget.onDone();
    scope?.openScreen(ShellScreen.live);
  }

  Future<bool?> _confirmLongItem(
    SetupFood food,
    SetupSummary summary,
    int delay,
  ) {
    final mid = summary.totalMin?.mid.round() ?? 0;
    return showModalCard(
      context,
      title: 'This will run long',
      confirmLabel: 'Add anyway',
      body: Text.rich(
        TextSpan(
          style: SmokeText.body.copyWith(
            color: SmokeTokens.of(context).textBody,
          ),
          children: <InlineSpan>[
            TextSpan(
              text: food.name,
              style: SmokeText.bodyStrong.copyWith(
                color: SmokeTokens.of(context).textHi,
              ),
            ),
            TextSpan(
              text: ' takes about $mid min, so it would finish roughly ',
            ),
            TextSpan(
              text: fmtDuration(delay * 60000),
              style: SmokeText.bodyStrong.copyWith(
                color: SmokeTokens.of(context).textHi,
              ),
            ),
            const TextSpan(
              text:
                  ' after everything else is already off the grill. '
                  'Add it to this cook?',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final unit =
        ref.watch(settingsProvider).value?.units ?? TempUnit.fahrenheit;
    final cook = ref.watch(snapshotProvider).value?.cook ?? const CookState();
    final food = _selected;
    final styles = _stylesFor(food);
    final style = setupStyleById(styles, _styleId);
    final timeline = food == null ? null : _timelineFor(food, style);
    final doneness = food?.donenessById(_donenessId);
    final summary = (food == null || doneness == null)
        ? null
        : setupSummary(
            food: food,
            doneness: doneness,
            style: style,
            timeline: timeline,
          );
    final refusal = food != null && food.isCustom && summary != null
        ? customTargetRefusal(hazard: food.hazard, targetF10: summary.targetF10)
        : null;

    final foods = _foods;
    final filtered = searchSetupFoods(
      foods,
      query: _query,
      category: _category,
    );
    final busy = busyJacks(cook, _selectedId);

    return Column(
      key: const ValueKey<String>('setup-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FilterChips<SetupMode>(
          key: const ValueKey<String>('setup-modes'),
          options: <SmokeSegment<SetupMode>>[
            for (final mode in SetupMode.values)
              SmokeSegment<SetupMode>(value: mode, label: mode.label),
          ],
          value: _mode,
          onChanged: (mode) => setState(() => _mode = mode),
        ),
        const SizedBox(height: 10),
        Text(
          _mode.sub,
          key: const ValueKey<String>('setup-mode-sub'),
          style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: 14),
        if (_mode == SetupMode.watch) ...<Widget>[
          CapabilityNotice(
            key: const ValueKey<String>('setup-watch-notice'),
            message:
                'No targets, no timers, no alarms. You will see live numbers '
                'and the graph. You can turn a cook on later without losing '
                'anything.',
          ),
          const SizedBox(height: 20),
        ] else ...<Widget>[
          if (_mode == SetupMode.existing) ...<Widget>[
            _ExistingSessionCard(
              anchor: _anchor,
              offsetMin: _customOffsetMin,
              onAnchor: (anchor) => setState(() => _anchor = anchor),
              onOffset: (minutes) => setState(() => _customOffsetMin = minutes),
            ),
            const SizedBox(height: 8),
          ],
          _CatalogPicker(
            foods: foods,
            filtered: filtered,
            query: _query,
            search: _search,
            category: _category,
            selectedId: _selectedId,
            unit: unit,
            styleCountOf: (food) => _stylesFor(food).length,
            onQuery: (value) => setState(() => _query = value),
            onClear: () => setState(() {
              _query = '';
              _search.clear();
            }),
            onCategory: (category) => setState(() {
              _category = category;
              _query = '';
              _search.clear();
              _selectedId = null;
              _styleId = null;
              _donenessId = null;
            }),
            onPick: _pickFood,
            onCustomFood: () =>
                ShellScope.maybeOf(context)?.openOverlay(DevOverlay.customFood),
          ),
          if (food != null) ...<Widget>[
            if (styles.isNotEmpty) ...<Widget>[
              SectionLabel(
                label: 'Preparation style',
                trailing: Text(
                  '${styles.length} ways to cook ${food.name}',
                  style: SmokeText.labelSm.copyWith(
                    fontSize: 10.5,
                    color: tokens.textMuted,
                  ),
                ),
              ),
              Text(
                'Same cut, different dish. Pick the one you are making — it '
                'sets the pit band, wrap, target, rest and timeline.',
                key: const ValueKey<String>('setup-styles-note'),
                style: SmokeText.labelSm.copyWith(
                  fontSize: 11,
                  color: tokens.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                key: const ValueKey<String>('setup-styles'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final item in styles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _StyleCard(
                        key: ValueKey<String>('setup-style-${item.id}'),
                        style: item,
                        selected: item.id == _styleId,
                        onTap: () => _pickStyle(food, item),
                      ),
                    ),
                ],
              ),
            ],
            if (food.doneness.length > 1) ...<Widget>[
              const SectionLabel(label: 'Doneness'),
              FilterChips<String>(
                key: const ValueKey<String>('setup-doneness'),
                options: <SmokeSegment<String>>[
                  for (final d in food.doneness)
                    SmokeSegment<String>(
                      value: d.id,
                      label: '${d.label} · ${fmtTempUnit(d.targetF10, unit)}',
                    ),
                ],
                value: food.donenessById(_donenessId).id,
                onChanged: (id) => setState(() => _donenessId = id),
              ),
            ],
            if (summary != null) ...<Widget>[
              const SizedBox(height: 14),
              _SummaryCard(summary: summary, unit: unit, style: style),
            ],
            const SectionLabel(label: 'Which probe?'),
            Wrap(
              key: const ValueKey<String>('setup-jacks'),
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final jack in ProbeJack.values)
                  _JackChip(
                    key: ValueKey<String>('setup-jack-${jack.n}'),
                    label: jackLabel(jack, busy: busy.contains(jack)),
                    selected: jack == _jack,
                    enabled: !busy.contains(jack),
                    onTap: () => setState(() => _jack = jack),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            CapabilityNotice(
              key: const ValueKey<String>('setup-jack-notice'),
              message:
                  'Jack 4 is the grate by default. Tap any jack to reassign it.',
            ),
            if (timeline != null &&
                (timeline.hasWrap ||
                    timeline.spritzEveryMin != null)) ...<Widget>[
              const SizedBox(height: 8),
              if (timeline.hasWrap)
                _ReminderRow(
                  key: const ValueKey<String>('setup-wrap-row'),
                  icon: SmokeGlyph.wrap,
                  name: 'Wrap reminder',
                  sub: timeline.wrap!.label.isEmpty
                      ? 'From the expected timeline'
                      : timeline.wrap!.label,
                  value: _wrap,
                  onChanged: (value) => setState(() => _wrap = value),
                ),
              if (timeline.spritzEveryMin != null)
                _ReminderRow(
                  key: const ValueKey<String>('setup-spritz-row'),
                  icon: SmokeGlyph.droplet,
                  name: 'Spritz every ${timeline.spritzEveryMin} min',
                  sub: 'From the expected timeline for ${food.name}',
                  value: _spritz,
                  onChanged: (value) => setState(() => _spritz = value),
                ),
            ],
          ],
        ],
        const SizedBox(height: 20),
        _PrimaryStart(
          mode: _mode,
          addContext: widget.addContext,
          hasFood: food != null,
          refusal: refusal,
          onPressed: _start,
        ),
        if (refusal != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              refusal,
              key: const ValueKey<String>('setup-safety-refusal'),
              textAlign: TextAlign.center,
              style: SmokeText.labelSm.copyWith(color: tokens.critical),
            ),
          ),
      ],
    );
  }
}

class _PrimaryStart extends StatelessWidget {
  const _PrimaryStart({
    required this.mode,
    required this.addContext,
    required this.hasFood,
    required this.refusal,
    required this.onPressed,
  });

  final SetupMode mode;
  final bool addContext;
  final bool hasFood;
  final String? refusal;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = mode == SetupMode.watch || (hasFood && refusal == null);
    final label = addContext && mode == SetupMode.newCook
        ? 'Add to cook'
        : mode.primaryLabel;
    return PrimaryAction(
      key: const ValueKey<String>('setup-start'),
      label: label,
      icon: switch (mode) {
        SetupMode.newCook => addContext ? SmokeGlyph.plus : SmokeGlyph.play,
        SetupMode.existing => SmokeGlyph.download,
        SetupMode.watch => SmokeGlyph.eye,
      },
      onPressed: enabled ? onPressed : null,
      enabledReason: enabled
          ? null
          : refusal ?? 'Pick a food above to continue',
    );
  }
}

/// N9.3 — the session-found card and the "when did it go on?" choice.
class _ExistingSessionCard extends ConsumerWidget {
  const _ExistingSessionCard({
    required this.anchor,
    required this.offsetMin,
    required this.onAnchor,
    required this.onOffset,
  });

  final _ExistingAnchor anchor;
  final int offsetMin;
  final ValueChanged<_ExistingAnchor> onAnchor;
  final ValueChanged<int> onOffset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SmokeTokens.of(context);
    final pending = ref.watch(snapshotProvider).value?.pendingSession;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CapabilityNotice(
          key: const ValueKey<String>('setup-existing-notice'),
          icon: SmokeGlyph.download,
          message:
              'The bridge has been recording without you. Pick what is on the '
              'grill and when it went on — we will pull the readings already '
              'collected and build the cook around them.',
        ),
        const SizedBox(height: 10),
        if (pending != null)
          SmokeCard(
            key: const ValueKey<String>('setup-existing-session'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _FactRow(
                  label: 'Session found',
                  value: pending.sessionId,
                  mono: true,
                ),
                const SizedBox(height: 6),
                _FactRow(
                  label: 'Started',
                  value:
                      '${fmtClock(DateTime.fromMillisecondsSinceEpoch(pending.startedAtMs))} '
                      '(${fmtDuration(ref.read(shellClockProvider).millisecondsSinceEpoch - pending.startedAtMs)} ago)',
                ),
                const SizedBox(height: 6),
                _FactRow(label: 'Samples', value: '${pending.samples}'),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'WHEN DID IT GO ON?',
          style: SmokeText.labelSm.copyWith(
            letterSpacing: 0.9,
            color: tokens.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        FilterChips<_ExistingAnchor>(
          key: const ValueKey<String>('setup-existing-when'),
          options: <SmokeSegment<_ExistingAnchor>>[
            SmokeSegment<_ExistingAnchor>(
              value: _ExistingAnchor.bridge,
              label: pending != null ? 'Bridge session start' : 'Just now',
            ),
            const SmokeSegment<_ExistingAnchor>(
              value: _ExistingAnchor.custom,
              label: 'I will set a time',
            ),
          ],
          value: anchor,
          onChanged: (value) => onAnchor(value),
        ),
        if (anchor == _ExistingAnchor.custom) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            key: const ValueKey<String>('setup-existing-offsets'),
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final offset in _existingOffsets)
                _JackChip(
                  key: ValueKey<String>(
                    'setup-existing-offset-${offset.minutes}',
                  ),
                  label: offset.label,
                  selected: offset.minutes == offsetMin,
                  enabled: true,
                  onTap: () => onOffset(offset.minutes),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// N9.4–N9.6 — search, category chips and the catalog tile grid.
class _CatalogPicker extends StatelessWidget {
  const _CatalogPicker({
    required this.foods,
    required this.filtered,
    required this.query,
    required this.search,
    required this.category,
    required this.selectedId,
    required this.unit,
    required this.styleCountOf,
    required this.onQuery,
    required this.onClear,
    required this.onCategory,
    required this.onPick,
    required this.onCustomFood,
  });

  final List<SetupFood> foods;
  final List<SetupFood> filtered;
  final String query;
  final TextEditingController search;
  final String category;
  final String? selectedId;
  final TempUnit unit;
  final int Function(SetupFood) styleCountOf;
  final ValueChanged<String> onQuery;
  final VoidCallback onClear;
  final ValueChanged<String> onCategory;
  final ValueChanged<SetupFood> onPick;
  final VoidCallback onCustomFood;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final q = query.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'WHAT ARE YOU COOKING?',
              style: SmokeText.labelSm.copyWith(
                letterSpacing: 0.9,
                color: tokens.textMuted,
              ),
            ),
            const Spacer(),
            Semantics(
              button: true,
              label: 'Custom food',
              child: InkWell(
                key: const ValueKey<String>('setup-custom-food'),
                onTap: onCustomFood,
                borderRadius: BorderRadius.circular(tokens.radii.control),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SmokeIcon(SmokeGlyph.plus, size: 12, color: tokens.pit),
                      const SizedBox(width: 4),
                      Text(
                        'Custom food',
                        style: SmokeText.label.copyWith(
                          fontSize: 12.5,
                          color: tokens.pit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey<String>('setup-catalog-search'),
          controller: search,
          onChanged: onQuery,
          style: SmokeText.body.copyWith(color: tokens.textHi),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search all foods — brisket, kalua, jerk, elote…',
            hintStyle: SmokeText.body.copyWith(color: tokens.textMuted),
            prefixIcon: SmokeIcon(
              SmokeGlyph.search,
              size: 16,
              color: tokens.textMuted,
            ),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey<String>('setup-catalog-clear'),
                    icon: SmokeIcon(
                      SmokeGlyph.x,
                      size: 14,
                      color: tokens.textMuted,
                    ),
                    onPressed: onClear,
                  ),
            filled: true,
            fillColor: tokens.well,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(tokens.radii.control),
              borderSide: BorderSide(color: tokens.hairlineStrong),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilterChips<String>(
          key: const ValueKey<String>('setup-categories'),
          options: <SmokeSegment<String>>[
            for (final category in _categories(foods))
              SmokeSegment<String>(value: category, label: category),
          ],
          value: q.isEmpty ? category : '',
          onChanged: onCategory,
        ),
        const SizedBox(height: 8),
        Text(
          q.isEmpty
              ? '${filtered.length} foods in $category'
              : '${filtered.length} '
                    '${filtered.length == 1 ? 'result' : 'results'} for “$q”',
          key: const ValueKey<String>('setup-catalog-count'),
          style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'No foods match that search.',
              key: const ValueKey<String>('setup-catalog-empty'),
              textAlign: TextAlign.center,
              style: SmokeText.sub.copyWith(color: tokens.textMuted),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 8.0;
              final width = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: <Widget>[
                  for (final food in filtered)
                    SizedBox(
                      width: width,
                      child: _CatalogTile(
                        key: ValueKey<String>('setup-food-${food.id}'),
                        food: food,
                        selected: food.id == selectedId,
                        unit: unit,
                        styleCount: styleCountOf(food),
                        onTap: () => onPick(food),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  static List<String> _categories(List<SetupFood> foods) {
    final seen = <String>[];
    for (final food in foods) {
      if (!seen.contains(food.category)) {
        seen.add(food.category);
      }
    }
    return seen;
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({
    super.key,
    required this.food,
    required this.selected,
    required this.unit,
    required this.styleCount,
    required this.onTap,
  });

  final SetupFood food;
  final bool selected;
  final TempUnit unit;
  final int styleCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Material(
      color: selected ? tokens.tint(tokens.pit, 0.12) : tokens.cardSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radii.control),
        side: BorderSide(
          color: selected ? tokens.tint(tokens.pit, 0.45) : tokens.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radii.control),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FoodAvatar(FoodGlyph.parse(food.glyph)),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      food.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SmokeText.bodyStrong.copyWith(
                        fontSize: 13,
                        color: tokens.textHi,
                      ),
                    ),
                  ),
                  if (food.isCustom) ...<Widget>[
                    const SizedBox(width: 4),
                    _Badge(label: 'Custom'),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                food.blurb,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SmokeText.labelSm.copyWith(
                  fontSize: 11,
                  color: tokens.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${fmtTempUnit(food.defaultDoneness.targetF10, unit)} · '
                'pit ${(food.pitBandMinF10 / 10).round()}–'
                '${(food.pitBandMaxF10 / 10).round()}°'
                '${styleCount > 0 ? ' · $styleCount styles' : ''}',
                key: ValueKey<String>('setup-food-meta-${food.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SmokeText.labelSm.copyWith(
                  fontSize: 10.5,
                  color: tokens.textBody,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.tint(tokens.pit, 0.14),
        borderRadius: BorderRadius.circular(tokens.radii.pill),
        border: Border.all(color: tokens.tint(tokens.pit, 0.35)),
      ),
      child: Text(
        label,
        style: SmokeText.labelSm.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: tokens.textHi,
        ),
      ),
    );
  }
}

/// N9.7 — a preparation-style card.
class _StyleCard extends StatelessWidget {
  const _StyleCard({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final CookStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Material(
      color: selected ? tokens.tint(tokens.pit, 0.12) : tokens.cardSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radii.control),
        side: BorderSide(
          color: selected ? tokens.tint(tokens.pit, 0.45) : tokens.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radii.control),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SmokeIcon(SmokeGlyph.utensils),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            style.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SmokeText.bodyStrong.copyWith(
                              fontSize: 13.5,
                              color: tokens.textHi,
                            ),
                          ),
                        ),
                        if (style.region.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 6),
                          _Badge(label: style.region),
                        ],
                      ],
                    ),
                    if (style.tagline.isNotEmpty)
                      Text(
                        style.tagline,
                        style: SmokeText.labelSm.copyWith(
                          fontSize: 11.5,
                          color: tokens.textBody,
                        ),
                      ),
                    if (style.note.isNotEmpty)
                      Text(
                        style.note,
                        style: SmokeText.labelSm.copyWith(
                          fontSize: 11,
                          color: tokens.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// N9.9 — the target/pull/rest/cook summary.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.unit,
    required this.style,
  });

  final SetupSummary summary;
  final TempUnit unit;
  final CookStyle? style;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return SmokeCard(
      key: const ValueKey<String>('setup-summary'),
      subtle: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _FactRow(
            key: const ValueKey<String>('setup-summary-target'),
            label: 'Target (after rest)',
            value: fmtTempUnit(summary.targetF10, unit),
            strong: true,
          ),
          if (summary.carryoverF10 > 0) ...<Widget>[
            const SizedBox(height: 6),
            _FactRow(
              key: const ValueKey<String>('setup-summary-pull'),
              label: 'Pull early by carryover',
              value:
                  '${fmtTempUnit(summary.pullF10, unit)} '
                  '(−${(summary.carryoverF10 / 10).round()}°)',
            ),
          ],
          const SizedBox(height: 6),
          _FactRow(
            key: const ValueKey<String>('setup-summary-rest'),
            label: 'Expected rest',
            value: '${summary.restMin} min',
          ),
          const SizedBox(height: 6),
          _FactRow(
            key: const ValueKey<String>('setup-summary-cook'),
            label: 'Expected cook',
            value: expectedCookLabel(summary.totalMin),
          ),
          if (style != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Style: ${style!.name}',
              key: const ValueKey<String>('setup-summary-style'),
              style: SmokeText.labelSm.copyWith(
                fontSize: 11,
                color: tokens.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool mono;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final valueStyle = mono
        ? SmokeText.monoValue.copyWith(fontSize: 13, color: tokens.textHi)
        : SmokeText.bodyStrong.copyWith(
            fontSize: 13,
            color: strong ? tokens.textHi : tokens.textBody,
          );
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: SmokeText.labelSm.copyWith(
              fontSize: 11.5,
              color: tokens.textMuted,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: valueStyle,
          ),
        ),
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    super.key,
    required this.icon,
    required this.name,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  final SmokeGlyph icon;
  final String name;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Row(
      children: <Widget>[
        SmokeIcon(icon, size: 17, color: tokens.textBody),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                name,
                style: SmokeText.bodyStrong.copyWith(
                  fontSize: 13,
                  color: tokens.textHi,
                ),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SmokeToggle(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// A single-select chip that can be individually disabled (busy jacks, N9.10).
class _JackChip extends StatelessWidget {
  const _JackChip({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: selected ? tokens.tint(tokens.pit, 0.15) : tokens.cardSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radii.pill),
          side: BorderSide(
            color: selected ? tokens.tint(tokens.pit, 0.40) : tokens.hairline,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(tokens.radii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: SmokeText.label.copyWith(
                fontSize: 12.5,
                color: selected ? tokens.textHi : tokens.textBody,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
