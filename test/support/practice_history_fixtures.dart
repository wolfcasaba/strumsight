// A minimal, valid `PracticeHistoryEntry` builder for tests that only care
// about the identity/recency/tempo fields (WP-H2, 2026-09-06).
//
// Everything not named by the caller is a neutral, VALID value — never a
// value a cell could accidentally assert on.
import 'package:strumsight/features/practice/public.dart';

PracticeMetricSnapshot neutralPracticeMetricSnapshot() =>
    const PracticeMetricSnapshot(
      completion: PracticeMetricDimensionNotApplicable(),
      rhythm: PracticeMetricDimensionNotApplicable(),
      direction: PracticeMetricDimensionNotApplicable(),
      chord: PracticeMetricDimensionNotApplicable(),
      overall: PracticeMetricDimensionNotApplicable(),
    );

PracticeHistoryEntry practiceHistoryFixture({
  required String id,
  required String definitionId,
  required DateTime createdAt,
  double? highestStableTempoBpm,
  List<String> skillTags = const <String>[],
}) => PracticeHistoryEntry(
  id: id,
  modeCode: 'practice.mode.strumPattern',
  sourceCode: 'builtin',
  createdAt: createdAt,
  definitionId: definitionId,
  displayTitle: '',
  finishReasonCode: PracticeFinishReason.completedAllTargets.code,
  activeDuration: const Duration(seconds: 30),
  pausedDuration: Duration.zero,
  attemptsCount: 1,
  finalMetricSnapshot: neutralPracticeMetricSnapshot(),
  totalTargets: 4,
  resolvedTargets: 4,
  scorePoints: 100,
  maxCombo: 4,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
  coachingSummary: const <String>[],
  skillTags: skillTags,
  highestStableTempoBpm: highestStableTempoBpm,
);
