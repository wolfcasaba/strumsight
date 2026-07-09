import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/model/lesson_progress.dart';
import 'package:music_theory/features/learn/providers/lesson_progress_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LessonProgress.stars', () {
    test('maps accuracy to 0..3 stars at the thresholds', () {
      expect(LessonProgress.stars(0.95), 3);
      expect(LessonProgress.stars(0.9), 3);
      expect(LessonProgress.stars(0.85), 2);
      expect(LessonProgress.stars(0.7), 1);
      expect(LessonProgress.stars(0.69), 0);
      expect(LessonProgress.isPassed(0.7), isTrue);
      expect(LessonProgress.isPassed(0.6), isFalse);
    });
  });

  group('lesson catalogue', () {
    test('every lesson has a unique id and a non-empty tier', () {
      final ids = Lessons.all.map((l) => l.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final d in Difficulty.values) {
        expect(Lessons.byDifficulty(d), isNotEmpty);
      }
    });
  });

  group('LessonProgressController', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('keeps the best accuracy and never regresses', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(lessonProgressProvider.notifier);

      await n.record('a', 0.8);
      expect(n.bestAccuracy('a'), 0.8);
      expect(n.stars('a'), 2);

      await n.record('a', 0.6); // worse → ignored
      expect(n.bestAccuracy('a'), 0.8);

      await n.record('a', 0.95); // better → kept
      expect(n.stars('a'), 3);
    });

    test('progression unlocks the next lesson once the previous passes',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(lessonProgressProvider.notifier);
      final tier = Lessons.byDifficulty(Difficulty.beginner);

      expect(n.isUnlocked(tier[0]), isTrue); // first is always open
      expect(n.isUnlocked(tier[1]), isFalse); // locked until #1 passes

      await n.record(tier[0].id, 0.75); // pass #1
      expect(n.isUnlocked(tier[1]), isTrue);
      expect(n.isUnlocked(tier[2]), isFalse); // #3 still locked
    });

    test('progress persists across a fresh controller', () async {
      final c1 = ProviderContainer();
      await c1.read(lessonProgressProvider.notifier).record('x', 0.9);
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(lessonProgressProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c2.read(lessonProgressProvider.notifier).bestAccuracy('x'), 0.9);
    });
  });
}
