/// Repositories: BridgeRepository and SessionRepository (cache-first),
/// plus the delta-sync engine.
///
/// Repositories mediate between transports, the drift cache, and the
/// feature layers. See design 08 §8.3, §8.5.
library;

export 'cook_repository.dart';
export 'repositories.dart';
export 'sync_engine.dart';
