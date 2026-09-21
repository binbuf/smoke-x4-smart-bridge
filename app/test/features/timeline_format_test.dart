/// N8 — the Timeline screen's pure projections.
///
/// Pins the prototype's projection rules: bar length from the `totalMin`
/// midpoint, the 38–72 % stall band, the 55 % wrap tick, the upcoming
/// dedupe/cap, the `autoWrapReminder`/per-cook gates, the actual ∪ predicted
/// rail with its "now" node, and the N8.8 honesty rule.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/content/catalog.dart';
import 'package:smoke_bridge/data/model/connection_state.dart';
import 'package:smoke_bridge/data/model/cook_state.dart';
import 'package:smoke_bridge/domain/domain.dart';
import 'package:smoke_bridge/features/timeline/timeline_format.dart';

const int _min = 60 * 1000;
const int _t0 = 1700000000000;

TimelineRow _row({
  ProbeJack jack = ProbeJack.one,
  int startMs = _t0,
  MinuteRange total = const MinuteRange(100, 200),
  StallWindow? stall,
  WrapStep? wrap,
  int? spritz,
  TurnStep? turn,
  List<CookPhaseSpec> phases = const <CookPhaseSpec>[],
  bool wrapEnabled = true,
  bool spritzEnabled = true,
}) => TimelineRow(
  jack: jack,
  presetId: 'beef_brisket',
  name: 'Brisket',
  glyph: 'brisket',
  timeline: CookTimeline(
    totalMin: total,
    stall: stall,
    wrap: wrap,
    spritzEveryMin: spritz,
    turn: turn,
    phases: phases,
  ),
  startMs: startMs,
  expectedMin: total.mid,
  wrapEnabled: wrapEnabled,
  spritzEnabled: spritzEnabled,
);

void main() {
  group('row geometry (N8.3–N8.5)', () {
    test('bar length is the totalMin midpoint', () {
      final row = _row();
      expect(row.expectedMin, 150);
      expect(row.endMs, _t0 + 150 * _min);
      expect(row.progressAt(_t0 + 75 * _min), closeTo(0.5, 1e-9));
      expect(row.progressAt(_t0 - _min), 0);
      expect(row.progressAt(_t0 + 500 * _min), 1);
    });

    test('stall band is 38–72 % and the wrap tick is 55 %', () {
      final row = _row(
        stall: const StallWindow(
          minF10: 1500,
          maxF10: 1650,
          durationMin: MinuteRange(45, 90),
        ),
        wrap: const WrapStep(tempF10: 1650, label: 'Wrap in paper'),
      );
      expect(row.stallStartMs, _t0 + (150 * 0.38 * _min).round());
      expect(row.stallEndMs, _t0 + (150 * 0.72 * _min).round());
      expect(row.wrapAtMs, _t0 + (150 * 0.55 * _min).round());
      expect(row.hasStall, isTrue);
      expect(row.hasWrapMilestone, isTrue);
    });

    test('a cut with no stall/wrap has neither milestone', () {
      final row = _row();
      expect(row.stallStartMs, isNull);
      expect(row.stallEndMs, isNull);
      expect(row.wrapAtMs, isNull);
      expect(row.hasWrapMilestone, isFalse);
    });

    test('the milestone is a fact of the cut, not the reminder', () {
      final row = _row(wrap: const WrapStep(label: 'Wrap'), wrapEnabled: false);
      expect(row.hasWrapMilestone, isTrue);
      expect(row.wrapAtMs, isNotNull);
      expect(row.wrapEnabled, isFalse);
    });
  });

  group('schedule header (N8.2)', () {
    test('last end, served-by and the domain tail', () {
      final cook = CookState(
        active: true,
        startedAtMs: _t0,
        items: <CookItem>[
          CookItem(
            presetId: 'beef_brisket',
            jack: ProbeJack.one,
            addedAtMs: _t0,
          ),
        ],
      );
      final model = buildTimelineModel(
        cook: cook,
        pendingSession: null,
        catalog: kCatalogTable,
        marks: const <Mark>[],
        nowMs: _t0 + 60 * _min,
        autoWrapReminder: true,
      );
      final mid = kCatalogTable.timelineFor('beef_brisket')!.totalMin.mid;
      expect(model.itemCount, 1);
      expect(model.lastEndMs, _t0 + (mid * _min).round());
      expect(model.servedByMs, model.lastEndMs! + kServeOffsetMin * _min);
      expect(model.domainEndMs, model.lastEndMs! + kDomainTailMin * _min);
      expect(model.startedMs, _t0);
    });

    test('an empty cook is tolerated (N8.12)', () {
      final model = buildTimelineModel(
        cook: const CookState(active: true, startedAtMs: _t0),
        pendingSession: null,
        catalog: kCatalogTable,
        marks: const <Mark>[],
        nowMs: _t0 + 30 * _min,
        autoWrapReminder: true,
      );
      expect(model.isEmpty, isTrue);
      expect(model.lastEndMs, isNull);
      expect(model.servedByMs, isNull);
      expect(model.domainEndMs, _t0 + 30 * _min + kDomainTailMin * _min);
      expect(model.upcoming, isEmpty);
      expect(model.events, isEmpty);
      expect(model.xPercent(model.startedMs), 0);
    });

    test('the pending session start anchors a schedule with no cook', () {
      final model = buildTimelineModel(
        cook: const CookState(),
        pendingSession: const PendingSession(
          sessionId: 'SMK-1',
          startedAtMs: _t0 - 2 * 60 * _min,
          samples: 10,
          probeCount: 1,
        ),
        catalog: kCatalogTable,
        marks: const <Mark>[],
        nowMs: _t0,
        autoWrapReminder: true,
      );
      expect(model.startedMs, _t0 - 120 * _min);
    });

    test('an unknown preset falls back to 60–90 minutes (N8.12)', () {
      final model = buildTimelineModel(
        cook: CookState(
          active: true,
          startedAtMs: _t0,
          items: <CookItem>[
            CookItem(
              presetId: 'not_in_the_catalog',
              jack: ProbeJack.two,
              addedAtMs: _t0,
            ),
          ],
        ),
        pendingSession: null,
        catalog: kCatalogTable,
        marks: const <Mark>[],
        nowMs: _t0,
        autoWrapReminder: true,
      );
      expect(model.items.single.name, 'Item');
      expect(model.items.single.expectedMin, 75);
      expect(model.upcoming, isEmpty);
    });

    test('a per-item timeline overrides the catalog table (N9.18 seam)', () {
      final model = buildTimelineModel(
        cook: CookState(
          active: true,
          startedAtMs: _t0,
          items: <CookItem>[
            CookItem(
              presetId: 'beef_brisket',
              jack: ProbeJack.one,
              addedAtMs: _t0,
              timeline: const CookTimeline(totalMin: MinuteRange(10, 20)),
            ),
          ],
        ),
        pendingSession: null,
        catalog: kCatalogTable,
        marks: const <Mark>[],
        nowMs: _t0,
        autoWrapReminder: true,
      );
      expect(model.items.single.expectedMin, 15);
    });
  });

  group('upcoming (N8.6/N8.9/N8.10)', () {
    final now = _t0 + 60 * _min;

    test('wrap + spritz + turn are sorted by time', () {
      final upcoming = buildUpcoming(
        <TimelineRow>[
          _row(
            spritz: 45,
            turn: const TurnStep(elapsedMin: 200, note: 'Rotate'),
            wrap: const WrapStep(label: 'Wrap in paper', note: 'Now'),
          ),
        ],
        nowMs: now,
        autoWrapReminder: true,
      );
      expect(upcoming.map((u) => u.kind).toList(), <InterventionKind>[
        InterventionKind.spritz,
        InterventionKind.wrap,
        InterventionKind.turn,
      ]);
      expect(upcoming.first.note, 'Every 45 min to keep the bark moist.');
    });

    test('a past intervention is not upcoming', () {
      final upcoming = buildUpcoming(
        <TimelineRow>[_row(turn: const TurnStep(elapsedMin: 5))],
        nowMs: now,
        autoWrapReminder: true,
      );
      expect(upcoming, isEmpty);
    });

    test('autoWrapReminder off drops wrap and spritz, keeps turn', () {
      final upcoming = buildUpcoming(
        <TimelineRow>[
          _row(
            spritz: 45,
            turn: const TurnStep(elapsedMin: 200),
            wrap: const WrapStep(label: 'Wrap'),
          ),
        ],
        nowMs: now,
        autoWrapReminder: false,
      );
      expect(upcoming.map((u) => u.kind), <InterventionKind>[
        InterventionKind.turn,
      ]);
    });

    test('per-cook toggles gate each nudge', () {
      final upcoming = buildUpcoming(
        <TimelineRow>[
          _row(
            spritz: 45,
            turn: const TurnStep(elapsedMin: 200),
            wrap: const WrapStep(label: 'Wrap'),
            wrapEnabled: false,
            spritzEnabled: false,
          ),
        ],
        nowMs: now,
        autoWrapReminder: true,
      );
      expect(upcoming.map((u) => u.kind), <InterventionKind>[
        InterventionKind.turn,
      ]);
    });

    test('a cut with no wrap shows no wrap reminder', () {
      final upcoming = buildUpcoming(
        <TimelineRow>[_row()],
        nowMs: now,
        autoWrapReminder: true,
      );
      expect(upcoming, isEmpty);
    });

    test('identical spritzes dedupe and the list is capped at four', () {
      final rows = <TimelineRow>[
        _row(spritz: 45),
        _row(jack: ProbeJack.two, spritz: 45),
        _row(jack: ProbeJack.three, spritz: 45),
        _row(jack: ProbeJack.four, spritz: 45),
        _row(turn: const TurnStep(elapsedMin: 300)),
      ];
      final upcoming = buildUpcoming(rows, nowMs: now, autoWrapReminder: true);
      // Four spritz cards collapse to one; the turn survives; the cap applies.
      expect(
        upcoming.where((u) => u.kind == InterventionKind.spritz).length,
        1,
      );
      expect(upcoming.length, lessThanOrEqualTo(kUpcomingLimit));
    });
  });

  group('event rail (N8.7/N8.8)', () {
    test(
      'actual marks and predicted phases interleave, first future is now',
      () {
        final row = _row(
          phases: const <CookPhaseSpec>[
            CookPhaseSpec(id: 'on', label: 'On the smoker'),
            CookPhaseSpec(id: 'stall', label: 'The stall'),
            CookPhaseSpec(id: 'wrap', label: 'Wrap in paper'),
            CookPhaseSpec(id: 'pull', label: 'Pull'),
            CookPhaseSpec(id: 'rest', label: 'Rest'),
          ],
        );
        final events = buildRailEvents(
          rows: <TimelineRow>[row],
          marks: const <Mark>[
            Mark(t: 0, kind: MarkKind.phaseChange, text: 'Cook started'),
            Mark(t: 3600, kind: MarkKind.note, text: 'Spritzed ribs'),
          ],
          startedMs: _t0,
          nowMs: _t0 + 60 * _min,
        );
        expect(events.where((e) => e.actual).length, 2);
        final predicted = events.where((e) => e.predicted).toList();
        // Phases at 0, 37.5, 75, 112.5 and 150 min; only > now survive.
        expect(predicted.length, 3);
        expect(events.first.actual, isTrue);
        expect(predicted.first.isNow, isTrue);
        expect(events.where((e) => e.isNow).length, 1);
        expect(predicted.first.title, 'Brisket · Wrap in paper');
      },
    );

    test('a predicted time says expected; an actual does not', () {
      final event = TimelineEvent(
        atMs: _t0,
        title: 'Wrap',
        note: '',
        actual: false,
        isNow: true,
      );
      expect(railTimeLabel(event), contains('· expected'));
      expect(
        railTimeLabel(
          const TimelineEvent(atMs: 0, title: 'x', note: '', actual: true),
        ),
        isNot(contains('expected')),
      );
    });

    test('mark kinds read as the prototype words', () {
      expect(markKindWord(MarkKind.phaseChange), 'phase change');
      expect(markKindWord(MarkKind.lidOpen), 'lid open');
      expect(markKindWord(MarkKind.spritz), 'spritz');
    });
  });
}
