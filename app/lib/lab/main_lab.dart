/// A22.5 / A23 — the UX lab entrypoint (design 13, 14).
///
/// A minimal `runApp` that mounts a launcher over the new design theme — **no
/// bootstrap, no database, no transport, no platform channels** — so the whole
/// review harness runs anywhere with zero hardware:
///
///   flutter run  -d chrome  -t lib/lab/main_lab.dart
///   flutter run  -d windows -t lib/lab/main_lab.dart
///
/// The launcher offers the two hardware-free flows: [CookLab] (the live Cook
/// tab, A22.5) and [SetupLab] (the guided three-hop setup driven by the real
/// [SetupMachine] over fakes, A23). Both are one tap away and neither touches a
/// radio, a socket or a plugin. The full app entrypoint is `lib/main.dart`;
/// this one never touches it.
library;

import 'package:flutter/material.dart';

import '../design/design.dart';
import 'cook_lab.dart';
import 'setup_lab.dart';

void main() {
  runApp(const _LabApp());
}

class _LabApp extends StatelessWidget {
  const _LabApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Smoke Bridge — UX Lab',
    debugShowCheckedModeBanner: false,
    theme: SmokeTheme.dark,
    home: const _LabHome(),
  );
}

class _LabHome extends StatelessWidget {
  const _LabHome();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Smoke Bridge — UX Lab')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LabEntry(
                icon: Icons.local_fire_department_rounded,
                label: 'Cook lab',
                blurb: 'The live Cook tab — telemetry, probes, controls.',
                builder: (_) => const CookLab(),
              ),
              const SizedBox(height: SmokeTokens.s3),
              _LabEntry(
                icon: Icons.cable_rounded,
                label: 'Setup flow',
                blurb: 'The guided three-hop setup, run by the real machine.',
                builder: (_) => const SetupLab(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabEntry extends StatelessWidget {
  const _LabEntry({
    required this.icon,
    required this.label,
    required this.blurb,
    required this.builder,
  });

  final IconData icon;
  final String label;
  final String blurb;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Card(
      color: t.surface,
      child: ListTile(
        leading: Icon(icon, color: StatusPalette.pit),
        title: Text(label, style: SmokeType.title.copyWith(color: t.textHi)),
        subtitle: Text(
          blurb,
          style: SmokeType.bodySm.copyWith(color: t.textMuted),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: t.textMuted),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: builder)),
      ),
    );
  }
}
