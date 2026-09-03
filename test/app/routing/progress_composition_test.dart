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
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

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
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            adaptiveShellEnabled: true,
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

  group(
    'A10 — three qualifying sessions clear the new-user state (§0.0.H)',
    () {
      testWidgets(
        'the dashboard shows measured skill rows, never stuck on get-started',
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
