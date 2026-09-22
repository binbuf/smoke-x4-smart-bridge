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

/// A streamed firmware image, ready to hand to the OTA upload (N15.20).
///
/// Deliberately transport-neutral: the picker (a platform seam) produces one
/// and the repository streams it to `BridgeTransport.uploadOta`. The image is
/// never buffered by the app.
class FirmwareImage {
  const FirmwareImage({
    required this.name,
    required this.bytes,
    this.lengthBytes,
  });

  final String name;
  final Stream<List<int>> bytes;

  /// The picked file's length when known, for a progress read-out.
  final int? lengthBytes;
}

/// How the composition root produces a firmware image (N15.20). Null picker =
/// the build has no file picker and OTA stays a named notice.
typedef FirmwarePicker = Future<FirmwareImage?> Function();

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

  /// N11.8 — snooze an alarm's *notifications* for [minutes]. The alarm stays
  /// raised and unacknowledged: the device owns alarm state, so this is an
  /// app-side delivery suppression only (never a resolve, I2).
  Future<void> snoozeAlarm(String alarmId, {int minutes = 10});

  /// N11.3 — raise a test alarm so the user can prove delivery works. App-tier
  /// and critical so it bypasses quiet hours; it is a real alarm row and can be
  /// acknowledged like any other.
  Future<void> sendTestAlarm();

  /// N11.4/N11.16 — enable or disable an alarm rule.
  ///
  /// A device rule is a *request* mirrored to the bridge (the device remains
  /// authoritative, I2); an app rule is app-side. Both are data in the mock.
  Future<void> setAlarmRuleEnabled(String ruleId, bool enabled);

  /// N11.16 — create or update an **app-tier** rule. Device rules are toggled,
  /// never invented.
  Future<void> saveAppAlarmRule(AlarmRule rule);

  /// N11.16 — delete an app-tier rule.
  Future<void> deleteAppAlarmRule(String ruleId);

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

  /// N15.20 — stream a picked firmware image to the bridge.
  ///
  /// **HTTP only**: an image is too big for Bluetooth, so a BLE-only link
  /// refuses with a named notice rather than attempting it. Returns `true`
  /// when the bridge accepted the upload. Never throws (I15).
  Future<bool> uploadFirmware(FirmwareImage image, {bool force = false});

  /// Look for a firmware update.
  Future<void> checkForUpdates();

  /// Star / unstar a past cook.
  Future<void> setFavourite(String cookId, bool favourite);

  // ── N12 history annotation verbs ──────────────────────────────────────
  //
  // Every one of these edits the **annotation**, never a sample row (I10).
  // N15 implements them on the real CookRepository (drift); the mock keeps
  // them in memory.

  /// Delete a cook annotation and its marks. The underlying recording is kept
  /// (N12.13, I8/I10).
  Future<void> deleteCook(String cookId);

  /// Replace a past cook's notes (N12.14).
  Future<void> setCookNotes(String cookId, String notes);

  /// End (`false`) or reopen (`true`) a cook annotation (N12.14).
  Future<void> setCookEnded(String cookId, bool ended);

  /// Add a mark to a past cook at [atMs] (defaults to the cook's end) — the
  /// "pull" and "marks edit" verbs (N12.14).
  Future<void> addCookMark(
    String cookId, {
    required MarkKind kind,
    String text = '',
    int? atMs,
  });

  /// Remove one mark from a past cook by index (N12.14).
  Future<void> deleteCookMark(String cookId, int index);

  /// Build the device-compatible CSV for one cook from the cache (N12.12).
  ///
  /// The format is byte-compatible with the device's own `format=csv`:
  /// `t_s,iso8601,p1_f,p2_f,p3_f,p4_f,billows,rssi`, detached probes as empty
  /// fields, ISO-8601 UTC (empty when the session has no clock, I11). It reads
  /// the cache, so it works with the bridge offline. N15 streams it from drift.
  Future<String> exportCookCsv(String cookId);

  /// Dev panel: switch scenario.
  Future<void> selectScenario(String key);

  /// Dev panel: fire a mock event.
  Future<void> fireEvent(String eventId);

  /// Release the stream controllers.
  Future<void> dispose();
}
