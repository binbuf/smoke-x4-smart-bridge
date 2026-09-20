/// The reader's half of reconciliation (design 16 §16.3).
///
/// `reconcile()` is the reconciler and it already exists — pure, tested at a
/// desk, facts in and one [Situation] out. What did not exist was anybody
/// **handing it facts**, which is why a model with thirteen named situations
/// had zero consumers and every mismatch in the world still collapsed into
/// "Offline · retry 6".
///
/// This is the gathering step, and only that: it reads what the reader can
/// already see — the launch state, the snapshot, whether a cook is running —
/// and states it as [SituationFacts]. It decides nothing.
///
/// **Two facts are deliberately left `null`, and null means "not known yet".**
/// That distinction is the whole reason every field on [SituationFacts] is
/// nullable, and getting it wrong is how an app tells someone their bridge was
/// reset while it is still booting:
///
///  * **`supportsFullHistory`.** `DashboardSnapshot.fullHistory` is false on
///    *any* Bluetooth lane, not only on old firmware — so feeding it in would
///    raise "your firmware is too old" at every user who happens to be out of
///    Wi-Fi range. The transport's limits are stated by the capability notice
///    on the reader itself; §16.3 #10 is about firmware, and the reader has no
///    firmware fact to offer.
///  * **`deviceClockValid`.** A missing `startedUnixMs` means "no clock" *or*
///    "no session"; the two are indistinguishable from here, and accusing a
///    healthy bridge of having lost the time is worse than saying nothing.
///
/// Identity (`rememberedBridgeId` vs `reachedDeviceId`) is likewise not
/// invented here. Both sides get the same value, so this function can never
/// produce `bridgeWasReset` — the one situation §16.3 says must never be
/// resolved automatically is also the one that needs the persisted bridge id,
/// which lives behind the connection layer, not on the reader.
///
/// **This is a floor, not the destination.** `features/shell/situation_resolver.dart`
/// is the resolver that probes the OS, remembers what the phone knew and
/// *acts* on the remedy. The moment `ShellSession` exposes its verdict, `LiveTab`
/// should read that instead of calling this — one line, because `CookView`
/// already takes the [Situation] as a parameter and does not care who
/// reconciled it. Until then the reader states what it can see rather than
/// showing nothing, which is how a thirteen-situation model ended up with zero
/// consumers in the first place.
library;

import '../../app/connection.dart';
import '../../domain/situation/situation.dart';
import '../dashboard/dashboard_snapshot.dart';

/// A stable stand-in for the bridge's identity. It is compared only against
/// itself (see the library doc), so it can never accuse a bridge of being a
/// different bridge — it exists so `remembersAnything` is true for a phone
/// that has plainly met one.
const String _knownBridge = 'this-bridge';

/// Reconcile what the reader can see.
///
/// [bluetoothOn] and [missingPermission] are passed straight through: the OS
/// facts have to come from the platform seams, and a screen may not go and ask
/// for them (asking costs a permission prompt, and Android stops showing the
/// dialog after two refusals — forever).
Situation liveSituation({
  required LaunchState launch,
  required DashboardSnapshot? snapshot,
  required bool hasRunningCook,
  required int nowUnixMs,
  bool? bluetoothOn,
  String? missingPermission,

  /// When this phone last actually reached the bridge, from the store.
  ///
  /// §16.3: *"`lastSeenUnixMs` is always in the copy when the app cannot reach
  /// the bridge."* The snapshot cannot supply it — going offline means no
  /// snapshot is arriving, and the device counter it used to be derived from
  /// is frozen at whatever it said when the link died, which rendered
  /// "last seen moments ago" for as long as the bridge stayed away. The store
  /// is written on every successful reach, so it is the fact that survives.
  int? lastSeenUnixMs,
}) {
  // Nothing has ever been set up on this phone. Every other fact below would
  // be a guess about a bridge that does not exist.
  if (launch is LaunchNeedsOnboarding) {
    return reconcile(
      SituationFacts(
        bluetoothOn: bluetoothOn,
        missingPermission: missingPermission,
        nowUnixMs: nowUnixMs,
      ),
    );
  }

  final reached = launch is LaunchConnected && snapshot != null;
  final address = snapshot?.address ?? '';
  final sAgo = snapshot?.lastPacketSAgo;

  return reconcile(
    SituationFacts(
      // Remembered: enough that the reconciler knows this phone has met a
      // bridge. The address is echoed on both sides so a lane with no URL (the
      // Bluetooth one) cannot read as "your bridge moved".
      rememberedBridgeId: _knownBridge,
      rememberedBaseUrl: address.isEmpty ? null : address,
      // The store first: it is the only one of the two that keeps counting
      // while the bridge is away. The snapshot's device counter is the
      // fallback for a session that has reached a bridge but never stored it.
      lastSeenUnixMs:
          lastSeenUnixMs ?? (sAgo == null ? null : nowUnixMs - sAgo * 1000),
      hasRunningCook: hasRunningCook,

      bluetoothOn: bluetoothOn,
      missingPermission: missingPermission,

      reachedDeviceId: reached ? _knownBridge : null,
      reachedAddress: reached && address.isNotEmpty ? address : null,
      reachedNetMode: reached ? snapshot.netMode : null,
      // `paired` defaults true on a cache read precisely so an offline
      // snapshot does not cry wolf, so it is only a fact once reached.
      pairedToBase: reached ? snapshot.paired : null,

      nowUnixMs: nowUnixMs,
    ),
  );
}
