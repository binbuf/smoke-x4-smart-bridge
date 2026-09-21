/// N0.7 — the placeholder route table. N4 replaces this with the five
/// destinations, the overlay stack and the fullscreen graph host.
library;

import 'package:go_router/go_router.dart';

import '../design/gallery.dart';
import '../features/home/home_page.dart';

final GoRouter appRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(path: '/', builder: (context, state) => const HomePage()),
    // N3's exit gate: the component gallery, reachable for manual review. N4
    // replaces this table; N16 may keep it behind a debug flag.
    GoRoute(
      path: '/design',
      builder: (context, state) => const DesignGallery(),
    ),
  ],
);
