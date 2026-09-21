/// N4 — the shell root.
///
/// [AppShell] is the persistent chrome every destination is rendered inside.
/// It owns **no business state**: the connection, alarms and cook all come from
/// the N2 providers; the shell only projects them onto the chrome and routes
/// navigation.
///
/// Navigation is **controlled**: [location] is the current URL and
/// [onLocation] asks the router to move. That keeps the shell testable without
/// go_router while the real router passes `GoRouterState.uri` and `context.go`.
/// Named overlays are read straight from the location's query string, so a deep
/// link and a tap produce exactly the same surface.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dev_panel.dart';
import '../../data/providers.dart';
import '../../design/design.dart';
import '../dev/dev_panel.dart';
import '../graph/graph_fullscreen.dart';
import '../onboarding/onboarding_model.dart';
import '../onboarding/onboarding_sheet.dart';
import 'app_bar.dart';
import 'bottom_nav.dart';
import 'graph_host.dart';
import 'overlay.dart';
import 'phone_frame.dart';
import 'shell_screen.dart';
import 'toast.dart';
import 'transport_status.dart';

/// Whether the shell mounts its repeating pulse controller.
///
/// Production leaves it on: a root-owned repeating animation makes
/// `pumpAndSettle` unusable, so tests that need to settle override this to
/// false and get a static dot.
final shellPulseEnabledProvider = Provider<bool>((ref) => true);

/// The status-bar clock source. Overridable so goldens are deterministic.
final shellClockProvider = Provider<DateTime>((ref) => DateTime.now());

/// The path half of a location, with the query stripped.
String baseLocation(String location) => Uri.parse(location).path;

/// The named overlay a location asks for, or null.
OverlayRequest? overlayRequestFromLocation(String location) {
  final link = DevDeepLink.parse(location);
  final overlay = link.overlay;
  if (overlay == null) {
    return null;
  }
  return OverlayRequest(overlay, link.props);
}

/// A location that opens [overlay] with [props], preserving the path.
String locationWithOverlay(
  String location,
  DevOverlay overlay, [
  Map<String, String> props = const <String, String>{},
]) {
  return Uri(
    path: baseLocation(location),
    queryParameters: <String, String>{'overlay': overlay.name, ...props},
  ).toString();
}

/// The callbacks a destination uses to reach the shell.
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.openOverlay,
    required this.closeOverlay,
    required this.showToast,
    required this.toggleFullGraph,
    required this.openScreen,
    this.openCookDetail = _noopOpenCookDetail,
    required super.child,
  });

  final void Function(DevOverlay overlay, [Map<String, String> props])
  openOverlay;
  final VoidCallback closeOverlay;
  final void Function(String message) showToast;
  final VoidCallback toggleFullGraph;

  /// Navigates to a bottom-nav destination (Live → Graph, etc.).
  final ValueChanged<ShellScreen> openScreen;

  /// Navigates to one past cook's detail (`/settings/history/:id`, N12.1).
  final ValueChanged<String> openCookDetail;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}

void _noopOpenCookDetail(String id) {}

/// The persistent shell.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
    this.onLocation,
  });

  /// The current path + query. The router passes `GoRouterState.uri`.
  final String location;

  /// The destination page body.
  final Widget child;

  /// Asks the router to move. When null the shell navigates locally, which is
  /// what the widget tests use.
  final ValueChanged<String>? onLocation;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  late final DateTime _now;
  late final ShellToastController _toast;
  late final AnimationController? _pulse;
  final Map<String, ScrollController> _overlayScroll =
      <String, ScrollController>{};
  final Map<String, double> _overlayScrollOffsets = <String, double>{};
  String? _localLocation;
  bool _fullGraph = false;
  bool _appliedInitialDeepLink = false;

  String get _location => _localLocation ?? widget.location;

  @override
  void initState() {
    super.initState();
    _now = ref.read(shellClockProvider);
    _toast = ShellToastController();
    _pulse = ref.read(shellPulseEnabledProvider)
        ? (AnimationController(vsync: this, duration: const SmokeMotion().pulse)
            ..repeat(reverse: true))
        : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyInitialDeepLink();
    });
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _localLocation = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    _toast.dispose();
    for (final controller in _overlayScroll.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _applyInitialDeepLink() {
    if (_appliedInitialDeepLink) {
      return;
    }
    _appliedInitialDeepLink = true;
    if (kReleaseMode) {
      return;
    }
    final link = ref.read(initialDevDeepLinkProvider);
    if (link.isEmpty) {
      return;
    }
    var target = baseLocation(widget.location);
    if (link.screen != null) {
      target = baseLocation(pathForDevScreen(link.screen!));
    }
    if (link.overlay != null) {
      target = locationWithOverlay(target, link.overlay!, link.props);
    }
    _go(target);
  }

  void _go(String location) {
    if (location == _location) {
      return;
    }
    final onLocation = widget.onLocation;
    if (onLocation != null) {
      onLocation(location);
    } else {
      setState(() => _localLocation = location);
    }
  }

  void _onNavSelect(ShellScreen screen) => _go(screen.path);

  void _openCookDetail(String id) => _go('${ShellScreen.history.path}/$id');

  void _onBack(ShellScreen screen) {
    switch (screen) {
      case ShellScreen.cookDetail:
        _go(ShellScreen.history.path);
      case ShellScreen.history:
        _go(ShellScreen.settings.path);
      default:
        break;
    }
  }

  void _openOverlay(
    DevOverlay overlay, [
    Map<String, String> props = const <String, String>{},
  ]) {
    final restore = _overlayScrollOffsets[overlay.name];
    if (restore != null && restore > 0) {
      // The sheet is rebuilt on open; restore its body scroll once attached
      // (N4.11 — per-overlay scroll survives close/reopen).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = _overlayScroll[overlay.name];
        if (controller != null && controller.hasClients) {
          controller.jumpTo(
            math.min(restore, controller.position.maxScrollExtent),
          );
        }
      });
    }
    _go(locationWithOverlay(_location, overlay, props));
  }

  void _closeOverlay() {
    final request = overlayRequestFromLocation(_location);
    if (request != null) {
      final controller = _overlayScroll[request.name.name];
      if (controller != null && controller.hasClients) {
        _overlayScrollOffsets[request.name.name] = controller.offset;
      }
    }
    _go(baseLocation(_location));
  }

  void _toggleFullGraph() => setState(() => _fullGraph = !_fullGraph);

  ScrollController? _overlayScrollController(OverlayRequest? request) {
    if (request == null) {
      return null;
    }
    return _overlayScroll.putIfAbsent(
      request.name.name,
      () => ScrollController(),
    );
  }

  void _onDevScreen(DevScreen screen) => _go(pathForDevScreen(screen));

  void _onDevOverlay(DevOverlay overlay, Map<String, String> props) =>
      _openOverlay(overlay, props);

  @override
  Widget build(BuildContext context) {
    final screen = screenFromPath(_location);
    final snapshot = ref.watch(snapshotProvider).value;
    final unacked = snapshot?.alarms.where((alarm) => !alarm.acked).length ?? 0;
    final transport = snapshot == null
        ? TransportStatus.unknown
        : TransportStatus.from(snapshot.connection);
    final overlay = overlayRequestFromLocation(_location);
    final onboardingRequired = ref.watch(onboardingRequiredProvider);

    final chrome = ShellScope(
      openOverlay: _openOverlay,
      closeOverlay: _closeOverlay,
      showToast: _toast.show,
      toggleFullGraph: _toggleFullGraph,
      openScreen: _onNavSelect,
      openCookDetail: _openCookDetail,
      child: SmokePulseScope(
        pulse: _pulse,
        child: ShellPhoneFrame(
          now: _now,
          overlay: _overlayStack(overlay, onboardingRequired),
          toast: ShellToastHost(controller: _toast),
          child: Column(
            children: <Widget>[
              ShellAppBar(
                screen: screen,
                unackedAlarms: unacked,
                transport: transport,
                onAlerts: () => _openOverlay(DevOverlay.alarms),
                onBack: () => _onBack(screen),
                onStartCook: () => _openOverlay(DevOverlay.setup),
                onConnection: () => _openOverlay(DevOverlay.connect),
              ),
              Expanded(child: widget.child),
              ShellBottomNav(
                current: screen,
                unackedAlarms: unacked,
                onSelect: _onNavSelect,
              ),
            ],
          ),
        ),
      ),
    );

    if (kReleaseMode) {
      return chrome;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 700 && constraints.maxHeight >= 500;
        if (!wide) {
          return Stack(
            children: <Widget>[
              Positioned.fill(child: chrome),
              Positioned(
                right: 12,
                bottom: 78,
                child: _DevPanelButton(
                  onTap: () => unawaited(_openDevPanel(context)),
                ),
              ),
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 390,
                  height: math.min(844, constraints.maxHeight),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(43),
                    child: chrome,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 340,
              child: DevPanel(onScreen: _onDevScreen, onOverlay: _onDevOverlay),
            ),
          ],
        );
      },
    );
  }

  Widget? _overlayStack(OverlayRequest? overlay, bool onboardingRequired) {
    if (overlay == null && !_fullGraph && !onboardingRequired) {
      return null;
    }
    return Stack(
      children: <Widget>[
        if (overlay != null)
          Positioned.fill(
            child: ShellOverlayHost(
              request: overlay,
              onDismiss: _closeOverlay,
              scrollController: _overlayScrollController(overlay),
            ),
          ),
        if (_fullGraph)
          Positioned.fill(
            child: ShellFullscreenGraphHost(
              onDismiss: _toggleFullGraph,
              child: GraphFullscreenBody(onDismiss: _toggleFullGraph),
            ),
          ),
        // N14.12 — while no bridge is known the wizard owns the screen. It is
        // mounted last so it sits above any deep-linked overlay too.
        if (onboardingRequired)
          Positioned.fill(
            child: OnboardingSurface(onDone: _onboardingDone, onSkip: () {}),
          ),
      ],
    );
  }

  void _onboardingDone() => _go(ShellScreen.live.path);

  Future<void> _openDevPanel(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.surface,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
        ),
        child: DevPanel(onScreen: _onDevScreen, onOverlay: _onDevOverlay),
      ),
    );
  }
}

class _DevPanelButton extends StatelessWidget {
  const _DevPanelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SmokeTokens.of(context);
    return Semantics(
      button: true,
      label: 'Prototype controls',
      child: Material(
        key: const ValueKey<String>('shell-dev-panel-button'),
        color: tokens.cardRaised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SmokeIcon(
              SmokeGlyph.sliders,
              size: 22,
              color: tokens.textHi,
            ),
          ),
        ),
      ),
    );
  }
}
