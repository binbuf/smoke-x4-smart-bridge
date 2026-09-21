/// N1.4 — a user- or firmware-placed mark on the session timeline.
///
/// Marks match the wire `mark_rec.kind` values. They are evidence for session
/// anchors ([candidateAnchors]) and for cook stats (lid-open count), never a
/// second sample stream.
library;

/// Mark kinds, matching `mark_rec.kind`.
enum MarkKind {
  note,
  wrapped,
  lidOpen,
  fuel,
  probeMoved,
  alarm,
  phaseChange,
  autoDetected,
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
