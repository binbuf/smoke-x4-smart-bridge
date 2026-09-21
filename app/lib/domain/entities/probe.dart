/// N1.2 — a probe's physical jack and its assigned role.
///
/// The hardware cannot tell a role from the plug; the *user* assigns one, and
/// role defaults are a convention, not a fact about the socket. The prototype's
/// convention is that **jack 4 is the grate/pit** ([ProbeRole.defaultFor]).
library;

/// The four physical jacks on the Smoke X4 base, 1..4.
enum ProbeJack {
  one(1),
  two(2),
  three(3),
  four(4);

  const ProbeJack(this.n);

  /// 1..4, matching the wire and `Sample.tempsF10` ordering.
  final int n;

  /// The convention the prototype's probe picker opens on.
  ProbeRole get defaultRole => ProbeRole.defaultFor(this);

  /// Parses a 1..4 value, or returns null when out of range.
  static ProbeJack? fromN(int n) {
    for (final j in ProbeJack.values) {
      if (j.n == n) {
        return j;
      }
    }
    return null;
  }

  /// The jack at `index` in a 4-element list (0-based), or null.
  static ProbeJack? fromIndex(int index) =>
      index >= 0 && index < ProbeJack.values.length
      ? ProbeJack.values[index]
      : null;
}

/// What a jack is being used for. The device tiers and gauges need all four;
/// the gauge's two-state question is just `pit` vs not.
enum ProbeRole {
  unused,
  food,
  pit,
  ambient;

  /// **Jack 4 is the pit by default** (NOTES §7.2). Everything else starts
  /// unused rather than guessing that a plugged-in probe is food.
  static ProbeRole defaultFor(ProbeJack jack) =>
      jack == ProbeJack.four ? ProbeRole.pit : ProbeRole.unused;

  String get label => switch (this) {
    ProbeRole.unused => 'Unused',
    ProbeRole.food => 'Food',
    ProbeRole.pit => 'Pit',
    ProbeRole.ambient => 'Ambient',
  };

  bool get isPit => this == ProbeRole.pit;
  bool get isFood => this == ProbeRole.food;
}

/// A probe's *configured* identity — name, role, target and alarm band. Live
/// values travel in `Sample`s; the two meet in the UI, not here.
class Probe {
  const Probe({
    required this.jack,
    this.name = '',
    this.role = ProbeRole.unused,
    this.targetF10,
    this.alarmMinF10,
    this.alarmMaxF10,
  });

  final ProbeJack jack;
  final String name;
  final ProbeRole role;

  /// Final (post-rest) target, tenths °F. Null means no target set.
  final int? targetF10;

  /// The device-tier `pit_out_of_band` alarm band, tenths °F. Null = no band.
  final int? alarmMinF10;
  final int? alarmMaxF10;

  bool get isPit => role == ProbeRole.pit;

  Probe copyWith({
    String? name,
    ProbeRole? role,
    int? targetF10,
    bool clearTarget = false,
    int? alarmMinF10,
    int? alarmMaxF10,
  }) => Probe(
    jack: jack,
    name: name ?? this.name,
    role: role ?? this.role,
    targetF10: clearTarget ? null : (targetF10 ?? this.targetF10),
    alarmMinF10: alarmMinF10 ?? this.alarmMinF10,
    alarmMaxF10: alarmMaxF10 ?? this.alarmMaxF10,
  );
}
