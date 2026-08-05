/// `/device/settings/fieldreport` — run the battery, share the log.
///
/// One screen, one button, one file out. The whole point is that somebody
/// standing next to a smoker can run it without a laptop and hand back a text
/// file that answers every question the desk could not.
///
/// Two deliberate choices:
///
///  * **Progress is per-check, not a spinner.** The BLE history transfer alone
///     can take a minute; a harness that looks hung is a harness somebody
///     force-quits at 40 %, and then the trip was wasted.
///  * **The destructive check is a separate, explicit opt-in** with its cost
///     stated in the same keeps/loses shape every other destructive action in
///     this app uses. It breaks the Wi-Fi link on purpose for about a minute —
///     which is the property being tested, and still a surprise if unasked for.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_env.dart';
import '../../design/design.dart';
import '../../platform/device_facts.dart';
import '../../ui/ui.dart';
import '../shell/shell_scope.dart';
import 'field_probes.dart';
import 'field_report.dart';
import 'field_runner.dart';

class FieldReportRoute extends StatefulWidget {
  const FieldReportRoute({super.key, this.deviceInfo});

  /// Injected by tests; production reads it from the platform layer. Null
  /// rather than `const {}` so a test can assert an EMPTY map is honoured —
  /// the difference between "no facts" and "not asked".
  final Map<String, Object?>? deviceInfo;

  @override
  State<FieldReportRoute> createState() => _FieldReportRouteState();
}

class _FieldReportRouteState extends State<FieldReportRoute> {
  final List<CheckResult> _live = [];
  bool _running = false;
  bool _includeDestructive = false;
  FieldReport? _report;
  int _done = 0;
  int _total = 0;
  String _saved = '';

  Future<void> _run() async {
    final env = AppEnv.instance;
    if (env == null) {
      return;
    }
    setState(() {
      _running = true;
      _live.clear();
      _report = null;
      _saved = '';
      _done = 0;
      _total = 0;
    });
    final report = await runFieldReport(
      ProbeContext(
        env: env,
        transport: ShellScope.maybeOf(context)?.bridge?.transport,
        deviceInfo: widget.deviceInfo ?? deviceFacts(),
      ),
      includeDestructive: _includeDestructive,
      onProgress: (result, done, total) {
        if (mounted) {
          setState(() {
            _live.add(result);
            _done = done;
            _total = total;
          });
        }
      },
    );
    if (mounted) {
      setState(() {
        _report = report;
        _running = false;
      });
    }
    await _save(report);
  }

  /// Writes the report through the same export sink a CSV uses, then offers it
  /// to the share sheet. The path is still named, because it is what you need
  /// when a file does not turn up where you expected.
  Future<void> _save(FieldReport report) async {
    final env = AppEnv.instance;
    if (env == null) {
      return;
    }
    try {
      final where = await env.exportSink.write(
        fieldReportFileName(report.startedUnixMs),
        Stream<List<int>>.value(report.render().codeUnits),
      );
      if (mounted) {
        setState(() => _saved = where);
      }
    } on Object {
      // The report is still on screen and still copyable; failing to write a
      // file must not lose the run that produced it.
    }
  }

  Future<void> _share() async {
    final report = _report;
    final env = AppEnv.instance;
    if (report == null || env == null || _saved.isEmpty) {
      return;
    }
    await env.shareSheet?.shareFile(_saved, subject: 'Smoke Bridge field report');
  }

  Future<void> _confirmDestructive(bool value) async {
    if (!value) {
      setState(() => _includeDestructive = false);
      return;
    }
    final ok = await showCostSheet(
      context,
      title: 'Include the network rollback test?',
      body:
          'The app will ask the bridge to join a network that does not exist, '
          'then wait for it to put itself back. That is the whole point of the '
          'test — but it does mean the Wi-Fi link really goes away for about a '
          'minute.',
      keeps:
          'Every reading. The bridge keeps recording throughout, and Bluetooth '
          'stays connected as the escape hatch.',
      loses:
          'The Wi-Fi link, for roughly a minute. If the rollback is broken, '
          'you may need to reach the bridge on its own network at '
          '192.168.4.1.',
      confirmLabel: 'Include it',
      cancelLabel: 'Skip it',
    );
    setState(() => _includeDestructive = ok);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final report = _report;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Field report')),
      body: SafeArea(
        child: ListView(
          key: const Key('field-report'),
          padding: const EdgeInsets.all(SmokeTokens.s4),
          children: [
            SmokeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'One run, one log',
                    style: SmokeType.title.copyWith(color: t.textHi),
                  ),
                  const SizedBox(height: SmokeTokens.s2),
                  Text(
                    'Checks the things only a real phone and a real bridge can '
                    'answer: whether an alarm actually wakes you, whether the '
                    'background monitor survives, whether writes reach the '
                    'device, and how fast Bluetooth really is. Takes a couple '
                    'of minutes. Stand near the bridge.',
                    style: SmokeType.bodySm.copyWith(color: t.textBody),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SmokeTokens.s3),
            SmokeCard(
              child: SwitchListTile(
                key: const Key('field-report-destructive'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Include the network rollback test'),
                subtitle: const Text(
                  'Breaks the Wi-Fi link on purpose for about a minute.',
                ),
                value: _includeDestructive,
                onChanged: _running
                    ? null
                    : (v) => unawaited(_confirmDestructive(v)),
              ),
            ),
            const SizedBox(height: SmokeTokens.s3),
            PrimaryAction(
              key: const Key('field-report-run'),
              label: _running ? 'Running…' : 'Run the checks',
              icon: Icons.play_arrow_rounded,
              onPressed: _running ? null : () => unawaited(_run()),
            ),
            if (_running || _live.isNotEmpty) ...[
              const SizedBox(height: SmokeTokens.s3),
              if (_total > 0)
                LinearProgressIndicator(
                  value: _done / _total,
                  backgroundColor: t.cardSubtle,
                ),
              const SizedBox(height: SmokeTokens.s2),
              for (final r in _live) _resultRow(t, r),
            ],
            if (report != null) ...[
              const SizedBox(height: SmokeTokens.s4),
              SmokeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      report.headline,
                      style: SmokeType.title.copyWith(color: t.textHi),
                    ),
                    if (_saved.isNotEmpty) ...[
                      const SizedBox(height: SmokeTokens.s2),
                      Text(
                        _saved,
                        style: SmokeType.labelSm.copyWith(color: t.textMuted),
                      ),
                    ],
                    const SizedBox(height: SmokeTokens.s3),
                    PrimaryAction(
                      key: const Key('field-report-share'),
                      label: 'Share the log',
                      icon: Icons.ios_share,
                      onPressed: _saved.isEmpty
                          ? null
                          : () => unawaited(_share()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SmokeTokens.s3),
              // The raw text, selectable, so a phone with no share target can
              // still get the report off it by copy and paste.
              SmokeCard(
                child: SelectableText(
                  report.render(),
                  style: SmokeType.mono.copyWith(color: t.textBody),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultRow(SmokeTokens t, CheckResult r) {
    final role = switch (r.status) {
      CheckStatus.pass => StatusRole.positive,
      CheckStatus.fail => StatusRole.critical,
      CheckStatus.skipped => StatusRole.info,
      CheckStatus.info => StatusRole.info,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: StatusPalette.fill(role),
              borderRadius: BorderRadius.circular(SmokeTokens.radiusChip),
              border: Border.all(color: StatusPalette.border(role)),
            ),
            child: Text(
              r.marker,
              textAlign: TextAlign.center,
              style: SmokeType.labelSm.copyWith(color: t.textHi),
            ),
          ),
          const SizedBox(width: SmokeTokens.s2),
          Expanded(
            child: Text(
              r.title,
              style: SmokeType.bodySm.copyWith(color: t.textBody),
            ),
          ),
        ],
      ),
    );
  }
}
