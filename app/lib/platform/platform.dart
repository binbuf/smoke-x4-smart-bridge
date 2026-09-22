/// The platform layer (N15.3, N15.15–N15.22).
///
/// Every plugin touch in the app hides behind a seam declared here, so the
/// layers above are pure and host-testable. The `*_plugin.dart` /
/// `*_fbp.dart` files are the only ones that import a plugin; importing this
/// barrel does not pull them in (it would otherwise drag platform channels into
/// hosts that never touch them).
library;

export 'device_facts.dart';
export 'firmware_picker.dart';
export 'network_binder.dart';
export 'notifications.dart';
export 'permissions.dart';
export 'share.dart';
export 'system_settings.dart';
