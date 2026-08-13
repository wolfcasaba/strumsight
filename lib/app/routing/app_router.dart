import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/analyze/screens/analyze_screen.dart';
import '../../features/audio_analysis/domain/analysis_document.dart';
import '../../features/audio_analysis/presentation/analysis_metric_detail_screen.dart';
import '../../features/audio_analysis/presentation/analysis_overview_screen.dart';
import '../../features/audio_analysis/presentation/controllers/overview_view_model.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/chords/screens/chord_library_screen.dart';
import '../../features/learn/screens/latency_calibration_screen.dart';
import '../../features/learn/screens/lesson_list_screen.dart';
import '../../features/library/public.dart';
import '../../features/library/screens/library_screen.dart';
import '../../features/library/screens/session_detail_screen.dart';
import '../../features/live/screens/live_screen.dart';
import '../../features/metronome/screens/metronome_screen.dart';
import '../../features/onboarding/onboarding_provider.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/practice/presentation/screens/practice_hub_screen.dart';
import '../../features/practice/presentation/screens/practice_result_screen.dart';
import '../../features/practice/presentation/screens/practice_setup_screen.dart';
import '../../features/practice/presentation/screens/practice_session_screen.dart';
import '../../features/progress/screens/progress_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/songs/screens/setlist_list_screen.dart';
import '../../features/songs/screens/song_list_screen.dart';
import '../../features/streak/screens/streak_screen.dart';
import '../../features/song_trainer/public.dart';
import '../../features/song_trainer/application/song_trainer_providers.dart';
import '../../features/song_trainer/application/trainer/song_trainer_result.dart';
import '../../features/song_trainer/presentation/screens/song_editor_screen.dart';
import '../../features/song_trainer/presentation/screens/song_overview_screen.dart';
import '../../features/song_trainer/presentation/screens/song_result_screen.dart';
import '../../features/song_trainer/presentation/screens/song_trainer_screen.dart';
import '../../features/song_trainer/presentation/screens/trainer_setup_screen.dart';
import '../../features/ai_tutor/presentation/screens/tutor_chat_screen.dart';
import '../../features/ai_tutor/presentation/screens/tutor_data_screen.dart';
import '../../features/ai_tutor/presentation/screens/tutor_home_screen.dart';
import '../../features/ai_tutor/presentation/screens/tutor_privacy_screen.dart';
import '../../features/ai_tutor/presentation/screens/tutor_profile_screen.dart';
import '../../features/tuner/screens/tuner_screen.dart';
import '../../features/vision/public.dart';
import '../config/app_config.dart';
import '../home_shell.dart';
import 'app_route.dart';
import 'route_guards.dart';

final class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

/// App router: a bottom-nav [ShellRoute] over the five tabs, plus full-screen
/// routes pushed from those destinations.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.listen(onboardingSeenProvider, (_, _) => refreshNotifier.refresh());

  // E02-R12: the Practice hub and setup routes are flag-gated. When the
  // flag is off, the routes are not registered, so a `/practice*` URL
  // hits the existing onException below and lands on Live — a
  // measurement, not new behaviour.
  final practiceEnabled = ref
      .read(appConfigProvider)
      .flags
      .practiceEngineV2Enabled;
  final songTrainerEnabled = ref
      .read(appConfigProvider)
      .flags
      .songTrainerV2Enabled;
  final aiTutorEnabled = ref.read(appConfigProvider).flags.aiTutorEnabled;
  final visionEnabled = ref.read(appConfigProvider).flags.visionEnabled;
  final visionSetupEnabled = ref
      .read(appConfigProvider)
      .flags
      .visionSetupEnabled;
  final visionGuitarGeometryEnabled = ref
      .read(appConfigProvider)
      .flags
      .visionGuitarGeometryEnabled;
  final audioAnalysisV2Enabled = ref
      .read(appConfigProvider)
      .flags
      .audioAnalysisV2Enabled;

  final router = GoRouter(
    initialLocation: AppRoutes.live,
    refreshListenable: refreshNotifier,
    onException: (_, _, router) => router.go(AppRoutes.live),
    redirect: (_, state) => onboardingRedirect(
      seen: ref.read(onboardingSeenProvider),
      location: state.uri.path,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, _) => const OnboardingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            HomeShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: AppRoutes.live, builder: (_, _) => const LiveScreen()),
          GoRoute(
            path: AppRoutes.analyze,
            builder: (_, _) => const AnalyzeScreen(),
          ),
          GoRoute(
            path: AppRoutes.learn,
            builder: (_, _) => const LessonListScreen(),
          ),
          GoRoute(
            path: AppRoutes.library,
            builder: (_, _) => const LibraryScreen(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (_, _) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(path: AppRoutes.tuner, builder: (_, _) => const TunerScreen()),
      GoRoute(
        path: AppRoutes.metronome,
        builder: (_, _) => const MetronomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.calibrate,
        builder: (_, _) => const LatencyCalibrationScreen(),
      ),
      GoRoute(path: AppRoutes.streak, builder: (_, _) => const StreakScreen()),
      GoRoute(
        path: AppRoutes.progress,
        builder: (_, _) => const ProgressScreen(),
      ),
      GoRoute(path: AppRoutes.songs, builder: (_, _) => const SongListScreen()),
      GoRoute(
        path: AppRoutes.setlists,
        builder: (_, _) => const SetlistListScreen(),
      ),
      GoRoute(
        path: AppRoutes.chords,
        builder: (_, _) => const ChordLibraryScreen(),
      ),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.librarySession,
        redirect: (_, state) =>
            state.extra is AnalyzedSession ? null : AppRoutes.library,
        builder: (_, state) {
          final session = state.extra;
          if (session is AnalyzedSession) {
            return SessionDetailScreen(session: session);
          }
          return const LibraryScreen();
        },
      ),
      if (practiceEnabled) ...[
        GoRoute(
          path: AppRoutes.practiceHub,
          builder: (_, _) => const PracticeHubScreen(),
        ),
        GoRoute(
          path: AppRoutes.practiceSetup,
          builder: (_, _) => const PracticeSetupScreen(),
        ),
        GoRoute(
          path: AppRoutes.practiceSession,
          builder: (_, _) => const PracticeSessionScreen(),
        ),
        GoRoute(
          path: AppRoutes.practiceResult,
          builder: (_, _) => const PracticeResultFallback(),
        ),
      ],
      if (songTrainerEnabled) ...[
        GoRoute(
          path: AppRoutes.songTrainerLibrary,
          builder: (_, _) => const SongLibraryScreen(),
        ),
        GoRoute(
          path: AppRoutes.songTrainerImport,
          builder: (_, _) => const SongImportScreen(),
        ),
        GoRoute(
          path: AppRoutes.songTrainerNewEditor,
          builder: (_, _) => const SongEditorScreen.newDocument(),
        ),
        GoRoute(
          path: AppRoutes.songTrainerEditor,
          builder: (_, state) =>
              SongEditorScreen(songId: state.pathParameters['songId']!),
        ),
        GoRoute(
          path: AppRoutes.songTrainerOverview,
          builder: (_, state) =>
              SongOverviewScreen(songId: state.pathParameters['songId']!),
        ),
        GoRoute(
          path: AppRoutes.songTrainerSetup,
          builder: (_, state) =>
              TrainerSetupScreen(songId: state.pathParameters['songId']!),
        ),
        GoRoute(
          path: AppRoutes.songTrainerSession,
          builder: (_, state) => SongTrainerScreen(
            songId: state.pathParameters['songId']!,
            inputs: state.extra! as SongTrainerControllerInputs,
          ),
        ),
        GoRoute(
          path: AppRoutes.songTrainerResult,
          builder: (_, state) =>
              SongResultScreen(result: state.extra! as SongTrainerResult),
        ),
      ],
      if (aiTutorEnabled) ...[
        GoRoute(
          path: AppRoutes.tutorHome,
          builder: (_, _) => const TutorHomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.tutorChat,
          builder: (_, _) => const TutorChatScreen(),
        ),
        GoRoute(
          path: AppRoutes.tutorProfile,
          builder: (_, _) => const TutorProfileScreen(),
        ),
        GoRoute(
          path: AppRoutes.tutorPrivacy,
          builder: (_, _) => const TutorPrivacyScreen(),
        ),
        GoRoute(
          path: AppRoutes.tutorData,
          builder: (_, _) => const TutorDataScreen(),
        ),
      ],
      if (visionEnabled && visionSetupEnabled) ...[
        GoRoute(
          path: AppRoutes.visionSetup,
          builder: (_, _) => const VisionSetupScreen(),
        ),
      ],
      if (visionEnabled && visionGuitarGeometryEnabled) ...[
        GoRoute(
          path: AppRoutes.visionGuitarGeometry,
          builder: (_, _) => const GuitarCalibrationScreen(),
        ),
      ],
      if (visionEnabled) ...[
        GoRoute(
          path: AppRoutes.visionSession,
          builder: (_, _) => const VisionSessionScreen(),
        ),
      ],
      if (audioAnalysisV2Enabled) ...[
        GoRoute(
          path: AppRoutes.analysisOverview,
          redirect: (_, state) =>
              state.extra is AnalysisDocument ? null : AppRoutes.live,
          builder: (_, state) {
            final extra = state.extra;
            if (extra is AnalysisDocument) {
              return AnalysisOverviewScreen(document: extra);
            }
            return const AnalysisOverviewScreen();
          },
        ),
        GoRoute(
          path: AppRoutes.analysisMetricDetail,
          redirect: (_, state) {
            final extra = state.extra;
            // Accept a card list (single-metric navigation source), the
            // combined metrics+insights payload (the "Részletek" entry
            // point), or a document (the overview header's legacy entry).
            if (extra is List<OverviewMetricCard> ||
                extra is OverviewDetailsPayload ||
                extra is AnalysisDocument) {
              return null;
            }
            return AppRoutes.live;
          },
          builder: (_, state) {
            final extra = state.extra;
            if (extra is OverviewDetailsPayload) {
              return AnalysisMetricDetailScreen(
                metrics: extra.metrics,
                remainingInsights: extra.remainingInsights,
              );
            }
            if (extra is List<OverviewMetricCard>) {
              return AnalysisMetricDetailScreen(metrics: extra);
            }
            return const AnalysisMetricDetailScreen();
          },
        ),
      ],
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refreshNotifier.dispose();
  });
  return router;
});
