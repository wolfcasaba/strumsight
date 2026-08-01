import '../../practice/public.dart';
import '../model/lesson.dart';
import 'lesson_practice_target.dart';

/// Scores Learn strum directions through the V2 matcher and direction scorer.
double scoreLessonV2(
  Lesson lesson,
  List<StrumObservation> observations, {
  Duration inputLatency = Duration.zero,
  double? bpm,
}) {
  final target = compileLessonPracticeTarget(
    lesson,
    bpm: bpm,
    inputLatency: inputLatency,
  );
  final matcher = PracticeEventMatcher(
    target: target,
    scoringProfile: ScoringProfile.legacyLearnParity,
    inputLatency: inputLatency,
  );
  final observationsByTargetIndex = <int, StrumObservation>{};

  for (final observation in observations) {
    matcher.advance(observation.at);
    final match = matcher.registerStrum(observation);
    if (match != null) {
      observationsByTargetIndex[match.targetIndex] = observation;
    }
  }
  matcher.finalize();

  final directionScore = const PracticeDirectionScorer().score(
    matches: matcher.results,
    observationsByTargetIndex: observationsByTargetIndex,
  );
  final applicable = directionScore.events
      .where((event) => event.outcome != DirectionOutcome.notApplicable)
      .length;
  if (applicable == 0) return 0.0;
  final correct = directionScore.events
      .where((event) => event.outcome == DirectionOutcome.correct)
      .length;
  return correct / applicable;
}
