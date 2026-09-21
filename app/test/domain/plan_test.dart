/// N1.15/N1.17 — the four-phase arc and the cook-annotation verbs.
library;

import 'package:smoke_bridge/domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('N1.15 cook phase arc', () {
    test('approaching below the pull temperature', () {
      final state = cookPhaseFor(
        tempF10: 1000,
        targetF10: 1350,
        pullF10: 1150,
        nowUnixMs: 0,
      );
      expect(state.phase, CookPhase.approaching);
    });

    test('pullNow at the pull temperature, and it never infers a pull', () {
      final state = cookPhaseFor(
        tempF10: 1160,
        targetF10: 1350,
        pullF10: 1150,
        nowUnixMs: 0,
      );
      expect(state.phase, CookPhase.pullNow, reason: 'no sensor sees a pull');

      // Even hours later, with no user tap, it is still asking for a pull.
      final later = cookPhaseFor(
        tempF10: 1160,
        targetF10: 1350,
        pullF10: 1150,
        nowUnixMs: 999999999,
      );
      expect(later.phase, CookPhase.pullNow);
    });

    test('resting is an estimate once the user says they pulled it', () {
      final state = cookPhaseFor(
        tempF10: 1100,
        targetF10: 1350,
        pullF10: 1150,
        nowUnixMs: 0,
        pulledAtUnixMs: 0,
      );
      expect(state.phase, CookPhase.resting);
      expect(state.estimated, isTrue);
      expect(state.restRemainingS, 1200);
      expect(state.restProgress, 0);
    });

    test('the sensor wins over the rest clock', () {
      final state = cookPhaseFor(
        tempF10: 1350,
        targetF10: 1350,
        pullF10: 1150,
        nowUnixMs: 0,
        pulledAtUnixMs: 0,
      );
      expect(state.phase, CookPhase.ready);
      expect(state.detail, 'Rested to target.');
    });

    test('ready when the rest clock finishes', () {
      final state = cookPhaseFor(
        tempF10: 1100,
        targetF10: 1350,
        pullF10: 1150,
        nowUnixMs: 1300000,
        pulledAtUnixMs: 0,
      );
      expect(state.phase, CookPhase.ready);
    });

    test('no target is not a phase', () {
      final state = cookPhaseFor(
        tempF10: 1000,
        targetF10: null,
        pullF10: null,
        nowUnixMs: 0,
      );
      expect(state.phase, CookPhase.approaching);
      expect(state.detail, 'No target set yet.');
    });
  });

  group('N1.17 cook annotation verbs are metadata only', () {
    CookAnnotation annotation() => CookAnnotation(
      id: 7,
      bridgeId: 'b1',
      name: 'Brisket',
      startUnixMs: 1000,
      createdUnixMs: 1000,
      endUnixMs: 5000,
      notes: 'note',
      hazard: HazardClass.wholeMuscleRedMeat,
      roles: const [
        CookProbeRole(
          jack: ProbeJack.one,
          role: ProbeRole.food,
          label: 'Brisket',
          targetF10: 1350,
          pullOffsetF10: 20,
        ),
      ],
    );

    test('status is scheduled / running / finished', () {
      expect(annotation().statusAt(0), CookStatus.scheduled);
      expect(
        annotation().copyWith(clearEnd: true).statusAt(2000),
        CookStatus.running,
      );
      expect(annotation().statusAt(2000), CookStatus.finished);
    });

    test('backdate moves the start and refuses an inverted window', () {
      expect(annotation().backdatedTo(500).startUnixMs, 500);
      expect(() => annotation().backdatedTo(5000), throwsArgumentError);
    });

    test('split produces two windows and keeps the what, not the when', () {
      final (before, after) = annotation().splitAt(3000);
      expect(before.endUnixMs, 3000);
      expect(after.startUnixMs, 3000);
      expect(after.id, 0, reason: 'unsaved until the repository assigns an id');
      expect(after.roles.single.targetF10, 1350);
      expect(after.name, 'Brisket (2)');
      expect(() => annotation().splitAt(1000), throwsArgumentError);
    });

    test('merge spans both and keeps the earlier identity', () {
      final other = annotation().copyWith(startUnixMs: 5000, endUnixMs: 9000);
      final merged = annotation().mergedWith(other);
      expect(merged.startUnixMs, 1000);
      expect(merged.endUnixMs, 9000);
      expect(merged.name, 'Brisket');
    });

    test('retarget takes the target but keeps the window', () {
      final source = annotation().copyWith(
        name: 'Pork',
        hazard: HazardClass.pork,
        roles: const [
          CookProbeRole(
            jack: ProbeJack.two,
            role: ProbeRole.food,
            targetF10: 1450,
          ),
        ],
      );
      final retargeted = annotation().retargetedTo(source);
      expect(retargeted.startUnixMs, 1000);
      expect(retargeted.endUnixMs, 5000);
      expect(retargeted.notes, 'note');
      expect(retargeted.hazard, HazardClass.pork);
      expect(retargeted.roles.single.jack, ProbeJack.two);
    });

    test('repeat copies the what and neither the notes nor the times', () {
      final repeated = annotation().repeatAt(20000, newName: 'Brisket again');
      expect(repeated.id, 0);
      expect(repeated.startUnixMs, 20000);
      expect(repeated.notes, isEmpty);
      expect(repeated.roles.single.targetF10, 1350);
      expect(repeated.name, 'Brisket again');
    });

    test('projecting to a plan re-runs the safety gate', () {
      final plan = annotation().toPlan();
      expect(plan.primaryFood!.targetF10, 1350);

      final unsafe = annotation().copyWith(
        hazard: HazardClass.poultry,
        roles: const [
          CookProbeRole(
            jack: ProbeJack.one,
            role: ProbeRole.food,
            targetF10: 1000,
          ),
        ],
      );
      expect(unsafe.toPlan, throwsArgumentError);
    });

    test('candidate anchors are evidence, newest first', () {
      final samples = <Sample>[
        const Sample(t: 0, tempsF10: [null, null, null, null]),
        const Sample(t: 30, tempsF10: [1000, null, null, null]),
        const Sample(t: 60, tempsF10: [1000, 800, null, null]),
        const Sample(t: 90, tempsF10: [1000, 1000, null, null]),
      ];
      final anchors = candidateAnchors(
        samples: samples,
        sessionStartUnixMs: 1000000,
        marks: const [
          Mark(t: 45, kind: MarkKind.note, text: 'Added ribs', probe: 2),
        ],
      );
      final kinds = anchors.map((a) => a.kind).toSet();
      expect(kinds, contains(AnchorKind.probeInserted));
      expect(kinds, contains(AnchorKind.crossedAmbient));
      expect(kinds, contains(AnchorKind.mark));
      expect(kinds, contains(AnchorKind.recordingStart));
      expect(anchors.first.unixMs, 1000000 + 90 * 1000);
    });

    test('a bridge with no clock offers no anchors', () {
      final anchors = candidateAnchors(
        samples: const [
          Sample(t: 0, tempsF10: [1000, null, null, null]),
        ],
        sessionStartUnixMs: null,
      );
      expect(anchors, isEmpty);
    });
  });
}
