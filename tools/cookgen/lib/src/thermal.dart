/// The thermal model (T2.1): Newton cooling toward a pit temperature that
/// itself wanders, per probe — so scenarios are *generated*, not recorded.
///
/// Everything is deterministic from the seed. No wall-clock anywhere.
library;

import 'dart:math';

/// One simulated probe.
class ProbeSpec {
  const ProbeSpec({
    required this.role,
    required this.startF,
    this.k = 0.18,
    this.name = '',
  });

  /// probe_role wire value: 1 pit · 2 food · 3 ambient · 0 unused.
  final int role;
  final double startF;

  /// Newton coefficient, per hour: dT/dt = k · (T_pit − T).
  final double k;
  final String name;
}

/// A lid-open excursion: the pit drops [dropF] within ~2 minutes and
/// recovers exponentially over [recoverS].
class LidOpenEvent {
  const LidOpenEvent({required this.atS, this.dropF = 40, this.recoverS = 600});
  final int atS;
  final double dropF;
  final int recoverS;
}

/// The evaporative stall: while active and the probe sits inside the
/// 140–180 °F band, heat input is almost exactly balanced by evaporation.
class StallEvent {
  const StallEvent({
    required this.startS,
    required this.durationS,
    this.plateauF = 157,
  });
  final int startS;
  final int durationS;
  final double plateauF;
}

/// A probe reads detached (sentinel) for a window.
class DetachEvent {
  const DetachEvent({
    required this.probe,
    required this.fromS,
    required this.toS,
  });
  final int probe; // 0-based index
  final int fromS;
  final int toS;
}

/// The base station is flipped to °C at [atS] (values stay canonical °F —
/// only the provenance flag changes; there must be NO cliff in the series).
class CelsiusSwitchEvent {
  const CelsiusSwitchEvent({required this.atS});
  final int atS;
}

/// One simulated instant, before wire encoding.
class ModelSample {
  ModelSample({
    required this.tS,
    required this.tempsF,
    required this.detached,
    required this.sourceCelsius,
    required this.rssi,
  });

  final int tS;
  final List<double> tempsF; // length 4; NaN where unused
  final List<bool> detached; // length 4
  final bool sourceCelsius;
  final int rssi;
}

class CookModel {
  CookModel({
    required this.seed,
    required this.durationS,
    required this.probes,
    this.periodS = 30,
    this.pitSetpointF = 250,
    this.lidOpens = const [],
    this.stalls = const [],
    this.detaches = const [],
    this.celsiusSwitch,
    this.dropoutPct = 0,
  }) : assert(
         probes.length == 4,
         'always model 4 slots; use role 0 for unused',
       );

  final int seed;
  final int durationS;
  final int periodS;
  final double pitSetpointF;
  final List<ProbeSpec> probes;
  final List<LidOpenEvent> lidOpens;
  final List<StallEvent> stalls;
  final List<DetachEvent> detaches;
  final CelsiusSwitchEvent? celsiusSwitch;

  /// 0–100: probability a sample is never emitted (a real reception gap —
  /// the sample is OMITTED, so `t` deltas grow past 45 s; never zeros).
  final double dropoutPct;

  /// Runs the simulation. Deterministic: same seed → identical output.
  List<ModelSample> run() {
    final rand = Random(seed);
    final out = <ModelSample>[];

    // Pit state: bounded random walk + slow drift around the setpoint.
    var pit = pitSetpointF - 30; // coming up to temperature
    final temps = [for (final p in probes) p.startF];

    for (var t = 0; t <= durationS; t += periodS) {
      final dtH = periodS / 3600.0;

      // Pit dynamics: pull toward setpoint, slow sinusoidal wander, noise.
      final pull = (pitSetpointF - pit) * 0.25 * dtH * 60 / 15;
      final wander = 4 * sin(t / 5400 * 2 * pi) * dtH;
      final noise = (rand.nextDouble() - 0.5) * 1.6;
      pit += pull + wander + noise;
      pit = pit.clamp(pitSetpointF - 25, pitSetpointF + 15).toDouble();

      // Lid-open depression: sharp drop, exponential recovery.
      var pitEffective = pit;
      for (final lid in lidOpens) {
        if (t >= lid.atS) {
          final since = t - lid.atS;
          if (since <= lid.recoverS + 1200) {
            const rampS = 120; // the drop develops over ~2 minutes
            final depth = since < rampS
                ? lid.dropF * (since / rampS)
                : lid.dropF * exp(-(since - rampS) / (lid.recoverS / 2.2));
            pitEffective -= depth;
          }
        }
      }

      // Probe dynamics.
      for (var i = 0; i < probes.length; i++) {
        final p = probes[i];
        switch (p.role) {
          case 1: // pit probe reads the (possibly depressed) pit + jitter
            temps[i] = pitEffective + (rand.nextDouble() - 0.5) * 1.2;
          case 2: // food: Newton toward the pit
            var dT = p.k * (pitEffective - temps[i]) * dtH;
            for (final s in stalls) {
              final inWindow = t >= s.startS && t < s.startS + s.durationS;
              final inBand = temps[i] >= 140 && temps[i] <= 180;
              if (inWindow && inBand) {
                // Evaporation balances heat input: pull to the plateau with
                // |slope| well under 2 °F/hr plus tiny noise.
                dT =
                    (s.plateauF - temps[i]) * 0.05 * dtH * 60 / 30 +
                    (rand.nextDouble() - 0.5) * 0.02;
              }
            }
            temps[i] += dT;
          case 3: // ambient
            temps[i] = p.startF + (rand.nextDouble() - 0.5) * 2.0;
          default:
            temps[i] = double.nan;
        }
      }

      // Reception: drop this sample entirely?
      if (dropoutPct > 0 && rand.nextDouble() * 100 < dropoutPct && t != 0) {
        continue;
      }

      final detached = [
        for (var i = 0; i < probes.length; i++)
          probes[i].role == 0 ||
              detaches.any((d) => d.probe == i && t >= d.fromS && t < d.toS),
      ];

      out.add(
        ModelSample(
          tS: t,
          tempsF: List.of(temps),
          detached: detached,
          sourceCelsius: celsiusSwitch != null && t >= celsiusSwitch!.atS,
          rssi: -62 - (rand.nextDouble() * 14).round(),
        ),
      );
    }
    return out;
  }
}
