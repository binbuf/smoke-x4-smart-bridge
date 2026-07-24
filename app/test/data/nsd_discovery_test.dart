/// A7.4 — the production DiscoverySource, over a fake service registry.
///
/// A7.2 shipped the seam, the TXT parser and a fake, and never this — so
/// the mDNS lane of the §8.4 race has been empty since M2. The rule the
/// lane lives under is the one most of these cases check: **discovery
/// swallows its own errors.** A missing permission, an unresolvable
/// service, a plugin that throws — all of them mean "no candidate", never
/// "the race failed".
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/transport/discovery.dart';
import 'package:smoke_bridge/data/transport/nsd_discovery.dart';

Map<String, Uint8List?> _txt(Map<String, String> m) => {
  for (final e in m.entries) e.key: Uint8List.fromList(utf8.encode(e.value)),
};

class _FakeNsd implements NsdOps {
  _FakeNsd(this.services, {this.throwOnStart = false, this.closeAfter = true});

  final List<NsdService> services;
  final bool throwOnStart;

  /// A real browse stays open until it is stopped; tests that want to
  /// drain with `toList()` ask it to close once it has said everything.
  final bool closeAfter;
  int stops = 0;
  StreamController<NsdService>? controller;

  @override
  Stream<NsdService> browse(String serviceType) {
    final c = StreamController<NsdService>();
    controller = c;
    c.onListen = () {
      if (throwOnStart) {
        unawaited(c.close());
        return;
      }
      for (final s in services) {
        c.add(s);
      }
      if (closeAfter) {
        unawaited(c.close());
      }
    };
    c.onCancel = stop;
    return c.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

void main() {
  test(
    'a resolved service becomes a candidate through A7.2\'s parser',
    () async {
      final ops = _FakeNsd([
        (
          host: '10.50.50.38',
          port: 80,
          txt: _txt({
            'id': '8274',
            'fw': '1.0.0',
            'probes': '4',
            'paired': '1',
            'session': '1',
            'mode': 'sta',
          }),
        ),
      ]);
      final found = await NsdDiscoverySource(ops: ops).discover().first;
      expect(found.baseUrl, 'http://10.50.50.38');
      expect(found.id, '8274');
      expect(found.probes, 4);
      expect(found.paired, isTrue);
      expect(found.cooking, isTrue);
    },
  );

  test('a non-default port lands in the base URL', () async {
    final ops = _FakeNsd([
      (host: 'localhost', port: 8085, txt: <String, Uint8List?>{}),
    ]);
    final found = await NsdDiscoverySource(ops: ops).discover().first;
    expect(found.baseUrl, 'http://localhost:8085');
  });

  test('a service with no TXT record at all still resolves', () async {
    final ops = _FakeNsd([(host: '192.168.4.1', port: 80, txt: null)]);
    final found = await NsdDiscoverySource(ops: ops).discover().first;
    expect(found.baseUrl, 'http://192.168.4.1');
    expect(found.id, '');
    expect(found.cooking, isFalse);
  });

  test(
    'an unresolved service is dropped, not emitted as a null host',
    () async {
      final ops = _FakeNsd([
        (host: null, port: 80, txt: null),
        (host: '', port: 80, txt: null),
        (host: '10.0.0.5', port: 80, txt: null),
      ]);
      final all = await NsdDiscoverySource(ops: ops).discover().toList();
      expect(all.map((b) => b.host), ['10.0.0.5']);
    },
  );

  test(
    'a chatty browse does not make the race probe the same address 4x',
    () async {
      final one = (host: '10.0.0.5', port: 80, txt: <String, Uint8List?>{});
      final ops = _FakeNsd([one, one, one, one]);
      final all = await NsdDiscoverySource(ops: ops).discover().toList();
      expect(all, hasLength(1));
    },
  );

  test(
    'a plugin that cannot start closes the lane instead of throwing',
    () async {
      final ops = _FakeNsd(const [], throwOnStart: true);
      // No permission, no mDNS, no plugin: the lane simply has nothing to
      // offer, and the race must not learn about it as an error.
      expect(await NsdDiscoverySource(ops: ops).discover().toList(), isEmpty);
    },
  );

  test(
    'an error mid-stream degrades silently — a lane never fails the race',
    () async {
      final ops = _FakeNsd([
        (host: '10.0.0.5', port: 80, txt: <String, Uint8List?>{}),
      ], closeAfter: false);
      final source = NsdDiscoverySource(ops: ops);
      final got = <DiscoveredBridge>[];
      final done = Completer<void>();
      source.discover().listen(
        got.add,
        onError: (Object e) => done.completeError(e),
        onDone: done.complete,
      );
      await Future<void>.delayed(Duration.zero);
      ops.controller!.addError(StateError('NsdError: securityIssue'));
      await ops.controller!.close();
      await done.future;
      expect(got, hasLength(1));
    },
  );

  test('cancelling the stream frees the native discovery', () async {
    final ops = _FakeNsd([
      (host: '10.0.0.5', port: 80, txt: <String, Uint8List?>{}),
    ], closeAfter: false);
    final sub = NsdDiscoverySource(ops: ops).discover().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(ops.stops, greaterThanOrEqualTo(1));
  });

  test('dispose is safe to call twice', () async {
    final ops = _FakeNsd(const []);
    final source = NsdDiscoverySource(ops: ops);
    await source.dispose();
    await source.dispose();
    expect(ops.stops, 2);
  });

  test('the service type is one constant, shared with the device', () {
    // The device's mDNS record, the sim's --advertise-mdns and this lane
    // can never disagree, because there is only one spelling of it.
    expect(smokeBridgeServiceType, '_smokebridge._tcp');
  });
}
