/// Cooks as annotations: backdating, splitting, merging, repeating, and the
/// anchor detection that makes retroactive start a two-tap job (newapp §D.1,
/// §D.3, §D.6).
///
/// These are the invariants §I.2 asks for as *pure metadata* tests — no drift,
/// no widgets. If splitting a cook needed a database to reason about, it would
/// not be the cheap operation the reframe promised.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';

const int _hour = 3600 * 1000;

CookAnnotation _cook({
  int id = 1,
  int start = 0,
  int? end,
  String name = 'Brisket',
  List<CookProbeRole> roles = const [],
}) => CookAnnotation(
  id: id,
  bridgeId: 'bridge-a',
  name: name,
  startUnixMs: start,
  endUnixMs: end,
  createdUnixMs: start,
  roles: roles,
);

void main() {
  group('status is a function of the clock, not a stored flag', () {
    test('a start in the future is scheduled, not running', () {
      final cook = _cook(start: 10 * _hour);
      expect(cook.statusAt(5 * _hour), CookStatus.scheduled);
      expect(cook.statusAt(10 * _hour), CookStatus.running);
    });

    test('an unbounded cook stays running however long it runs', () {
      final cook = _cook(start: 0);
      expect(cook.statusAt(400 * _hour), CookStatus.running);
    });

    test('a bounded cook is finished', () {
      expect(_cook(start: 0, end: _hour).statusAt(2 * _hour),
          CookStatus.finished);
    });
  });

  group('coverage is half-open, so a split boundary belongs to one side', () {
    test('start is inclusive and end exclusive', () {
      final cook = _cook(start: 100, end: 200);
      expect(cook.covers(100), isTrue);
      expect(cook.covers(199), isTrue);
      expect(cook.covers(200), isFalse);
      expect(cook.covers(99), isFalse);
    });

    test('a split leaves no sample claimed twice and none orphaned', () {
      final (before, after) = _cook(start: 0, end: 10).splitAt(4);
      for (var t = 0; t < 10; t++) {
        final claims = [before.covers(t), after.covers(t)].where((c) => c);
        expect(claims.length, 1, reason: 't=$t must belong to exactly one half');
      }
    });
  });

  group('§D.3 — backdating is metadata only', () {
    test('moving the start earlier keeps everything else', () {
      final cook = _cook(start: 5 * _hour, end: 9 * _hour, name: 'Pork');
      final moved = cook.backdatedTo(2 * _hour);
      expect(moved.startUnixMs, 2 * _hour);
      expect(moved.endUnixMs, 9 * _hour);
      expect(moved.name, 'Pork');
      expect(moved.id, cook.id);
    });

    test('a start at or after the end is refused, not clamped', () {
      final cook = _cook(start: 5 * _hour, end: 9 * _hour);
      expect(() => cook.backdatedTo(9 * _hour), throwsArgumentError);
      expect(() => cook.backdatedTo(10 * _hour), throwsArgumentError);
    });

    test('a running cook can be backdated to anything before now', () {
      final cook = _cook(start: 5 * _hour);
      expect(cook.backdatedTo(0).startUnixMs, 0);
    });
  });

  group('§C.4 — split', () {
    test('splits a finished cook into two bounded halves', () {
      final (before, after) = _cook(start: 0, end: 8 * _hour).splitAt(3 * _hour);
      expect(before.startUnixMs, 0);
      expect(before.endUnixMs, 3 * _hour);
      expect(after.startUnixMs, 3 * _hour);
      expect(after.endUnixMs, 8 * _hour);
    });

    test('the second half of a running cook is still running', () {
      final (before, after) = _cook(start: 0).splitAt(3 * _hour);
      expect(before.endUnixMs, 3 * _hour);
      expect(after.endUnixMs, isNull);
    });

    test('the new half is unsaved so the repository assigns its id', () {
      final (before, after) = _cook(id: 7, start: 0, end: 10).splitAt(5);
      expect(before.id, 7);
      expect(after.id, 0);
    });

    test('roles carry across — a split is about when, not what', () {
      final roles = [
        const CookProbeRole(jack: 1, role: ProbeRole.pit),
        const CookProbeRole(jack: 2, role: ProbeRole.food, targetF10: 2030),
      ];
      final (before, after) =
          _cook(start: 0, end: 10, roles: roles).splitAt(5);
      expect(before.roles, roles);
      expect(after.roles, roles);
    });

    test('the pull does not follow the second half into a rest it never had',
        () {
      final cook = _cook(start: 0, end: 10).copyWith(pulledAtUnixMs: 3);
      final (before, after) = cook.splitAt(5);
      expect(before.pulledAtUnixMs, 3);
      expect(after.pulledAtUnixMs, isNull);
    });

    test('a split outside the bounds is refused', () {
      final cook = _cook(start: 100, end: 200);
      expect(() => cook.splitAt(100), throwsArgumentError);
      expect(() => cook.splitAt(200), throwsArgumentError);
      expect(() => cook.splitAt(50), throwsArgumentError);
    });
  });

  group('§C.4 — merge', () {
    test('spans both and keeps the earlier identity', () {
      final a = _cook(id: 1, start: 0, end: 3 * _hour, name: 'First');
      final b = _cook(id: 2, start: 3 * _hour, end: 8 * _hour, name: 'Second');
      final merged = a.mergedWith(b);
      expect(merged.id, 1);
      expect(merged.name, 'First');
      expect(merged.startUnixMs, 0);
      expect(merged.endUnixMs, 8 * _hour);
    });

    test('merging is order-independent', () {
      final a = _cook(id: 1, start: 0, end: 3 * _hour);
      final b = _cook(id: 2, start: 3 * _hour, end: 8 * _hour);
      expect(b.mergedWith(a).startUnixMs, a.mergedWith(b).startUnixMs);
      expect(b.mergedWith(a).endUnixMs, a.mergedWith(b).endUnixMs);
      expect(b.mergedWith(a).id, 1, reason: 'the earlier cook keeps identity');
    });

    test('a running half makes the merged cook running', () {
      final a = _cook(id: 1, start: 0, end: 3 * _hour);
      final b = _cook(id: 2, start: 3 * _hour);
      expect(a.mergedWith(b).endUnixMs, isNull);
    });

    test('notes concatenate rather than one silently winning', () {
      final a = _cook(id: 1, start: 0, end: 10).copyWith(notes: 'wrapped');
      final b = _cook(id: 2, start: 10, end: 20).copyWith(notes: 'rested');
      expect(a.mergedWith(b).notes, 'wrapped\nrested');
    });

    test('cooks on different bridges cannot merge', () {
      final a = _cook(id: 1, start: 0, end: 10);
      final b = CookAnnotation(
        id: 2,
        bridgeId: 'bridge-b',
        startUnixMs: 10,
        createdUnixMs: 10,
      );
      expect(() => a.mergedWith(b), throwsArgumentError);
    });
  });

  group('§D.6 — repeat this cook', () {
    test('copies the targets and drops the history', () {
      final roles = [
        const CookProbeRole(
          jack: 2,
          role: ProbeRole.food,
          targetF10: 2030,
          pullOffsetF10: 80,
        ),
      ];
      final original = _cook(id: 4, start: 0, end: 8 * _hour, roles: roles)
          .copyWith(notes: 'used apple wood', presetId: 'beef_brisket');
      final repeat = original.repeatAt(100 * _hour);

      expect(repeat.id, 0, reason: 'unsaved until the repository writes it');
      expect(repeat.startUnixMs, 100 * _hour);
      expect(repeat.endUnixMs, isNull);
      expect(repeat.roles.single.targetF10, 2030);
      expect(repeat.roles.single.pullOffsetF10, 80);
      expect(repeat.presetId, 'beef_brisket');
      expect(
        repeat.notes,
        isEmpty,
        reason: 'the notes belonged to the cook that happened',
      );
    });
  });

  group('§D.3.2 — a cook can exist before its target does', () {
    test('hasNoTarget is true for roles with no targets', () {
      final cook = _cook(
        roles: const [
          CookProbeRole(jack: 1, role: ProbeRole.pit),
          CookProbeRole(jack: 2, role: ProbeRole.food),
        ],
      );
      expect(cook.hasNoTarget, isTrue);
      expect(cook.primaryFood?.jack, 2);
    });

    test('adding a target later flips it', () {
      final cook = _cook(
        roles: const [CookProbeRole(jack: 2, role: ProbeRole.food)],
      );
      final targeted = cook.copyWith(
        roles: [cook.roles.single.copyWith(targetF10: 1650)],
      );
      expect(targeted.hasNoTarget, isFalse);
    });
  });

  group('the plan projection re-runs the safety gate', () {
    test('an unsafe annotation throws rather than rendering gauges', () {
      final cook = _cook(
        roles: const [
          CookProbeRole(
            jack: 2,
            role: ProbeRole.food,
            targetF10: 1400,
            hazard: HazardClass.poultry,
          ),
        ],
      );
      expect(cook.toPlan, throwsArgumentError);
    });

    test('a safe annotation projects a plan carrying its id and start', () {
      final cook = _cook(
        id: 9,
        start: 42,
        roles: const [
          CookProbeRole(jack: 1, role: ProbeRole.pit),
          CookProbeRole(
            jack: 2,
            role: ProbeRole.food,
            targetF10: 2030,
            pullOffsetF10: 80,
            label: 'Brisket',
          ),
        ],
      );
      final plan = cook.toPlan();
      expect(plan.cookId, 9);
      expect(plan.startedUnixMs, 42);
      expect(plan.pit?.jack, 1);
      expect(plan.primaryFood?.pullF10, 1950);
    });

    test('round-trips through fromPlan', () {
      final cook = _cook(
        id: 3,
        start: 1000,
        roles: const [
          CookProbeRole(jack: 1, role: ProbeRole.pit),
          CookProbeRole(jack: 2, role: ProbeRole.food, targetF10: 1650,
              hazard: HazardClass.poultry),
        ],
      );
      final back = CookAnnotation.fromPlan(
        cook.toPlan(),
        bridgeId: 'bridge-a',
        nowUnixMs: 2000,
        id: 3,
      );
      expect(back.startUnixMs, 1000);
      expect(back.roles.length, 2);
      expect(back.roleFor(2)?.targetF10, 1650);
    });

    test('an unused jack does not become a plan probe', () {
      final cook = _cook(
        roles: const [
          CookProbeRole(jack: 1, role: ProbeRole.pit),
          CookProbeRole(jack: 4, role: ProbeRole.unused),
        ],
      );
      expect(cook.toPlan().probes.map((p) => p.jack), [1]);
    });
  });

  group('§D.3.1 — candidate anchors', () {
    Sample s(int t, List<int?> temps) => Sample(t: t, tempsF10: temps);

    test('a probe going from detached to reading is offered', () {
      final anchors = candidateAnchors(
        samples: [
          s(0, [null, null, null, null]),
          s(30, [null, null, null, null]),
          s(60, [700, null, null, null]),
        ],
        sessionStartUnixMs: 1000,
      );
      expect(
        anchors.any(
          (a) => a.kind == AnchorKind.probeInserted && a.unixMs == 1000 + 60000,
        ),
        isTrue,
      );
    });

    test('a probe crossing ambient is offered', () {
      final anchors = candidateAnchors(
        samples: [
          s(0, [700, null, null, null]),
          s(30, [850, null, null, null]),
          s(60, [950, null, null, null]),
        ],
        sessionStartUnixMs: 0,
      );
      final crossing = anchors
          .where((a) => a.kind == AnchorKind.crossedAmbient)
          .toList();
      expect(crossing.length, 1);
      expect(crossing.single.unixMs, 60000);
    });

    test('marks are offered, and the recording start always is', () {
      final anchors = candidateAnchors(
        samples: [s(0, [700, null, null, null])],
        sessionStartUnixMs: 0,
        marks: const [Mark(t: 120, kind: MarkKind.wrapped, text: 'Wrapped')],
      );
      expect(anchors.any((a) => a.kind == AnchorKind.mark), isTrue);
      expect(anchors.any((a) => a.kind == AnchorKind.recordingStart), isTrue);
    });

    test('a clockless session offers nothing rather than epoch-zero times', () {
      expect(
        candidateAnchors(
          samples: [s(0, [700, null, null, null])],
          sessionStartUnixMs: null,
        ),
        isEmpty,
        reason:
            'an anchor the user cannot be shown a time for is not an offer, '
            'and inventing one would violate the never-rewrite-device-time rule',
      );
    });

    test('newest first, and capped', () {
      final anchors = candidateAnchors(
        samples: [
          for (var i = 0; i < 40; i++)
            s(i * 30, [i.isEven ? null : 950, null, null, null]),
        ],
        sessionStartUnixMs: 0,
        limit: 4,
      );
      expect(anchors.length, 4);
      for (var i = 1; i < anchors.length; i++) {
        expect(anchors[i].unixMs, lessThanOrEqualTo(anchors[i - 1].unixMs));
      }
    });
  });
}
