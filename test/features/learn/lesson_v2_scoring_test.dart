import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/learn/adapter/lesson_practice_target.dart';
import 'package:strumsight/features/learn/adapter/lesson_v2_scoring.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/practice/public.dart';

List<StrumObservation> _observationsAtTargets(
  Lesson lesson, {
  required bool Function(int index) isCorrect,
}) {
  final target = compileLessonPracticeTarget(lesson);
  return [
    for (var index = 0; index < target.events.length; index++)
      StrumObservation(
        at: target.events[index].time,
        sequence: index,
        direction: isCorrect(index)
            ? target.events[index].direction!
            : _opposite(target.events[index].direction!),
        confidence: 1,
      ),
  ];
}

StrumDirection _opposite(StrumDirection direction) =>
    direction == StrumDirection.down ? StrumDirection.up : StrumDirection.down;

MetricValue _scorerDirection(
  Lesson lesson,
  List<StrumObservation> observations,
) {
  final target = compileLessonPracticeTarget(lesson);
  final matcher = PracticeEventMatcher(
    target: target,
    scoringProfile: ScoringProfile.legacyLearnParity,
    inputLatency: Duration.zero,
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
  return const PracticeDirectionScorer()
      .score(
        matches: matcher.results,
        observationsByTargetIndex: observationsByTargetIndex,
      )
      .direction;
}

void main() {
  group('Lesson V2 direction scoring', () {
    test('A7.0 mutáció: every reversed direction scores zero', () {
      final lesson = Lessons.downUpGroove;

      final accuracy = scoreLessonV2(
        lesson,
        _observationsAtTargets(lesson, isCorrect: (_) => false),
      );

      expect(accuracy, 0.0);
    });

    test('A7.0 részleges cellák: exact correct-target ratio', () {
      final lesson = Lessons.downUpGroove;
      final targetCount = compileLessonPracticeTarget(lesson).events.length;
      final firstAccuracy = scoreLessonV2(
        lesson,
        _observationsAtTargets(lesson, isCorrect: (index) => index < 6),
      );
      final secondAccuracy = scoreLessonV2(
        lesson,
        _observationsAtTargets(lesson, isCorrect: (index) => index < 12),
      );

      expect(firstAccuracy, 6 / targetCount);
      expect(secondAccuracy, 12 / targetCount);
    });

    test('A7.0 kvantálás: seven correct targets preserve the exact ratio', () {
      final lesson = Lessons.downUpGroove;
      final targetCount = compileLessonPracticeTarget(lesson).events.length;
      final observations = _observationsAtTargets(
        lesson,
        isCorrect: (index) => index < 7,
      );

      final accuracy = scoreLessonV2(lesson, observations);
      final direction = _scorerDirection(lesson, observations);

      expect(targetCount, 24);
      expect(accuracy, 7 / targetCount);
      expect(direction, const MetricAvailable(0.291));
      expect(
        (accuracy * 1000).floor() / 1000,
        (direction as MetricAvailable).value,
      );
    });

    test('A7.0 import tiltás: adapters never name legacy scorer', () {
      for (final path in const [
        'lib/features/learn/adapter/lesson_practice_target.dart',
        'lib/features/learn/adapter/lesson_v2_scoring.dart',
      ]) {
        expect(File(path).readAsStringSync(), isNot(contains('lesson_scorer')));
      }
    });
  });
}
