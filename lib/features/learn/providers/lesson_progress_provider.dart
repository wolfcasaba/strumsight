import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lesson_progress_repository.dart';
import '../model/lesson.dart';
import '../model/lesson_progress.dart';

/// Per-lesson best accuracy (0..1), keyed by lesson id. Persisted locally so the
/// library can show stars and unlock the next lesson (RAG chunk 014). Local
/// habit/progress state, like the streak — not synced.
///
/// Read synchronously from the injected repository in [build] (E01-R07), which
/// retires the r150 load gate: a run recorded at cold start always merges onto
/// the stored map instead of racing it.
class LessonProgressController extends Notifier<Map<String, double>> {
  LessonProgressRepository get _repo =>
      ref.read(lessonProgressRepositoryProvider);

  @override
  Map<String, double> build() => _repo.load();

  /// Record a run's [accuracy] for [lessonId], keeping the best so far.
  Future<void> record(String lessonId, double accuracy) async {
    final prev = state[lessonId] ?? 0;
    if (accuracy <= prev) return; // never regress the best score
    state = {...state, lessonId: accuracy};
    await _repo.save(state);
  }

  double bestAccuracy(String lessonId) => state[lessonId] ?? 0;
  int stars(String lessonId) => LessonProgress.stars(bestAccuracy(lessonId));
  bool isPassed(String lessonId) =>
      LessonProgress.isPassed(bestAccuracy(lessonId));

  /// Curriculum gate: a lesson is unlocked if it's the first of its tier, or the
  /// previous lesson in the same tier has been passed.
  bool isUnlocked(Lesson lesson) {
    final tier = Lessons.byDifficulty(lesson.difficulty);
    final i = tier.indexWhere((l) => l.id == lesson.id);
    if (i <= 0) return true;
    return isPassed(tier[i - 1].id);
  }

  /// Where the player should pick up: the first unlocked, not-yet-passed
  /// lesson in curriculum order, or null when everything is passed
  /// (round 93 — the Learn home's "Continue" card).
  Lesson? recommendedNext() {
    for (final l in Lessons.all) {
      if (!isPassed(l.id) && isUnlocked(l)) return l;
    }
    return null;
  }
}

final lessonProgressProvider =
    NotifierProvider<LessonProgressController, Map<String, double>>(
      LessonProgressController.new,
    );
