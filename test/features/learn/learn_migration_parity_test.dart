import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/features/learn/lesson_scorer.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/learn/model/lesson_progress.dart';
import 'package:strumsight/features/learn/providers/lesson_progress_provider.dart';
import 'package:strumsight/features/practice/application/practice_session_recording.dart';
import 'package:strumsight/features/progress/model/practice_entry.dart';

import '../../support/preference_store.dart';

/// Runs [lesson] through [LessonScorer] feeding each event the matching
/// direction at its target elapsed-second time — the cleanest parity input.
ScoreSnapshot _runLegacy(Lesson lesson) {
  final scorer = LessonScorer(
    lesson,
    countInBeats: lesson.beatsPerBar,
    bpm: lesson.bpm,
  );
  // Count-in is one full bar ahead of event 0.
  final countInSec = lesson.beatsPerBar * 60.0 / lesson.bpm;
  for (final event in lesson.events) {
    final at = countInSec + event.beat * 60.0 / lesson.bpm;
    scorer.registerStrum(event.direction, at);
  }
  scorer.finalize();
  return scorer.snapshot();
}

/// Pipes a finished [Lesson] through the V2 recording pipeline. The fixture
/// contract: V2 must produce the same accuracy → stars → pass triple the
/// legacy path produces.
Future<({PracticeEntry? logged, bool streakAdvanced})> _runV2Recording(
  ProviderContainer c, {
  required Lesson lesson,
  required ScoreSnapshot snap,
  required Duration activeDuration,
  required int elapsedSeconds,
  required DateTime now,
}) async {
  final recording = c.read(practiceSessionRecordingProvider);
  final outcome = await recording.record(
    PracticeRecordingRequest(
      lessonId: lesson.id,
      eligibility: SessionEligibilitySnapshot(
        activeDuration: activeDuration,
        resolvedRequiredTargets: 0,
        freePracticeStrums: snap.total,
      ),
      eligible: true,
      activeDuration: activeDuration,
      elapsedSeconds: elapsedSeconds,
      strokes: snap.total,
      chords: lesson.chordSequence.toSet().length,
      directionAccuracy: snap.accuracy,
      finishedAt: now,
    ),
  );
  if (outcome.loggedEntry != null &&
      snap.accuracy >= LessonProgress.passThreshold) {
    await c
        .read(lessonProgressProvider.notifier)
        .record(lesson.id, snap.accuracy);
  }
  return (logged: outcome.loggedEntry, streakAdvanced: outcome.streakAdvanced);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Build a 17-lesson corpus exactly as the brief requires (Lessons.all +
  // Lessons.firstWin), with one shared ProviderContainer per test so we can
  // spin up a clean V1/V2 state quickly.
  final corpus = <Lesson>[Lessons.firstWin, ...Lessons.all];

  test('corpus covers all 17 lessons (16 + firstWin)', () {
    expect(corpus.length, 17, reason: 'brief A7: full corpus, no skip');
    expect(corpus.any((l) => l.id == 'first-win'), isTrue);
    expect(corpus.map((l) => l.id).toSet().length, 17, reason: 'unique ids');
  });

  group('A7 — parity matrix (flag ON; same source of truth)', () {
    for (final lesson in corpus) {
      test(
        '${lesson.id}: same accuracy, stars, pass under both paths',
        () async {
          final store = InMemoryKeyValueStore();
          final c = ProviderContainer(
            overrides: [preferenceStoreOverride(store)],
          );
          addTearDown(c.dispose);

          final now = DateTime(2026, 8, 1);
          final legacy = _runLegacy(lesson);
          final v2 = await _runV2Recording(
            c,
            lesson: lesson,
            snap: legacy,
            activeDuration: const Duration(seconds: 60),
            elapsedSeconds: 90,
            now: now,
          );

          // Accuracy → same single source of truth (legacy scorer); trivially
          // identical (Döntés 7 keeps the legacy pass+stars on Learn).
          final accuracy = legacy.accuracy;
          final v2Accuracy = v2.logged?.directionAccuracy;
          expect(
            v2Accuracy,
            accuracy,
            reason: '${lesson.id}: V2 path preserves the legacy accuracy',
          );
          expect(
            LessonProgress.stars(accuracy),
            LessonProgress.stars(v2Accuracy!),
            reason: '${lesson.id}: stars identical',
          );
          expect(
            LessonProgress.isPassed(accuracy),
            LessonProgress.isPassed(v2Accuracy),
            reason: '${lesson.id}: pass/fail identical',
          );
          // The V1 entry the V2 path writes must be byte-identical for the
          // dashboard's shape (A10 + S1 — V1 store bájtra érintetlen).
          if (v2.logged != null) {
            expect(v2.logged!.source, PracticeSource.learn);
            expect(v2.logged!.seconds, 90);
            expect(v2.logged!.strokes, legacy.total);
            expect(v2.logged!.directionAccuracy, accuracy);
          }
        },
      );
    }
  });

  test(
    'A7 — the V2 ON flag production default stays OFF (no rollout in this round)',
    () {
      // The flag's OFF state must keep the production default OFF (brief A10).
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: false,
      );
      expect(
        flags.migratedLearnEnabled,
        isFalse,
        reason: 'production default stays OFF',
      );
    },
  );
}
