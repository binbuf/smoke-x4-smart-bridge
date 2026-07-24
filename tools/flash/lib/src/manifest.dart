/// T5.2 — the esp-web-tools manifest and the documented esptool command,
/// generated from the same knowledge so neither can drift from the image.
///
/// §10.8 keeps manual flashing documented for people who prefer it. The
/// command is emitted verbatim by the tool so the copy in the README
/// cannot drift from the offsets the build actually produced.
library;

import 'merge.dart';

/// esp-web-tools' `chipFamily` spelling, from the build's own chip.
String chipFamilyFor(String chip) {
  switch (chip) {
    case 'esp32':
      return 'ESP32';
    case 'esp32s2':
      return 'ESP32-S2';
    case 'esp32s3':
      return 'ESP32-S3';
    case 'esp32c3':
      return 'ESP32-C3';
    case 'esp32c6':
      return 'ESP32-C6';
    default:
      throw MergeException('no esp-web-tools chipFamily for "$chip"');
  }
}

/// The merged image's release filename (§10.8).
String mergedImageName(String version) => 'smoke-bridge-heltec-v3-$version.bin';

/// The app-only OTA image's release filename (§10.8).
///
/// Deliberately unmistakable against [mergedImageName]: F14.1 exists
/// because somebody uploads the wrong one anyway, and two names that
/// differ by one word in the middle are two names that get confused.
String otaImageName(String version) => 'smoke-bridge-$version-ota.bin';

/// `manifest.json` for esp-web-tools.
///
/// One part at offset 0 — the merged image — rather than the reference's
/// four-part list, because we already did the merging and a single part
/// cannot be assembled in the wrong order by a browser.
Map<String, Object?> webToolsManifest({
  required String version,
  required FlasherArgs args,
  String? imagePath,
}) => {
  'name': 'Smoke X4 Smart Bridge',
  'version': version,
  // A board carrying a previous install has an otadata and a `cooks`
  // filesystem that a fresh flash should not inherit silently.
  'new_install_prompt_erase': true,
  'builds': [
    {
      'chipFamily': chipFamilyFor(args.chip),
      'parts': [
        {'path': imagePath ?? mergedImageName(version), 'offset': 0},
      ],
    },
  ],
};

/// §10.8's manual command, with the real chip, offset and filename.
String esptoolCommand({
  required String version,
  required FlasherArgs args,
  String port = '<PORT>',
}) =>
    'python -m esptool --chip ${args.chip} -p $port -b 460800 '
    'write_flash 0x0 ${mergedImageName(version)}';
