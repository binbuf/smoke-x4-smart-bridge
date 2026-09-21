/// N0.8 — the golden harness.
///
/// **These goldens are text, not bitmaps, and that is a decision.** The same
/// widget rasterises differently across platform and Flutter version, so a PNG
/// rendered on a Windows dev box red-lights on CI's Ubuntu runner, and the fix
/// everyone reaches for is `skip:`. A skipped golden protects nothing.
///
/// What is pinned here is a **deterministic description** of the rendered tree:
/// every visible string, semantics label, key, icon and disabled state. A
/// one-pixel rendering difference must not fail it; a screen silently
/// changing what it says must.
///
/// Regenerate with `flutter test --update-goldens test/golden` (or
/// `make app.golden`) and review the diff. CI never passes the flag, and a
/// missing golden fails rather than writing itself.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where committed snapshots live.
const String goldenDir = 'test/golden/goldens';

/// True under `UPDATE_GOLDENS=1`, the environment-variable spelling some tasks
/// use. `--update-goldens` is the canonical switch and sets
/// [autoUpdateGoldenFiles].
bool get updatingGoldens => Platform.environment['UPDATE_GOLDENS'] == '1';

/// Pumps [child] at a fixed surface (default 390×844, the phone frame the
/// prototype targets) and text scale.
///
/// Set [settle] to false when the tree contains an intentional **indeterminate**
/// animation (a spinner, the liveness pulse): `pumpAndSettle` never returns for
/// those. The description only records text/icon/button structure, so a fixed
/// number of frames is still deterministic.
Future<void> pumpForGolden(
  WidgetTester tester,
  Widget child, {
  Size surface = const Size(390, 844),
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view
    ..physicalSize = surface
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: surface,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }
}

/// Compares the rendered tree against the committed snapshot.
///
/// Set [allowUpdate] to false when testing the harness itself: regenerating a
/// golden named "does not exist" would defeat the point.
void expectGolden(WidgetTester tester, String name, {bool allowUpdate = true}) {
  final actual = describeTree(tester);
  final file = File('$goldenDir/$name.golden.txt');

  if (allowUpdate && (updatingGoldens || autoUpdateGoldenFiles)) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(actual);
    return;
  }

  if (!file.existsSync()) {
    fail(
      'No golden at ${file.path}. Goldens are committed, never written by a '
      'passing test — run `flutter test --update-goldens test/golden` and '
      'review the diff.',
    );
  }

  final expected = file.readAsStringSync().replaceAll('\r\n', '\n');
  expect(
    actual,
    expected,
    reason:
        'The rendered tree changed. If that was intended, regenerate with '
        '`flutter test --update-goldens test/golden` and review the diff.',
  );
}

/// The serialization. **Order is tree order**, never hash order, so two runs
/// of the same screen produce the same bytes.
String describeTree(WidgetTester tester) {
  final out = StringBuffer();
  var depth = 0;
  void emit(String line) => out.writeln('${'  ' * depth}$line');

  void visit(Element element) {
    final lines = _describe(element.widget);
    if (lines.isEmpty) {
      element.visitChildren(visit);
      return;
    }
    for (final line in lines) {
      emit(line);
    }
    depth++;
    element.visitChildren(visit);
    depth--;
  }

  final root = find.byType(MaterialApp);
  expect(
    root,
    findsOneWidget,
    reason: 'a golden describes exactly one MaterialApp tree',
  );
  visit(tester.element(root));
  return out.toString();
}

List<String> _describe(Widget widget) {
  final lines = <String>[];
  final key = widget.key;
  if (key is ValueKey<String>) {
    lines.add('[${key.value}]');
  }
  switch (widget) {
    case Text(:final data, :final semanticsLabel):
      lines.add(
        'text ${_q(data ?? '')}'
        '${semanticsLabel == null ? '' : ' semantics ${_q(semanticsLabel)}'}',
      );
    case Icon(:final icon):
      lines.add('icon ${icon?.codePoint}');
    case ButtonStyleButton(:final onPressed):
      lines.add(onPressed == null ? 'button disabled' : 'button enabled');
    case SwitchListTile(:final value, :final onChanged):
      lines.add(
        'switch ${value ? 'on' : 'off'} '
        '${onChanged == null ? 'disabled' : 'enabled'}',
      );
    default:
      break;
  }
  return lines;
}

String _q(String value) => '"${value.replaceAll('\n', r'\n')}"';
