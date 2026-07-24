/// F14.1's image inspector, in Dart.
///
/// **Hand-written, not generated** — the layout it parses belongs to
/// Espressif, not to `protocol/records.yaml`. It lives here rather than in
/// one tool because two of them need it: `tools/sim` (so the fake bridge
/// refuses the same images the real one does) and `tools/flash` (so the
/// merged-image builder can name what it just packed).
///
/// The C original is `firmware/components/app_ota/ota_image.c`, and the two
/// parse the same committed fixtures under `protocol/fixtures/ota/`. Any
/// disagreement between them is a defect in one, not a dialect.
///
/// Why the header is checked at all (design 06 §6.2): the likeliest
/// mis-upload is not a corrupt file, it is **the wrong one of the two files
/// this project ships** — the merged image (flashable at `0x0`, starts with
/// the bootloader) instead of the app-only OTA image. Writing the merged
/// image into an OTA slot produces a board that does not boot, and there is
/// no second board.
library;

import 'dart:typed_data';

/// `esp_image_header_t` (24 B) + `esp_image_segment_header_t` (8 B) +
/// `esp_app_desc_t`'s first 256 B.
const int otaHeaderMin = 288;
const int espChipIdEsp32s3 = 0x0009;

const int _offMagic = 0;
const int _offChipId = 12;
const int _offAppDesc = 32;
const int _offVersion = 48;
const int _offProject = 80;
const int _offIdfVer = 144;
const int _descStrLen = 32;

const int _imageMagic = 0xE9;
const int _appDescMagic = 0xABCD5432;

class OtaImageInfo {
  const OtaImageInfo({
    required this.ok,
    required this.reason,
    this.chipId = 0,
    this.version = '',
    this.project = '',
    this.idfVer = '',
  });

  final bool ok;

  /// Distinct per failure. "invalid image" with no detail is what makes a
  /// support conversation take an hour.
  final String reason;
  final int chipId;

  /// Read and **reported, never enforced** — a fork that renames its CMake
  /// project should not be locked out of its own hardware.
  final String version;
  final String project;
  final String idfVer;
}

String _descStr(Uint8List b, int off) {
  final end = off + _descStrLen;
  final buf = StringBuffer();
  for (var i = off; i < end && i < b.length; i++) {
    if (b[i] == 0) break;
    buf.writeCharCode(b[i]);
  }
  return buf.toString();
}

/// Inspects the front of an image. Fewer than [otaHeaderMin] bytes is
/// `header_incomplete` — undecided, not invalid, because a caller may be
/// streaming.
OtaImageInfo inspectOtaImage(List<int> bytes) {
  final b = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (b.length < otaHeaderMin) {
    return const OtaImageInfo(ok: false, reason: 'header_incomplete');
  }
  if (b[_offMagic] != _imageMagic) {
    return const OtaImageInfo(ok: false, reason: 'not_an_esp_image');
  }
  final view = ByteData.sublistView(b);
  final chipId = view.getUint16(_offChipId, Endian.little);
  if (chipId != espChipIdEsp32s3) {
    return OtaImageInfo(ok: false, reason: 'wrong_chip', chipId: chipId);
  }
  // The clause that catches the merged image and `bootloader.bin`: both
  // carry 0xE9 and the right chip id, and neither has an `esp_app_desc_t`.
  if (view.getUint32(_offAppDesc, Endian.little) != _appDescMagic) {
    return OtaImageInfo(
      ok: false,
      // Named for the mistake, not for the byte.
      reason: 'not_an_app_image_use_the_ota_bin',
      chipId: chipId,
    );
  }
  return OtaImageInfo(
    ok: true,
    reason: 'ok',
    chipId: chipId,
    version: _descStr(b, _offVersion),
    project: _descStr(b, _offProject),
    idfVer: _descStr(b, _offIdfVer),
  );
}
