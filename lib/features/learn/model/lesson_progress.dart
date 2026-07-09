/// Pure helpers for lesson progress: best accuracy → stars, and the pass mark.
/// Progress itself is a `Map<lessonId, bestAccuracy>` (see the provider).
class LessonProgress {
  LessonProgress._();

  /// Matches [LessonScorer.passThreshold]; kept here so the library can render
  /// pass/stars without importing the scorer.
  static const double passThreshold = 0.7;

  /// Stars for a best accuracy: 3 ≥ 90%, 2 ≥ 80%, 1 ≥ 70% (a pass), else 0.
  static int stars(double accuracy) {
    if (accuracy >= 0.9) return 3;
    if (accuracy >= 0.8) return 2;
    if (accuracy >= passThreshold) return 1;
    return 0;
  }

  static bool isPassed(double accuracy) => accuracy >= passThreshold;
}
