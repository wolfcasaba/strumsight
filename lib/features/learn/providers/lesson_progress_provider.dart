import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/lesson.dart';
import '../model/lesson_progress.dart';

/// Per-lesson best accuracy (0..1), keyed by lesson id. Persisted locally so the
/// library can show stars and unlock the next lesson (RAG chunk 014). Local
/// habit/progress state, like the streak — not synced.
class LessonProgressController extends Notifier<Map<String, double>> {
  static const _key = 'lesson_progress_v1';

  SharedPreferences? _prefs;
  // Mutations WAIT for the initial load (r150, the r149 race class): a
  // mutation racing the load used to persist the near-empty default over the
  // unread on-disk collection, wiping it.
  final Completer<void> _loaded = Completer<void>();

  @override
  Map<String, double> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      if (raw != null) {
        final map = (jsonDecode(raw) as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        );
        state = map;
      }
    } catch (_) {
      // Prefs unavailable → keep the empty default.
    } finally {
      // Riverpod keeps the notifier instance across ref.invalidate — build()
      // and _load() re-run on the SAME object, so the Completer may already
      // be done (r158 probe: 'Bad state: Future already completed').
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  /// Record a run's [accuracy] for [lessonId], keeping the best so far.
  Future<void> record(String lessonId, double accuracy) async {
    await _loaded.future; // merge onto the LOADED map, never the default
    final prev = state[lessonId] ?? 0;
    if (accuracy <= prev) return; // never regress the best score
    state = {...state, lessonId: accuracy};
    await _persist();
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

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_key, jsonEncode(state));
    } catch (_) {
      // Best-effort.
    }
  }
}

final lessonProgressProvider =
    NotifierProvider<LessonProgressController, Map<String, double>>(
        LessonProgressController.new);
