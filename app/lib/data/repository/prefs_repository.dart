/// N2.29 — preferences seam.
///
/// In-memory for the mock build; the real `shared_preferences` implementation
/// is deferred to N15. The interface is what N15 swaps behind.
library;

import 'dart:async';

import '../model/app_settings.dart';

/// Read and watch [AppSettings].
abstract interface class PrefsRepository {
  /// The current settings, then every change.
  Stream<AppSettings> watch();

  /// The current settings.
  AppSettings get current;

  /// Replace the whole settings value.
  Future<void> write(AppSettings settings);

  /// Read-modify-write.
  Future<void> update(AppSettings Function(AppSettings) transform);

  /// Release the stream controller.
  Future<void> dispose();
}

/// The in-memory implementation the mock app runs on.
class MockPrefsRepository implements PrefsRepository {
  MockPrefsRepository({AppSettings? initial})
    : _settings = initial ?? AppSettings.defaults;

  AppSettings _settings;
  final StreamController<AppSettings> _controller =
      StreamController<AppSettings>.broadcast();

  @override
  AppSettings get current => _settings;

  @override
  Stream<AppSettings> watch() async* {
    yield _settings;
    yield* _controller.stream;
  }

  @override
  Future<void> write(AppSettings settings) async {
    _settings = settings;
    _emit();
  }

  @override
  Future<void> update(AppSettings Function(AppSettings) transform) =>
      write(transform(_settings));

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_settings);
    }
  }

  @override
  Future<void> dispose() => _controller.close();
}
