/// `share_plus` behind the [ShareSheet] seam (newapp §C.1).
///
/// The only file in the app that imports `share_plus`, so the seam stays a
/// seam: nothing above `platform/` learns that a share is a platform intent
/// rather than a function call, and `flutter test` never loads the plugin.
library;

import 'package:share_plus/share_plus.dart';

import 'share.dart';

class PluginShareSheet implements ShareSheet {
  const PluginShareSheet();

  @override
  Future<void> shareFile(String path, {String subject = ''}) async {
    await Share.shareXFiles(
      [XFile(path, mimeType: 'text/csv')],
      subject: subject,
    );
  }
}
