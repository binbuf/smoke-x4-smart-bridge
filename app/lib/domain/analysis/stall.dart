/// N1.12 — the stall detector.
///
/// The classic barbecue evaporative plateau. Worth surfacing because it
/// *prevents* a wrong action: "the stall is normal, do not raise the pit".
///
///   enter:  food probe, `|slope| < 2 °F/hr` sustained ≥ 30 min, 140–180 °F
///   exit:   `slope > 4 °F/hr` sustained ≥ 15 min
///
/// The sustain windows are the hysteresis: a probe hovering at either threshold
/// must not oscillate.
library;

import '../entities/probe.dart';
import 'rate_of_change.dart';
import 'series.dart';

const double stallEnterSlopeFPerHr = 2;
const double stallExitSlopeFPerHr = 4;
const int stallEnterSustainS = 1800;
const int stallExitSustainS = 900;
const double stallBandLowF = 140;
const double stallBandHighF = 180;

/// Feed samples in order; read [stalled] (or the return of [add]).
class StallDetector {
  StallDetector({this.role = ProbeRole.food});

  final ProbeRole role;

  final List<TempPoint> _series = [];
  bool _stalled = false;
  int? _enterHeldSince;
  int? _exitHeldSince;

  bool get stalled => _stalled;

  /// Returns the stall state after ingesting the sample at [t].
  bool add(int t, double? f) {
    if (role != ProbeRole.food) {
      return false;
    }
    _series.add((t: t, f: f));
    // Keep ~45 min: enough for the 10-minute slope plus the sustain windows.
    while (_series.length > 2 && _series.first.t < t - 2700) {
      _series.removeAt(0);
    }

    final slope = rateOfChange(_series, atT: t);

    if (!_stalled) {
      final entering =
          slope != null &&
          slope.abs() < stallEnterSlopeFPerHr &&
          f != null &&
          f >= stallBandLowF &&
          f <= stallBandHighF;
      if (entering) {
        _enterHeldSince ??= t;
        if (t - _enterHeldSince! >= stallEnterSustainS) {
          _stalled = true;
          _exitHeldSince = null;
        }
      } else {
        _enterHeldSince = null;
      }
    } else {
      final exiting = slope != null && slope > stallExitSlopeFPerHr;
      if (exiting) {
        _exitHeldSince ??= t;
        if (t - _exitHeldSince! >= stallExitSustainS) {
          _stalled = false;
          _enterHeldSince = null;
        }
      } else {
        _exitHeldSince = null;
      }
    }
    return _stalled;
  }
}
