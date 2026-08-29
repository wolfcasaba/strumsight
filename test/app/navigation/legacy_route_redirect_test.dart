// E13-R08 (ADR 0275) — A2, A5.
//
// A2: all eleven Ch13 §7.5 legacy routes (brief §0.0 D5) redirect to their
// adaptive-shell target when `adaptiveShellEnabled` is on, preserving the
// query string and fragment (D8) — a redirect built from a string constant
// instead of `uri.replace(path: ...)` would silently drop them.
// A5: the redirect map satisfies the four D7 contracts (no self-edge, no
// value is also a key, every value is reachable, and the key set is exactly
// the pinned eleven).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/adaptive_shell_routes.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/features/analyze/screens/analyze_screen.dart';
import 'package:strumsight/features/chords/screens/chord_library_screen.dart';
import 'package:strumsight/features/learn/screens/lesson_list_screen.dart';
import 'package:strumsight/features/library_v2/screens/unified_library_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/progress/screens/progress_screen.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/songs/screens/setlist_list_screen.dart';
import 'package:strumsight/features/streak/screens/streak_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

class _RouterTestApp extends ConsumerWidget {
  const _RouterTestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

Future<GoRouter> _pumpAdaptiveRouter(WidgetTester tester) async {
  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: true,
            labModeAvailable: true,
            adaptiveShellEnabled: true,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  final router = container.read(routerProvider);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await liveEngine.dispose();
    await tunerEngine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const _RouterTestApp(),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// The pinned D5 legacy → target map, kept independent of production's
/// `legacyRedirects` so a silently narrowed/widened production map goes red
/// here rather than trivially agreeing with itself.
const Map<String, String> _pinnedLegacy = <String, String>{
  '/live': '/practice/live',
  '/analyze': '/practice/analyze',
  '/learn': '/practice/learn',
  '/library': '/profile/library',
  '/settings': '/profile/settings',
  '/tuner': '/practice/tuner',
  '/metronome': '/practice/metronome',
  '/progress': '/profile/progress',
  '/streak': '/profile/rewards',
  '/setlists': '/songs/setlists',
  '/chords': '/practice/chords',
};

void main() {
  group('A5 — legacyRedirects satisfies the four D7 contracts', () {
    test('contract 1: no key maps to itself', () {
      for (final entry in legacyRedirects.entries) {
        expect(entry.key, isNot(entry.value));
      }
    });

    test('contract 2: values and keys are disjoint (single-step, acyclic)', () {
      expect(
        legacyRedirects.values.toSet().intersection(
          legacyRedirects.keys.toSet(),
        ),
        isEmpty,
      );
    });

    test('contract 4: the key set is exactly the pinned eleven D5 routes', () {
      expect(legacyRedirects.keys.toSet(), _pinnedLegacy.keys.toSet());
    });

    test('the pinned map matches production 1:1 (values too)', () {
      expect(legacyRedirects, _pinnedLegacy);
    });

    test(
      'AppRoutes.songs is not a redirect source (identity, not an edge)',
      () {
        expect(legacyRedirects.containsKey(AppRoutes.songs), isFalse);
      },
    );
  });

  group(
    'A2 / A5 contract 3 — every legacy route redirects to a live screen',
    () {
      testWidgets('all eleven legacy routes resolve to their target adapter', (
        tester,
      ) async {
        final router = await _pumpAdaptiveRouter(tester);
        final expectedScreens = <String, Type>{
          AppRoutes.live: LiveScreen,
          AppRoutes.analyze: AnalyzeScreen,
          AppRoutes.learn: LessonListScreen,
          // E13-R28 (§0.0/B2) — `/library` redirects to `/profile/library`,
          // which now renders the unified library (the legacy `LibraryScreen`
          // itself stays wired, untouched, at the bare `/library` route).
          AppRoutes.library: UnifiedLibraryScreen,
          AppRoutes.settings: SettingsScreen,
          AppRoutes.tuner: TunerScreen,
          AppRoutes.metronome: MetronomeScreen,
          AppRoutes.progress: ProgressScreen,
          AppRoutes.streak: StreakScreen,
          AppRoutes.setlists: SetlistListScreen,
          AppRoutes.chords: ChordLibraryScreen,
        };

        for (final entry in expectedScreens.entries) {
          final legacy = entry.key;
          final target = legacyRedirects[legacy]!;

          router.go(legacy);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull, reason: legacy);
          expect(
            router.state.uri.path,
            target,
            reason: '$legacy must redirect to $target, not loop back',
          );
          expect(
            find.byWidgetPredicate((w) => w.runtimeType == entry.value),
            findsOneWidget,
            reason: '$target must render a ${entry.value}',
          );
        }
      });
    },
  );

  group('A2 — deep-link query + fragment survive the redirect (D8)', () {
    testWidgets('query string and fragment are preserved, not dropped', (
      tester,
    ) async {
      final router = await _pumpAdaptiveRouter(tester);

      router.go('/library?tab=sessions&sort=recent#top');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.profileLibrary);
      expect(router.state.uri.query, 'tab=sessions&sort=recent');
      expect(router.state.uri.fragment, 'top');
    });

    testWidgets('a redirect with no query/fragment stays clean', (
      tester,
    ) async {
      final router = await _pumpAdaptiveRouter(tester);

      router.go(AppRoutes.setlists);
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.songsSetlists);
      expect(router.state.uri.query, isEmpty);
      expect(router.state.uri.fragment, isEmpty);
    });
  });
}
