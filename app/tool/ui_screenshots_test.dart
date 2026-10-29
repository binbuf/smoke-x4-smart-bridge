import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui show ImageByteFormat;
import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smoke_bridge/features/device/device_preview_screen.dart';
import 'package:smoke_bridge/features/history/history_full_screen.dart';
import 'package:smoke_bridge/features/history/history_screen.dart';
import 'package:smoke_bridge/features/settings/bridge_details.dart';
import 'package:smoke_bridge/features/settings/settings_details.dart';
import 'package:smoke_bridge/features/settings/settings_views.dart';
import 'package:smoke_bridge/features/setup/setup_screen.dart';
import 'package:smoke_bridge/features/shell/app_shell.dart';
import 'package:smoke_bridge/debug/fixtures.dart';
import 'package:smoke_bridge/domain/models.dart';
import 'package:smoke_bridge/app/bridge_controller.dart';
import 'package:smoke_bridge/debug/demo_content.dart';
import 'package:smoke_bridge/debug/scenario_lab.dart';
import 'package:smoke_bridge/theme/app_theme.dart';

Future<void> _loadFont(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// Resolve the Flutter SDK so the golden test finds the same Roboto and
/// MaterialIcons files on a developer machine and on CI.
String _flutterRoot() {
  final candidates = <String>[
    ?Platform.environment['FLUTTER_ROOT'],
    r'D:\flutter',
    '/opt/flutter',
  ];
  for (final entry in (Platform.environment['PATH'] ?? '').split(
    Platform.isWindows ? ';' : ':',
  )) {
    final dir = entry.trim();
    if (dir.isEmpty) continue;
    final flutter = File(
      '$dir${Platform.pathSeparator}flutter${Platform.isWindows ? '.bat' : ''}',
    );
    if (flutter.existsSync()) {
      candidates.add(Directory(dir).parent.path);
    }
  }
  for (final root in candidates) {
    final fonts = Directory('$root/bin/cache/artifacts/material_fonts');
    if (fonts.existsSync()) return root;
  }
  throw StateError(
    'Cannot find Flutter material fonts. Set FLUTTER_ROOT or put flutter on PATH.',
  );
}

void main() {
  setUpAll(() async {
    final root = '${_flutterRoot()}/bin/cache/artifacts/material_fonts';
    await _loadFont('Roboto', '$root/roboto-regular.ttf');
    await _loadFont('Roboto', '$root/roboto-bold.ttf');
    await _loadFont('MaterialIcons', '$root/materialicons-regular.otf');
  });

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget screen, {
    Brightness brightness = Brightness.dark,
    bool settle = true,
    Future<void> Function(WidgetTester tester)? interact,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final theme = brightness == Brightness.dark
        ? AppTheme.dark()
        : AppTheme.light();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
          ),
          home: screen,
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    if (interact != null) {
      await interact(tester);
      await tester.pumpAndSettle();
    }
    // Asset decoding runs off the test's fake clock, so the first capture in a
    // run would otherwise show the frame before the image has painted. Wait
    // for every image on screen to be in the cache, then paint it.
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pumpAndSettle();
    // `make design-export` sets this to dump the laid-out text boxes instead of
    // comparing goldens. CI never sets it, so the screenshot contract above is
    // unchanged.
    final dumpDirectory = Platform.environment['FIGCRAFT_DUMP'];
    if (dumpDirectory != null && dumpDirectory.isNotEmpty) {
      await _writeTextDump(tester, key, name, dumpDirectory);
      return;
    }
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('../screenshots/$name.png'),
    );
  }

  testWidgets('live dark', (tester) async {
    final controller = demoBridgeController();
    await shot(tester, 'live_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('live light', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'live_light',
      AppShell(controller: controller),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('live billows detected', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'live_billows_detected',
      AppShell(controller: controller),
      interact: (tester) async {
        await tester.drag(find.byType(ListView).first, const Offset(0, -320));
      },
    );
    controller.dispose();
  });

  testWidgets('live billows lost', (tester) async {
    final controller = demoBridgeController()
      ..billowsAttachment = BillowsAttachment.detached
      ..billowsSeenThisSession = true
      ..smokeXChannel4SetKnown = false;
    await shot(
      tester,
      'live_billows_lost',
      AppShell(controller: controller),
      interact: (tester) async {
        await tester.drag(find.byType(ListView).first, const Offset(0, -320));
      },
    );
    controller.dispose();
  });

  testWidgets('live offline cache', (tester) async {
    final controller = demoBridgeController()
      ..phase = ConnectionPhase.offline
      ..offlineCache = true;
    await shot(tester, 'live_offline_cache', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('live stale dark', (tester) async {
    final controller = demoBridgeController()
      ..phase = ConnectionPhase.stale
      ..smokeXAgeOverride = const Duration(minutes: 4);
    await shot(tester, 'live_stale_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('live offline without cache dark', (tester) async {
    final controller = demoBridgeController()
      ..phase = ConnectionPhase.offline
      ..offlineCache = false;
    await shot(
      tester,
      'live_offline_nocache_dark',
      AppShell(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('live X4 warning dark', (tester) async {
    final controller = demoBridgeController()
      ..smokeXStatus = SmokeXStatus.pairedLive
      ..smokeXAgeOverride = const Duration(minutes: 4);
    await shot(
      tester,
      'live_x4_warning_dark',
      AppShell(controller: controller),
      interact: (tester) async {
        await tester.tap(find.byKey(const Key('live.smokeXWarning')));
        await tester.pumpAndSettle();
      },
    );
    controller.dispose();
  });

  testWidgets('history dark', (tester) async {
    final controller = demoBridgeController()
      ..tab = AppTab.history
      ..historyRange = HistoryRange.twentyFourHours
      ..historyMissingFromBridge = true;
    await shot(tester, 'history_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('history light', (tester) async {
    final controller = demoBridgeController()..tab = AppTab.history;
    await shot(
      tester,
      'history_light',
      AppShell(controller: controller),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('history custom range dark', (tester) async {
    final controller = demoBridgeController()..tab = AppTab.history;
    await shot(
      tester,
      'history_custom_range_dark',
      AppShell(controller: controller),
      interact: (tester) async {
        await tester.tap(find.byKey(const Key('history.range.menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('history.range.custom')));
        await tester.pumpAndSettle();
      },
    );
    controller.dispose();
  });

  testWidgets('history all dark', (tester) async {
    final controller = demoBridgeController()
      ..tab = AppTab.history
      ..historyRange = HistoryRange.custom
      ..historyEstimated = true;
    controller.historyCustomRange = controller.entireHistoryRange;
    await shot(tester, 'history_all_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('history cooks dark', (tester) async {
    final controller = demoBridgeController()
      ..tab = AppTab.history
      ..historyRange = HistoryRange.twoDays;
    await shot(
      tester,
      'history_cooks_dark',
      AppShell(controller: controller),
      interact: (tester) async {
        await tester.drag(find.byType(ListView).first, const Offset(0, -520));
      },
    );
    controller.dispose();
  });

  testWidgets('cook dark', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'past_cook_dark',
      PastCookScreen(controller: controller, cook: buildCookSessions().first),
    );
    controller.dispose();
  });

  testWidgets('cook light', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'past_cook_light',
      PastCookScreen(controller: controller, cook: buildCookSessions().first),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('history probe filter dark', (tester) async {
    final controller = demoBridgeController()
      ..tab = AppTab.history
      ..historyRange = HistoryRange.oneHour
      ..historyProbe = 1;
    await shot(tester, 'history_filter_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('history no data dark', (tester) async {
    final controller = demoBridgeController()
      ..tab = AppTab.history
      ..historyHasData = false
      ..phoneRecords = 0;
    await shot(tester, 'history_empty_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('history probe no data dark', (tester) async {
    final controller = demoBridgeController()
      ..tab = AppTab.history
      ..historyOneProbe = true
      ..historyProbe = 1
      ..historyRange = HistoryRange.oneHour;
    await shot(
      tester,
      'history_probe_empty_dark',
      AppShell(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('settings dark', (tester) async {
    final controller = demoBridgeController()..tab = AppTab.settings;
    await shot(tester, 'settings_dark', AppShell(controller: controller));
    controller.dispose();
  });

  testWidgets('settings light', (tester) async {
    final controller = demoBridgeController()..tab = AppTab.settings;
    await shot(
      tester,
      'settings_light',
      AppShell(controller: controller),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('bridge details dark', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'bridge_details_dark',
      BridgeDetailsScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('bridge details light', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'bridge_details_light',
      BridgeDetailsScreen(controller: controller),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('history storage dark', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'history_storage_dark',
      HistoryStorageScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('history storage light', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'history_storage_light',
      HistoryStorageScreen(controller: controller),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('appearance dark', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'appearance_dark',
      AppearanceScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('appearance light', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'appearance_light',
      AppearanceScreen(controller: controller),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('setup dark', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'setup_dark',
      SetupScreen(controller: controller, autoAdvance: false),
    );
    controller.dispose();
  });

  testWidgets('setup light', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'setup_light',
      SetupScreen(controller: controller, autoAdvance: false),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('passkey dark', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'passkey_dark',
      SetupScreen(
        controller: controller,
        initialStep: SetupStep.passkey,
        autoAdvance: false,
      ),
    );
    controller.dispose();
  });

  testWidgets('experimental lab dark', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'scenario_lab_dark',
      ScenarioLabScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('oled page dark', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'oled_page_dark',
      DevicePreviewScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('oled passkey dark', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'oled_passkey_dark',
      DevicePreviewScreen(
        controller: controller,
        initialOverlay: DeviceOverlay.passkey,
      ),
    );
    controller.dispose();
  });

  testWidgets('re-pair dark', (tester) async {
    final controller = demoBridgeController();
    await shot(tester, 're_pair_dark', RePairScreen(controller: controller));
    controller.dispose();
  });

  testWidgets('history on phone dark', (tester) async {
    final controller = demoBridgeController()..hasSavedData = true;
    await shot(
      tester,
      'device_log_dark',
      SavedDataScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('billows settings dark', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'billows_settings_dark',
      BillowsSettingsScreen(controller: controller),
    );
    controller.dispose();
  });

  testWidgets('factory reset confirmation dark', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'confirm_factory_reset_dark',
      ConfirmationPreviewScreen(
        controller: controller,
        kind: DestructiveKind.factoryReset,
      ),
    );
    controller.dispose();
  });

  testWidgets('power off confirmation light', (tester) async {
    final controller = demoBridgeController();
    await shot(
      tester,
      'confirm_power_off_light',
      ConfirmationPreviewScreen(
        controller: controller,
        kind: DestructiveKind.powerOff,
      ),
      brightness: Brightness.light,
    );
    controller.dispose();
  });

  testWidgets('history standalone full screen dark', (tester) async {
    final controller = demoBridgeController()
      ..tab = AppTab.history
      ..historyRange = HistoryRange.custom
      ..historyEstimated = true;
    controller.historyCustomRange = controller.entireHistoryRange;
    await shot(
      tester,
      'history_fullscreen_dark',
      HistoryFullScreenScreen(controller: controller),
    );
    controller.dispose();
  });
}

/// One same-styled slice of a paragraph, with offsets into the plain text.
class _TextPart {
  _TextPart(this.text, this.start, this.style);

  final String text;
  final int start;
  final TextStyle style;

  String get styleKey => [
    style.fontFamily,
    style.fontSize,
    style.fontWeight?.value,
    style.color?.toARGB32(),
    style.letterSpacing,
    style.height,
    style.decoration,
    style.fontStyle,
  ].join('|');

  _TextPart joined(_TextPart next) => _TextPart(
    text + next.text,
    start,
    style,
  );
}

int _collectParts(
  InlineSpan span,
  TextStyle? inherited,
  int offset,
  List<_TextPart> out,
) {
  final style = switch ((inherited, span.style)) {
    (final a?, final b?) => a.merge(b),
    (final a?, null) => a,
    (null, final b?) => b,
    (null, null) => const TextStyle(),
  };
  if (span is TextSpan) {
    if (span.text != null && span.text!.isNotEmpty) {
      out.add(_TextPart(span.text!, offset, style));
      offset += span.text!.length;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      offset = _collectParts(child, style, offset, out);
    }
  } else if (span is WidgetSpan) {
    offset += 1;
  }
  return offset;
}

String _hex(Color color) {
  final argb = color.toARGB32();
  final rgb = argb & 0x00FFFFFF;
  final alpha = (argb >> 24) & 0xFF;
  // FigCraft paints use #RRGGBBAA; Flutter stores ARGB.
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}'
      '${alpha.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

String _alignName(TextAlign align) => switch (align) {
  TextAlign.center => 'center',
  TextAlign.right || TextAlign.end => 'right',
  TextAlign.justify => 'justify',
  _ => 'left',
};

Future<void> _writeTextDump(
  WidgetTester tester,
  GlobalKey key,
  String name,
  String directory,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final origin = boundary.localToGlobal(Offset.zero);
  final width = boundary.size.width;
  final height = boundary.size.height;
  final runs = <Map<String, Object?>>[];
  final occluders = <({int order, Rect rect})>[];
  var order = 0;

  Rect? opaqueRect(RenderObject node) {
    if (node is! RenderBox || !node.hasSize) return null;
    Color? colour;
    if (node is RenderDecoratedBox) {
      final decoration = node.decoration;
      if (decoration is BoxDecoration) colour = decoration.color;
    } else if (node is RenderPhysicalModel) {
      colour = node.color;
    } else if (node is RenderPhysicalShape) {
      colour = node.color;
    }
    if (colour == null || colour.a < 0.999) return null;
    return node.localToGlobal(Offset.zero) & node.size;
  }

  void visit(RenderObject node, {bool translucent = false}) {
    order += 1;
    final myOrder = order;
    // AppShell keeps every tab alive in an IndexedStack; only the selected
    // child is painted, so dumping the others would duplicate copy from hidden
    // screens at identical coordinates.
    if (node is RenderIndexedStack) {
      final index = node.index ?? 0;
      final children = <RenderObject>[];
      node.visitChildren(children.add);
      if (index >= 0 && index < children.length) {
        visit(children[index], translucent: translucent);
      }
      return;
    }
    if (node is RenderOffstage && node.offstage) return;
    final faded = translucent ||
        (node is RenderOpacity && node.opacity < 0.999);
    if (node is RenderOpacity && node.opacity == 0) return;
    if (node is RenderParagraph && node.hasSize && node.size.isFinite) {
      _dumpParagraph(node, origin, width, height, runs, myOrder);
    }
    final occluder = faded ? null : opaqueRect(node);
    if (occluder != null) occluders.add((order: myOrder, rect: occluder));
    node.visitChildren((child) => visit(child, translucent: faded));
  }

  visit(boundary);

  // Drop copy that a later, opaque surface covers (the bottom navigation bar,
  // a sheet, a dialog). The reference screenshot already shows the top layer,
  // so keeping those runs would paint duplicate words over it.
  final visible = <Map<String, Object?>>[];
  for (final run in runs) {
    final rect = run['rect']! as List<double>;
    final bounds = Rect.fromLTWH(rect[0], rect[1], rect[2], rect[3]);
    final paintedAt = run['order']! as int;
    final covered = occluders.any(
      (occluder) =>
          occluder.order > paintedAt &&
          occluder.rect.contains(bounds.topLeft) &&
          occluder.rect.contains(bounds.bottomRight),
    );
    if (covered) continue;
    run.remove('order');
    visible.add(run);
  }

  // The goldens are 1x; a 3x capture keeps the FigCraft reference crisp on a
  // large canvas. Same widget tree, same layout. `runAsync` runs the engine
  // work on the real clock instead of the test's fake one.
  final shotDirectory = Directory('${Directory(directory).parent.path}/shots');
  shotDirectory.createSync(recursive: true);
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data;
  });
  if (bytes != null) {
    File('${shotDirectory.path}/$name.png').writeAsBytesSync(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }

  final file = File('$directory/$name.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'name': name,
      'width': width,
      'height': height,
      'runs': visible,
    }),
  );
}

void _dumpParagraph(
  RenderParagraph paragraph,
  Offset origin,
  double width,
  double height,
  List<Map<String, Object?>> out,
  int paintedAt,
) {
  if (paragraph.text.toPlainText().trim().isEmpty) return;
  final parts = <_TextPart>[];
  _collectParts(paragraph.text, null, 0, parts);

  // Coalesce adjacent slices that share a face so a line of ordinary prose is
  // one editable layer rather than one per span.
  final merged = <_TextPart>[];
  for (final part in parts) {
    if (part.text.isEmpty) continue;
    final previous = merged.isEmpty ? null : merged.last;
    if (previous != null &&
        previous.styleKey == part.styleKey &&
        previous.start + previous.text.length == part.start) {
      merged[merged.length - 1] = previous.joined(part);
    } else {
      merged.add(part);
    }
  }

  final paragraphTopLeft =
      paragraph.localToGlobal(Offset.zero) - origin;
  final paragraphRect = paragraphTopLeft & paragraph.size;

  for (final part in merged) {
    if (part.text.trim().isEmpty) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(
        baseOffset: part.start,
        extentOffset: part.start + part.text.length,
      ),
      boxHeightStyle: BoxHeightStyle.strut,
    );
    if (boxes.isEmpty) continue;

    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    final lineTops = <int>{};
    for (final box in boxes) {
      left = left < box.left ? left : box.left;
      top = top < box.top ? top : box.top;
      right = right > box.right ? right : box.right;
      bottom = bottom > box.bottom ? bottom : box.bottom;
      lineTops.add(box.top.round());
    }
    final rect = Rect.fromLTRB(left, top, right, bottom).shift(paragraphTopLeft);
    if (rect.isEmpty) continue;
    if (rect.right < 0 ||
        rect.bottom < 0 ||
        rect.left > width ||
        rect.top > height) {
      continue;
    }

    final style = part.style;
    final family = style.fontFamily ?? 'Roboto';
    final fontSize = style.fontSize ?? 14;
    final lines = lineTops.length;
    final lineHeight = lines > 1 ? rect.height / lines : rect.height;
    final icon =
        family.contains('MaterialIcons') || family.contains('Material Icons');
    final align = _alignName(paragraph.textAlign);

    out.add({
      'text': part.text,
      'order': paintedAt,
      'rect': [rect.left, rect.top, rect.width, rect.height],
      'paragraph': [
        paragraphRect.left,
        paragraphRect.top,
        paragraphRect.width,
        paragraphRect.height,
      ],
      'fontFamily': family,
      'fontSize': fontSize,
      'fontWeight': style.fontWeight?.value ?? 400,
      'fontStyle': style.fontStyle?.name ?? 'normal',
      'color': _hex(style.color ?? const Color(0xFF000000)),
      'letterSpacing': style.letterSpacing,
      'lineHeight': lineHeight,
      'align': align,
      'maxLines': paragraph.maxLines,
      'icon': icon,
    });
  }
}
