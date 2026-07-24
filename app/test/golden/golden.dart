/// A15.1 — the snapshot harness (design 08 §8.9).
///
/// **These goldens are text, not bitmaps, and that is a decision.**
/// §8.9 asks for `golden_toolkit` snapshots at several data shapes; the
/// value it is asking for is *"a change to what the screen says gets
/// reviewed"*, and a PNG delivers that only where it can survive the trip
/// to CI. It cannot: the same widget rasterises differently across
/// platform and Flutter version, so a golden rendered on the author's
/// Windows box red-lights on CI's Ubuntu runner, and the fix everyone
/// reaches for is `skip:`. A skipped golden protects nothing.
///
/// So what is pinned here is a **deterministic description** of the
/// rendered tree: every visible string, every semantics label, every key,
/// every icon, whether a control is disabled, and — because A10.2's whole
/// point is that identity must be reviewable — the resolved colour and
/// stroke of every series. A one-pixel rendering difference must not fail
/// these. A probe silently turning into `0 °F` must.
///
/// Regenerate with `UPDATE_GOLDENS=1 flutter test test/golden`. CI never
/// sets it, and a missing golden fails rather than writing itself.
library;

import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smoke_bridge/app/theme.dart';

/// Where the committed snapshots live.
const String goldenDir = 'test/golden/goldens';

bool get updatingGoldens => Platform.environment['UPDATE_GOLDENS'] == '1';

/// Pumps [child] at a fixed surface and text scale under [brightness].
///
/// The surface is deliberately tall: these screens are lists, and a
/// lazily-built child that was never on screen is not in the tree to be
/// described. A golden that silently covers half a screen is worse than
/// no golden.
Future<void> pumpForGolden(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
  Size surface = const Size(420, 2400),
  double textScale = 1,
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
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? SmokeTheme.dark
            : SmokeTheme.light,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

/// Compares the rendered tree against the committed snapshot.
void expectGolden(
  WidgetTester tester,
  String name, {

  /// False when the caller is testing the harness itself: regenerating a
  /// golden named "does not exist" would defeat the point.
  bool allowUpdate = true,
}) {
  final actual = describeTree(tester);
  final file = File('$goldenDir/$name.golden.txt');
  if (updatingGoldens && allowUpdate) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(actual);
    return;
  }
  if (!file.existsSync()) {
    fail(
      'No golden at ${file.path}. Goldens are committed, never written by '
      'a passing test — run `UPDATE_GOLDENS=1 flutter test test/golden` '
      'and review the diff.',
    );
  }
  final expected = file.readAsStringSync().replaceAll('\r\n', '\n');
  expect(
    actual,
    expected,
    reason:
        'The rendered tree changed. If that was intended, regenerate with '
        'UPDATE_GOLDENS=1 and review the diff.',
  );
}

/// The serialization. **Order is tree order**, never hash order, so two
/// runs of the same screen produce the same bytes.
String describeTree(WidgetTester tester) {
  final out = StringBuffer();
  var depth = 0;
  void emit(String line) => out.writeln('${'  ' * depth}$line');

  void visit(Element element) {
    final widget = element.widget;
    final lines = _describe(widget);
    if (lines.isNotEmpty) {
      for (final l in lines) {
        emit(l);
      }
      depth++;
      element.visitChildren(visit);
      depth--;
    } else {
      element.visitChildren(visit);
    }
  }

  tester.allElements.first.visitAncestorElements((e) => true);
  visit(tester.element(find.byType(MaterialApp)));
  return out.toString();
}

List<String> _describe(Widget w) {
  final lines = <String>[];
  final key = w.key;
  if (key is ValueKey<String>) {
    lines.add('[${key.value}]');
  }
  switch (w) {
    case Text(:final data, :final semanticsLabel):
      lines.add(
        'text ${_q(data ?? '')}'
        '${semanticsLabel == null ? '' : ' semantics ${_q(semanticsLabel)}'}',
      );
    case Icon(:final icon):
      lines.add('icon ${icon?.codePoint}');
    case TextField(:final decoration):
      lines.add(
        'field label ${_q(decoration?.labelText ?? '')}'
        '${decoration?.errorText == null ? '' : ' error ${_q(decoration!.errorText!)}'}',
      );
    case LinearProgressIndicator(:final value):
      lines.add('progress ${value?.toStringAsFixed(2)}');
    case ButtonStyleButton(:final onPressed):
      lines.add(onPressed == null ? 'button disabled' : 'button enabled');
    case ListTile(:final enabled):
      lines.add(enabled ? 'tile enabled' : 'tile disabled');
    case SwitchListTile(:final value, :final onChanged):
      lines.add(
        'switch ${value ? 'on' : 'off'} '
        '${onChanged == null ? 'disabled' : 'enabled'}',
      );
    case LineChart(:final data):
      lines.addAll(_describeChart(data));
    case CustomPaint(:final painter) when painter != null:
      lines.add('paint ${painter.runtimeType}');
    default:
      break;
  }
  return lines;
}

/// The chart's content is structural: how many segments, where they
/// broke, which overlays exist, and — the reviewable half of A10.2 —
/// what colour and stroke each series drew with.
List<String> _describeChart(LineChartData d) {
  final lines = <String>[
    'chart x ${d.minX.round()}..${d.maxX.round()} '
        'y ${d.minY.round()}..${d.maxY.round()} '
        'touch ${d.lineTouchData.enabled ? 'builtin' : 'ours'}',
  ];
  for (final bar in d.lineBarsData) {
    final spots = bar.spots;
    lines.add(
      '  bar color ${_hex(bar.color)} width ${bar.barWidth} '
      'dash ${bar.dashArray ?? 'solid'} '
      'spots ${spots.length} '
      '${spots.isEmpty ? '' : 'from ${spots.first.x.round()} to ${spots.last.x.round()}'}',
    );
  }
  for (final l in d.extraLinesData.horizontalLines) {
    lines.add('  target y ${l.y.toStringAsFixed(1)} ${_hex(l.color)}');
  }
  for (final l in d.extraLinesData.verticalLines) {
    lines.add('  mark x ${l.x.round()}');
  }
  for (final a in d.rangeAnnotations.horizontalRangeAnnotations) {
    lines.add('  band ${a.y1.toStringAsFixed(1)}..${a.y2.toStringAsFixed(1)}');
  }
  return lines;
}

String _hex(Color? c) => c == null
    ? 'none'
    : '#${((c.a * 255).round() << 24 | (c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(8, '0')}';

String _q(String s) => '"${s.replaceAll('\n', r'\n')}"';
