/// N0.8 — the checked-in placeholder golden: the app shell at 390×844.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/smoke_app.dart';

import 'golden.dart';

void main() {
  testWidgets('the app shell at 390x844 matches its committed golden', (
    tester,
  ) async {
    await pumpForGolden(
      tester,
      const ProviderScope(child: SmokeApp()),
      // Written out even though it is `pumpForGolden`'s default: the phone
      // frame is the point of the placeholder golden (N0.8).
      // ignore: avoid_redundant_argument_values
      surface: const Size(390, 844),
    );

    expectGolden(tester, 'app_shell');
  });
}
