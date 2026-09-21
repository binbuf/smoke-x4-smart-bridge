/// N1.4 — a user- or firmware-placed mark on the session timeline.
///
/// Marks are evidence for session anchors ([candidateAnchors]) and for cook
/// stats (lid-open count), never a second sample stream.
///
/// The wire `mark_rec.kind` values are a **subset**: the firmware emits `note`,
/// `wrapped`, `lid_open`, `fuel`, `probe_moved`, `alarm`, `phase_change` and
/// `auto_detected`. The app also lets the user log [spritz] and [turn], which
/// the prototype's mark sheet offers (N5.13) and the graph/timeline draw as
/// their own verticals (N7.7/N8). Those two are app-originated for now; N15
/// must either carry them on the wire or map them when writing a `mark_rec`.
library;

/// Mark kinds. A superset of `mark_rec.kind` — see the library doc.
enum MarkKind {
  note,
  wrapped,
  lidOpen,
  fuel,
  probeMoved,
  alarm,
  phaseChange,
  autoDetected,

  /// User logged a spritz. App-originated (not yet a wire kind).
  spritz,

  /// User logged a turn/rotation. App-originated (not yet a wire kind).
  turn,
}

/// One mark.
class Mark {
  const Mark({
    required this.t,
    required this.kind,
    this.probe = 0,
    this.text = '',
  });

  /// Seconds since session start.
  final int t;
  final MarkKind kind;

  /// 0 = whole cook, 1..4 = a specific jack.
  final int probe;
  final String text;
}
