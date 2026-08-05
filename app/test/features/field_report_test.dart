/// The field report harness itself.
///
/// **A diagnostic that lies is worse than no diagnostic, because it is
/// believed.** This harness exists to answer questions the desk cannot, which
/// means nobody will be in a position to sanity-check its output — so the
/// properties that make it trustworthy have to be pinned here:
///
///  1. a probe that throws becomes a FAIL **with its reason**, and the run
///     continues (a harness that aborts halfway wastes a trip to the smoker);
///  2. "could not run" is SKIP, never FAIL — the two call for different next
///     steps and collapsing them wastes the run;
///  3. the destructive check never runs unless it was asked for;
///  4. the rendered report is greppable and loses nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/app_env.dart';
import 'package:smoke_bridge/features/fieldreport/field_probes.dart';
import 'package:smoke_bridge/features/fieldreport/field_report.dart';
import 'package:smoke_bridge/features/fieldreport/field_runner.dart';

import '../support/fake_env.dart';

ProbeContext _ctx(AppEnv env) => ProbeContext(
  env: env,
  now: () => DateTime(2026, 8, 5, 14, 30),
  deviceInfo: const {'platform': 'android', 'os version': 'test'},
);

ProbeGroup _group(String title, List<(String, Probe)> probes) => ProbeGroup(
  title,
  [for (final (id, run) in probes) (id: id, title: id, run: run)],
);

void main() {
  late AppEnv env;

  setUp(() {
    env = fakeEnv();
    AppEnv.instance = env;
  });
  tearDown(() => AppEnv.instance = null);

  group('a probe that throws does not take the run with it', () {
    test('it becomes a FAIL carrying the reason, and the rest still run',
        () async {
      final report = await runFieldReport(
        _ctx(env),
        groups: [
          _group('g', [
            ('ok.first', (_) async => const CheckResult.pass('ok.first', 'a')),
            ('boom', (_) async => throw StateError('radio on fire')),
            ('ok.last', (_) async => const CheckResult.pass('ok.last', 'c')),
          ]),
        ],
      );

      final results = report.allResults.toList();
      expect(results, hasLength(3));
      expect(results[1].status, CheckStatus.fail);
      expect(
        results[1].detail,
        contains('radio on fire'),
        reason: 'the reason is the whole value of the check having failed',
      );
      expect(
        results[2].status,
        CheckStatus.pass,
        reason: 'a harness that stops at the first fault wastes the trip',
      );
    });

    test('every result is timed, including the one that threw', () async {
      final report = await runFieldReport(
        _ctx(env),
        groups: [
          _group('g', [('boom', (_) async => throw StateError('x'))]),
        ],
      );
      expect(report.allResults.single.elapsedMs, isNotNull);
    });
  });

  group('skipped is not failed', () {
    test('a bridge-facing probe with no transport SKIPS', () async {
      // The default battery with no transport: every link check must skip,
      // and NONE of them may fail. A yard trip that reports twelve failures
      // because the bridge was off is a yard trip that teaches nobody
      // anything.
      final report = await runFieldReport(_ctx(env));
      final linkResults = report.sections
          .firstWhere((s) => s.title == 'The link')
          .results;
      expect(linkResults, isNotEmpty);
      for (final r in linkResults.where((r) => r.id != 'link.transport')) {
        expect(
          r.status,
          isNot(CheckStatus.fail),
          reason: '${r.id} must skip, not fail, with nothing connected',
        );
      }
    });

    test('the headline distinguishes them', () {
      const skipped = FieldReport(
        startedUnixMs: 0,
        appVersion: 't',
        sections: [
          ReportSection('s', [CheckResult.skip('a', 'A')]),
        ],
      );
      expect(skipped.headline, contains('could not run'));
      expect(skipped.headline, isNot(contains('FAILED')));

      const failed = FieldReport(
        startedUnixMs: 0,
        appVersion: 't',
        sections: [
          ReportSection('s', [CheckResult.fail('a', 'A')]),
        ],
      );
      expect(failed.headline, contains('FAILED'));
    });
  });

  group('the destructive check is opt-in', () {
    test('it is absent by default', () async {
      final report = await runFieldReport(_ctx(env));
      expect(
        report.allResults.map((r) => r.id),
        isNot(contains('net.rollback')),
        reason:
            'it breaks the Wi-Fi link on purpose; running it unasked mid-cook '
            'would be a bad surprise',
      );
    });

    test('and present when asked for, last', () async {
      final report = await runFieldReport(_ctx(env), includeDestructive: true);
      expect(report.sections.last.title, contains('Destructive'));
      expect(
        report.allResults.last.id,
        'net.rollback',
        reason: 'nothing after it would be trustworthy anyway',
      );
    });
  });

  group('progress is reported per check', () {
    test('so a minute-long BLE transfer does not look hung', () async {
      final seen = <(String, int, int)>[];
      await runFieldReport(
        _ctx(env),
        groups: [
          _group('g', [
            ('a', (_) async => const CheckResult.pass('a', 'A')),
            ('b', (_) async => const CheckResult.pass('b', 'B')),
          ]),
        ],
        onProgress: (r, done, total) => seen.add((r.id, done, total)),
      );
      expect(seen, [('a', 1, 2), ('b', 2, 2)]);
    });
  });

  group('the rendered report', () {
    final report = FieldReport(
      startedUnixMs: DateTime(2026, 8, 5, 14, 30).millisecondsSinceEpoch,
      finishedUnixMs: DateTime(2026, 8, 5, 14, 33).millisecondsSinceEpoch,
      appVersion: '1.0.0',
      sections: const [
        ReportSection('The phone', [
          CheckResult.fail(
            'notify.permission',
            'Notifications allowed',
            detail: 'DENIED — nothing this app posts reaches the user.',
          ),
          CheckResult.info(
            'ble.history',
            'BLE throughput',
            data: {'bytes/sec': 4200, 'battery %': null},
          ),
        ]),
      ],
    );

    test('is greppable — one fixed marker at the start of every check line',
        () {
      final lines = report.render().split('\n');
      final checkLines = lines.where(
        (l) => l.startsWith('PASS') || l.startsWith('FAIL') ||
            l.startsWith('SKIP') || l.startsWith('INFO'),
      );
      expect(checkLines, hasLength(2));
      expect(
        checkLines.first,
        startsWith('FAIL'),
        reason: 'grep FAIL is meant to be the whole triage step',
      );
    });

    test('carries the id, the title, the detail and every measurement', () {
      final text = report.render();
      expect(text, contains('notify.permission'));
      expect(text, contains('Notifications allowed'));
      expect(text, contains('DENIED'));
      expect(text, contains('bytes/sec: 4200'));
    });

    test('renders an absent measurement as absent, never as zero', () {
      // The house rule, applied to the diagnostics that verify the house rule.
      final text = report.render();
      expect(text, contains('battery %: (absent)'));
      expect(text, isNot(contains('battery %: 0')));
      expect(text, isNot(contains('battery %: null')));
    });

    test('leads with the verdict and the counts', () {
      final text = report.render();
      final head = text.split('\n').take(8).join('\n');
      expect(head, contains('verdict'));
      expect(head, contains('1 FAILED'));
      expect(head, contains('counts'));
    });

    test('names an incomplete run rather than pretending it finished', () {
      const partial = FieldReport(
        startedUnixMs: 0,
        appVersion: 't',
        sections: [],
      );
      expect(partial.render(), contains('(incomplete)'));
    });
  });

  group('the filename sorts and says what it is', () {
    test('date and time, zero padded', () {
      final name = fieldReportFileName(
        DateTime(2026, 8, 5, 9, 7).millisecondsSinceEpoch,
      );
      expect(name, 'smokebridge-field-report-20260805-0907.txt');
    });
  });

  group('the checks that need no bridge still answer', () {
    test('the escalation ladder is verified against the device clock',
        () async {
      final report = await runFieldReport(_ctx(env));
      final rung = report.allResults.firstWhere(
        (r) => r.id == 'notify.escalation',
      );
      expect(rung.status, CheckStatus.pass);
      expect(rung.data['fresh'], 0);
    });

    test('the schema check reports the real version and row counts', () async {
      final report = await runFieldReport(_ctx(env));
      final schema = report.allResults.firstWhere((r) => r.id == 'db.schema');
      expect(schema.status, CheckStatus.pass);
      expect(schema.data['user_version'], 2);
      expect(schema.data.containsKey('cooks'), isTrue);
      expect(schema.data.containsKey('samples with no wall clock'), isTrue);
    });

    test('the phone identity carries whatever the platform said', () async {
      final report = await runFieldReport(_ctx(env));
      final phone = report.allResults.firstWhere(
        (r) => r.id == 'phone.identity',
      );
      expect(phone.data['platform'], 'android');
      expect(phone.data['app version'], isNotNull);
    });
  });
}
