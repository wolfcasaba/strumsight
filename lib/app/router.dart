import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/analyze/screens/analyze_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/library/model/analyzed_session.dart';
import '../features/library/screens/library_screen.dart';
import '../features/library/screens/session_detail_screen.dart';
import '../features/chords/screens/chord_library_screen.dart';
import '../features/learn/screens/lesson_list_screen.dart';
import '../features/live/screens/live_screen.dart';
import '../features/onboarding/onboarding_provider.dart';
import '../features/onboarding/screens/onboarding_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/streak/screens/streak_screen.dart';
import '../features/tuner/screens/tuner_screen.dart';
import 'home_shell.dart';

/// App router: a bottom-nav [ShellRoute] over the four tabs, plus the Tuner as
/// a full-screen route pushed from Live. A first-run [redirect] gates everything
/// behind `/welcome` until onboarding is completed.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/live',
    redirect: (context, state) {
      final seen = ref.read(onboardingSeenProvider);
      final atWelcome = state.uri.path == '/welcome';
      if (!seen && !atWelcome) return '/welcome';
      if (seen && atWelcome) return '/live';
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const OnboardingScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            HomeShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/live', builder: (_, _) => const LiveScreen()),
          GoRoute(
            path: '/analyze',
            builder: (_, _) => const AnalyzeScreen(),
          ),
          GoRoute(
            path: '/learn',
            builder: (_, _) => const LessonListScreen(),
          ),
          GoRoute(
            path: '/library',
            builder: (_, _) => const LibraryScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(path: '/tuner', builder: (_, _) => const TunerScreen()),
      GoRoute(path: '/streak', builder: (_, _) => const StreakScreen()),
      GoRoute(
          path: '/chords', builder: (_, _) => const ChordLibraryScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/library/session',
        builder: (_, state) =>
            SessionDetailScreen(session: state.extra as AnalyzedSession),
      ),
    ],
  );
});
