/// A23.1 — the resume/persistence coordinate for guided setup
/// (design 13 §13.2, §13.2.4).
///
/// WHY a separate enum, not the live `SetupState`: `prefs.setupResumeAt`
/// (§13.2.4) is written at every proof point so that killing the app at hop 2
/// re-enters at hop 2. The persisted thing must be a *stable, coarse*
/// coordinate — one value per hop boundary — not the ~40-case sealed
/// `SetupState`, whose names and fields will churn as screens are built.
/// A `SetupStage` survives a schema bump; a serialized `SetupBaseListening`
/// would not.
///
/// The order of the values is the order of the three hops plus their
/// bookends, so `index` is a monotonic "how far did we get" measure.
library;

/// Where a setup attempt had reached, coarse enough to persist and resume.
///
/// One value per hop boundary (§13.2): [findBridge]/[pair] are hop 1,
/// [baseListen] is hop 2, [network]/[applying] are hop 3. [preflight] is
/// hop 0 (§13.2.0) and [done] is the landing (§13.2.4).
enum SetupStage {
  /// Hop 0 — adapter/permission/location gate (§13.2.0). Nothing persisted
  /// resumes *into* preflight; it is always re-run on entry.
  preflight,

  /// Hop 1, first half — the BLE scan/find list (§13.2.1).
  findBridge,

  /// Hop 1, second half — bonding and its four outcomes (§13.2.1).
  pair,

  /// Hop 2 — listening for the Smoke X base over LoRa (§13.2.2).
  baseListen,

  /// Hop 3, first half — the Wi-Fi network picker (§13.2.3).
  network,

  /// Hop 3, second half — the config write and the narrated handoff
  /// (§13.2.3). A resume lands here at the picker, never mid-handoff.
  applying,

  /// The flow completed (or every remaining hop was skipped) (§13.2.4).
  done,
}
