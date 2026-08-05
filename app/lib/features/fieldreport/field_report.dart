/// The **field report**: one run on a real phone, one log, everything the
/// desk cannot know.
///
/// A large part of this redesign is provably correct at the desk — 1,177 tests,
/// 27 firmware host suites — and a specific, enumerable part of it is not
/// provable there at all:
///
///  * whether Android actually delivers a critical notification, and whether it
///    lights the screen on **this** OEM (§G.4, and J1 names Samsung, Xiaomi and
///    OnePlus specifically);
///  * whether the `connectedDevice` foreground service survives, or whether the
///    OEM killer takes it anyway;
///  * whether the §E.3 rollback really puts the bridge back — 27/27 host suites
///    prove the state machine, and none of them has ever seen a radio;
///  * whether the alarm-rule mapping onto the firmware's twelve global tunables
///    is right, since it was **inferred from reading C** and has only ever been
///    exercised against `MockTransport`;
///  * what BLE actually negotiates and achieves, which decides §E.6's open
///    question and J2's risk;
///  * whether the chart holds a frame budget on a real 15-hour dataset, which
///    is the profiling spike §H.2's open decision 3 is waiting on.
///
/// So this is a **scripted battery of probes** that runs on the device, records
/// what happened in the device's own words, and produces one shareable text
/// report. It is deliberately a screen in the app rather than an
/// `integration_test`: the interesting checks need the real notification
/// channel, the real foreground service and the real bridge, and a harness that
/// needs a laptop tethered to it is a harness that gets run at a desk, which is
/// the one place these answers are not.
///
/// **This library is pure** — no Flutter, no plugins, no I/O. It is the model
/// and the formatter; `field_probes.dart` holds the checks and
/// `field_report_route.dart` the screen. That split is the same one the whole
/// app uses, and it is why the report's format is testable without a phone.
library;

/// How a check came out.
enum CheckStatus {
  /// It did what it should.
  pass,

  /// It did not, and that is a finding rather than a crash.
  fail,

  /// Could not be run here — no bridge, wrong lane, unsupported platform.
  /// **Distinct from a failure**, because "we did not learn this" and "this is
  /// broken" call for completely different next steps.
  skipped,

  /// Ran, and the answer is a measurement rather than a verdict.
  info,
}

/// One check's outcome.
class CheckResult {
  const CheckResult({
    required this.id,
    required this.title,
    required this.status,
    this.detail = '',
    this.data = const {},
    this.elapsedMs,
  });

  const CheckResult.pass(
    this.id,
    this.title, {
    this.detail = '',
    this.data = const {},
    this.elapsedMs,
  }) : status = CheckStatus.pass;

  const CheckResult.fail(
    this.id,
    this.title, {
    this.detail = '',
    this.data = const {},
    this.elapsedMs,
  }) : status = CheckStatus.fail;

  const CheckResult.skip(this.id, this.title, {this.detail = ''})
    : status = CheckStatus.skipped,
      data = const {},
      elapsedMs = null;

  const CheckResult.info(
    this.id,
    this.title, {
    this.detail = '',
    this.data = const {},
    this.elapsedMs,
  }) : status = CheckStatus.info;

  /// Stable, machine-greppable. Never renumbered — a report from three months
  /// ago has to stay comparable with one from today.
  final String id;
  final String title;
  final CheckStatus status;

  /// One sentence for a human. The *reason*, not a stack trace.
  final String detail;

  /// The measurements. Everything here lands in the report verbatim, because
  /// the point of the exercise is that the desk gets the numbers rather than a
  /// verdict somebody already summarised.
  final Map<String, Object?> data;
  final int? elapsedMs;

  String get marker => switch (status) {
    CheckStatus.pass => 'PASS',
    CheckStatus.fail => 'FAIL',
    CheckStatus.skipped => 'SKIP',
    CheckStatus.info => 'INFO',
  };
}

/// A named group of checks, in the order they ran.
class ReportSection {
  const ReportSection(this.title, this.results);
  final String title;
  final List<CheckResult> results;
}

/// The whole run.
class FieldReport {
  const FieldReport({
    required this.startedUnixMs,
    required this.appVersion,
    required this.sections,
    this.finishedUnixMs,
  });

  final int startedUnixMs;
  final int? finishedUnixMs;
  final String appVersion;
  final List<ReportSection> sections;

  Iterable<CheckResult> get allResults =>
      sections.expand((s) => s.results);

  int countOf(CheckStatus s) =>
      allResults.where((r) => r.status == s).length;

  /// A one-line verdict for the top of the file, so the first thing read is
  /// whether anything is actually wrong.
  String get headline {
    final failed = countOf(CheckStatus.fail);
    final skipped = countOf(CheckStatus.skipped);
    if (failed > 0) {
      return '$failed FAILED, $skipped skipped — see the FAIL lines below.';
    }
    if (skipped > 0) {
      return 'Nothing failed. $skipped check(s) could not run — see SKIP.';
    }
    return 'Everything that ran, passed.';
  }

  /// The report, as the text that gets shared.
  ///
  /// Plain text on purpose: it has to survive being pasted into a chat window,
  /// an email, or an issue, and it has to be greppable. Fixed-width markers at
  /// the start of every line so `grep FAIL` is the whole triage step.
  String render() {
    final b = StringBuffer()
      ..writeln('SMOKE BRIDGE — FIELD REPORT')
      ..writeln('=' * 60)
      ..writeln('app        : $appVersion')
      ..writeln('started    : ${_iso(startedUnixMs)}')
      ..writeln(
        'finished   : ${finishedUnixMs == null ? '(incomplete)' : _iso(finishedUnixMs!)}',
      )
      ..writeln('verdict    : $headline')
      ..writeln(
        'counts     : ${countOf(CheckStatus.pass)} pass · '
        '${countOf(CheckStatus.fail)} fail · '
        '${countOf(CheckStatus.skipped)} skip · '
        '${countOf(CheckStatus.info)} info',
      )
      ..writeln();

    for (final section in sections) {
      if (section.results.isEmpty) {
        continue;
      }
      b
        ..writeln('-' * 60)
        ..writeln('## ${section.title}')
        ..writeln('-' * 60);
      for (final r in section.results) {
        b.write('${r.marker}  ${r.id.padRight(28)}  ${r.title}');
        if (r.elapsedMs != null) {
          b.write('  (${r.elapsedMs} ms)');
        }
        b.writeln();
        if (r.detail.isNotEmpty) {
          for (final line in _wrap(r.detail, 66)) {
            b.writeln('      $line');
          }
        }
        for (final entry in r.data.entries) {
          b.writeln('      · ${entry.key}: ${_value(entry.value)}');
        }
      }
      b.writeln();
    }

    b
      ..writeln('=' * 60)
      ..writeln('END OF REPORT');
    return b.toString();
  }

  static String _iso(int unixMs) =>
      DateTime.fromMillisecondsSinceEpoch(unixMs).toIso8601String();

  /// Renders a value without ever losing the difference between "absent" and
  /// "zero" — the house rule, applied to the diagnostics that verify it.
  static String _value(Object? v) => switch (v) {
    null => '(absent)',
    final List<Object?> l => l.isEmpty ? '(empty)' : l.join(', '),
    _ => '$v',
  };

  static List<String> _wrap(String text, int width) {
    final out = <String>[];
    for (final paragraph in text.split('\n')) {
      var line = '';
      for (final word in paragraph.split(' ')) {
        if (line.isEmpty) {
          line = word;
        } else if (line.length + 1 + word.length <= width) {
          line = '$line $word';
        } else {
          out.add(line);
          line = word;
        }
      }
      out.add(line);
    }
    return out;
  }
}

/// A filename that sorts and says what it is.
String fieldReportFileName(int startedUnixMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(startedUnixMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return 'smokebridge-field-report-'
      '${d.year}${two(d.month)}${two(d.day)}-'
      '${two(d.hour)}${two(d.minute)}.txt';
}
