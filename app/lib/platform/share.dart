/// The share sheet (newapp §C.1, §F "Data & export").
///
/// `share_plus` has been a declared dependency since A24.2 and had **zero call
/// sites**: the export wrote a file and the snackbar showed its path, which is
/// an outcome only a developer can act on. "Where did my CSV go" is not a
/// question a barbecue app should be able to provoke.
///
/// A seam rather than a direct call, for the same reason every platform touch
/// in this app is one: `flutter test` has no Android intent to hand a file to,
/// and a screen that cannot be tested without a device is a screen that gets
/// tested on a device — that is, rarely.
library;

import 'dart:async';

/// Hands a file to the platform's share sheet.
abstract interface class ShareSheet {
  /// [path] is whatever [ExportSink.write] returned. [subject] is the title an
  /// email client would use.
  Future<void> shareFile(String path, {String subject = ''});
}

/// Records what would have been shared. The test double, and the honest
/// fallback on a platform with no share intent (web, desktop) — where the
/// caller falls back to naming the path instead of offering a dead button.
class RecordingShareSheet implements ShareSheet {
  final List<({String path, String subject})> shared = [];

  @override
  Future<void> shareFile(String path, {String subject = ''}) async {
    shared.add((path: path, subject: subject));
  }
}
