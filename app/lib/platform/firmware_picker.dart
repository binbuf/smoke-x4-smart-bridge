/// Picking a firmware `.bin` (N15.20).
///
/// Registers a real source using the platform's document picker through
/// `file_selector`, which is a first-party Flutter plugin and needs no new
/// Android permission (the Storage Access Framework grants per-file access at
/// pick time, which is exactly the scope wanted).
///
/// The image is streamed rather than read into memory: an ESP32-S3 app image is
/// a couple of megabytes today and the OTA path is already a stream, so there
/// is no reason for the picker to be the one place that buffers it.
///
/// OTA upload itself is HTTP-only ([BridgeTransport.uploadOta]); this seam only
/// produces the stream.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// A picked firmware image, ready to hand to the streamed OTA upload.
class PickedFirmware {
  const PickedFirmware({
    required this.name,
    required this.lengthBytes,
    required this.bytes,
  });

  final String name;
  final int lengthBytes;

  /// A plain file read, so the OTA path can back-pressure normally.
  final Stream<List<int>> bytes;
}

/// Opens the OS document picker for a firmware `.bin`.
///
/// Returns null when the user cancels — a cancel is an outcome, not an error,
/// and the screen must return to its resting state rather than reporting a
/// failure nobody caused.
Future<PickedFirmware?> pickFirmwareImage() async {
  const typeGroup = XTypeGroup(
    label: 'Firmware',
    extensions: ['bin'],
    // Some pickers filter on MIME rather than extension, and an unfiltered
    // picker is how somebody uploads a photo to a bootloader.
    mimeTypes: ['application/octet-stream'],
  );
  final file = await openFile(acceptedTypeGroups: const [typeGroup]);
  if (file == null) {
    return null;
  }
  final length = await file.length();
  return PickedFirmware(
    name: file.name,
    lengthBytes: length,
    bytes: File(file.path).openRead(),
  );
}
