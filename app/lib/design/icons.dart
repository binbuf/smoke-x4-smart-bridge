/// N3.11 — the icon set.
///
/// The prototype carries ~67 inline SVG paths in `app.js` `ICON_PATHS`. Flutter
/// has no SVG path renderer in the SDK, so the **contract that survives** is the
/// set of icon *names* every screen uses; [SmokeGlyph] is that contract and
/// [SmokeIcons.data] maps each name to the closest Material Symbols glyph.
/// Swapping the artwork later is a one-file change with no screen edits.
///
/// [SmokeIcon] is the only way a screen draws an icon. It is stateless, sizes
/// in logical pixels and defaults to `currentColor` (i.e. it inherits the text
/// colour), matching the prototype's `stroke="currentColor"`.
library;

import 'package:flutter/material.dart';

/// Every icon name the prototype uses.
enum SmokeGlyph {
  bluetooth,
  wifi,
  wifiOff,
  router,
  thermometer,
  flame,
  clock,
  list,
  chart,
  history,
  cpu,
  bell,
  chevronRight,
  chevronDown,
  chevronLeft,
  plus,
  check,
  x,
  play,
  pause,
  edit,
  refresh,
  link,
  unlink,
  alertTriangle,
  alertCircle,
  info,
  question,
  zap,
  bookmark,
  share,
  download,
  trash,
  lock,
  battery,
  target,
  arrowUp,
  arrowDown,
  arrowRight,
  arrowLeft,
  minus,
  utensils,
  wrap,
  droplet,
  rotate,
  calendar,
  sun,
  moon,
  monitor,
  sliders,
  more,
  activity,
  eye,
  mapPin,
  package,
  upload,
  compass,
  key,
  search,
  signal,
  expand,
  compress,
  zoomIn,
  zoomOut,
  qr,
  camera,
  star,
}

/// The name → glyph table.
abstract final class SmokeIcons {
  const SmokeIcons._();

  static const Map<SmokeGlyph, IconData> _data = <SmokeGlyph, IconData>{
    SmokeGlyph.bluetooth: Icons.bluetooth,
    SmokeGlyph.wifi: Icons.wifi,
    SmokeGlyph.wifiOff: Icons.wifi_off,
    SmokeGlyph.router: Icons.router,
    SmokeGlyph.thermometer: Icons.thermostat,
    SmokeGlyph.flame: Icons.local_fire_department,
    SmokeGlyph.clock: Icons.schedule,
    SmokeGlyph.list: Icons.format_list_bulleted,
    SmokeGlyph.chart: Icons.bar_chart,
    SmokeGlyph.history: Icons.history,
    SmokeGlyph.cpu: Icons.memory,
    SmokeGlyph.bell: Icons.notifications_none,
    SmokeGlyph.chevronRight: Icons.chevron_right,
    SmokeGlyph.chevronDown: Icons.expand_more,
    SmokeGlyph.chevronLeft: Icons.chevron_left,
    SmokeGlyph.plus: Icons.add,
    SmokeGlyph.check: Icons.check,
    SmokeGlyph.x: Icons.close,
    SmokeGlyph.play: Icons.play_arrow,
    SmokeGlyph.pause: Icons.pause,
    SmokeGlyph.edit: Icons.edit,
    SmokeGlyph.refresh: Icons.refresh,
    SmokeGlyph.link: Icons.link,
    SmokeGlyph.unlink: Icons.link_off,
    SmokeGlyph.alertTriangle: Icons.warning_amber,
    SmokeGlyph.alertCircle: Icons.error_outline,
    SmokeGlyph.info: Icons.info_outline,
    SmokeGlyph.question: Icons.help_outline,
    SmokeGlyph.zap: Icons.bolt,
    SmokeGlyph.bookmark: Icons.bookmark_border,
    SmokeGlyph.share: Icons.ios_share,
    SmokeGlyph.download: Icons.download,
    SmokeGlyph.trash: Icons.delete_outline,
    SmokeGlyph.lock: Icons.lock_outline,
    SmokeGlyph.battery: Icons.battery_full,
    SmokeGlyph.target: Icons.my_location,
    SmokeGlyph.arrowUp: Icons.arrow_upward,
    SmokeGlyph.arrowDown: Icons.arrow_downward,
    SmokeGlyph.arrowRight: Icons.arrow_forward,
    SmokeGlyph.arrowLeft: Icons.arrow_back,
    SmokeGlyph.minus: Icons.remove,
    SmokeGlyph.utensils: Icons.restaurant,
    SmokeGlyph.wrap: Icons.inventory_2_outlined,
    SmokeGlyph.droplet: Icons.water_drop_outlined,
    SmokeGlyph.rotate: Icons.rotate_right,
    SmokeGlyph.calendar: Icons.calendar_today,
    SmokeGlyph.sun: Icons.wb_sunny_outlined,
    SmokeGlyph.moon: Icons.dark_mode_outlined,
    SmokeGlyph.monitor: Icons.desktop_windows_outlined,
    SmokeGlyph.sliders: Icons.tune,
    SmokeGlyph.more: Icons.more_horiz,
    SmokeGlyph.activity: Icons.show_chart,
    SmokeGlyph.eye: Icons.visibility_outlined,
    SmokeGlyph.mapPin: Icons.place_outlined,
    SmokeGlyph.package: Icons.inventory_2_outlined,
    SmokeGlyph.upload: Icons.upload,
    SmokeGlyph.compass: Icons.explore_outlined,
    SmokeGlyph.key: Icons.key,
    SmokeGlyph.search: Icons.search,
    SmokeGlyph.signal: Icons.signal_cellular_alt,
    SmokeGlyph.expand: Icons.open_in_full,
    SmokeGlyph.compress: Icons.close_fullscreen,
    SmokeGlyph.zoomIn: Icons.zoom_in,
    SmokeGlyph.zoomOut: Icons.zoom_out,
    SmokeGlyph.qr: Icons.qr_code,
    SmokeGlyph.camera: Icons.photo_camera_outlined,
    SmokeGlyph.star: Icons.star,
  };

  /// The Material glyph for a name.
  static IconData data(SmokeGlyph glyph) => _data[glyph]!;

  /// Resolve the prototype's string name (parity with `ICON_PATHS` keys).
  static IconData? byName(String name) {
    for (final entry in _data.entries) {
      if (entry.key.name == name) {
        return entry.value;
      }
    }
    return null;
  }

  /// Every name in the set.
  static Iterable<SmokeGlyph> get all => _data.keys;

  /// The number of icons ported.
  static int get count => _data.length;
}

/// Draws a [SmokeGlyph].
class SmokeIcon extends StatelessWidget {
  const SmokeIcon(this.glyph, {super.key, this.size = 18, this.color});

  final SmokeGlyph glyph;
  final double size;

  /// Defaults to the inherited text colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(SmokeIcons.data(glyph), size: size, color: color);
  }
}
