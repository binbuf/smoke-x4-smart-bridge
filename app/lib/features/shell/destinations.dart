/// N4.3 / feature wiring — the destination screens.
///
/// The real Live / Temps / Timeline / Graph / Settings / History / Cook detail
/// screens. N5–N13 replaced the original placeholder stack one task at a time;
/// N13's [SettingsPage] was the last, so the placeholder is gone.
library;

import 'package:flutter/material.dart';

import '../graph/graph.dart';
import '../history/history.dart';
import '../live/live_page.dart';
import '../settings/settings_page.dart';
import '../temps/temps_page.dart';
import '../timeline/timeline.dart';

/// Live destination (N5).
class LiveDestination extends StatelessWidget {
  const LiveDestination({super.key});

  @override
  Widget build(BuildContext context) => const LivePage();
}

/// Temps destination (N6).
class TempsDestination extends StatelessWidget {
  const TempsDestination({super.key});

  @override
  Widget build(BuildContext context) => const TempsPage();
}

/// Timeline destination (N8).
class TimelineDestination extends StatelessWidget {
  const TimelineDestination({super.key});

  @override
  Widget build(BuildContext context) => const TimelinePage();
}

/// Graph destination (N7).
class GraphDestination extends StatelessWidget {
  const GraphDestination({super.key});

  @override
  Widget build(BuildContext context) => const GraphPage();
}

/// Settings destination (N13).
class SettingsDestination extends StatelessWidget {
  const SettingsDestination({super.key});

  @override
  Widget build(BuildContext context) => const SettingsPage();
}

/// History destination (N12).
class HistoryDestination extends StatelessWidget {
  const HistoryDestination({super.key});

  @override
  Widget build(BuildContext context) => const HistoryPage();
}

/// Cook detail destination (N12).
class CookDetailDestination extends StatelessWidget {
  const CookDetailDestination({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context) => CookDetailPage(id: id);
}
