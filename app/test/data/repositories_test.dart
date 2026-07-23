/// A4.4: cache-first reads — after one sync, every read is served from
/// drift with the transport gone. An 18-hour cook scrolls on the couch
/// with the bridge unplugged.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/data/repos/repositories.dart';
import 'package:smoke_bridge/data/transport/mock_transport.dart';
import 'package:smoke_bridge/domain/entities/entities.dart';

import 'records_parity_test.dart' show repoRoot;

void main() {
  test(
    'the full 18 h cook is served with the transport disconnected',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final smk = File(
        '${repoRoot()}/protocol/fixtures/brisket-18h.smk',
      ).readAsBytesSync();
      final transport = MockTransport.fromSmkBytes(smk);
      final bridge = BridgeRepository(db, transport);

      final report = await bridge.refresh();
      expect(report.samplesInserted, greaterThan(2000));
      final bridgeId = report.bridgeId;

      // The bridge goes away. Everything below is cache only.
      await transport.close();

      final sessions = SessionRepository(db, bridgeId: bridgeId);
      final list = await sessions.sessions();
      expect(list, hasLength(1));
      expect(list.first.id, 27);
      expect(list.first.numProbes, 4);

      final all = await sessions.samples(27);
      expect(all.length, report.samplesInserted);
      expect(all.first.t, lessThanOrEqualTo(30));
      // Monotonic t, gaps preserved as gaps (no resampling in the cache).
      for (var i = 1; i < all.length; i++) {
        expect(all[i].t, greaterThan(all[i - 1].t));
      }

      // A chart window read: the last two hours only.
      final lastT = all.last.t;
      final window = await sessions.samples(27, fromT: lastT - 7200);
      expect(window.length, greaterThan(100));
      expect(window.length, lessThan(300));

      // The synthetic brisket detaches probe 4 for a stretch — those rows
      // must surface as null, never 0 (the chart draws a break).
      final detached = all.where((s) => s.tempsF10[3] == null).length;
      expect(detached, greaterThan(0));
      expect(all.where((s) => s.tempsF10[3] == 0), isEmpty);
    },
  );

  test('watchSessions streams cache updates', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final sessions = SessionRepository(db, bridgeId: 'b');

    final futureFirst = sessions.watchSessions().firstWhere(
      (l) => l.isNotEmpty,
    );
    await db.sessionDao.upsertSessions('b', const []);
    await db.sessionDao.upsertSessions('b', const [
      CookSession(id: 1, name: 'live', sampleCount: 1),
    ]);
    final got = await futureFirst;
    expect(got.single.name, 'live');
  });
}
