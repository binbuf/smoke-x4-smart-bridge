/// The in-app error boundary (design 08 §8.3 — A1.2).
///
/// Three hooks feed one readable screen, so an uncaught exception NEVER
/// surfaces as the framework's grey box:
///
///  * [ErrorWidget.builder] → [appErrorWidgetBuilder]: a widget that throws
///    during build/layout is replaced in place by [AppErrorScreen];
///  * the `runZonedGuarded` handler (see `bootstrap.dart`) → [AppErrors
///    .reportFatal]: uncaught async errors overlay the whole app via
///    [ErrorBoundary];
///  * [FlutterError.onError] keeps console reporting and forwards to the
///    same sink.
library;

import 'package:flutter/widgets.dart';

/// One captured failure: what was thrown and where.
@immutable
class AppErrorReport {
  const AppErrorReport(this.error, this.stack);

  final Object error;
  final StackTrace? stack;

  String get message => error.toString();
}

/// Process-wide error sink. Fatal reports drive the [ErrorBoundary] overlay.
abstract final class AppErrors {
  /// The most recent uncaught error, or `null` when the app is healthy.
  static final ValueNotifier<AppErrorReport?> lastFatal =
      ValueNotifier<AppErrorReport?>(null);

  /// Record an uncaught error and surface it in the UI.
  static void reportFatal(Object error, StackTrace? stack) {
    debugPrint('FATAL: $error\n${stack ?? ''}');
    lastFatal.value = AppErrorReport(error, stack);
  }

  /// Clear the overlay (the "Dismiss" action).
  static void clearFatal() => lastFatal.value = null;
}

/// Install the global hooks. Called once from `bootstrap.dart`, before
/// `runApp`. Not called by widget tests, which install only the pieces they
/// exercise.
void installGlobalErrorHooks() {
  ErrorWidget.builder = appErrorWidgetBuilder;
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    // Keep the console output — field debugging needs the full report.
    defaultOnError?.call(details);
    // Build-phase errors already surface in place via ErrorWidget.builder;
    // no overlay here, or a single overflow would eclipse the whole app.
  };
}

/// Replacement for the default grey/red [ErrorWidget]: a readable, in-place
/// error screen.
Widget appErrorWidgetBuilder(FlutterErrorDetails details) => AppErrorScreen(
  error: details.exception,
  stack: details.stack,
);

/// Wraps the app (via `MaterialApp.builder`) and overlays [AppErrorScreen]
/// whenever [AppErrors.lastFatal] is set by the zone handler.
class ErrorBoundary extends StatelessWidget {
  const ErrorBoundary({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppErrorReport?>(
        valueListenable: AppErrors.lastFatal,
        builder: (context, report, _) {
          if (report == null) {
            return child;
          }
          return AppErrorScreen(
            error: report.error,
            stack: report.stack,
            onDismiss: AppErrors.clearFatal,
          );
        },
      );
}

/// The readable error screen: message plus a stack snippet.
///
/// Deliberately built from raw widgets (no Material, own [Directionality])
/// so it renders anywhere in the tree — including as an [ErrorWidget]
/// replacement above/outside `MaterialApp`. Palette is hardcoded dark-first.
class AppErrorScreen extends StatelessWidget {
  const AppErrorScreen({
    required this.error,
    super.key,
    this.stack,
    this.onDismiss,
  });

  final Object error;
  final StackTrace? stack;
  final VoidCallback? onDismiss;

  static const Color _bg = Color(0xFF14090B);
  static const Color _fg = Color(0xFFF2F3F5);
  static const Color _accent = Color(0xFFFF6B6B);

  String get _stackSnippet {
    final trace = stack;
    if (trace == null) {
      return '(no stack trace)';
    }
    const maxLines = 12;
    final lines = trace.toString().trimRight().split('\n');
    final snippet = lines.take(maxLines).join('\n');
    return lines.length > maxLines ? '$snippet\n…' : snippet;
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: _bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Something went wrong',
              style: TextStyle(
                color: _accent,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              error.toString(),
              style: const TextStyle(
                color: _fg,
                fontSize: 17,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _stackSnippet,
              style: const TextStyle(
                color: Color(0xFFB8BCC2),
                fontSize: 13,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onDismiss,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: _accent, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Dismiss',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
