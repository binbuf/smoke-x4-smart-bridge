/// The settings tree: §F's frozen v1 scope, rendered in the 16 §16.5 layout
/// system.
///
/// Two rules run through every file here, and they are the reason the tree was
/// rebuilt rather than restyled:
///
///  * **a control that cannot work is worse than no control** — every row is
///    live, absent (`—`), or present-and-dimmed with its reason beneath it;
///  * **a write is not saved until a read-back says so** — every write
///    resolves to a [WriteOutcome], including the honest "the bridge doesn't
///    report this one back, so the app can't confirm it".
library;

export 'netmode_switch.dart';
export 'netmode_switch_sheet.dart';
export 'settings_data.dart';
export 'settings_diagnostics.dart';
export 'settings_kit.dart';
export 'settings_mqtt.dart';
export 'settings_network.dart';
export 'settings_power.dart';
export 'settings_probes.dart';
export 'settings_route.dart';
export 'settings_screen.dart';
