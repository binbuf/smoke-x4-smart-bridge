/// A7.2 — mDNS discovery: the `_smokebridge._tcp` browse lane and the
/// §5.5 TXT-record model (design 05 §5.5, §5.8.5).
///
/// The `nsd` plugin is platform code, so the lane hides behind
/// [DiscoverySource]; host tests use a fake, and the live checks are the
/// sim's `--advertise-mdns` and the board at the bench sitting. Discovery
/// is one lane of five, never a prerequisite.
library;

import 'dart:convert';
import 'dart:typed_data';

/// What a §5.5 advertisement says about a bridge — enough for a picker to
/// render "Smoke Bridge · 4 probes · cooking" without connecting.
class DiscoveredBridge {
  const DiscoveredBridge({
    required this.host,
    required this.port,
    this.id = '',
    this.fw = '',
    this.probes = 0,
    this.paired = false,
    this.sessionId,
    this.mode = '',
  });

  final String host;
  final int port;
  final String id;
  final String fw;
  final int probes;
  final bool paired;
  final int? sessionId;
  final String mode;

  String get baseUrl => port == 80 ? 'http://$host' : 'http://$host:$port';
  bool get cooking => sessionId != null;
}

/// Parses nsd's TXT map (values are UTF-8 bytes or null) into the model.
/// Unknown keys are ignored, missing keys default, malformed values
/// degrade to defaults — a bad advertisement must never fail the race.
DiscoveredBridge bridgeFromTxt(
  String host,
  int port,
  Map<String, Uint8List?> txt,
) {
  String str(String key) {
    final v = txt[key];
    if (v == null) {
      return '';
    }
    try {
      return utf8.decode(v);
    } on FormatException {
      return '';
    }
  }

  int? num_(String key) => int.tryParse(str(key));

  final session = num_('session');
  return DiscoveredBridge(
    host: host,
    port: port,
    id: str('id'),
    fw: str('fw'),
    probes: num_('probes') ?? 0,
    paired: str('paired') == '1',
    sessionId: session != null && session > 0 ? session : null,
    mode: str('mode'),
  );
}

/// The seam the race consumes. The nsd-backed implementation lives in the
/// platform layer; tests fake it.
abstract interface class DiscoverySource {
  /// Emits bridges as advertisements resolve; completes or stalls freely.
  /// Implementations must swallow their own errors (a lane degrades
  /// silently, it never fails the race).
  Stream<DiscoveredBridge> discover();
}
