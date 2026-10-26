import 'package:flutter/foundation.dart';

/// The Experimental lab is a review tool. Debug builds get it by default;
/// release builds hide it unless explicitly enabled at compile time.
const bool experimentalLabEnabled = bool.fromEnvironment(
  'ENABLE_EXPERIMENTAL_LAB',
  defaultValue: kDebugMode,
);
