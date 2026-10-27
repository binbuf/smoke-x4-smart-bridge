import 'package:flutter/material.dart';

import '../../app/bridge_controller.dart';
import '../../app/view_state.dart';

/// Loads the History view state from the durable archive and rebuilds when the
/// filters, units, sort or committed archive rows change.
///
/// A controller without a database (fixture/review builds and most widget
/// tests) returns synchronously, so the approved shell is unchanged there.
class HistoryViewLoader extends StatefulWidget {
  const HistoryViewLoader({
    super.key,
    required this.controller,
    required this.builder,
    this.hasGap = true,
  });

  final BridgeController controller;
  final Widget Function(BuildContext context, HistoryViewState view) builder;
  final bool hasGap;

  @override
  State<HistoryViewLoader> createState() => _HistoryViewLoaderState();
}

class _HistoryViewLoaderState extends State<HistoryViewLoader> {
  String? _key;
  Future<HistoryViewState>? _future;
  HistoryViewState? _lastView;

  String _keyFor(BridgeController controller) {
    final range = controller.historyRange;
    final custom = controller.historyCustomRange;
    return [
      range.name,
      custom?.start.millisecondsSinceEpoch ?? 0,
      custom?.end.millisecondsSinceEpoch ?? 0,
      controller.historyProbe ?? 0,
      controller.historySort.name,
      controller.units.name,
      controller.historyRevision,
      controller.isOffline,
      controller.offlineCache,
      widget.hasGap,
    ].join('|');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final key = _keyFor(widget.controller);
        if (key != _key) {
          _key = key;
          _future = widget.controller.loadHistoryView(hasGap: widget.hasGap);
        }
        return FutureBuilder<HistoryViewState>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              _lastView = snapshot.data;
              return widget.builder(context, snapshot.data!);
            }
            if (snapshot.hasError) {
              return _HistoryLoadError(
                error: snapshot.error,
                onRetry: () => setState(() {
                  _key = null;
                }),
              );
            }
            final previous = _lastView;
            if (previous != null) {
              return widget.builder(context, previous);
            }
            return const _HistoryLoading();
          },
        );
      },
    );
  }
}

class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('history.loading'),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 80),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _HistoryLoadError extends StatelessWidget {
  const _HistoryLoadError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('history.loadError'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Couldn’t load saved readings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try again. The readings remain on your phone.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
