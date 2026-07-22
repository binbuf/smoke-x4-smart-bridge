/// tools/sim — the fake bridge (design 10 §10.3, tasks T3.1–T3.6).
///
/// The highest-leverage tool in the repo: the Flutter app is developable and
/// CI-testable against the complete HTTP + WebSocket device API before any
/// firmware exists, and stays testable afterwards without a smoker running.
library;

export 'src/mdns.dart';
export 'src/payloads.dart';
export 'src/scenarios.dart';
export 'src/server.dart';
export 'src/state.dart';
