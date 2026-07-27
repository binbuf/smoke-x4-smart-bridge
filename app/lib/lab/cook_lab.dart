/// A22.5 — the interactive UX lab (design 13, 14).
///
/// Plays the [labScenarios] through the real production [CookView] with a
/// play/pause and a scrub timeline, so the whole UX flow can be reviewed with
/// no bridge, no Smoke X, no deploy. The widgets it renders are the ones that
/// ship — this is a driver, not a mock UI.
///
/// Run it device-free:
///   flutter run -d chrome  -t lib/lab/main_lab.dart
///   flutter run -d windows -t lib/lab/main_lab.dart   (if desktop is enabled)
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../design/design.dart';
import '../features/cook/cook_view.dart';
import '../ui/ui.dart';
import 'scenarios.dart';

class CookLab extends StatefulWidget {
  const CookLab({super.key});

  @override
  State<CookLab> createState() => _CookLabState();
}

class _CookLabState extends State<CookLab> {
  LabScenario _scenario = labScenarios.first;
  int _t = 0;
  bool _playing = false;
  Timer? _timer;

  // Review overrides. Null freshness = "Auto" (obey the frame's scripted
  // freshness); a forced value lets a reviewer hold any rung of the freshness
  // ladder on the current frame without editing a scenario.
  ProbeFreshness? _forceFreshness;
  bool _celsius = false;

  // How many scenario-seconds pass per real second while playing. A 10 h cook
  // is unwatchable at 1×, so the lab runs fast and the scrubber is the truth.
  static const int _rate = 600;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    _timer?.cancel();
    if (_t >= _scenario.durationS) {
      _t = 0;
    }
    setState(() => _playing = true);
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() {
        _t += _rate ~/ 10;
        if (_t >= _scenario.durationS) {
          _t = _scenario.durationS;
          _playing = false;
          _timer?.cancel();
        }
      });
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _playing = false);
  }

  void _pick(LabScenario s) {
    _timer?.cancel();
    setState(() {
      _scenario = s;
      _t = 0;
      _playing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final frame = _scenario.at(_t);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('UX Lab'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.hairline),
        ),
      ),
      body: Column(
        children: [
          _scenarioBar(context),
          _captionBar(context, frame),
          _reviewBar(context),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                // A phone-width column so the review matches the target device.
                constraints: const BoxConstraints(maxWidth: 420),
                child: CookView(
                  key: ValueKey('${_scenario.id}-${frame.atS}'),
                  snapshot: frame.snapshot,
                  plan: frame.plan,
                  freshness: _forceFreshness ?? frame.freshness,
                  celsius: _celsius,
                  onSetupCook: () {},
                  onStop: frame.plan == null ? null : () {},
                ),
              ),
            ),
          ),
          _transport(context),
        ],
      ),
    );
  }

  Widget _scenarioBar(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final s in labScenarios)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(s.title),
                  selected: s.id == _scenario.id,
                  onSelected: (_) => _pick(s),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _captionBar(BuildContext context, LabFrame frame) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      color: t.cardSubtle,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _scenario.blurb,
            style: SmokeType.bodySm.copyWith(color: t.textMuted),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.play_circle_outline,
                size: 16,
                color: StatusPalette.pit,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  frame.label,
                  style: SmokeType.title.copyWith(color: t.textHi),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The reviewer's overrides: force any freshness rung on the current frame,
  /// and flip °F/°C. Neither edits a scenario — they re-drive the same
  /// production [CookView] so a reviewer can hold "stale" or read °C on demand.
  Widget _reviewBar(BuildContext context) {
    final t = context.tokens;
    return Container(
      color: t.surface,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              _reviewLabel(context, 'FRESHNESS'),
              const SizedBox(width: SmokeTokens.s2),
              Expanded(
                child: SegmentedChips<ProbeFreshness?>(
                  value: _forceFreshness,
                  onChanged: (v) => setState(() => _forceFreshness = v),
                  options: const [
                    ChipOption(null, 'Auto'),
                    ChipOption(ProbeFreshness.live, 'Live'),
                    ChipOption(ProbeFreshness.aging, 'Aging'),
                    ChipOption(ProbeFreshness.stale, 'Stale'),
                    ChipOption(ProbeFreshness.frozen, 'Frozen'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SmokeTokens.s2),
          Row(
            children: [
              _reviewLabel(context, 'UNITS'),
              const SizedBox(width: SmokeTokens.s2),
              Expanded(
                child: SegmentedChips<bool>(
                  value: _celsius,
                  onChanged: (v) => setState(() => _celsius = v),
                  options: const [
                    ChipOption(false, '°F'),
                    ChipOption(true, '°C'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reviewLabel(BuildContext context, String text) => SizedBox(
    width: 76,
    child: Text(
      text,
      style: SmokeType.label.copyWith(color: context.tokens.textMuted),
    ),
  );

  Widget _transport(BuildContext context) {
    final t = context.tokens;
    final dur = _scenario.durationS;
    return Container(
      color: t.surface,
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          IconButton(
            iconSize: 36,
            color: StatusPalette.pit,
            icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle),
            onPressed: _playing ? _pause : _play,
          ),
          Expanded(
            child: Slider(
              value: _t.clamp(0, dur).toDouble(),
              max: dur <= 0 ? 1 : dur.toDouble(),
              activeColor: StatusPalette.pit,
              onChanged: (v) {
                _pause();
                setState(() => _t = v.round());
              },
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              _fmt(_t),
              textAlign: TextAlign.right,
              style: SmokeType.mono.copyWith(color: t.textBody),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m}m';
  }
}
