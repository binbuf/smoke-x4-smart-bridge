/// N2.26 — the mock event bus.
///
/// The dev panel fires named events; each one mutates the repository's active
/// snapshot so every connection / alarm state can be exercised with no bridge.
/// The catalogue is data (`fixtures_data.dart`); the mutations live in
/// `MockBridgeRepository._applyEvent`.
library;

import 'dart:async';

import '../content/fixtures_data.dart';
import '../model/mock_event.dart';

/// A tiny synchronous bus: [fire] notifies the owner and any stream listeners.
class MockEventBus {
  MockEventBus({this.onEvent});

  final void Function(String eventId)? onEvent;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  /// Every fireable event, in dev-panel order.
  List<MockEventSpec> get catalogue => kMockEvents;

  /// Fires as they happen.
  Stream<String> get events => _controller.stream;

  /// Fire one event by id.
  void fire(String eventId) {
    onEvent?.call(eventId);
    if (!_controller.isClosed) {
      _controller.add(eventId);
    }
  }

  Future<void> dispose() => _controller.close();
}
