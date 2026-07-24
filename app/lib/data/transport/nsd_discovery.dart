/// A7.4 — the production `DiscoverySource`, backed by `nsd` (design 08
/// §8.4, 05 §5.5).
///
/// A7.2 shipped the seam, the §5.5 TXT parser and a fake — and never this.
/// The mDNS lane of the §8.4 race has therefore been permanently empty
/// since M2: the dashboard would have found the bridge only via the cached
/// address, `smokebridge.local` (which Android's resolver cannot answer)
/// or the AP default. The M3 bench sitting is where that became visible;
/// this is where it closes.
///
/// `nsd` wraps Android's `NsdManager`, whose resolve step is serialized
/// and OEM-variable (R3), so the plugin calls hide behind [NsdOps] and the
/// logic runs in the host suite against a fake registry — the same
/// discipline `flutter_blue_plus` lives under as `BleGattClient`. Parsing
/// is **not** re-implemented here: it goes through A7.2's already-tested
/// `bridgeFromTxt`.
///
/// The lane's contract, restated because it is the whole reason this is
/// small: **discovery swallows its own errors.** A missing permission, an
/// unresolvable service, a plugin that throws on a platform without mDNS —
/// all of them mean "no candidate from this lane", never "the race
/// failed".
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import 'discovery.dart';

/// The §5.5 service type. One constant, so the device's mDNS TXT record,
/// the sim's `--advertise-mdns`, and this lane can never disagree.
const String smokeBridgeServiceType = '_smokebridge._tcp';

/// One discovered advertisement, already resolved.
typedef NsdService = ({String? host, int? port, Map<String, Uint8List?>? txt});

/// The narrow platform façade. Production is [PluginNsdOps]; tests pass a
/// fake registry and never touch a method channel.
abstract interface class NsdOps {
  /// Starts a browse for [serviceType]. The stream emits each resolved
  /// service as it arrives and must not close on a per-service error.
  Stream<NsdService> browse(String serviceType);

  /// Frees the native discovery. Must be safe to call twice, and a
  /// failure here is logged and forgotten — a discovery we cannot stop is
  /// not a reason to fail the caller.
  Future<void> stop();
}

class PluginNsdOps implements NsdOps {
  nsd.Discovery? _discovery;

  @override
  Stream<NsdService> browse(String serviceType) {
    late final StreamController<NsdService> out;
    late final nsd.ServiceListener listener;

    Future<void> start() async {
      try {
        // autoResolve: the Android docs suggest resolving lazily, but the
        // race needs a host and a port to probe — an unresolved entry is
        // not a candidate.
        final d = await nsd.startDiscovery(serviceType);
        _discovery = d;
        d.addServiceListener(listener);
        for (final s in d.services) {
          listener(s, nsd.ServiceStatus.found);
        }
      } on Object {
        // No permission, no mDNS, no plugin: the lane simply has nothing
        // to offer. Closing is how it says so.
        await out.close();
      }
    }

    out = StreamController<NsdService>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        await stop();
      },
    );
    listener = (service, status) {
      if (status != nsd.ServiceStatus.found || out.isClosed) {
        return;
      }
      out.add((host: service.host, port: service.port, txt: service.txt));
    };
    return out.stream;
  }

  @override
  Future<void> stop() async {
    final d = _discovery;
    _discovery = null;
    if (d == null) {
      return;
    }
    try {
      await nsd.stopDiscovery(d);
    } on Object {
      // Deliberately swallowed; see the library comment.
    }
  }
}

/// The [DiscoverySource] the ConnectionManager consumes.
class NsdDiscoverySource implements DiscoverySource {
  NsdDiscoverySource({NsdOps? ops, this.serviceType = smokeBridgeServiceType})
    : _ops = ops ?? PluginNsdOps();

  final NsdOps _ops;
  final String serviceType;

  @override
  Stream<DiscoveredBridge> discover() {
    final seen = <String>{};
    return _ops
        .browse(serviceType)
        .map((s) {
          final host = s.host;
          if (host == null || host.isEmpty) {
            return null;
          }
          return bridgeFromTxt(host, s.port ?? 80, s.txt ?? const {});
        })
        .where((b) {
          // A browse re-announces; the race must not probe the same
          // address four times because the router was chatty.
          if (b == null || !seen.add(b.baseUrl)) {
            return false;
          }
          return true;
        })
        .cast<DiscoveredBridge>()
        // A lane degrades silently, it never fails the race (A7.2).
        .handleError((Object _) {});
  }

  /// Releases the native discovery. Safe to call more than once.
  Future<void> dispose() => _ops.stop();
}
