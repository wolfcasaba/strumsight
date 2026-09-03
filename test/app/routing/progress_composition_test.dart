// E16-R02 §6 A1/A2/A10 (ADR 0500) — the router builds a REAL Progress V2
// projection for `/profile/progress` (not a placeholder), the skill-detail
// route resolves `:skillId` and redirects an unknown one, and three
// measured builtin sessions clear the new-user state.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/domain/repository/practice_history_repository.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

/// Review MAJOR-2 — the narrower `progressPracticeHistoryProvider.
/// overrideWithValue(...)` used by every other cell in this file feeds the
/// dashboard directly, bypassing `progressPracticeHistoryProvider`'s own body
/// (`ref.watch(practiceHistoryV2ListProvider).value ?? []`,
/// `progress_providers.dart:23-28`) entirely. The A10 cell overrides one
/// layer deeper — the repository `practiceHistoryV2ListProvider` itself
/// reads from — so the real chain (repository → `practiceHistoryV2ListProvider`
/// → `progressPracticeHistoryProvider` → builder → screen) runs end to end.
class _FakeHistoryRepository implements PracticeHistoryRepository {
  const _FakeHistoryRepository(this.entries);
  final List<PracticeHistoryEntry> entries;

  @override
  Future<AppResult<List<PracticeHistoryEntry>>> load() async =>
      Success(entries);

  @override
  Future<AppResult<void>> save(PracticeHistoryEntry entry) async =>
      const AppResult.success(null);

  @override
  Future<AppResult<void>> clear() async => const AppResult.success(null);
}

PracticeMetricSnapshot _chordSnapshot(double value) => PracticeMetricSnapshot(
  completion: const PracticeMetricDimensionNotApplicable(),
  rhythm: const PracticeMetricDimensionNotApplicable(),
  direction: const PracticeMetricDimensionNotApplicable(),
  chord: PracticeMetricDimension.available(value),
  overall: PracticeMetricDimension.available(value),
);

PracticeHistoryEntry _chordSession(String id, DateTime createdAt) =>
    PracticeHistoryEntry(
      id: id,
      modeCode: 'practice.mode.strumPattern',
      sourceCode: 'builtin',
      createdAt: createdAt,
      definitionId: 'builtin.quarterDownstrokes.v1',
      displayTitle: '',
      finishReasonCode: PracticeFinishReason.completedAllTargets.code,
      activeDuration: const Duration(seconds: 30),
      pausedDuration: Duration.zero,
      attemptsCount: 1,
      finalMetricSnapshot: _chordSnapshot(0.9),
      totalTargets: 4,
      resolvedTargets: 4,
      scorePoints: 100,
      maxCombo: 4,
      meanAbsoluteOffset: Duration.zero,
      timingBias: Duration.zero,
      coachingSummary: const <String>[],
      skillTags: const <String>[],
    );

/// Three qualifying sessions clear `mastery_chord_transition_v1`'s
/// `minEvidenceSessions: 3` at a measured value above its `0.8` threshold —
/// the fixture the A10 mérce-mátrix cell names (§0.0.H).
List<PracticeHistoryEntry> _threeQualifyingChordSessions() => [
  _chordSession('chord-1', DateTime.utc(2026, 8, 1)),
  _chordSession('chord-2', DateTime.utc(2026, 8, 2)),
  _chordSession('chord-3', DateTime.utc(2026, 8, 3)),
];

Future<GoRouter> _pumpRouterTo(
  WidgetTester tester,
  String path, {
  List<Override> extraOverrides = const [],
  bool adaptiveShellEnabled = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...extraOverrides,
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            adaptiveShellEnabled: adaptiveShellEnabled,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  router.go(path);
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('A1 — /profile/progress renders a REAL projection', () {
    testWidgets(
      'the dashboard reflects seeded practice history, not a placeholder',
      (tester) async {
        await _pumpRouterTo(
          tester,
          AppRoutes.profileProgress,
          extraOverrides: [
            progressPracticeHistoryProvider.overrideWithValue(
              _threeQualifyingChordSessions(),
            ),
          ],
        );

        expect(find.byType(ProgressDashboardScreen), findsOneWidget);
        final screen = tester.widget<ProgressDashboardScreen>(
          find.byType(ProgressDashboardScreen),
        );
        final chordEntry = screen.projection.milestones.firstWhere(
          (entry) => entry.milestone.id == 'mastery_chord_transition_v1',
        );
        expect(chordEntry.hasEvidence, isTrue);
        expect(chordEntry.progress.evidenceSessionCount, 3);
        expect(chordEntry.progress.isAchieved, isTrue);
        // The localized title is real ARB text, not the raw key.
        expect(chordEntry.title, isNot('masteryChordTransitionTitle'));
        expect(chordEntry.title, isNotEmpty);
      },
    );

    testWidgets('an empty history renders the new-user state honestly', (
      tester,
    ) async {
      await _pumpRouterTo(
        tester,
        AppRoutes.profileProgress,
        extraOverrides: [
          progressPracticeHistoryProvider.overrideWithValue(
            const <PracticeHistoryEntry>[],
          ),
        ],
      );

      expect(
        find.byKey(const Key('progress-dashboard-new-user')),
        findsOneWidget,
      );
    });
  });

  group(
    'A2 — the skill-detail route resolves :skillId and redirects unknown ones',
    () {
      testWidgets('a valid skillId opens SkillDetailScreen with a real title', (
        tester,
      ) async {
        final router = await _pumpRouterTo(
          tester,
          AppRoutes.profileProgressSkill.replaceFirst(
            ':skillId',
            'chordTransition',
          ),
          extraOverrides: [
            progressPracticeHistoryProvider.overrideWithValue(
              _threeQualifyingChordSessions(),
            ),
          ],
        );

        expect(find.byType(SkillDetailScreen), findsOneWidget);
        expect(
          router.state.uri.path,
          '/profile/progress/skills/chordTransition',
        );
        final screen = tester.widget<SkillDetailScreen>(
          find.byType(SkillDetailScreen),
        );
        expect(screen.projection.title, isNot('masteryChordTransitionTitle'));
        expect(screen.projection.evidence, hasLength(3));
      });

      testWidgets(
        'an unknown skillId redirects to the overview, not a 404 or a throw',
        (tester) async {
          final router = await _pumpRouterTo(
            tester,
            AppRoutes.profileProgressSkill.replaceFirst(
              ':skillId',
              'notARealSkill',
            ),
          );

          expect(tester.takeException(), isNull);
          expect(router.state.uri.path, AppRoutes.profileProgress);
          expect(find.byType(ProgressDashboardScreen), findsOneWidget);
          expect(find.byType(SkillDetailScreen), findsNothing);
        },
      );

      testWidgets(
        'tempoStability (no v1 milestone) also redirects to the overview',
        (tester) async {
          final router = await _pumpRouterTo(
            tester,
            AppRoutes.profileProgressSkill.replaceFirst(
              ':skillId',
              'tempoStability',
            ),
          );

          expect(router.state.uri.path, AppRoutes.profileProgress);
          expect(find.byType(ProgressDashboardScreen), findsOneWidget);
        },
      );

      testWidgets(
        'tapping a milestone row from the dashboard opens its skill detail',
        (tester) async {
          final router = await _pumpRouterTo(
            tester,
            AppRoutes.profileProgress,
            extraOverrides: [
              progressPracticeHistoryProvider.overrideWithValue(
                _threeQualifyingChordSessions(),
              ),
            ],
          );

          await tester.tap(
            find.byKey(
              const ValueKey('progress-skill-row-mastery_chord_transition_v1'),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            router.state.uri.path,
            '/profile/progress/skills/chordTransition',
          );
          expect(find.byType(SkillDetailScreen), findsOneWidget);
        },
      );
    },
  );

  group('shell-OFF — the skill-detail route never renders on top of a disabled '
      'surface and never falls through to the generic /live catch-all (review '
      'MAJOR-1, §5.8)', () {
    testWidgets(
      'a valid skillId does not open SkillDetailScreen and lands on the '
      'always-registered legacy /progress, not /live',
      (tester) async {
        final router = await _pumpRouterTo(
          tester,
          AppRoutes.profileProgressSkill.replaceFirst(
            ':skillId',
            'chordTransition',
          ),
          adaptiveShellEnabled: false,
          extraOverrides: [
            progressPracticeHistoryProvider.overrideWithValue(
              _threeQualifyingChordSessions(),
            ),
          ],
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(SkillDetailScreen), findsNothing);
        expect(router.state.uri.path, AppRoutes.progress);
        expect(router.state.uri.path, isNot(AppRoutes.live));
      },
    );

    testWidgets(
      'an unknown skillId also lands on the legacy /progress, not /live',
      (tester) async {
        final router = await _pumpRouterTo(
          tester,
          AppRoutes.profileProgressSkill.replaceFirst(
            ':skillId',
            'notARealSkill',
          ),
          adaptiveShellEnabled: false,
        );

        expect(tester.takeException(), isNull);
        expect(router.state.uri.path, AppRoutes.progress);
        expect(router.state.uri.path, isNot(AppRoutes.live));
      },
    );
  });

  group(
    'A10 — three qualifying sessions clear the new-user state (§0.0.H)',
    () {
      testWidgets(
        'the dashboard shows measured skill rows, never stuck on get-started, '
        'through the REAL repository chain (review MAJOR-2)',
        (tester) async {
          await _pumpRouterTo(
            tester,
            AppRoutes.profileProgress,
            extraOverrides: [
              practiceHistoryRepositoryProvider.overrideWithValue(
                _FakeHistoryRepository(_threeQualifyingChordSessions()),
              ),
            ],
          );

          expect(
            find.byKey(const Key('progress-dashboard-new-user')),
            findsNothing,
          );
          expect(
            find.byKey(
              const ValueKey('progress-skill-row-mastery_chord_transition_v1'),
            ),
            findsOneWidget,
          );
        },
      );
    },
  );
}
