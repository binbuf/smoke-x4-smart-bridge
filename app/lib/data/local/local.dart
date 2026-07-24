/// Local persistence: the drift database, DAOs, and migrations.
///
/// The app owns a full copy of every cook it has seen; charts read from
/// drift, never from the network (design 08 §8.5).
library;

export 'database.dart';
export 'open_database.dart';
