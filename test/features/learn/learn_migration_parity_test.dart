import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/learn/adapter/lesson_practice_target.dart';
import 'package:strumsight/features/learn/adapter/lesson_v2_scoring.dart';
import 'package:strumsight/features/learn/lesson_scorer.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/learn/model/lesson_progress.dart';
import 'package:strumsight/features/learn/providers/lesson_progress_provider.dart';
import 'package:strumsight/features/practice/public.dart' hide PracticeSource;
import 'package:strumsight/features/progress/model/practice_entry.dart';

import '../../support/preference_store.dart';

typedef _SyntheticStrum = ({Duration at, StrumDirection direction});

enum _ParityShape { perfect, mixed, extraAndMissing }

const _strictlyInsideWindowOffset = Duration(milliseconds: 150);
const _strictlyOutsideWindowOffset = Duration(milliseconds: 400);
const _nonZeroInputLatency = Duration(milliseconds: 300);

StrumDirection _opposite(StrumDirection direction) =>
    direction == StrumDirection.down ? StrumDirection.up : StrumDirection.down;

List<_SyntheticStrum> _sharedSequence(Lesson lesson, _ParityShape shape) {
  final target = compileLessonPracticeTarget(lesson);
  final strums = <_SyntheticStrum>[];

  for (var index = 0; index < target.events.length; index++) {
    final event = target.events[index];
    if (shape == _ParityShape.mixed && index == target.events.length - 1) {
      // This is deliberately beyond the final target's window. Keeping it on
      // the final target prevents the late strum from resolving a neighbour.
      strums.add((
        at: event.time + _strictlyOutsideWindowOffset,
        direction: event.direction!,
      ));
      continue;
    }
    switch (shape) {
      case _ParityShape.perfect:
        strums.add((at: event.time, direction: event.direction!));
      case _ParityShape.mixed:
        switch (index % 3) {
          case 0:
            strums.add((at: event.time, direction: event.direction!));
          case 1:
            strums.add((
              at: event.time,
              direction: _opposite(event.direction!),
            ));
          case 2:
            // Other misses are deliberately left unresolved. The final target
            // is instead shifted outside its window above, so P2 measures a
            // timing miss as well as an omitted event.
            break;
        }
      case _ParityShape.extraAndMissing:
        if (index >= 2) {
          strums.add((at: event.time, direction: event.direction!));
        }
    }
  }

  if (shape != _ParityShape.perfect) {
    final afterSession = target.events.last.time + const Duration(seconds: 1);
    strums.add((at: afterSession, direction: StrumDirection.down));
    if (shape == _ParityShape.extraAndMissing) {
      strums.add((
        at: afterSession + const Duration(milliseconds: 1),
        direction: StrumDirection.up,
      ));
    }
  }
  return strums;
}

/// Feeds the exact same synthetic strum series used by the V2 adapter.
ScoreSnapshot _runLegacy(
  Lesson lesson,
  List<_SyntheticStrum> strums, {
  Duration inputLatency = Duration.zero,
}) {
  final scorer = LessonScorer(
    lesson,
    countInBeats: lesson.beatsPerBar,
    bpm: lesson.bpm,
    inputLatencySec:
        inputLatency.inMicroseconds / Duration.microsecondsPerSecond,
  );
  for (final strum in strums) {
    final elapsedSec = strum.at.inMicroseconds / Duration.microsecondsPerSecond;
    scorer.advance(elapsedSec);
    scorer.registerStrum(strum.direction, elapsedSec);
  }
  scorer.finalize();
  return scorer.snapshot();
}

double _runV2(
  Lesson lesson,
  List<_SyntheticStrum> strums, {
  Duration inputLatency = Duration.zero,
}) => scoreLessonV2(lesson, [
  for (var index = 0; index < strums.length; index++)
    StrumObservation(
      at: strums[index].at,
      sequence: index,
      direction: strums[index].direction,
      confidence: 1,
    ),
], inputLatency: inputLatency);

List<_SyntheticStrum> _withOffset(
  List<_SyntheticStrum> strums,
  Duration offset,
) => [
  for (final strum in strums)
    (at: strum.at + offset, direction: strum.direction),
];

List<_SyntheticStrum> _withOnlyFinalTargetShifted(
  Lesson lesson,
  Duration offset,
) {
  final target = compileLessonPracticeTarget(lesson);
  return [
    for (var index = 0; index < target.events.length; index++)
      (
        at:
            target.events[index].time +
            (index == target.events.length - 1 ? offset : Duration.zero),
        direction: target.events[index].direction!,
      ),
  ];
}

/// Pipes the V2 direction result through the real recording path.
Future<({PracticeEntry? logged, bool streakAdvanced})> _runV2Recording(
  ProviderContainer c, {
  required Lesson lesson,
  required ScoreSnapshot legacy,
  required double directionAccuracy,
  required DateTime now,
}) async {
  final recording = c.read(practiceSessionRecordingProvider);
  final outcome = await recording.record(
    PracticeRecordingRequest(
      lessonId: lesson.id,
      eligibility: SessionEligibilitySnapshot(
        activeDuration: const Duration(seconds: 60),
        resolvedRequiredTargets: 0,
        freePracticeStrums: legacy.total,
      ),
      eligible: true,
      activeDuration: const Duration(seconds: 60),
      elapsedSeconds: 90,
      strokes: legacy.total,
      chords: lesson.chordSequence.toSet().length,
      directionAccuracy: directionAccuracy,
      finishedAt: now,
    ),
  );
  if (outcome.loggedEntry != null &&
      directionAccuracy >= LessonProgress.passThreshold) {
    await c
        .read(lessonProgressProvider.notifier)
        .record(lesson.id, directionAccuracy);
  }
  return (logged: outcome.loggedEntry, streakAdvanced: outcome.streakAdvanced);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final corpus = <Lesson>[Lessons.firstWin, ...Lessons.all];

  test('corpus covers all 17 lessons (16 + firstWin)', () {
    expect(corpus.length, 17, reason: 'brief A7: full corpus, no skip');
    expect(corpus.any((lesson) => lesson.id == 'first-win'), isTrue);
    expect(corpus.map((lesson) => lesson.id).toSet().length, 17);
  });

  group('A7.1 — 51-cell Learn parity matrix (flag ON)', () {
    for (final lesson in corpus) {
      for (final shape in _ParityShape.values) {
        test('${lesson.id} / ${shape.name}', () async {
          final store = InMemoryKeyValueStore();
          final container = ProviderContainer(
            overrides: [preferenceStoreOverride(store)],
          );
          addTearDown(container.dispose);

          final strums = _sharedSequence(lesson, shape);
          final legacy = _runLegacy(lesson, strums);
          final v2Accuracy = _runV2(lesson, strums);
          final v2 = await _runV2Recording(
            container,
            lesson: lesson,
            legacy: legacy,
            directionAccuracy: v2Accuracy,
            now: DateTime(2026, 8, 1),
          );

          expect(
            v2Accuracy,
            legacy.accuracy,
            reason: '${lesson.id}/${shape.name}: exact V2 direction parity',
          );
          expect(
            LessonProgress.stars(v2Accuracy),
            LessonProgress.stars(legacy.accuracy),
            reason: '${lesson.id}/${shape.name}: stars identical',
          );
          expect(
            LessonProgress.isPassed(v2Accuracy),
            LessonProgress.isPassed(legacy.accuracy),
            reason: '${lesson.id}/${shape.name}: pass/fail identical',
          );
          expect(v2.logged?.source, PracticeSource.learn);
          expect(v2.logged?.seconds, 90);
          expect(v2.logged?.strokes, legacy.total);
          expect(v2.logged?.directionAccuracy, legacy.accuracy);
        });
      }
    }
  });

  test('A7.1 exercises wrong directions, misses, and unmatched extras', () {
    final strums = _sharedSequence(Lessons.downUpGroove, _ParityShape.mixed);
    final snapshot = _runLegacy(Lessons.downUpGroove, strums);

    expect(snapshot.hits, greaterThan(0));
    expect(snapshot.wrong, greaterThan(0));
    expect(snapshot.missed, greaterThan(0));
  });

  test('A7.1 measures strictly inside and outside timing offsets', () {
    final lesson = Lessons.downUpGroove;
    final target = compileLessonPracticeTarget(lesson);
    final insideWindow = <_SyntheticStrum>[
      (
        at: target.events.first.time + _strictlyInsideWindowOffset,
        direction: target.events.first.direction!,
      ),
      for (var index = 1; index < target.events.length; index++)
        (
          at: target.events[index].time,
          direction: target.events[index].direction!,
        ),
    ];
    final outsideWindow = _withOnlyFinalTargetShifted(
      lesson,
      _strictlyOutsideWindowOffset,
    );
    final mixed = _sharedSequence(lesson, _ParityShape.mixed);

    final insideLegacy = _runLegacy(lesson, insideWindow);
    final insideV2 = _runV2(lesson, insideWindow);
    final outsideLegacy = _runLegacy(lesson, outsideWindow);
    final outsideV2 = _runV2(lesson, outsideWindow);

    expect(insideLegacy.hits, insideLegacy.total);
    expect(insideV2, insideLegacy.accuracy);
    expect(outsideLegacy.hits, outsideLegacy.total - 1);
    expect(outsideLegacy.missed, 1);
    expect(outsideV2, outsideLegacy.accuracy);
    expect(
      mixed.any(
        (strum) =>
            strum.at == target.events.last.time + _strictlyOutsideWindowOffset,
      ),
      isTrue,
      reason: 'P2 includes a shifted, strictly outside-window miss',
    );
  });

  test('A7.1 applies the same non-zero input latency on both paths', () {
    final lesson = Lessons.downUpGroove;
    final detectedStrums = _withOffset(
      _sharedSequence(lesson, _ParityShape.perfect),
      _nonZeroInputLatency,
    );

    final legacy = _runLegacy(
      lesson,
      detectedStrums,
      inputLatency: _nonZeroInputLatency,
    );
    final v2 = _runV2(
      lesson,
      detectedStrums,
      inputLatency: _nonZeroInputLatency,
    );

    expect(legacy.hits, legacy.total);
    expect(v2, legacy.accuracy);
  });

  test('A7 — the V2 ON flag production default stays OFF (no rollout)', () {
    final flags = FeatureFlags.forEnvironment(
      AppEnvironment.production,
      accountEnabled: false,
    );
    expect(flags.migratedLearnEnabled, isFalse);
  });
}
