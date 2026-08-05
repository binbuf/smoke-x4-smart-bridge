/// Editable alarm rules, both tiers (newapp §G.2).
///
/// **The biggest missing feature, and the one with the sharpest edge.** Not one
/// rule was editable before this: the bridge's nine ran with hard-coded
/// thresholds and the app's advisory ones were a `const` map behind a null
/// callback. The rule editor is what makes "settings control everything" true
/// rather than aspirational.
///
/// **Two tiers, still visibly separate.** This is one type with a [tier]
/// discriminator because they share a shape, not because they share a promise:
///
///  * [AlarmTier.device] runs on the ESP32 and **keeps working with the phone
///    off, flat, or out of range**. The app mirrors its state and never
///    re-decides it.
///  * [AlarmTier.app] is advisory, needs the app running, and never replaces
///    the device tier.
///
/// Listing them as one list of switches would imply the phone tier can be
/// turned off and the device tier cannot, so the editor renders two sections
/// with two stated promises. This library provides the words for both.
///
/// The taxonomy follows MEATER's Add Alert grouping — AMBIENT falls below /
/// rises above, INTERNAL falls below / rises above, TIME elapsed / before the
/// end — plus FireBoard's per-channel bounds, TempPro's beloved pre-alarm
/// offset, and this device's own nine rules.
library;

/// Who runs the rule, and therefore what it promises.
enum AlarmTier {
  /// On the bridge. Survives the phone.
  device,

  /// On this phone. Advisory only.
  app;

  String get label => switch (this) {
    AlarmTier.device => 'On the bridge',
    AlarmTier.app => 'On this phone',
  };

  String get promise => switch (this) {
    AlarmTier.device =>
      'These keep working with your phone switched off, flat or out of range.',
    AlarmTier.app =>
      'Advisory only. These need the app running, and they never replace the '
          'bridge’s own alarms.',
  };
}

/// What a rule watches. The unit of [AlarmRuleSpec.threshold] depends on this —
/// see [thresholdUnit].
enum AlarmRuleType {
  // ── AMBIENT (the pit / ambient probe) ──────────────────────────────
  ambientBelow,
  ambientAbove,

  /// The pit left its configured band, either way. The device's own rule.
  pitOutOfBand,

  /// The pit is falling fast enough that the fire is going out.
  pitCrash,

  // ── INTERNAL (a food probe) ────────────────────────────────────────
  internalBelow,
  internalAbove,

  /// Reached its cook target.
  targetReached,

  /// TempPro's pre-alarm: fire when the probe is within N degrees of target.
  preAlarm,

  // ── TIME ───────────────────────────────────────────────────────────
  /// An amount of time has passed since the cook started.
  timeElapsed,

  /// A time before the cook's estimated end. Needs an ETA to mean anything,
  /// and refuses (like the ETA does) rather than guessing.
  timeBeforeEnd,

  // ── DEVICE HEALTH (device tier only) ───────────────────────────────
  probeUnplugged,
  baseLost,
  batteryLow,
  storageFull,
  restart,

  /// The Smoke X base station's own alarm, relayed.
  baseStationAlarm;

  /// The section header this rule sits under in the add-rule sheet.
  String get group => switch (this) {
    AlarmRuleType.ambientBelow ||
    AlarmRuleType.ambientAbove ||
    AlarmRuleType.pitOutOfBand ||
    AlarmRuleType.pitCrash => 'Ambient',
    AlarmRuleType.internalBelow ||
    AlarmRuleType.internalAbove ||
    AlarmRuleType.targetReached ||
    AlarmRuleType.preAlarm => 'Internal',
    AlarmRuleType.timeElapsed || AlarmRuleType.timeBeforeEnd => 'Time',
    _ => 'The bridge itself',
  };

  String get label => switch (this) {
    AlarmRuleType.ambientBelow => 'Ambient falls below',
    AlarmRuleType.ambientAbove => 'Ambient rises above',
    AlarmRuleType.pitOutOfBand => 'Pit leaves its band',
    AlarmRuleType.pitCrash => 'Pit is crashing',
    AlarmRuleType.internalBelow => 'Internal falls below',
    AlarmRuleType.internalAbove => 'Internal rises above',
    AlarmRuleType.targetReached => 'Target reached',
    AlarmRuleType.preAlarm => 'Nearly at target',
    AlarmRuleType.timeElapsed => 'Time has passed',
    AlarmRuleType.timeBeforeEnd => 'Before the cook ends',
    AlarmRuleType.probeUnplugged => 'A probe is unplugged',
    AlarmRuleType.baseLost => 'Base station lost',
    AlarmRuleType.batteryLow => 'Battery low',
    AlarmRuleType.storageFull => 'Storage nearly full',
    AlarmRuleType.restart => 'The bridge restarted',
    AlarmRuleType.baseStationAlarm => 'The Smoke X is alarming',
  };

  /// One sentence, in the sheet, under the label. Says what will actually
  /// happen — never restates the label.
  String get blurb => switch (this) {
    AlarmRuleType.ambientBelow =>
      'The fire is dropping off. Useful for a charcoal cook overnight.',
    AlarmRuleType.ambientAbove => 'The pit is running away.',
    AlarmRuleType.pitOutOfBand =>
      'Either side of the band you set for this cook.',
    AlarmRuleType.pitCrash =>
      'A fast fall — the fire is going out, not drifting.',
    AlarmRuleType.internalBelow => 'The food is colder than you expected.',
    AlarmRuleType.internalAbove => 'The food has passed a temperature.',
    AlarmRuleType.targetReached => 'The food hit the target for this cook.',
    AlarmRuleType.preAlarm =>
      'A head start, so you are at the smoker before it is done.',
    AlarmRuleType.timeElapsed => 'A plain timer from the cook’s start.',
    AlarmRuleType.timeBeforeEnd =>
      'Uses the estimate, so it stays quiet when the estimate refuses.',
    AlarmRuleType.probeUnplugged => 'A probe left its jack mid-cook.',
    AlarmRuleType.baseLost => 'The bridge stopped hearing the Smoke X.',
    AlarmRuleType.batteryLow => 'The bridge is running out of charge.',
    AlarmRuleType.storageFull =>
      'The bridge is about to start overwriting the oldest readings.',
    AlarmRuleType.restart => 'The bridge rebooted when nobody asked it to.',
    AlarmRuleType.baseStationAlarm =>
      'Relays whatever the Smoke X base is beeping about.',
  };

  /// What [AlarmRuleSpec.threshold] means for this type, or null when the rule
  /// carries none at all.
  AlarmThresholdUnit? get thresholdUnit => switch (this) {
    AlarmRuleType.ambientBelow ||
    AlarmRuleType.ambientAbove ||
    AlarmRuleType.internalBelow ||
    AlarmRuleType.internalAbove => AlarmThresholdUnit.temperatureF10,
    // A pre-alarm is a *distance* from target, not a temperature.
    AlarmRuleType.preAlarm => AlarmThresholdUnit.degreesBelowTarget,
    AlarmRuleType.timeElapsed ||
    AlarmRuleType.timeBeforeEnd => AlarmThresholdUnit.seconds,
    AlarmRuleType.batteryLow => AlarmThresholdUnit.percent,
    AlarmRuleType.storageFull => AlarmThresholdUnit.percent,
    _ => null,
  };

  /// Whether the rule is about one jack. A rule that is not per-probe stores
  /// `jack == null` and the editor does not offer a probe picker.
  bool get isPerProbe => switch (this) {
    AlarmRuleType.internalBelow ||
    AlarmRuleType.internalAbove ||
    AlarmRuleType.targetReached ||
    AlarmRuleType.preAlarm ||
    AlarmRuleType.probeUnplugged ||
    AlarmRuleType.ambientBelow ||
    AlarmRuleType.ambientAbove => true,
    _ => false,
  };

  /// Which tiers can actually run this.
  ///
  /// **Derived from [deviceRuleId], not hand-listed**, so the two can never
  /// disagree: a type the firmware has no rule for is app-tier by definition,
  /// and offering it as a device rule would be a control that cannot work.
  /// The device-health rules go the other way — the phone cannot see the
  /// bridge's battery or its flash, so they are device-only.
  Set<AlarmTier> get tiers {
    if (deviceRuleId == null) {
      return const {AlarmTier.app};
    }
    return switch (this) {
      AlarmRuleType.baseLost ||
      AlarmRuleType.batteryLow ||
      AlarmRuleType.storageFull ||
      AlarmRuleType.restart ||
      AlarmRuleType.baseStationAlarm => const {AlarmTier.device},
      _ => const {AlarmTier.device, AlarmTier.app},
    };
  }

  /// The device's nine, by their firmware rule ids
  /// (`bridge_alarm_rule_str`, 09 §9.2). Used to mirror a raised [Alarm] back
  /// onto the rule that produced it.
  static AlarmRuleType? fromDeviceRule(String rule) => switch (rule) {
    'smoke_x_alarm' => AlarmRuleType.baseStationAlarm,
    'target_reached' => AlarmRuleType.targetReached,
    'pit_out_of_band' => AlarmRuleType.pitOutOfBand,
    'pit_crash' => AlarmRuleType.pitCrash,
    'probe_detached' => AlarmRuleType.probeUnplugged,
    'base_lost' => AlarmRuleType.baseLost,
    'battery_low' => AlarmRuleType.batteryLow,
    'storage_low' => AlarmRuleType.storageFull,
    'system_fault' => AlarmRuleType.restart,
    _ => null,
  };

  /// The wire name, or **null for a rule the firmware does not have**.
  ///
  /// The nine are the nine: `bridge_alarm_rule_str` is the contract and the app
  /// does not get to invent a tenth. Everything else here is app-tier by
  /// construction, which is why [tiers] declines to offer those as device rules
  /// rather than letting the editor write a name the bridge would ignore.
  String? get deviceRuleId => switch (this) {
    AlarmRuleType.baseStationAlarm => 'smoke_x_alarm',
    AlarmRuleType.targetReached => 'target_reached',
    AlarmRuleType.pitOutOfBand => 'pit_out_of_band',
    AlarmRuleType.pitCrash => 'pit_crash',
    AlarmRuleType.probeUnplugged => 'probe_detached',
    AlarmRuleType.baseLost => 'base_lost',
    AlarmRuleType.batteryLow => 'battery_low',
    AlarmRuleType.storageFull => 'storage_low',
    AlarmRuleType.restart => 'system_fault',
    _ => null,
  };

  /// The firmware tunables this rule's [AlarmRuleSpec.threshold] and
  /// [AlarmRuleSpec.windowS] map onto, as `(thresholdKey, windowKey)`.
  ///
  /// **The device's thresholds are global tunables, not per-rule fields.**
  /// `/api/v1/config/alarms` carries `pit_band_f10`, `pit_crash_sustain_s`,
  /// `battery_warn_pct` and nine more beside a rules array holding only
  /// `{rule, enabled, severity}`. That is the shape the firmware has, so it is
  /// the shape this maps onto — inventing a per-rule threshold field would
  /// produce a settings screen writing JSON the bridge discards, which is the
  /// same class of bug as the settings tree's silent no-op.
  (String?, String?) get deviceTunables => switch (this) {
    AlarmRuleType.pitOutOfBand => ('pit_band_f10', 'pit_band_sustain_s'),
    AlarmRuleType.pitCrash => ('pit_crash_below_f10', 'pit_crash_sustain_s'),
    AlarmRuleType.baseLost => (null, 'base_lost_s'),
    AlarmRuleType.batteryLow => ('battery_warn_pct', null),
    AlarmRuleType.storageFull => ('storage_free_pct', null),
    _ => (null, null),
  };
}

/// What a threshold counts in. Kept explicit so an editor never renders
/// "1650 seconds" under a temperature rule.
enum AlarmThresholdUnit {
  /// Tenths of °F, the storage-canonical unit.
  temperatureF10,

  /// Tenths of °F *below* the cook's target.
  degreesBelowTarget,
  seconds,
  percent,
}

/// One rule. Persisted in the `alarm_rules` table; see `database.dart`.
class AlarmRuleSpec {
  const AlarmRuleSpec({
    required this.id,
    required this.bridgeId,
    required this.tier,
    required this.type,
    this.jack,
    this.threshold,
    this.windowS,
    this.enabled = true,
    this.pushedToDevice = false,
    this.lastConfirmedUnixMs,
    this.cookId,
  });

  /// 0 = not saved yet.
  final int id;
  final String bridgeId;
  final AlarmTier tier;
  final AlarmRuleType type;

  /// 1..4, or null for a whole-cook rule.
  final int? jack;

  /// Unit per [AlarmRuleType.thresholdUnit]; null where the type carries none.
  final int? threshold;

  /// Dwell before firing, seconds. Null = instant. A pit band that alarms on
  /// one noisy packet is a pit band nobody leaves switched on.
  final int? windowS;
  final bool enabled;

  /// **Only ever set by a confirmed read-back** (§G.3). A rule that was written
  /// and not verified stays false, and the row says "Not saved to the bridge
  /// yet" rather than claiming success the transport never confirmed.
  final bool pushedToDevice;
  final int? lastConfirmedUnixMs;

  /// Scoped to one cook, or null for a standing rule.
  final int? cookId;

  /// Whether this rule is currently trustworthy as a device-tier promise.
  /// An app-tier rule is always local and always true here.
  bool get isLive => tier == AlarmTier.app || pushedToDevice;

  AlarmRuleSpec copyWith({
    int? id,
    AlarmTier? tier,
    AlarmRuleType? type,
    int? jack,
    bool clearJack = false,
    int? threshold,
    bool clearThreshold = false,
    int? windowS,
    bool? enabled,
    bool? pushedToDevice,
    int? lastConfirmedUnixMs,
    int? cookId,
  }) => AlarmRuleSpec(
    id: id ?? this.id,
    bridgeId: bridgeId,
    tier: tier ?? this.tier,
    type: type ?? this.type,
    jack: clearJack ? null : (jack ?? this.jack),
    threshold: clearThreshold ? null : (threshold ?? this.threshold),
    windowS: windowS ?? this.windowS,
    enabled: enabled ?? this.enabled,
    pushedToDevice: pushedToDevice ?? this.pushedToDevice,
    lastConfirmedUnixMs: lastConfirmedUnixMs ?? this.lastConfirmedUnixMs,
    cookId: cookId ?? this.cookId,
  );

  /// The **merge patch** for `POST /api/v1/config/alarms`, or null for a rule
  /// the device cannot run — which is what disables the row rather than letting
  /// a write appear to succeed and write nothing.
  ///
  /// A rules array of exactly one entry, plus whichever global tunables this
  /// rule owns; the firmware treats every absent field as "leave it alone".
  Map<String, Object?>? toDeviceJson() {
    final ruleId = type.deviceRuleId;
    if (tier != AlarmTier.device || ruleId == null) {
      return null;
    }
    final (thresholdKey, windowKey) = type.deviceTunables;
    return {
      'rules': [
        {'rule': ruleId, 'enabled': enabled},
      ],
      if (thresholdKey != null && threshold != null) thresholdKey: threshold,
      if (windowKey != null && windowS != null) windowKey: windowS,
    };
  }

  /// Whether the device's own `GET /config/alarms` shows what we asked for.
  ///
  /// The write-then-verify pattern in one method (§G.3). It compares **only
  /// what was sent** — a device echoing the other eleven tunables is not a
  /// mismatch — and it **fails closed**: a config it cannot find the rule in is
  /// a config that did not take.
  bool matchesReadBack(Map<String, Object?> config) {
    final sent = toDeviceJson();
    if (sent == null) {
      return false;
    }
    final rules = config['rules'];
    if (rules is! List) {
      return false;
    }
    final echoed = rules
        .whereType<Map<Object?, Object?>>()
        .where((r) => r['rule'] == type.deviceRuleId)
        .firstOrNull;
    if (echoed == null || echoed['enabled'] != enabled) {
      return false;
    }
    for (final entry in sent.entries) {
      if (entry.key == 'rules') {
        continue;
      }
      if (config[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}

/// The nine device rules a fresh bridge runs, as rows the editor can show and
/// edit rather than as a hardcoded const map behind a null callback.
///
/// Thresholds are the firmware's own defaults. They are seeded into the table
/// on first run so the editor has something to render before the device has
/// ever been asked, and each one is marked **unpushed** until a read-back
/// confirms it — the app does not get to claim the bridge agreed.
List<AlarmRuleSpec> defaultDeviceRules(String bridgeId) => [
  for (final (type, threshold, window) in <(AlarmRuleType, int?, int?)>[
    (AlarmRuleType.baseStationAlarm, null, null),
    (AlarmRuleType.targetReached, null, null),
    (AlarmRuleType.pitOutOfBand, null, 120),
    (AlarmRuleType.pitCrash, null, 300),
    (AlarmRuleType.probeUnplugged, null, 60),
    (AlarmRuleType.baseLost, null, 300),
    (AlarmRuleType.batteryLow, 15, null),
    (AlarmRuleType.storageFull, 90, null),
    (AlarmRuleType.restart, null, null),
  ])
    AlarmRuleSpec(
      id: 0,
      bridgeId: bridgeId,
      tier: AlarmTier.device,
      type: type,
      threshold: threshold,
      windowS: window,
    ),
];

/// The app's advisory rules, likewise as real rows.
List<AlarmRuleSpec> defaultAppRules(String bridgeId) => [
  for (final (type, threshold) in <(AlarmRuleType, int?)>[
    (AlarmRuleType.timeBeforeEnd, 30 * 60),
    (AlarmRuleType.preAlarm, 100),
  ])
    AlarmRuleSpec(
      id: 0,
      bridgeId: bridgeId,
      tier: AlarmTier.app,
      type: type,
      threshold: threshold,
    ),
];
