/// cookgen — synthesizes physically plausible cook data (design 10 §10.3).
///
/// Newton cooling toward a wandering pit, an event repertoire (stall,
/// lid-open, detach, dropout, °C switch), and real .smk/.mrk emission in the
/// P1 wire format. Deterministic from a seed; `tools/sim` consumes this
/// library to generate scenarios in-process.
library;

export 'src/scenarios.dart';
export 'src/smk_io.dart';
export 'src/thermal.dart';
