/// The app's runtime environment: the handful of things that must be
/// built once, at boot, and that every route then borrows.
///
/// It exists so the routes stay wiring rather than construction — and so
/// a widget test can install a fake environment (an in-memory database, a
/// `MockTransport`, an in-memory export sink) and drive the real screens
/// with no plugin, no socket and no radio anywhere.
library;

import '../data/local/database.dart';
import '../data/prefs/bridge_prefs.dart';
import '../data/transport/connection_manager.dart';
import '../data/transport/discovery.dart';
import '../data/transport/http_transport.dart';
import '../features/sessions/export.dart';
import 'connection.dart';

class AppEnv {
  AppEnv({
    required this.db,
    required this.prefs,
    required this.exportSink,
    TransportFactory? transportFor,
    this.discovery,
    this.bleAttempt,
    this.probe,
    this.appVersion = '1.0.0',
  }) : transportFor = transportFor ?? HttpTransport.new;

  final AppDatabase db;
  final BridgePrefs prefs;
  final ExportSink exportSink;
  final TransportFactory transportFor;
  final DiscoverySource? discovery;
  final BleAttempt? bleAttempt;
  final ConnectionProbe? probe;
  final String appVersion;

  /// A fresh race per route: `ConnectionManager`'s manual-entry completer
  /// is single-shot by design (A7.1), so reusing one across screens would
  /// mean the escape hatch works exactly once.
  AppConnection newConnection() => AppConnection(
    prefs: prefs,
    transportFor: transportFor,
    discovery: discovery,
    bleAttempt: bleAttempt,
    probe: probe,
  );

  static AppEnv? instance;
}
