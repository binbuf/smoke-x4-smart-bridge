/// N2 — the data barrel.
///
/// Pure Dart (no Flutter), so `dart test test/data` can import the whole data
/// layer. The Riverpod providers live in `providers.dart`, which imports
/// Flutter and is deliberately not exported here.
library;

export 'content/catalog.dart';
export 'content/catalog_data.dart';
export 'content/fixtures_data.dart';
export 'content/scenarios.dart';
export 'content/styles_data.dart';
export 'content/timelines.dart';
export 'dev_panel.dart';
export 'model/alarm.dart';
export 'model/alarm_rule.dart';
export 'model/app_settings.dart';
export 'model/bridge_snapshot.dart';
export 'model/catalog_entry.dart';
export 'model/connection_mode.dart';
export 'model/connection_state.dart';
export 'model/cook_state.dart';
export 'model/device_info.dart';
export 'model/history_entry.dart';
export 'model/mock_event.dart';
export 'repository/bridge_repository.dart';
export 'repository/mock_bridge_repository.dart';
export 'repository/mock_event_bus.dart';
export 'repository/prefs_repository.dart';
