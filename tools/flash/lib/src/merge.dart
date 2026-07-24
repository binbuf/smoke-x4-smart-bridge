/// T5.1 — the merged image, built here rather than shelled out to
/// `esptool merge-bin`.
///
/// `esptool merge-bin` would work. It also puts Python and an esptool
/// version on the critical path of every release and every CI run, for an
/// operation that is **arithmetic**: place four files at four offsets in a
/// `0xFF`-filled buffer. Doing it in Dart makes it a host-tested unit —
/// with the offsets read from the build's own `flasher_args.json` rather
/// than transcribed, which is the actual mitigation, because a transcribed
/// offset is right until the day the partition table moves.
///
/// **The reference's offsets do not transfer.** It merges at
/// `0x0 / 0x8000 / 0x10000 / 0x210000` with a single `factory` app and a
/// SPIFFS blob; ours is `0x0 / 0x8000 / 0xf000 / 0x20000` with dual OTA
/// slots and an `otadata` the reference does not have at all
/// (design 03 §3.5). The root `Makefile` has carried a comment saying so
/// since T1.4.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One file, at one offset.
class FlashPart {
  const FlashPart({
    required this.offset,
    required this.path,
    required this.bytes,
  });

  final int offset;
  final String path;
  final Uint8List bytes;

  int get end => offset + bytes.length;
}

/// Everything `flasher_args.json` tells us. Nothing here is a constant we
/// chose; it all comes out of the build.
class FlasherArgs {
  const FlasherArgs({
    required this.chip,
    required this.flashMode,
    required this.flashSize,
    required this.flashFreq,
    required this.parts,
    required this.appPart,
  });

  final String chip; // esp32s3
  final String flashMode; // dio
  final String flashSize; // 8MB
  final String flashFreq; // 80m
  final List<FlashPart> parts; // sorted by offset
  final FlashPart appPart;

  int get flashSizeBytes => _flashSizeBytes(flashSize);
}

class MergeException implements Exception {
  MergeException(this.message);
  final String message;
  @override
  String toString() => 'MergeException: $message';
}

int _flashSizeBytes(String size) {
  final m = RegExp(r'^(\d+)MB$').firstMatch(size);
  if (m == null) throw MergeException('unrecognised flash size "$size"');
  return int.parse(m.group(1)!) * 1024 * 1024;
}

/// esptool's `esp_image_header_t` byte 2.
const _flashModeCodes = {'qio': 0, 'qout': 1, 'dio': 2, 'dout': 3};

/// esptool's ESP32-S3 frequency encoding (byte 3, low nibble).
const _flashFreqCodes = {'80m': 0xF, '40m': 0x0, '20m': 0x2};

/// Byte 3, high nibble.
const _flashSizeCodes = {
  '1MB': 0,
  '2MB': 1,
  '4MB': 2,
  '8MB': 3,
  '16MB': 4,
  '32MB': 5,
};

/// Reads `flasher_args.json` out of an ESP-IDF build directory and loads
/// every part it names.
FlasherArgs readFlasherArgs(String buildDir) {
  final file = File('$buildDir/flasher_args.json');
  if (!file.existsSync()) {
    throw MergeException(
      'no flasher_args.json in $buildDir — build the firmware first',
    );
  }
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final settings = json['flash_settings'] as Map<String, Object?>? ?? {};
  final extra = json['extra_esptool_args'] as Map<String, Object?>? ?? {};
  final files = json['flash_files'] as Map<String, Object?>? ?? {};
  if (files.isEmpty) {
    throw MergeException('flasher_args.json names no flash_files');
  }

  final parts = <FlashPart>[];
  for (final entry in files.entries) {
    final offset = int.parse(entry.key.replaceFirst('0x', ''), radix: 16);
    final rel = entry.value! as String;
    final f = File('$buildDir/$rel');
    if (!f.existsSync()) {
      throw MergeException('flasher_args.json names $rel, which is missing');
    }
    parts.add(FlashPart(offset: offset, path: rel, bytes: f.readAsBytesSync()));
  }
  parts.sort((a, b) => a.offset.compareTo(b.offset));

  final appRel = (json['app'] as Map<String, Object?>?)?['file'] as String?;
  final appPart = parts.firstWhere(
    (p) => p.path == appRel,
    orElse: () => throw MergeException('flasher_args.json names no app'),
  );

  return FlasherArgs(
    chip: (extra['chip'] as String?) ?? 'esp32s3',
    flashMode: (settings['flash_mode'] as String?) ?? 'dio',
    flashSize: (settings['flash_size'] as String?) ?? '8MB',
    flashFreq: (settings['flash_freq'] as String?) ?? '80m',
    parts: parts,
    appPart: appPart,
  );
}

/// Builds the single image flashable at `0x0`.
///
/// The one behaviour beyond concatenation is esptool's: the image at
/// offset 0 gets flash mode / size / frequency patched into bytes 2–3. For
/// a build whose bootloader was already produced with those settings this
/// is a **no-op**, and the test asserts exactly that — the day it stops
/// being a no-op is the day someone changed a flash setting without
/// changing the bootloader.
Uint8List mergeImage(FlasherArgs args) {
  var end = 0;
  FlashPart? previous;
  for (final part in args.parts) {
    if (previous != null && part.offset < previous.end) {
      throw MergeException(
        '${part.path} at 0x${part.offset.toRadixString(16)} overlaps '
        '${previous.path} which ends at 0x${previous.end.toRadixString(16)}',
      );
    }
    if (part.end > args.flashSizeBytes) {
      throw MergeException(
        '${part.path} ends at 0x${part.end.toRadixString(16)}, past the '
        '${args.flashSize} flash',
      );
    }
    previous = part;
    if (part.end > end) end = part.end;
  }

  // A merged image without ota_data_initial boots nowhere: the bootloader
  // reads otadata to choose a slot, and an erased one on a board with a
  // stale otadata is not the same thing.
  final hasOtaData = args.parts.any((p) => p.path.contains('ota_data'));
  if (!hasOtaData) {
    throw MergeException(
      'no ota_data_initial in flasher_args.json — a merged image without '
      'it does not select a boot slot',
    );
  }

  final out = Uint8List(end)..fillRange(0, end, 0xFF);
  for (final part in args.parts) {
    out.setRange(part.offset, part.end, part.bytes);
  }
  _patchFlashHeader(out, args);
  return out;
}

void _patchFlashHeader(Uint8List image, FlasherArgs args) {
  if (image.length < 4 || image[0] != 0xE9) {
    return; // nothing at offset 0 that carries a flash header
  }
  final mode = _flashModeCodes[args.flashMode];
  final freq = _flashFreqCodes[args.flashFreq];
  final size = _flashSizeCodes[args.flashSize];
  if (mode == null || freq == null || size == null) {
    throw MergeException(
      'unrecognised flash settings ${args.flashMode}/${args.flashFreq}/'
      '${args.flashSize}',
    );
  }
  image[2] = mode;
  image[3] = (size << 4) | freq;
}

/// True when [mergeImage]'s header patch would change nothing — which is
/// the expected state for our own builds, and worth asserting rather than
/// assuming.
bool headerPatchIsNoop(FlasherArgs args) {
  final first = args.parts.first;
  if (first.offset != 0 || first.bytes.length < 4 || first.bytes[0] != 0xE9) {
    return true;
  }
  final mode = _flashModeCodes[args.flashMode]!;
  final freq = _flashFreqCodes[args.flashFreq]!;
  final size = _flashSizeCodes[args.flashSize]!;
  return first.bytes[2] == mode && first.bytes[3] == ((size << 4) | freq);
}
