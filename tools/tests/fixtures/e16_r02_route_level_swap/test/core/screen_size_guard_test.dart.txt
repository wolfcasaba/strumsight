import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/features/chords/screens/chord_library_screen.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/features/songs/screens/song_builder_screen.dart';
import 'package:strumsight/features/streak/screens/streak_screen.dart';
import 'package:strumsight/main.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/learn/screens/learn_screen.dart';
import 'package:strumsight/features/learn/screens/lesson_list_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/features/practice/application/practice_catalog_controller.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_setup_controller.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/repository/practice_catalog_repository.dart';
import 'package:strumsight/features/practice/presentation/practice_route_args.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_hub_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/features/progress/screens/progress_screen.dart';
import 'package:strumsight/features/tuner/model/tuner_reading.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_engines.dart';
import '../support/preference_store.dart';

/// Round 96 — layout guard: every main screen must build WITHOUT overflow on
/// a small phone (320×568 logical, iPhone-SE class) and in landscape
/// (915×412). RenderFlex overflows surface as test-framework exceptions, so
/// pumping alone is the assertion.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> atSize(
    WidgetTester tester,
    Size logical,
    Future<void> Function() pumpScreen,
  ) async {
    tester.view.physicalSize = logical;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpScreen();
    await tester.pump(const Duration(milliseconds: 400));
  }

  final sizes = <String, Size>{
    'small portrait (320×568)': const Size(320, 568),
    'normal portrait (412×915)': const Size(412, 915),
    'landscape (915×412)': const Size(915, 412),
  };

  for (final entry in sizes.entries) {
    group(entry.key, () {
      testWidgets('Tuner (with a live reading)', (tester) async {
        final engine = FakeTunerEngine();
        addTearDown(engine.dispose);
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                ...preferenceOverrides(),
                tunerEngineProvider.overrideWithValue(engine),
              ],
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: TunerScreen(),
              ),
            ),
          );
          await tester.pump();
          engine.emit(
            const TunerReading(note: 'A', cents: 3, frequencyHz: 110),
          );
          await tester.pump();
        });
      });

      testWidgets('Learn home (lesson list)', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: preferenceOverrides(),
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: LessonListScreen(now: DateTime(2026, 7, 11)),
              ),
            ),
          );
        });
      });

      testWidgets('Learn player (paused, with score HUD area)', (tester) async {
        final engine = FakeStrumEngine();
        addTearDown(engine.dispose);
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                ...preferenceOverrides(),
                strumEngineProvider.overrideWithValue(engine),
              ],
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: LearnScreen(lesson: Lessons.downUpGroove),
              ),
            ),
          );
        });
      });

      testWidgets('Metronome', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const MetronomeScreen(),
            ),
          );
        });
      });

      testWidgets('Chord library', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: preferenceOverrides(),
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: ChordLibraryScreen(),
              ),
            ),
          );
        });
      });

      testWidgets('Progress', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: preferenceOverrides(),
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: ProgressScreen(),
              ),
            ),
          );
        });
      });

      testWidgets('full app tab walk (Live→Analyze→Learn→Library→Settings)', (
        tester,
      ) async {
        PackageInfo.setMockInitialValues(
          appName: 'StrumSight',
          packageName: 'test',
          version: '0.0.0',
          buildNumber: '1',
          buildSignature: '',
        );
        final engine = FakeStrumEngine();
        addTearDown(engine.dispose);
        await atSize(tester, entry.value, () async {
          final container = ProviderContainer(
            overrides: [
              ...preferenceOverrides(),
              strumEngineProvider.overrideWithValue(engine),
            ],
          );
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const StrumSightApp(),
            ),
          );
          await tester.pumpAndSettle();
          // E15-R02 (ADR 0467 D9): the app boots on the adaptive shell's
          // /today entry point now; the legacy tab labels this walk used to
          // tap are gone from the bottom nav. Walk the legacyRedirects
          // targets instead — the same screens the old tab bar reached.
          final router = container.read(routerProvider);
          for (final target in [
            AppRoutes.practiceAnalyze,
            AppRoutes.practiceLearn,
            AppRoutes.profileLibrary,
            AppRoutes.profileSettings,
          ]) {
            router.go(target);
            await tester.pumpAndSettle();
          }
        });
      });

      testWidgets('Onboarding', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: OnboardingScreen(),
            ),
          );
        });
      });

      testWidgets('Streak', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: preferenceOverrides(),
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: StreakScreen(now: DateTime(2026, 7, 11)),
              ),
            ),
          );
        });
      });

      testWidgets('Song builder', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: preferenceOverrides(),
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: SongBuilderScreen(),
              ),
            ),
          );
        });
      });

      testWidgets('Practice hub (E02-R12)', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                ...preferenceOverrides(),
                practiceCatalogRepositoryProvider.overrideWithValue(
                  const _GuardRepository(),
                ),
              ],
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PracticeHubScreen(now: DateTime(2026, 7, 11)),
              ),
            ),
          );
          await tester.pump();
          // E15-R07 F1 (ADR 0491) — the ONE Practice Generator entry point
          // renders here too: `appConfigProvider`'s own default config
          // (`FeatureFlags.forEnvironment(AppEnvironment.development, ...)`)
          // now resolves `practiceGeneratorEnabled` to `nonProd` = true, and
          // this test never overrides it. Pinning presence at all three
          // viewport sizes (this test runs once per `sizes` entry) is the
          // §5.5 cell-addition this guard owes the new element.
          expect(tester.takeException(), isNull);
          expect(find.text('Build your practice plan'), findsOneWidget);
        });
      });

      testWidgets('Practice setup (E02-R12)', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                ...preferenceOverrides(),
                practiceCatalogRepositoryProvider.overrideWithValue(
                  const _GuardRepository(),
                ),
                practicePrepareSinkProvider.overrideWithValue(_noopSink),
              ],
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const PracticeSetupScreen(
                  argsOverride: PracticeSetupArgs(
                    request: PracticeSetupRequest.hasId,
                    definitionId: _GuardRepository.id,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        });
      });

      testWidgets('Practice session (E02-R13, null host → unavailable)', (
        tester,
      ) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: preferenceOverrides(),
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PracticeSessionScreen(),
              ),
            ),
          );
          await tester.pump();
        });
      });

      testWidgets('Practice result (E02-R18, fallback for empty entry)', (
        tester,
      ) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: preferenceOverrides(),
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PracticeResultFallback(),
              ),
            ),
          );
          await tester.pump();
        });
      });

      testWidgets('Practice result (E02-R18, strum pattern entry)', (
        tester,
      ) async {
        final fixture = PracticeHistoryEntry(
          id: 'guard.result.v1',
          modeCode: PracticeMode.strumPattern.code,
          sourceCode: PracticeSource.builtin.code,
          createdAt: DateTime(2026, 7, 11, 12, 0),
          definitionId: 'guard.result',
          displayTitle: 'Guard fixture',
          finishReasonCode: 'userFinished',
          activeDuration: const Duration(seconds: 30),
          pausedDuration: Duration.zero,
          attemptsCount: 1,
          finalMetricSnapshot: const PracticeMetricSnapshot(
            completion: PracticeMetricDimensionAvailable(0.9),
            rhythm: PracticeMetricDimensionAvailable(0.85),
            direction: PracticeMetricDimensionAvailable(0.95),
            chord: PracticeMetricDimensionNotApplicable(),
            overall: PracticeMetricDimensionAvailable(0.9),
          ),
          totalTargets: 16,
          resolvedTargets: 14,
          scorePoints: 800,
          maxCombo: 12,
          meanAbsoluteOffset: const Duration(milliseconds: 18),
          timingBias: const Duration(milliseconds: -2),
          coachingSummary: const ['practice.coach.late'],
          skillTags: const ['guard'],
          highestStableTempoBpm: 100.0,
        );
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: preferenceOverrides(),
              child: MaterialApp(
                theme: SsLightTheme.data(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PracticeResultScreen(entry: fixture),
              ),
            ),
          );
          await tester.pump();
        });
      });
    });
  }
}

/// One-definition catalog for the layout guard. The single definition
/// exercises every layout-sensitive surface (BPM slider, count-in stepper,
/// loop stepper, meter readout, scoring profile, chord hint).
class _GuardRepository implements PracticeCatalogRepository {
  const _GuardRepository();

  static const String id = 'guard.practice.v1';

  static final PracticeDefinition _def = PracticeDefinition(
    id: id,
    schemaVersion: 1,
    titleKey: 'practiceCatalogGuardTitle',
    descriptionKey: 'practiceCatalogGuardDescription',
    mode: PracticeMode.chordChanges,
    source: PracticeSource.builtin,
    meter: const Meter(beatsPerBar: 4),
    defaultTempo: const Tempo(100),
    totalBeats: BeatPosition.quarters(16),
    events: const <PracticeEvent>[],
    scoringProfile: ScoringProfile.chordChangeDefault,
    skillTags: const ['guard'],
    displayTitle: 'Guard fixture',
  );

  @override
  List<PracticeDefinition> all() =>
      List<PracticeDefinition>.unmodifiable(<PracticeDefinition>[_def]);
  @override
  PracticeDefinition? byId(String id) => id == _def.id ? _def : null;
  @override
  List<PracticeDefinition> byMode(PracticeMode mode) => mode == _def.mode
      ? List<PracticeDefinition>.unmodifiable(<PracticeDefinition>[_def])
      : const <PracticeDefinition>[];
  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      const <PracticeDefinition>[];
}

void _noopSink(PreparePractice _) {}
