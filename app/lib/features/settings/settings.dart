/// Settings feature: probes, alarms, network, device, advanced, firmware,
/// about (A12, M4).
///
/// See design 08 §8.6. The rule that runs through it: a control that
/// cannot work is worse than no control.
library;

export 'settings_network.dart';
export 'settings_probes.dart';
export 'settings_route.dart';
export 'settings_screen.dart';
