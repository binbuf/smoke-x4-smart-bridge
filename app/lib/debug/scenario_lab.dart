import 'package:flutter/material.dart';

import '../app/bridge_controller.dart';
import '../widgets/prototype_app_bar.dart';
import '../widgets/prototype_widgets.dart';
import 'scenario_catalog.dart';

/// The review gallery.
///
/// Every row and thumbnail comes from [scenarioCatalog]; this widget only
/// arranges it. That keeps the screens a reviewer taps through identical to the
/// ones `tool/ui_screenshots_test.dart` captures.
class ScenarioLabScreen extends StatefulWidget {
  const ScenarioLabScreen({super.key, required this.controller});

  final BridgeController controller;

  @override
  State<ScenarioLabScreen> createState() => _ScenarioLabScreenState();
}

class _ScenarioLabScreenState extends State<ScenarioLabScreen> {
  final _search = TextEditingController();
  String _query = '';

  BridgeController get controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final visible = labScenarios.where(_matches).toList();
        final goldens = visible.where((scenario) => scenario.golden).toList();
        final groups = _grouped(
          visible.where((scenario) => !scenario.golden).toList(),
        );

        return Scaffold(
          appBar: prototypeAppBar(context, controller, 'Experimental lab'),
          body: ListView(
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PrototypeThemeToggle(controller: controller),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search screens and states',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${visible.length} '
                            '${visible.length == 1 ? 'scenario' : 'scenarios'}'
                            ' · simulated',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            controller.reset();
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          },
                          child: const Text('Reset'),
                        ),
                        TextButton(
                          onPressed: () =>
                              _open(scenarioById('lab.setup.no_bridge')!),
                          child: const Text('First run'),
                        ),
                      ],
                    ),
                    if (visible.isEmpty) ...[
                      const SizedBox(height: 12),
                      SectionCard(
                        child: Column(
                          children: [
                            const Icon(Icons.search_off, size: 28),
                            const SizedBox(height: 8),
                            Text(
                              _query.trim().isEmpty
                                  ? 'No scenarios available'
                                  : 'No scenarios match “${_query.trim()}”',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              child: const Text('Clear search'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (goldens.isNotEmpty)
                      _GoldenGrid(goldens: goldens, onOpen: _open),
                    for (final group in groups)
                      _GroupCard(group: group, onOpen: _open),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Prototype only. Bluetooth, storage, sync, and '
                        'permissions are simulated',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _matches(Scenario scenario) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return scenario.title.toLowerCase().contains(query) ||
        scenario.subtitle.toLowerCase().contains(query) ||
        scenario.group.title.toLowerCase().contains(query) ||
        scenario.id.contains(query);
  }

  List<_LabGroup> _grouped(List<Scenario> entries) {
    final byGroup = <ScenarioGroup, List<Scenario>>{};
    for (final entry in entries) {
      byGroup.putIfAbsent(entry.group, () => <Scenario>[]).add(entry);
    }
    return [
      for (final entry in byGroup.entries)
        _LabGroup(group: entry.key, entries: entry.value),
    ];
  }

  void _open(Scenario scenario) {
    scenario.seed(controller);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => scenario.screen(controller)),
    );
  }
}

/// The approved screenshot set as a tappable contact sheet.
class _GoldenGrid extends StatelessWidget {
  const _GoldenGrid({required this.goldens, required this.onOpen});

  final List<Scenario> goldens;
  final void Function(Scenario scenario) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              'Approved screenshots',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              '${goldens.length} approved '
              '${goldens.length == 1 ? 'frame' : 'frames'}. '
              'Tap any frame to open the live screen.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: goldens.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
              childAspectRatio: 0.40,
            ),
            itemBuilder: (context, index) {
              final scenario = goldens[index];
              return _Thumb(scenario: scenario, onTap: () => onOpen(scenario));
            },
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.scenario, required this.onTap});

  final Scenario scenario;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Open ${scenario.title}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.8),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Image.asset(
                    'assets/thumbs/${scenario.id}.png',
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              scenario.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabGroup {
  const _LabGroup({required this.group, required this.entries});

  final ScenarioGroup group;
  final List<Scenario> entries;
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onOpen});

  final _LabGroup group;
  final void Function(Scenario scenario) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              group.group.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              group.group.description,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < group.entries.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        group.entries[i].icon,
                        size: 19,
                        color: scheme.primary,
                      ),
                    ),
                    title: Text(
                      group.entries[i].title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      group.entries[i].subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => onOpen(group.entries[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
