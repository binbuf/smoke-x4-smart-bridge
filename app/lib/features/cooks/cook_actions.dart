/// The verbs shared between the reader and the cook screens (newapp §C.1,
/// §C.4, §D.6).
///
/// Export, test-alarm, repeat and the confirm sheets live here rather than on
/// one screen because `/live` and `/cooks/:id` both need them and neither owns
/// them. Each one reports what happened in the user's terms — a control that
/// silently no-ops is the failure this app spends most of its copy budget
/// avoiding.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_env.dart';
import '../../data/repos/cook_repository.dart';
import '../../domain/entities/entities.dart';
import '../../domain/plan/plan.dart';
import '../alarms/delivery.dart';
import '../sessions/export.dart';
import '../shell/shell_session.dart';

/// §C.1 — the test alarm, moved off the deleted `/alerts` tab.
///
/// Posts on the **real** critical channel: an in-app toast would prove nothing
/// about the only thing worth testing, which is whether this phone makes a
/// noise at 3 a.m.
Future<void> sendTestAlarm(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await postTestAlarm();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(result.message),
      showCloseIcon: true,
      duration: const Duration(seconds: 6),
    ),
  );
}

/// §C.1 — export whatever the reader is currently showing.
Future<void> exportRunningCook(
  BuildContext context,
  ShellSession session,
) async {
  final snapshot = session.snapshot;
  if (snapshot == null) {
    return;
  }
  await exportSamples(
    context,
    name: session.plan?.title ?? snapshot.sessionName,
    id: snapshot.sessionId ?? 0,
    startedUnixMs: snapshot.startedUnixMs,
    samples: snapshot.samples,
  );
}

/// Writes the CSV and **hands it to the share sheet** (§C.1).
///
/// The old path ended at a snackbar showing an absolute path inside the app's
/// private documents directory — technically honest, practically useless, and
/// `share_plus` had been a declared dependency with no call site since A24.2.
/// The path is still named, because it is what you need when a file does not
/// turn up where you expected; it is just no longer the whole answer.
Future<void> exportSamples(
  BuildContext context, {
  required String name,
  required int id,
  required int? startedUnixMs,
  required List<Sample> samples,
}) async {
  final env = AppEnv.instance;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (env == null) {
    return;
  }
  if (samples.isEmpty) {
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Nothing to export yet — no readings in this cook.'),
      ),
    );
    return;
  }
  try {
    final where = await exportSessionCsv(
      session: CookSession(
        id: id,
        name: name,
        startedUnixMs: startedUnixMs,
      ),
      samples: samples,
      sink: env.exportSink,
    );
    final share = env.shareSheet;
    if (share == null) {
      // No share intent on this platform: name the path rather than offer a
      // button that cannot work.
      messenger?.showSnackBar(
        SnackBar(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Cook saved as CSV'),
              Text(where, style: const TextStyle(fontSize: 12)),
            ],
          ),
          showCloseIcon: true,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }
    await share.shareFile(where, subject: name.isEmpty ? 'Cook' : name);
  } on Object {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Couldn’t save that cook.')),
    );
  }
}

/// §D.6 — "Repeat this cook", with the confirmation that says what it copies.
Future<CookAnnotation?> repeatCook(
  BuildContext context,
  CookRepository repo,
  CookAnnotation cook,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final again = await repo.repeat(cook);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        'Started “${again.displayName()}” with the same targets. '
        'Move its start time if the meat went on earlier.',
      ),
      duration: const Duration(seconds: 6),
      showCloseIcon: true,
    ),
  );
  return again;
}
