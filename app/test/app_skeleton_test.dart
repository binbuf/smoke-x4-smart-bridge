import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/app/smoke_bridge_app.dart';
import 'package:smoke_bridge/data/db/app_database.dart';
import 'package:smoke_bridge/data/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeRepository implements BridgeRepository {
  _FakeRepository(this.snapshot);

  final BridgeSnapshot snapshot;
  bool closed = false;

  @override
  Future<BridgeSnapshot> loadSnapshot() async => snapshot;

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  sqfliteFfiInit();

  testWidgets('production app launches into the approved Live shell', (
    tester,
  ) async {
    final controller = BridgeController();
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(SmokeBridgeApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Live'), findsWidgets);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.byKey(const Key('status.connection')), findsOneWidget);
    expect(find.text('P1'), findsOneWidget);
    expect(find.text('P4'), findsOneWidget);
  });

  test(
    'controller reads the cached summary through the repository seam',
    () async {
      final repository = _FakeRepository(
        BridgeSnapshot(readingCount: 42, lastReadingAt: DateTime(2026, 10, 26)),
      );
      final controller = BridgeController(repository: repository);

      await controller.initialize();

      expect(controller.phoneRecords, 42);
      expect(controller.hasSavedData, isTrue);
      controller.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(repository.closed, isTrue);
    },
  );

  test('DB open path creates an in-memory SQLite database', () async {
    final database = await AppDatabase.openInMemory(
      factory: databaseFactoryFfi,
    );

    expect(database.path, inMemoryDatabasePath);
    expect(database.database.isOpen, isTrue);
    await database.close();
  });

  test(
    'SQLite repository reports the archive count and newest reading',
    () async {
      final database = await AppDatabase.openInMemory(
        factory: databaseFactoryFfi,
      );
      final repository = SqliteBridgeRepository(database);

      expect((await repository.loadSnapshot()).readingCount, 0);

      await database.database.insert('sample', <String, Object?>{
        'bridge_id': 'bridge-a',
        'generation': 1,
        'seq': 1,
        'recorded_ms': 1700000000000,
        'time_estimated': 0,
        'flags': 0,
      });
      await database.database.insert('sample', <String, Object?>{
        'bridge_id': 'bridge-a',
        'generation': 1,
        'seq': 2,
        'recorded_ms': 1700000060000,
        'time_estimated': 0,
        'flags': 0,
      });

      final snapshot = await repository.loadSnapshot();
      expect(snapshot.readingCount, 2);
      expect(
        snapshot.lastReadingAt,
        DateTime.fromMillisecondsSinceEpoch(1700000060000),
      );
      await repository.close();
    },
  );

  test('production entrypoint does not import prototype fixtures', () {
    for (final path in [
      'lib/main.dart',
      'lib/app/bootstrap.dart',
      'lib/app/smoke_bridge_app.dart',
      'lib/app/bridge_controller.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('prototype/'),
        isFalse,
        reason: '$path must not import prototype-only code',
      );
    }

    final mainSource = File('lib/main.dart').readAsStringSync();
    expect(mainSource, contains("import 'app/bootstrap.dart';"));
    expect(
      RegExp(r'^\s*import\s', multiLine: true).allMatches(mainSource).length,
      1,
    );
  });
}
