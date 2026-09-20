/// `/cooks` as list-detail on a wide window (16 §16.6, design 13 §13.3, §13.5.4).
///
/// On a phone, opening a cook is a navigation. From 600 dp it is a
/// **selection**: list on the left, detail on the right, one screen. That is
/// the canonical layout for this flow, and on this app it is also the fix for
/// the context loss — on a tablet or an unfolded Fold there is no navigation
/// left to lose context in.
///
/// Previously this file drove the *device-session* list, which `/cooks`
/// replaced. It drives the real screen now, at both widths.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/app_env.dart';
import 'package:smoke_bridge/data/local/database.dart';
import 'package:smoke_bridge/design/theme.dart';
import 'package:smoke_bridge/domain/plan/plan.dart';
import 'package:smoke_bridge/features/cooks/cook_detail_view.dart';
import 'package:smoke_bridge/features/cooks/cooks_tab.dart';

import '../support/fake_env.dart';
import '../support/load_fonts.dart';

const int _hour = 3600 * 1000;

Future<void> _save(
  AppDatabase db,
  String name, {
  required int startUnixMs,
  int? endUnixMs,
}) => db.cookDao.save(
  CookAnnotation(
    id: 0,
    bridgeId: 'b',
    name: name,
    startUnixMs: startUnixMs,
    endUnixMs: endUnixMs,
    createdUnixMs: startUnixMs,
  ),
);

void main() {
  setUpAll(loadAppFonts);

  late AppDatabase db;
  late int now;

  setUp(() async {
    now = DateTime.now().millisecondsSinceEpoch;
    db = AppDatabase(NativeDatabase.memory());
    await db.sessionDao.upsertBridge('b');
    AppEnv.instance = fakeEnv(db: db);
  });

  tearDown(() async {
    AppEnv.instance = null;
    await db.close();
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SmokeTheme.dark,
        home: const Scaffold(body: CooksTab()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The screen holds a drift subscription, and cancelling one schedules a
  /// zero-duration timer. Unmount **inside** the test body so that timer is
  /// drained before the binding checks for pending ones.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  Future<void> seedTwo() async {
    await _save(
      db,
      'Brisket',
      startUnixMs: now - 30 * _hour,
      endUnixMs: now - 24 * _hour,
    );
    await _save(
      db,
      'Pork butt',
      startUnixMs: now - 60 * _hour,
      endUnixMs: now - 54 * _hour,
    );
  }

  testWidgets('compact is a list and nothing else — opening is a navigation', (
    tester,
  ) async {
    await seedTwo();
    await pumpAt(tester, const Size(360, 800));

    expect(find.text('Brisket'), findsOneWidget);
    // No standing selection, no detail pane: there is nowhere on this screen
    // for one to live.
    expect(find.byType(CookDetailView), findsNothing);
    expect(find.text('Pick a cook'), findsNothing);

    await unmount(tester);
  });

  testWidgets('from 600 dp the detail is on the same screen', (tester) async {
    await seedTwo();
    await pumpAt(tester, const Size(1000, 1400));

    // Nothing chosen yet: the pane says what to do, it does not sit blank.
    expect(find.text('Pick a cook'), findsOneWidget);
    expect(find.byType(CookDetailView), findsNothing);

    await tester.tap(find.text('Brisket'));
    await tester.pumpAndSettle();

    // Tapping was a **selection**, not a navigation: the list is still there.
    expect(find.byType(CookDetailView), findsOneWidget);
    expect(find.text('Pork butt'), findsOneWidget);
    expect(find.text('Pick a cook'), findsNothing);

    await unmount(tester);
  });

  testWidgets('choosing another cook swaps the pane, not the screen', (
    tester,
  ) async {
    await seedTwo();
    await pumpAt(tester, const Size(1000, 1400));

    await tester.tap(find.text('Brisket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pork butt'));
    await tester.pumpAndSettle();

    expect(find.byType(CookDetailView), findsOneWidget);
    // Both rows are still on screen — the list never went anywhere.
    expect(find.text('Brisket'), findsWidgets);

    await unmount(tester);
  });

  testWidgets('an open cook reads as Recording, not "cooking"', (tester) async {
    await _save(db, 'Running one', startUnixMs: now - _hour);
    await pumpAt(tester, const Size(360, 800));

    // The bridge records whether or not a cook was ever set up (§13.7.6), so
    // an open cook means recording — it does not mean somebody is cooking.
    expect(find.text('Recording'), findsOneWidget);
    expect(find.textContaining('cooking'), findsNothing);

    await unmount(tester);
  });
}
