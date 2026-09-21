/// N3 — the component gallery (the epic's exit gate).
///
/// One screen that renders **every** primitive, so a golden can pin it in all
/// three theme combinations (dark/light/daylight) × both densities. It is a
/// catalogue, not a product screen, so the "one ember primary action per
/// screen" rule (I14) deliberately does not apply here — the gallery shows the
/// enabled, disabled and busy states side by side.
///
/// Every colour comes from [SmokeTokens] and every duration from
/// [SmokeMotion]; a layering test enforces that on the rest of the tree.
library;

import 'package:flutter/material.dart';

import 'atoms.dart';
import 'buttons.dart';
import 'card.dart';
import 'chips.dart';
import 'cost_sheet.dart';
import 'food_avatar.dart';
import 'icons.dart';
import 'indicators.dart';
import 'legend.dart';
import 'mono_well.dart';
import 'pulse.dart';
import 'rows.dart';
import 'states.dart';
import 'stats.dart';
import 'status.dart';
import 'text.dart';
import 'toggle.dart';
import 'tokens.dart';

void _noop() {}

/// The gallery screen.
class DesignGallery extends StatelessWidget {
  const DesignGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final gutter = tokens.density.pageGutter;
    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Design system',
                style: SmokeText.title.copyWith(color: tokens.textHi),
              ),
              Text(
                'Every primitive, dark / light / daylight, compact / comfortable.',
                style: SmokeText.sub.copyWith(color: tokens.textMuted),
              ),
              _section(context, 'Typography', _typography(context)),
              _section(context, 'Icons', _icons(context)),
              _section(context, 'Food avatars', _avatars(context)),
              _section(context, 'Cards', _cards(context)),
              _section(context, 'Buttons', _buttons(context)),
              _section(context, 'Chips', _chips(context)),
              _section(context, 'Rows & toggles', _rows(context)),
              _section(context, 'Atoms', _atoms(context)),
              _section(context, 'Chrome', _chrome(context)),
              _section(context, 'Indicators', _indicators(context)),
              _section(context, 'Banners', _banners(context)),
              _section(context, 'Mono well', _mono(context)),
              _section(context, 'States', _states(context)),
              _section(context, 'Stats', _stats(context)),
              _section(context, 'Legend', _legend(context)),
              _section(context, 'Cost sheet', _cost(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(label: title),
        child,
      ],
    );
  }

  Widget _typography(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    final styles = <String, TextStyle>{
      'heroTemp 96': SmokeText.heroTemp,
      'tempXl 52': SmokeText.tempXl,
      'tempLg 30': SmokeText.tempLg,
      'tempMd 26': SmokeText.tempMd,
      'gaugeValue 22': SmokeText.gaugeValue,
      'title 20': SmokeText.title,
      'cardTitle 15': SmokeText.cardTitle,
      'monoKey 34': SmokeText.monoKey,
      'monoValue 15': SmokeText.monoValue,
      'monoSmall 11': SmokeText.monoSmall,
      'body 14': SmokeText.body,
      'bodyStrong 14': SmokeText.bodyStrong,
      'sub 13': SmokeText.sub,
      'label 12': SmokeText.label,
      'labelSm 11': SmokeText.labelSm,
      'kicker 11': SmokeText.kicker,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final entry in styles.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${entry.key}  ·  ${entry.value.fontSize?.round()}°F',
              style: entry.value.copyWith(color: tokens.textHi),
            ),
          ),
        Text(
          'Reflow: ${SmokeTextScale.heroBase.round()} → '
          '${SmokeTextScale.heroDemoted.round()} hero, gauge '
          '${SmokeTextScale.gaugeBase.round()} → '
          '${SmokeTextScale.gaugeMin.round()} then dropped',
          style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }

  Widget _icons(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        for (final glyph in SmokeIcons.all)
          SizedBox(
            width: 30,
            height: 30,
            child: SmokeIcon(glyph, size: 22, color: tokens.textBody),
          ),
      ],
    );
  }

  Widget _avatars(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final glyph in FoodGlyph.values)
          FoodAvatar(glyph, size: FoodAvatarSize.sm),
        for (final glyph in <FoodGlyph>[
          FoodGlyph.brisket,
          FoodGlyph.fish,
          FoodGlyph.veg,
        ])
          FoodAvatar(glyph, register: FoodAvatarRegister.disciplined),
      ],
    );
  }

  Widget _cards(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SmokeCard(child: Text('Default card')),
        SmokeCard(
          subtle: true,
          margin: const EdgeInsets.only(top: 8),
          child: const Text('Subtle card'),
        ),
        SmokeCard(
          raised: true,
          margin: const EdgeInsets.only(top: 8),
          child: const Text('Raised card'),
        ),
        SmokeCard(
          inset: true,
          margin: const EdgeInsets.only(top: 8),
          child: const Text('Inset card'),
        ),
        SmokeCard(
          accent: tokens.p2,
          margin: const EdgeInsets.only(top: 8),
          onTap: _noop,
          footer: Text(
            'Footer · tap target',
            style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
          ),
          child: const Text('Accent card with a series spine'),
        ),
      ],
    );
  }

  Widget _buttons(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PrimaryAction(label: 'Start cook', onPressed: _noop),
        const SizedBox(height: 8),
        PrimaryAction(
          label: 'Join Wi-Fi first',
          onPressed: null,
          enabledReason: 'An image is Wi-Fi only',
        ),
        const SizedBox(height: 8),
        PrimaryAction(label: 'Installing…', onPressed: _noop, busy: true),
        const SizedBox(height: 12),
        ActionRow(
          actions: <SmokeActionSpec>[
            SmokeActionSpec(label: 'Mark', onPressed: _noop),
            const SmokeActionSpec(
              label: 'Pull',
              onPressed: null,
              reason: 'No target set',
            ),
            SmokeActionSpec(
              label: 'End',
              onPressed: _noop,
              variant: SmokeButtonVariant.danger,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: SmokeButton(
                label: 'Ghost',
                onPressed: _noop,
                variant: SmokeButtonVariant.ghost,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SmokeButton(
                label: 'Danger',
                onPressed: _noop,
                variant: SmokeButtonVariant.danger,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SmokeButton(
                label: 'Small',
                onPressed: _noop,
                size: SmokeButtonSize.sm,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chips(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SegmentedChips<String>(
          segments: const <SmokeSegment<String>>[
            SmokeSegment<String>(value: 'F', label: '°F'),
            SmokeSegment<String>(value: 'C', label: '°C'),
          ],
          value: 'F',
          onChanged: (_) {},
        ),
        const SizedBox(height: 10),
        FilterChips<String>(
          options: const <SmokeSegment<String>>[
            SmokeSegment<String>(value: '15m', label: '15 m'),
            SmokeSegment<String>(value: '1h', label: '1 h'),
            SmokeSegment<String>(value: '6h', label: '6 h'),
            SmokeSegment<String>(value: 'all', label: 'All'),
          ],
          value: '1h',
          onChanged: (_) {},
        ),
      ],
    );
  }

  Widget _rows(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SmokeCard(
          child: Column(
            children: <Widget>[
              SettingsRow(
                icon: SmokeGlyph.thermometer,
                name: 'Units',
                sub: 'Temperatures in Fahrenheit',
                trailing: SmokeToggle(value: true, onChanged: (_) {}),
              ),
              SettingsRow(
                icon: SmokeGlyph.wifi,
                name: 'Join your home network',
                sub: 'Reach the bridge anywhere',
                trailing: SmokeIcon(
                  SmokeGlyph.chevronRight,
                  color: tokens.textMuted,
                ),
                onTap: _noop,
              ),
              const SettingsRow(
                icon: SmokeGlyph.upload,
                name: 'Update firmware',
                sub: 'Over Wi-Fi only',
                disabledReason: 'Bridge is not on Wi-Fi',
              ),
              SettingsRow(
                icon: SmokeGlyph.trash,
                name: 'Factory reset',
                sub: 'Erase everything',
                danger: true,
                onTap: _noop,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SmokeCard(
          child: Column(
            children: <Widget>[
              LinkRow(
                icon: SmokeGlyph.bluetooth,
                name: 'Bluetooth',
                sub: 'Connected · −52 dBm',
                right: const SignalBars(bars: 3),
              ),
              LinkRow(
                icon: SmokeGlyph.router,
                name: 'Home Wi-Fi',
                sub: 'Not connected',
                off: true,
                right: const SignalBars(bars: 1),
              ),
              const LinkRow(
                icon: SmokeGlyph.wifi,
                name: 'Bridge hotspot',
                sub: 'Available',
                right: SignalBars(bars: 4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _atoms(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        const JackBadge(jack: 1),
        const JackBadge(jack: 2),
        const JackBadge(jack: 3),
        const JackBadge(jack: 4),
        const JackBadge(jack: 4, detached: true),
        const TargetPill(label: '203°F'),
        const TargetPill(label: '203°F', reached: true),
        const TrendChip(direction: TrendDirection.up, label: '+1.8°/h'),
        const TrendChip(direction: TrendDirection.down, label: '−0.4°/h'),
        const TrendChip(direction: TrendDirection.flat, label: '~0'),
        const ModeBadge(label: 'Home Wi-Fi'),
        const TierTag(tier: AlarmTier.device),
        const TierTag(tier: AlarmTier.app),
      ],
    );
  }

  Widget _chrome(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            PulseDot(),
            PulseDot(state: PulseState.warn),
            PulseDot(state: PulseState.crit),
            PulseDot(state: PulseState.idle),
            Text('live / warn / crit / idle'),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const <Widget>[
            TransportChip(
              label: 'Bluetooth',
              phase: TransportPhase.connected,
              primary: TransportPrimary.bt,
              btConnected: true,
            ),
            TransportChip(
              label: 'Home Wi-Fi',
              phase: TransportPhase.connected,
              primary: TransportPrimary.wifi,
              wifiConnected: true,
            ),
            TransportChip(
              label: 'Connecting…',
              phase: TransportPhase.connecting,
              btConnected: true,
            ),
            TransportChip(label: 'Offline', phase: TransportPhase.offline),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Primary action, one per screen',
          style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }

  Widget _indicators(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Sparkline(
              values: const <double>[58, 70, 96, 118, 132, 141, 150],
              color: tokens.p1,
            ),
            const SizedBox(width: 12),
            Sparkline(
              values: const <double>[70, 88, 120, 165, 190, 203],
              color: tokens.p4,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            TargetGauge(
              value: 141,
              min: 70,
              max: 210,
              target: 203,
              color: tokens.p1,
              center: '141°',
              caption: 'to target',
            ),
            const SizedBox(width: 16),
            TargetGauge(
              value: 230,
              min: 150,
              max: 350,
              bandMin: 225,
              bandMax: 275,
              color: tokens.pit,
              center: '230°',
              caption: 'pit',
            ),
            const SizedBox(width: 16),
            TargetGauge(
              value: 205,
              min: 70,
              max: 210,
              target: 203,
              color: tokens.p2,
              center: 'DONE',
              caption: 'target',
            ),
          ],
        ),
        const SizedBox(height: 16),
        const PhaseTrack(
          phases: <String>['Approach', 'Pull now', 'Resting', 'Ready'],
          currentIndex: 1,
        ),
      ],
    );
  }

  Widget _banners(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const InsightBanner(message: 'Full history needs Wi-Fi.'),
        const SizedBox(height: 8),
        const InsightBanner(
          message: 'This bridge is not on Wi-Fi right now.',
          severity: BannerSeverity.warn,
        ),
        const SizedBox(height: 8),
        const InsightBanner(
          message: 'Target reached — pull the brisket.',
          severity: BannerSeverity.critical,
        ),
        const SizedBox(height: 8),
        const CapabilityNotice(message: 'Jack 4 is the grate by default.'),
        const SizedBox(height: 12),
        AlarmBar(
          title: 'Target reached',
          detail: 'Food probe crossed 203°F',
          severity: BannerSeverity.critical,
          tier: AlarmTier.device,
          onAcknowledge: _noop,
          onTap: _noop,
        ),
      ],
    );
  }

  Widget _mono(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MonoWell(value: '481 902', onCopy: _noop),
        const SizedBox(height: 10),
        MonoWell(value: 'SmokeBridge-A1B2', small: true, onCopy: _noop),
      ],
    );
  }

  Widget _states(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EmptyState(
          title: 'No probes attached',
          copy: 'Plug a probe into the Smoke X4 and it will appear here.',
          actionLabel: 'View graph',
          onAction: _noop,
        ),
        const SizedBox(height: 12),
        ProblemState(
          title: 'Bridge unreachable',
          copy: 'It may have restarted. We will keep trying.',
          actionLabel: 'Reconnect',
          onAction: _noop,
        ),
        const SizedBox(height: 12),
        LoadingState(
          title: 'Finding the bridge',
          copy: 'Checking Bluetooth and Wi-Fi.',
          actionLabel: 'Cancel',
          onAction: _noop,
        ),
        const SizedBox(height: 12),
        StaleVeil(
          ageLabel: '12 min ago',
          child: SmokeCard(
            child: Text(
              '158°F',
              style: SmokeText.tempXl.copyWith(color: tokens.textHi),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stats(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const StatGrid(
          stats: <SmokeStat>[
            SmokeStat(label: 'Mean', value: '168°'),
            SmokeStat(label: 'Peak', value: '203°'),
            SmokeStat(label: 'In band', value: '2h 14m'),
          ],
        ),
        const SizedBox(height: 12),
        SmokeCard(
          child: Column(
            children: <Widget>[
              const RecapRow(
                label: 'Cook time',
                planned: '10h 00m',
                actual: '9h 24m',
                showHeader: true,
              ),
              const RecapRow(label: 'Peak', planned: '203°F', actual: '205°F'),
              const RecapRow(label: 'Rest', planned: '60m', actual: '52m'),
            ],
          ),
        ),
        Text(
          'planned vs actual',
          style: SmokeText.labelSm.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }

  Widget _legend(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return SeriesLegend(
      entries: <SeriesLegendEntry>[
        SeriesLegendEntry(
          label: 'Pit',
          color: tokens.pit,
          value: '230°',
          glyph: SmokeGlyph.flame,
        ),
        SeriesLegendEntry(
          label: 'Brisket',
          color: tokens.p1,
          value: '158°',
          dash: const <double>[6, 3],
          glyph: SmokeGlyph.utensils,
        ),
        SeriesLegendEntry(
          label: 'Pork',
          color: tokens.p2,
          value: '142°',
          dash: const <double>[2, 3],
        ),
      ],
      isolated: 'Brisket',
      onIsolate: (_) {},
    );
  }

  Widget _cost(BuildContext context) {
    return CostSheet(
      title: 'Forget this bridge?',
      message: 'The app removes the pairing. The bridge keeps recording.',
      keeps: const <String>['Recorded sessions on the bridge'],
      loses: const <String>['This phone\'s pairing and Wi-Fi settings'],
      confirmLabel: 'Forget bridge',
      cancelLabel: 'Keep it',
      onConfirm: _noop,
      onCancel: _noop,
    );
  }
}
