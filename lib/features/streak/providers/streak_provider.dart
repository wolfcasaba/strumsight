import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/streak_data.dart';
import '../streak_logic.dart';

/// Practice-streak state, persisted locally (RAG chunk 013 — retention). Call
/// [StreakController.recordPracticeToday] from any real practice moment (a Live
/// session that detects playing, or a completed Analyze). Local-only, like the
/// capo: a streak is per-device habit state, not a synced profile field.
class StreakController extends Notifier<StreakData> {
  static const _key = 'practice_streak_v1';

  SharedPreferences? _prefs;
  // Mutations WAIT for the initial load (r150, the r149 race class): a
  // cold-start practice moment used to apply onto the EMPTY default and
  // persist it — overwriting a multi-day streak on disk with a streak of 1.
  final Completer<void> _loaded = Completer<void>();

  @override
  StreakData build() {
    _load();
    return const StreakData();
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      if (raw != null) {
        state = StreakData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Prefs unavailable → keep the in-memory default.
    } finally {
      _loaded.complete();
    }
  }

  /// Record that the user practised now. Idempotent within a calendar day.
  /// Returns true if this call advanced the streak (i.e. first practice today).
  Future<bool> recordPracticeToday([DateTime? now]) async {
    await _loaded.future; // apply onto the LOADED streak, never the default
    final today = StreakLogic.epochDayOf(now ?? DateTime.now());
    final next = StreakLogic.applyPractice(state, today);
    if (next == state) return false; // already practised today / no change
    state = next;
    await _persist();
    return true;
  }

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_key, jsonEncode(state.toJson()));
    } catch (_) {
      // Best-effort; state stays correct in memory for this session.
    }
  }
}

final streakProvider =
    NotifierProvider<StreakController, StreakData>(StreakController.new);
