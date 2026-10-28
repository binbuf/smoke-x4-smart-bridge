/// Product copy catalogue.
///
/// This is the single place for user-facing strings that are shared by more
/// than one screen or asserted by the copy gate. Screens never build a status
/// sentence inline when the same sentence appears elsewhere.
///
/// Rules (12 and 13 §13.6):
/// - Sentence case for buttons, labels and messages; product names keep their
///   casing (`Smoke X4`, `Bridge`, `Billows`).
/// - No technical transport vocabulary in product copy. The only allow-listed
///   exceptions are the labels under `Technical details`.
/// - Counts, dates, times and temperatures come from `formatters.dart`; this
///   file holds words, not formatted numbers.
class AppStrings {
  const AppStrings._();

  // Navigation and shared chrome.
  static const live = 'Live';
  static const history = 'History';
  static const settings = 'Settings';
  static const cancel = 'Cancel';
  static const apply = 'Apply';
  static const gotIt = 'Got it';
  static const retry = 'Retry';
  static const bridgeDetails = 'Bridge details';
  static const save = 'Save';

  // Live.
  static const probes = 'Probes';
  static const billows = 'Billows';
  static const billowsDetected = 'Billows detected';
  static const billowsNotDetected = 'Billows not detected';
  static const lastDetected = 'Last detected';
  static const setOnSmokeX4 = 'Set on the Smoke X4.';
  static const canNotReachBridge = 'Can’t reach the Bridge';
  static const recordingContinues =
      'The app tried six times. Recording continues on the Bridge. Move closer and try again, or forget this phone and set it up again.';
  static const noDataFromSmokeX4 = 'No data from Smoke X4';
  static const smokeX4SignalLost = 'Smoke X4 signal lost';
  static const noDataX4Detail =
      'The Bridge is connected but isn’t receiving data from the Smoke X4. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.';
  static const smokeX4LostDetail =
      'The Bridge is connected but hasn’t received data from the Smoke X4 for a while. Put the Smoke X4 in SYNC mode and keep it in range of the Bridge.';
  static const pairingSteps = 'Pairing steps';
  static const noProbesConnected = 'No probes connected';
  static const plugInProbe =
      'Plug a probe into the Smoke X4 to see a reading.';
  static const historySyncFailed = 'History sync failed';
  static const noHistoryYet = 'No history yet';
  static const notRecording = 'Not recording';
  static const storageUnavailableDetail =
      'Live readings are available, but the Bridge can’t save them. Check the Bridge’s storage.';
  static const savedReadingsDetail =
      'These are saved readings, not live values. Retry when the Bridge is back in range.';
  static const offlineNothingSaved =
      'Bridge disconnected · nothing saved yet';
  static const offlineNothingSavedDetail =
      'This phone has no saved readings. Connect to your Bridge to see live values.';
  static const syncRecentTitle = 'Syncing saved readings';
  static const syncBackfillTitle = 'Loading saved readings';
  static const syncRecentDetail = 'Newest readings load first.';
  static const syncBackfillDetail =
      'Your latest readings are ready. Older readings continue in the background.';
  static const slowConnection = 'Slow connection';

  // History.
  static const summary = 'Summary';
  static const cooks = 'Cooks';
  static const latest = 'Latest';
  static const minimum = 'Min';
  static const maximum = 'Max';
  static const allProbes = 'All probes';
  static const noReadingsYet = 'No readings yet';
  static const noReadingsInRange = 'No readings in this range';
  static const bridgeRecordsAlways =
      'The Bridge records whenever it’s on and paired with the Smoke X4.';
  static const viewLive = 'View Live';
  static const showAllProbes = 'Show all probes';
  static const showAllSavedHistory = 'Show all saved history';
  static const noCookDetected = 'No cook detected yet';
  static const sinceCookStart = 'Since cook start';

  // Settings and Bridge details.
  static const preferences = 'Preferences';
  static const historyAndStorage = 'History & storage';
  static const units = 'Units';
  static const liveChangeWindow = 'Live change window';
  static const appearance = 'Appearance';
  static const about = 'About';
  static const bridgeStatus = 'Bridge status';
  static const connectionLog = 'Connection log';
  static const technicalDetails = 'Technical details';
  static const bridgeDisconnected = 'Bridge disconnected';
  static const rePairSmokeX4 = 'Re-pair Smoke X4';
  static const powerOff = 'Power off';
  static const factoryReset = 'Factory reset';
  static const forgetPhone = 'Forget phone';

  // Empty, error and destructive copy.
  static const noHistoryOnPhone = 'No history on this phone';
  static const deleteHistoryFromPhone = 'Delete history from this phone…';
  static const couldNotLoadSavedReadings = 'Couldn’t load saved readings';
  static const tryAgain = 'Try again';
}
