import 'app_route.dart';

/// Legacy → adaptive-shell-target redirect map (E13-R08, ADR 0275 §3).
///
/// Exactly the eleven Ch13 §7.5 legacy routes (brief §0.0 D5). `AppRoutes.songs`
/// is not a key: it IS the Songs destination itself, not a redirect source —
/// ADR 0275 §4 forbids a self-mapping edge. Every value here is a distinct
/// destination or target sub-route path (never also a key), which makes the
/// map single-step and therefore acyclic by construction (D7).
const Map<String, String> legacyRedirects = <String, String>{
  AppRoutes.live: AppRoutes.practiceLive,
  AppRoutes.analyze: AppRoutes.practiceAnalyze,
  AppRoutes.learn: AppRoutes.practiceLearn,
  AppRoutes.library: AppRoutes.profileLibrary,
  AppRoutes.settings: AppRoutes.profileSettings,
  AppRoutes.tuner: AppRoutes.practiceTuner,
  AppRoutes.metronome: AppRoutes.practiceMetronome,
  AppRoutes.progress: AppRoutes.profileProgress,
  AppRoutes.streak: AppRoutes.profileRewards,
  AppRoutes.setlists: AppRoutes.songsSetlists,
  AppRoutes.chords: AppRoutes.practiceChords,
};

/// The prefix shared by every concrete Song Trainer session URL, derived
/// from the [AppRoutes.songTrainerSession] template so the two can't drift.
final String _songTrainerSessionPrefix = AppRoutes.songTrainerSession
    .split(':')
    .first;

/// Whether primary navigation must stay hidden at [location] (ADR 0275 §5,
/// brief §0.0 D13). Deliberately narrow: only the session-style routes below
/// qualify. `/practice/live`, `/tuner`, and `/metronome` are NOT stage routes
/// in this round — the post-onboarding entry point resolves to one of them,
/// and hiding navigation there would strand the user without any way to
/// switch areas. Their Stage treatment is later-round work.
bool isStageRoute(String location) {
  if (location == AppRoutes.practiceSession) return true;
  if (location == AppRoutes.visionSession) return true;
  if (!location.startsWith(_songTrainerSessionPrefix)) return false;
  return !location.substring(_songTrainerSessionPrefix.length).contains('/');
}
