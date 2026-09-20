/// The `/cooks` list itself (16 §16.5, §16.6; newapp §C.3).
///
/// Stateless over plain values, so the real list renders in a widget test with
/// no repository, no `AppEnv` and no transport behind it — which is also the
/// screen's acceptance test, since `/cooks` is cache-only and must work with
/// the bridge unplugged.
///
/// **The layout decisions worth defending:**
///
///  * one [SmokeCard] per *section*, not per row (§16.5 — "never one card per
///    row"). A stack of floating cards reads as a stack of unrelated things;
///    a labelled card of divided rows reads as a history;
///  * the open cook gets the accent card, which is the one sanctioned use of a
///    series hue as a card border ("the active-cook header"), so the thing
///    still happening is never something you scroll for;
///  * the row's third line is a **sparkline in the pit hue, or nothing**. A
///    cook with no readings draws no line, because a flat line is a claim that
///    the temperature held steady;
///  * every part of the meta line that cannot be computed honestly is absent,
///    not zero: no peak means no "peak" segment, no readings means a sentence.
///
/// **Every row now leads with a [FoodAvatar]** (17 §17.3 A). MEATER puts a
/// circular animal glyph on every previous-cook row (`Meater-2`) and TempPro a
/// photograph on every profile row; this list had a name, a meta line and a
/// grey sparkline, and scanning it for *"the brisket from last Sunday"* meant
/// reading. The avatar is the identity channel (§17.2) — it says what was
/// cooked and never anything about how it went, which is what makes a saturated
/// fill legal on a screen whose colour rules are otherwise this strict.
library;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/design.dart';
import '../../domain/plan/plan.dart';
import '../../ui/probe/food_avatar.dart';
import '../../ui/ui.dart';
import 'cook_list_model.dart';

class CooksListView extends StatelessWidget {
  const CooksListView({
    required this.sections,
    this.celsius = false,
    this.selectedId,
    this.onOpen,
    this.nowUnixMs,
    super.key,
  });

  final List<CookSection> sections;
  final bool celsius;

  /// The row showing in the detail pane on a window wide enough to have one.
  /// Null on compact, where opening a cook is a navigation and there is no
  /// standing selection to show.
  final int? selectedId;

  final ValueChanged<CookAnnotation>? onOpen;

  /// Injected so a test can pin "so far" and "starts in" without waiting.
  final int? nowUnixMs;

  @override
  Widget build(BuildContext context) {
    final now = nowUnixMs ?? DateTime.now().millisecondsSinceEpoch;
    final t = context.tokens;
    return ListView.builder(
      key: const Key('cooks-list'),
      padding: const EdgeInsets.fromLTRB(
        SmokeTokens.s4,
        0,
        SmokeTokens.s4,
        SmokeTokens.s6,
      ),
      itemCount: sections.length,
      itemBuilder: (context, i) {
        final section = sections[i];
        final isOpen =
            section.group == CookGroup.running ||
            section.group == CookGroup.scheduled;
        return Padding(
          padding: EdgeInsets.only(
            top: i == 0 ? SmokeTokens.s2 : SmokeTokens.s5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: SmokeTokens.s1,
                  bottom: SmokeTokens.s2,
                ),
                child: Text(
                  section.group.label,
                  key: Key('cooks-section-${section.group.name}'),
                  style: SmokeType.label.copyWith(color: t.textMuted),
                ),
              ),
              SmokeCard(
                padding: EdgeInsets.zero,
                accent: isOpen ? StatusPalette.pit : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var r = 0; r < section.rows.length; r++) ...[
                      if (r > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          indent: SmokeTokens.s4,
                          endIndent: SmokeTokens.s4,
                          color: t.hairlineStrong,
                        ),
                      CookRowTile(
                        row: section.rows[r],
                        celsius: celsius,
                        nowUnixMs: now,
                        selected: section.rows[r].cook.id == selectedId,
                        onTap: onOpen == null
                            ? null
                            : () => onOpen!(section.rows[r].cook),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One cook: name · date · duration · peak · probes · sparkline (§16.6).
class CookRowTile extends StatelessWidget {
  const CookRowTile({
    required this.row,
    required this.nowUnixMs,
    this.celsius = false,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final CookListRow row;
  final int nowUnixMs;
  final bool celsius;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cook = row.cook;
    final status = cook.statusAt(nowUnixMs);
    final showPill = status != CookStatus.finished;
    final large = SmokeTextScale.isLarge(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: Key('cook-row-${cook.id}'),
        onTap: onTap,
        child: Container(
          // Comfortably past the 52 dp floor: this row carries three facts and
          // a mark, and cramming them would make the list unscannable at the
          // one moment it matters, which is at a glance.
          constraints: const BoxConstraints(minHeight: 52),
          color: selected ? t.cardRaised : null,
          padding: const EdgeInsets.symmetric(
            horizontal: SmokeTokens.s4,
            vertical: SmokeTokens.s3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // §17.3 A — the identity mark, and the reason this list is now
              // scannable rather than readable. Preset first, then the name the
              // user gave it, then the hazard class: see [FoodGlyph.forCook].
              FoodAvatar(
                key: Key('cook-avatar-${cook.id}'),
                glyph: FoodGlyph.forCook(
                  presetId: cook.presetId,
                  hazard: cook.hazard,
                  name: cook.name,
                ),
                size: 38,
                // §17.5, applied where it is most visible. A finished or
                // scheduled cook is **history or intent** — nothing on that row
                // claims a temperature, so it wears the rich register. The
                // recording one is live, so it cools. The list therefore shows
                // the transition rather than describing it: the cook you are
                // watching is the quiet one, and its section already carries an
                // accent border and a "Recording" pill so the difference is
                // never carried by saturation alone.
                vivid: status != CookStatus.running,
              ),
              const SizedBox(width: SmokeTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (cook.favourite) ...[
                          Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: t.textMuted,
                          ),
                          const SizedBox(width: SmokeTokens.s1),
                        ],
                        Expanded(
                          child: Text(
                            cook.displayName(),
                            style: SmokeType.title.copyWith(color: t.textHi),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // The pill rides the title until the row runs out of
                        // width, then stacks under it — §14.10's reflow ladder,
                        // and the avatar is what finally spent the 50 dp that
                        // used to make this fit at 200 % by luck.
                        if (showPill && !large) ...[
                          const SizedBox(width: SmokeTokens.s2),
                          CookStatusPill(status: status),
                        ],
                      ],
                    ),
                    if (showPill && large) ...[
                      const SizedBox(height: SmokeTokens.s1),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CookStatusPill(status: status),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      _meta(context, status),
                      style: SmokeType.bodySm.copyWith(color: t.textMuted),
                    ),
                    if (row.spark.hasLine) ...[
                      const SizedBox(height: SmokeTokens.s2),
                      SizedBox(
                        height: 22,
                        child: Sparkline(
                          key: Key('cook-spark-${cook.id}'),
                          points: row.spark.points,
                          // A mark, in the pit hue — never a fill, never a word.
                          color: ProbePalette.hue(1),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// date · duration · peak · probes. Anything the cache cannot answer is
  /// simply not in the sentence.
  String _meta(BuildContext context, CookStatus status) {
    final cook = row.cook;
    final summary = row.summary;
    final elapsedS = cook.elapsedMsAt(nowUnixMs) ~/ 1000;
    final parts = <String>[
      _when(cook.startUnixMs, status),
      switch (status) {
        CookStatus.scheduled => 'starts in '
            '${formatDuration((cook.startUnixMs - nowUnixMs) ~/ 1000)}',
        CookStatus.running => '${formatDuration(elapsedS)} so far',
        CookStatus.finished => formatDuration(elapsedS),
      },
      if (summary.peakF10 != null)
        'peak ${formatTemp(summary.peakF10, celsius: celsius)}',
      if (summary.count == 0)
        'no readings yet'
      else if (row.spark.probeCount == 0)
        'no probe plugged in'
      else
        '${row.spark.probeCount} '
            '${row.spark.probeCount == 1 ? 'probe' : 'probes'}',
    ];
    return parts.join(' · ');
  }

  /// Under "today" the date is already on screen, so the row shows the clock
  /// time and nothing else. Everywhere else it carries the full date.
  String _when(int unixMs, CookStatus status) {
    final now = DateTime.fromMillisecondsSinceEpoch(nowUnixMs);
    final at = DateTime.fromMillisecondsSinceEpoch(unixMs);
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    if (sameDay && status != CookStatus.scheduled) {
      return '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
    }
    return formatSessionDate(unixMs);
  }
}

/// "Recording" on the open annotation, "Scheduled" on one that has not begun.
///
/// Deliberately **not** "Cooking": an open cook only means the app is calling
/// this stretch of the recording by that name. The bridge records either way,
/// and claiming somebody is at the smoker is a claim the app cannot support.
class CookStatusPill extends StatelessWidget {
  const CookStatusPill({required this.status, super.key});

  final CookStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `positive` is transport health and nothing else, so a recording cook
    // wears the accent — the same hue the open section's card border wears.
    final role = status == CookStatus.running
        ? StatusRole.pit
        : StatusRole.info;
    final icon = status == CookStatus.running
        ? Icons.fiber_manual_record_rounded
        : Icons.schedule_rounded;
    return Container(
      key: Key('cook-status-${status.name}'),
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      decoration: BoxDecoration(
        color: StatusPalette.fill(role),
        borderRadius: BorderRadius.circular(SmokeTokens.radiusPill),
        border: Border.all(color: StatusPalette.border(role)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon and word together — a status hue never carries meaning alone.
          Icon(icon, size: 10, color: StatusPalette.hue(role)),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: SmokeType.labelSm.copyWith(color: t.textHi),
          ),
        ],
      ),
    );
  }
}
