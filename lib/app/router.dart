import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/analyze/screens/analyze_placeholder_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/library/screens/library_placeholder_screen.dart';
import '../features/live/screens/live_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/tuner/screens/tuner_screen.dart';
import 'home_shell.dart';

/// App router: a bottom-nav [ShellRoute] over the four tabs, plus the Tuner as
/// a full-screen route pushed from Live.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/live',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            HomeShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/live', builder: (_, _) => const LiveScreen()),
          GoRoute(
            path: '/analyze',
            builder: (_, _) => const AnalyzePlaceholderScreen(),
          ),
          GoRoute(
            path: '/library',
            builder: (_, _) => const LibraryPlaceholderScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(path: '/tuner', builder: (_, _) => const TunerScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    ],
  );
});
