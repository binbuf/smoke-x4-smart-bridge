/// Wire DTOs generated from `protocol/` — never used directly by the UI.
///
/// `records.g.dart` is emitted by `tools/protogen` from `protocol/records.yaml`
/// and must not be edited by hand (CI fails on any diff). Vendored here for
/// N15.3's BLE transport, exactly as `app.old` does; the BLE wire is binary so
/// the codec has to travel with the app rather than be re-derived per call.
library;

export 'records.g.dart';
