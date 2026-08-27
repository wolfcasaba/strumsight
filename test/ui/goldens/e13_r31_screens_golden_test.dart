// Golden snapshots of the E13-R31 Progress Dashboard and Skill Detail
// screens at a compact portrait phone (412×915) and the same frame at
// textScaler 2.0, per the round brief §7/A9. Pattern follows the merged
// `test/ui/goldens/e13_r30_screens_golden_test.dart` precedent: `AppTheme`
// (the app's actual runtime theme) plus a local `ProgressThemeScope` (mirrors
// `vision_theme_scope.dart`'s measured fix) because `AppTheme` alone does not
// carry the design-system's `SsColorScheme`/`SsTypography` extensions these
// screens' cards need.
//
// Recorded on x86_64 (ADR 0426, §0.0.B/B6) via `tools/golden-x86.sh record` —
// NOT `flutter test --update-goldens` on this (aarch64) box.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _compactPortrait = Size(412, 915);

MasteryMilestone _milestone(String id) => MasteryMilestone(
  id: id,
  catalogVersion: 2,
  skill: MasterySkill.chordTransition,
  metric: MasteryMetric.accuracy,
  minimumThreshold: 0.8,
  difficulty: MasteryDifficulty.beginner,
  tempoRange: MasteryTempoRange(minBpm: 60, maxBpm: 100),
  minEvidenceSessions: 5,
  titleKey: '${id}Title',
  descriptionKey: '${id}Description',
);

ProgressOverviewProjection _dashboardProjection() {
  final measured = _milestone('chord_transition_beginner');
  final unmeasured = _milestone('rhythm_accuracy_beginner');
  return ProgressOverviewProjection(
    isOffline: true,
    milestones: [
      MilestoneOverviewEntry(
        milestone: measured,
        progress: MasteryProgress(
          milestoneId: measured.id,
          catalogVersion: 2,
          evidenceSessionCount: 4,
        ),
        title: 'Chord transitions — beginner',
      ),
      MilestoneOverviewEntry(
        milestone: unmeasured,
        progress: MasteryProgress.fresh(
          milestoneId: unmeasured.id,
          catalogVersion: 1,
        ),
        title: 'Rhythm accuracy — beginner',
      ),
    ],
    trend: ProgressTrend(
      points: [
        for (var i = 0; i < 6; i++)
          ProgressTrendPoint(
            observedAt: DateTime.utc(2026, 8, 1 + i),
            value: 0.5 + i * 0.03,
          ),
      ],
    ),
    metricSegments: [
      MetricVersionSegment(
        catalogVersion: 1,
        points: [
          ProgressTrendPoint(observedAt: DateTime.utc(2026, 6, 1), value: 0.3),
        ],
      ),
      MetricVersionSegment(
        catalogVersion: 2,
        points: [
          ProgressTrendPoint(observedAt: DateTime.utc(2026, 8, 6), value: 0.68),
        ],
      ),
    ],
  );
}

SkillDetailProjection _skillDetailProjection() {
  final milestone = _milestone('chord_transition_beginner');
  return SkillDetailProjection(
    milestone: milestone,
    progress: MasteryProgress(
      milestoneId: milestone.id,
      catalogVersion: 2,
      evidenceSessionCount: 4,
    ),
    title: 'Chord transitions — beginner',
    description:
        'Smoothly changing between open chords at a steady beginner tempo.',
    evidence: [
      SkillEvidenceReference(
        sessionId: 'session-101',
        origin: MasteryEvidenceOrigin.vision,
        observedAt: DateTime.utc(2026, 8, 20),
      ),
      SkillEvidenceReference(
        sessionId: 'session-102',
        origin: MasteryEvidenceOrigin.analysis,
        observedAt: DateTime.utc(2026, 8, 22),
      ),
    ],
    achievedMilestoneIds: const {},
    recommendation: const SkillRecommendation(
      milestoneId: 'strum_consistency_intermediate',
      title: 'Strum consistency — intermediate',
      message: 'Ready for a faster tempo drill.',
      prerequisiteMilestoneId: 'chord_transition_beginner',
      prerequisiteTitle: 'Chord transitions — beginner',
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('progress dashboard — $suffix', (tester) async {
      await _pump(
        tester,
        ProgressDashboardScreen(
          projection: _dashboardProjection(),
          onOpenSkillDetail: (_) {},
          onGetStarted: () {},
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r31_progress_dashboard_$suffix');
    });

    testWidgets('skill detail — $suffix', (tester) async {
      await _pump(
        tester,
        SkillDetailScreen(
          projection: _skillDetailProjection(),
          onOpenEvidence: (_, _) {},
          onStartRecommendedPractice: () {},
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r31_skill_detail_$suffix');
    });
  }
}
