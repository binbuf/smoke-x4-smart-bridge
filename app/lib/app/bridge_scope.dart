/// Publishes the one [BridgeController] to the whole tree.
///
/// Inherited so a screen can read the controller without a provider package,
/// and so the connection stays alive across tab switches.
library;

import 'package:flutter/widgets.dart';

import 'bridge_controller.dart';

class BridgeScope extends InheritedNotifier<BridgeController> {
  const BridgeScope({
    super.key,
    required BridgeController controller,
    required super.child,
  }) : super(notifier: controller);

  static BridgeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BridgeScope>();
    assert(scope != null, 'BridgeScope missing above this widget');
    return scope!.notifier!;
  }
}
