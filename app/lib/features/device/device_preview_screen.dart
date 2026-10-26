import 'dart:async';

import 'package:flutter/material.dart';

import '../../prototype/formatters.dart';
import '../../prototype/prototype_controller.dart';
import '../../widgets/prototype_app_bar.dart';
import '../../widgets/prototype_widgets.dart';

enum DeviceOverlay {
  none,
  boot,
  passkey,
  power,
  storage,
  resetting,
  clearing,
  off,
}

class DevicePreviewScreen extends StatefulWidget {
  const DevicePreviewScreen({
    super.key,
    required this.controller,
    this.initialPage = 1,
    this.initialOverlay = DeviceOverlay.none,
  });

  final PrototypeController controller;
  final int initialPage;
  final DeviceOverlay initialOverlay;

  @override
  State<DevicePreviewScreen> createState() => _DevicePreviewScreenState();
}

class _DevicePreviewScreenState extends State<DevicePreviewScreen> {
  late int _page;
  late DeviceOverlay _overlay;
  int _countdown = 2;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _overlay = widget.initialOverlay;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: prototypeAppBar(context, widget.controller, 'Bridge screen'),
      body: ListView(
        children: [
          ContentWidth(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bridge screen preview',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '128×64 SSD1306 · simulated at 3×. One button, four pages, seven states.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                Center(child: _deviceFrame(context)),
                const SizedBox(height: 20),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pages',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final entry in const [
                            (1, 'Probes'),
                            (2, 'Connection'),
                            (3, 'Billows'),
                            (4, 'Bridge'),
                          ])
                            ChoiceChip(
                              label: Text('${entry.$1} · ${entry.$2}'),
                              selected:
                                  _overlay == DeviceOverlay.none &&
                                  _page == entry.$1,
                              onSelected: (_) => setState(() {
                                _overlay = DeviceOverlay.none;
                                _page = entry.$1;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'States & overlays',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in const [
                            (DeviceOverlay.boot, 'Boot'),
                            (DeviceOverlay.passkey, 'Pairing code'),
                            (DeviceOverlay.power, 'Power off'),
                            (DeviceOverlay.storage, 'Storage failure'),
                            (DeviceOverlay.resetting, 'Resetting'),
                            (DeviceOverlay.clearing, 'Clearing log'),
                            (DeviceOverlay.off, 'Off'),
                          ])
                            ChoiceChip(
                              label: Text(entry.$2),
                              selected: _overlay == entry.$1,
                              onSelected: (_) => setState(() {
                                _overlay = entry.$1;
                                if (entry.$1 == DeviceOverlay.power) {
                                  _countdown = 2;
                                }
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _tapPrg,
                              icon: const Icon(Icons.touch_app, size: 18),
                              label: const Text('Tap PRG'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _holdPrg,
                              icon: const Icon(Icons.timer_outlined, size: 18),
                              label: const Text('Hold PRG'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tap the PRG button to wake a sleeping display without changing the page. Hold it to show the countdown; release before 1.5 s cancels.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceFrame(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF29241F)
            : const Color(0xFFD8CFC4),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.contain,
        child: Container(
          width: 384,
          height: 192,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A342C), width: 2),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xFFE9E3D8),
              fontFamily: 'Roboto',
              fontSize: 12,
              height: 1.35,
              fontFeatures: [FontFeature.tabularFigures()],
              letterSpacing: 0.4,
            ),
            child: _overlay == DeviceOverlay.none
                ? _pageContent()
                : _overlayContent(),
          ),
        ),
      ),
    );
  }

  Widget _pageContent() {
    switch (_page) {
      case 1:
        final probes = widget.controller.probes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < probes.length; i++)
              _oledRow(
                'P${i + 1}',
                probes[i].connected
                    ? '${widget.controller.valueFor(probes[i].tempF)}${widget.controller.unitSuffix}'
                    : '---',
              ),
            const Spacer(),
            _oledRow('• App   • X4', '${widget.controller.batteryPercent}%'),
          ],
        );
      case 2:
        final linked = widget.controller.isConnected;
        final x4 = switch (widget.controller.smokeXStatus) {
          SmokeXStatus.pairedLive => 'paired',
          SmokeXStatus.pairedLost => 'no data 14m',
          SmokeXStatus.unpaired => 'not paired',
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _oledRow('App', linked ? 'connected' : 'ready to pair'),
            _oledRow('Name', 'SmokeX4-${widget.controller.deviceId}'),
            _oledRow('Phones paired', '2/4'),
            const SizedBox(height: 8),
            _oledRow('X4', x4),
            _oledRow('Radio', '910.5 MHz'),
            _oledRow('Signal ${widget.controller.rssi}', 'last 12s'),
          ],
        );
      case 3:
        final pit = widget.controller.probes[3];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _oledRow(
              'BILLOWS',
              widget.controller.billowsDetected ? 'DETECTED' : 'NOT DETECTED',
            ),
            _oledRow(
              'SET',
              widget.controller.smokeXChannel4SetKnown
                  ? widget.controller.tempFor(
                      widget.controller.smokeXChannel4SetF.toDouble(),
                    )
                  : '—',
            ),
            _oledRow(
              'P4',
              pit.connected
                  ? '${widget.controller.valueFor(pit.tempF)}${widget.controller.unitSuffix}'
                  : '—',
            ),
            const Spacer(),
            const Text('Set on the Smoke X4'),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _oledRow('BRIDGE', 'v${widget.controller.firmware}'),
            _oledRow('Battery', '3.89V  ${widget.controller.batteryPercent}%'),
            _oledRow('Log', '12.4 days left'),
            _oledRow('Readings', commaInt(widget.controller.bridgeRecords)),
            _oledRow('Uptime', '14:15:30'),
            _oledRow('Memory', '142k (low 128k)'),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _overlayContent() {
    switch (_overlay) {
      case DeviceOverlay.passkey:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('  PAIR WITH PHONE'),
            SizedBox(height: 15),
            Text(
              '      418 302',
              style: TextStyle(
                fontSize: 27,
                letterSpacing: 3,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 13),
            Text('  enter this code'),
            Text('  on your phone'),
          ],
        );
      case DeviceOverlay.power:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('  POWER OFF'),
            const SizedBox(height: 15),
            Text('  keep holding   $_countdown'),
            const SizedBox(height: 15),
            const Text('  release to cancel'),
          ],
        );
      case DeviceOverlay.storage:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(' STORAGE UNAVAILABLE'),
            SizedBox(height: 10),
            Text(' live readings only'),
            Text(' this session will'),
            Text(' not be recorded'),
          ],
        );
      case DeviceOverlay.boot:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('  SMOKE X4 BRIDGE'),
            SizedBox(height: 6),
            Text('       v0.1.0'),
            SizedBox(height: 18),
            Text('  Attach antenna before'),
            Text('  power'),
          ],
        );
      case DeviceOverlay.resetting:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('    RESETTING…'),
            SizedBox(height: 16),
            Text('  do not power off'),
          ],
        );
      case DeviceOverlay.clearing:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('   CLEARING LOG…'),
            SizedBox(height: 16),
            Text('  do not power off'),
          ],
        );
      case DeviceOverlay.off:
        return const Center(
          child: Text(
            '    OFF',
            style: TextStyle(
              fontSize: 27,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      case DeviceOverlay.none:
        return const SizedBox.shrink();
    }
  }

  Widget _oledRow(String left, String right) {
    return Row(
      children: [
        Expanded(
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.clip,
            softWrap: false,
          ),
        ),
        Text(right, maxLines: 1, overflow: TextOverflow.clip, softWrap: false),
      ],
    );
  }

  void _tapPrg() {
    setState(() {
      if (_overlay == DeviceOverlay.storage ||
          _overlay == DeviceOverlay.passkey ||
          _overlay == DeviceOverlay.power ||
          _overlay == DeviceOverlay.boot ||
          _overlay == DeviceOverlay.resetting ||
          _overlay == DeviceOverlay.clearing) {
        _overlay = DeviceOverlay.none;
      } else if (_overlay == DeviceOverlay.off) {
        _overlay = DeviceOverlay.boot;
      } else {
        _page = _page % 4 + 1;
      }
    });
  }

  void _holdPrg() {
    _timer?.cancel();
    setState(() {
      _overlay = DeviceOverlay.power;
      _countdown = 2;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (!mounted) return;
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          timer.cancel();
          _overlay = DeviceOverlay.off;
        }
      });
    });
  }
}
