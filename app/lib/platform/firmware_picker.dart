/// Picking a firmware `.bin` (newapp §C.5, §F "Firmware").
///
/// [FirmwareImageSource] has existed as a seam since A12.6 with **nothing
/// registered in it**, so the firmware screen explained the web installer and
/// the USB route instead of offering an update — correctly, by this app's own
/// no-dead-controls rule, but it is the wrong side of that rule to be on when
/// the transport underneath is finished and tested.
///
/// This registers a real source using the platform's document picker through
/// `file_selector`, which is a first-party Flutter plugin and needs no new
/// Android permission (the Storage Access Framework grants per-file access at
/// pick time, which is exactly the scope wanted).
///
/// The image is streamed rather than read into memory: an ESP32-S3 app image
/// is a couple of megabytes today and the OTA path is already a stream, so
/// there is no reason for the picker to be the one place that buffers it.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../data/transport/bridge_transport.dart';

/// A [FirmwareImageSource] backed by the OS document picker.
///
/// Returns null when the user cancels — a cancel is an outcome, not an error,
/// and the screen must return to its resting state rather than reporting a
/// failure nobody caused.
Future<FirmwareImage?> pickFirmwareImage() async {
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
  return FirmwareImage(
    name: file.name,
    lengthBytes: length,
    // `openRead` on the real file rather than `file.openRead()`, so the stream
    // is a plain file read the OTA path can back-pressure normally.
    bytes: File(file.path).openRead(),
  );
}
