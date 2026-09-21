/// N0.5 — the bundled-font licence registration, split out of `bootstrap.dart`
/// so it can be exercised by a test without booting the whole app.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registers the SIL OFL 1.1 texts that ship beside the three bundled fonts.
///
/// `LicenseRegistry` is what the licence page reads, so this is the difference
/// between complying with the licence and merely claiming to.
void registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    final archivo = await rootBundle.loadString('assets/fonts/OFL-Archivo.txt');
    yield LicenseEntryWithLineBreaks(const <String>['Archivo'], archivo);

    final inter = await rootBundle.loadString('assets/fonts/OFL-Inter.txt');
    yield LicenseEntryWithLineBreaks(const <String>['Inter'], inter);

    final mono = await rootBundle.loadString(
      'assets/fonts/OFL-JetBrainsMono.txt',
    );
    yield LicenseEntryWithLineBreaks(const <String>['JetBrainsMono'], mono);
  });
}
