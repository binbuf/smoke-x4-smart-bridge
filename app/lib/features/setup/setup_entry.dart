/// **Re-entry** — where guided setup should pick up, given what this phone
/// already knows (design 16 §16.3, 13 §13.2.4).
///
/// WHY this file exists: the three-hop machine is good at *first-time* setup
/// and bad at *coming back*. Every door into `/setup` — the Bridge tab's "Run
/// setup again", a factory reset, "Forget this bridge", the launch gate — used
/// to open on hop 0 and walk a returning user through a bond they already have,
/// a base they already paired and a network they already joined. That is the
/// complaint this file answers: **entering setup with knowledge must not throw
/// the knowledge away.**
///
/// It is the setup-side twin of `domain/situation/situation.dart`: same facts
/// in, but instead of "what should the banner say" it answers "which hop is
/// actually unfinished". Sharing [SituationFacts] is deliberate — one truth
/// model for recovery means the banner on `/live` and the screen inside
/// `/setup` can never disagree about what is wrong.
///
/// **Pure.** Facts in, one [SetupResumePlan] out. No I/O, no Flutter, no
/// machine — so every re-entry path is decidable at a desk, which is the only
/// way they get tested at all. The acting on it is [SetupMachine.startFrom].
library;

import 'package:flutter/foundation.dart';

import '../../domain/situation/situation.dart';
import 'setup_stage.dart';

/// What a re-entry into setup is *for*. One value per door back in, and the
/// order is the priority the reconciler applies (identity first, because it
/// invalidates every other conclusion).
enum SetupResumeKind {
  /// Nothing to skip: this phone has never met a bridge. The original
  /// three-hop flow, from hop 0.
  fresh,

  /// This phone forgot, but the bridge did not (§16.3 #4). The pairing is
  /// still live on the device side, so setup **adopts** it: reconnect, prove
  /// the identity, name it — and never ask for a passkey the user already
  /// entered once.
  adoptBridge,

  /// Reached and healthy, but it has never met a Smoke X (§16.3 #8). Hop 2 is
  /// the only unfinished hop; nothing else is wrong.
  pairBase,

  /// A bond exists and the network does not — or the user came back
  /// deliberately to change it. Hop 3, and hops 1 and 2 stay done.
  addNetwork,

  /// The bridge answering is **not the one this phone was set up with**
  /// (§16.3 #7). This really is a fresh setup — but the user is told why
  /// first, because being silently returned to step one is the thing that
  /// makes an app feel broken. Never resolved automatically: adopting a reset
  /// bridge silently would attach this phone's history to a device that did
  /// not record it.
  bridgeWasReset;

  /// The coarse coordinate this re-entry lands on — the same [SetupStage] the
  /// flow persists as `setupResumeAt`, so a resumed flow and a restored one
  /// take the identical route in.
  SetupStage get stage => switch (this) {
    SetupResumeKind.fresh => SetupStage.findBridge,
    SetupResumeKind.bridgeWasReset => SetupStage.findBridge,
    SetupResumeKind.adoptBridge => SetupStage.pair,
    SetupResumeKind.pairBase => SetupStage.baseListen,
    SetupResumeKind.addNetwork => SetupStage.network,
  };

  /// Whether this re-entry skips work the phone already did. `fresh` and
  /// `bridgeWasReset` do not — they start at the top, and say so.
  bool get skipsAhead =>
      this == SetupResumeKind.adoptBridge ||
      this == SetupResumeKind.pairBase ||
      this == SetupResumeKind.addNetwork;
}

/// Where setup should pick up, and everything the copy needs to say why.
///
/// Deliberately flat and serialisable-shaped: it is passed in from a route, a
/// situation banner, or derived from stored preferences, and none of those can
/// hand over a live transport.
@immutable
class SetupResumePlan {
  const SetupResumePlan({
    required this.kind,
    this.bridgeName = '',
    this.bridgeId,
    this.bleDeviceId,
    this.reachedBridgeId,
    this.hasNetwork = false,
    this.lastSeenUnixMs,
  });

  /// The first-time flow: nothing known, nothing skipped.
  static const SetupResumePlan fresh = SetupResumePlan(
    kind: SetupResumeKind.fresh,
  );

  final SetupResumeKind kind;

  /// What to call it on screen. Empty when this phone never learned a name —
  /// the copy then falls back to "your bridge" rather than printing an id.
  final String bridgeName;

  /// The bridge identity this phone was set up with (`device_info.id`).
  final String? bridgeId;

  /// The OS address to dial over Bluetooth. **Without it there is no lane back
  /// in**, so a plan that has none is downgraded to [SetupResumeKind.fresh]
  /// by [setupResumePlanFor]: hop 1 is then the only honest door.
  final String? bleDeviceId;

  /// The identity that actually answered, when it differs from [bridgeId].
  /// Only set on [SetupResumeKind.bridgeWasReset].
  final String? reachedBridgeId;

  /// Whether this phone already has a Wi-Fi address for the bridge. It changes
  /// what hop 3 is *for*: adding a network the bridge has never had, versus
  /// swapping one it already has. Saying the wrong one is how a returning user
  /// concludes the app forgot everything.
  final bool hasNetwork;

  final int? lastSeenUnixMs;

  SetupStage get stage => kind.stage;
  bool get skipsAhead => kind.skipsAhead;

  SetupResumePlan copyWith({
    SetupResumeKind? kind,
    String? bridgeName,
    String? bridgeId,
    String? bleDeviceId,
    String? reachedBridgeId,
    bool? hasNetwork,
    int? lastSeenUnixMs,
  }) => SetupResumePlan(
    kind: kind ?? this.kind,
    bridgeName: bridgeName ?? this.bridgeName,
    bridgeId: bridgeId ?? this.bridgeId,
    bleDeviceId: bleDeviceId ?? this.bleDeviceId,
    reachedBridgeId: reachedBridgeId ?? this.reachedBridgeId,
    hasNetwork: hasNetwork ?? this.hasNetwork,
    lastSeenUnixMs: lastSeenUnixMs ?? this.lastSeenUnixMs,
  );

  @override
  String toString() =>
      'SetupResumePlan(${kind.name}, name: $bridgeName, id: $bridgeId)';
}

/// Reconcile what the phone remembers against what is observable, and return
/// the single hop setup should open on.
///
/// The ordering is the whole design, and it mirrors `reconcile()` in
/// `domain/situation` for exactly the reason that function gives: a mismatch
/// diagnosed in the wrong order sends someone to the yard for nothing.
///
///  1. **Identity**, because a different bridge invalidates every other
///     conclusion — and is the one case the app must not resolve itself.
///  2. **Does this phone know a bridge at all?** A bond the *device* still
///     holds is adoptable; nothing at all is a first-time setup.
///  3. **Is there a lane back in?** With no Bluetooth address to dial there is
///     nothing to skip, however much is remembered: hop 1 is the only door.
///  4. **Hop 2 before hop 3**, because RF pairing is the hop that needs the
///     user at a second device and it ends with a real temperature (§13.2).
///  5. Otherwise the bond stands and the network is what is left.
SetupResumePlan setupResumePlanFor(SituationFacts f) {
  final remembered = f.rememberedBridgeId;
  final reached = f.reachedDeviceId;
  final name = f.bondedBridgeName ?? f.visibleApSsid ?? '';

  // 1. Identity. Never automatic (§16.3): the user is told, then chooses.
  if (reached != null &&
      remembered != null &&
      reached.isNotEmpty &&
      remembered.isNotEmpty &&
      reached != remembered) {
    return SetupResumePlan(
      kind: SetupResumeKind.bridgeWasReset,
      bridgeName: name,
      bridgeId: remembered,
      reachedBridgeId: reached,
      bleDeviceId: f.rememberedBleDeviceId,
      hasNetwork: (f.rememberedBaseUrl ?? '').isNotEmpty,
      lastSeenUnixMs: f.lastSeenUnixMs,
    );
  }

  // 2. This phone knows nothing. If the bridge still names itself — an OS
  //    bond, or its own access point in range — the *device* holds the
  //    identity and it still holds it, so adopting is safe.
  if (!f.remembersAnything) {
    if (name.isNotEmpty) {
      return SetupResumePlan(
        kind: SetupResumeKind.adoptBridge,
        bridgeName: name,
      );
    }
    return SetupResumePlan.fresh;
  }

  // 3. Remembered, but with no Bluetooth address there is nothing to dial and
  //    so nothing to skip. Setup drives over Bluetooth; hop 1 is the door.
  final ble = f.rememberedBleDeviceId;
  if (ble == null || ble.isEmpty) {
    return SetupResumePlan(
      kind: SetupResumeKind.fresh,
      bridgeName: name,
      bridgeId: remembered,
      lastSeenUnixMs: f.lastSeenUnixMs,
    );
  }

  final base = SetupResumePlan(
    kind: SetupResumeKind.addNetwork,
    bridgeName: name,
    bridgeId: remembered,
    bleDeviceId: ble,
    hasNetwork: (f.rememberedBaseUrl ?? '').isNotEmpty,
    lastSeenUnixMs: f.lastSeenUnixMs,
  );

  // 4. Reached, and it has never met a Smoke X. Hop 2, and nothing else is
  //    wrong — so nothing else is asked.
  if (f.pairedToBase == false) {
    return base.copyWith(kind: SetupResumeKind.pairBase);
  }

  // 5. The bond stands. What is left is the network — which is also what
  //    "Run setup again" means to someone changing their Wi-Fi.
  return base;
}
