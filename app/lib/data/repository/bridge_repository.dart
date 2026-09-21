/// N2.27 — the repository seam.
///
/// This is the **only** source of truth for screens (D3): no widget imports
/// `mock-data`, and no screen knows whether the live implementation is the mock
/// or the real bridge. N15 supplies the real implementation; the interface does
/// not change.
library;

import '../../domain/domain.dart';
import '../content/catalog.dart';
import '../model/alarm_rule.dart';
import '../model/bridge_snapshot.dart';
import '../model/connection_mode.dart';
import '../model/device_info.dart';
import '../model/history_entry.dart';
import '../model/mock_event.dart';

/// A device action with a cost sheet and a progress sheet.
enum DeviceVerb { restart, forget, factoryReset, ota }

/// The contract every screen codes against.
abstract interface class BridgeRepository {
  /// The current snapshot, then every subsequent change.
  Stream<BridgeSnapshot> snapshot();

  /// The value the last emitted snapshot held (never a second source).
  BridgeSnapshot get current;

  /// Past cooks, newest first.
  Stream<List<HistoryEntry>> watchHistory();

  /// The current history list.
  List<HistoryEntry> get history;

  /// The reviewer-owned content library.
  CatalogTable get catalog;

  /// The three transport modes and their capability flags.
  List<ConnectionMode> get connectionModes;

  /// The alarm-rule catalogue (nine device + three app).
  List<AlarmRule> get alarmRules;

  /// The mock event-bus catalogue the dev panel fires.
  List<MockEventSpec> get mockEvents;

  /// Device identity and diagnostics.
  DeviceInfo get device;

  /// The firmware fixture.
  FirmwareInfo get firmware;

  /// Which scenario is active (dev panel).
  String get activeScenarioKey;

  /// Every scenario fixture (dev panel).
  List<Scenario> get scenarios;

  /// Pull fresh data from the bridge.
  Future<void> resync();

  /// Bring the link up.
  Future<void> connect();

  /// Drop the link (the bridge keeps recording — I2).
  Future<void> disconnect();

  /// Send home-Wi-Fi credentials to the bridge **over Bluetooth** (N10.7).
  ///
  /// The password is an argument only: it is never stored by the app or by
  /// this repository. The bridge tries to join and reports back through
  /// [snapshot] (`connecting` then `connected` or a named `error`).
  Future<void> joinWifi({required String ssid, required String password});

  /// Ask the bridge to broadcast its own hotspot (N10.8).
  Future<void> useHotspot();

  /// The user confirmed their phone joined the bridge hotspot (N10.8).
  Future<void> confirmHotspotJoined();

  /// Forget the saved home network — app-side only (N10.9).
  Future<void> forgetNetwork();

  /// Adopt the bridge's already-running session as a cook.
  Future<void> adoptSession();

  /// Freeze/resume the **displayed** stopwatch. UI-only: the bridge keeps
  /// recording either way (I2, NOTES §7.3).
  Future<void> setCookPaused(bool paused);

  /// Move the cook window without rewriting any recorded sample (I10).
  Future<void> setCookStart(int startedAtMs);

  /// Drop the bridge's unadopted session (the "Start fresh" action).
  Future<void> discardSession();

  /// Begin a guided cook on [jack], or append to a running one (N9.13/N9.19).
  ///
  /// [timeline] is the per-item expected timeline a custom food carries
  /// (N9.18); [wrap]/[spritz] are the setup reminders (N9.11); [pullF10] is the
  /// floor-clamped pull the setup sheet already computed (I12). When
  /// [adoptPendingSession] is true and a session is waiting, the cook is
  /// backdated to the bridge session's start and that session is cleared
  /// (N9.15, I10). [startedAtMs] sets an explicit start for the "set a time"
  /// branch of `existing` mode.
  Future<void> startCook({
    required String presetId,
    required ProbeJack jack,
    String? styleId,
    String? title,
    int? targetF10,
    int? pullF10,
    CookTimeline? timeline,
    bool? wrap,
    bool? spritz,
    int? startedAtMs,
    bool adoptPendingSession = false,
  });

  /// Add an item to the running cook on [jack].
  Future<void> addItem({
    required String presetId,
    required ProbeJack jack,
    String? styleId,
    int? targetF10,
    int? pullF10,
    CookTimeline? timeline,
    bool? wrap,
    bool? spritz,
  });

  /// The user says the food on [jack] is out.
  Future<void> markPulled(ProbeJack jack);

  /// Place a mark on the timeline.
  Future<void> mark({
    required MarkKind kind,
    String text = '',
    ProbeJack? jack,
    int? atMs,
  });

  /// Acknowledge one alarm.
  Future<void> ackAlarm(String alarmId);

  /// Re-role a jack.
  Future<void> probeRole(ProbeJack jack, ProbeRole role);

  /// Set (or clear) a jack's target, tenths °F.
  Future<void> setTarget(ProbeJack jack, int? targetF10);

  /// Toggle a cook item's wrap/spritz reminders for this cook (N8.10).
  ///
  /// A null flag leaves the current override untouched. The seed value comes
  /// from the cut's expected timeline; setup (N9.11) writes the same fields.
  Future<void> setItemInterventions(ProbeJack jack, {bool? wrap, bool? spritz});

  /// Apply a transport mode (`ble` / `ap` / `sta`).
  Future<void> applyMode(String modeId);

  /// Run a device verb. [force] is the OTA session-active override.
  Future<void> performVerb(DeviceVerb verb, {bool force = false});

  /// Look for a firmware update.
  Future<void> checkForUpdates();

  /// Star / unstar a past cook.
  Future<void> setFavourite(String cookId, bool favourite);

  /// Dev panel: switch scenario.
  Future<void> selectScenario(String key);

  /// Dev panel: fire a mock event.
  Future<void> fireEvent(String eventId);

  /// Release the stream controllers.
  Future<void> dispose();
}
