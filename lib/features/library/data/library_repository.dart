import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/analyzed_session.dart';

/// Persists analyzed sessions locally (offline). Backed by shared_preferences —
/// a JSON array under one key. An interface so tests use an in-memory fake.
abstract interface class LibraryRepository {
  Future<List<AnalyzedSession>> load();
  Future<void> save(List<AnalyzedSession> sessions);
}

class PrefsLibraryRepository implements LibraryRepository {
  static const _key = 'library_sessions';

  @override
  Future<List<AnalyzedSession>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => AnalyzedSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupt/unavailable store → start empty rather than crash.
      return [];
    }
  }

  @override
  Future<void> save(List<AnalyzedSession> sessions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(sessions.map((s) => s.toJson()).toList());
      await prefs.setString(_key, raw);
    } catch (_) {
      // Best-effort; a failed write must not crash the UI.
    }
  }
}

final libraryRepositoryProvider =
    Provider<LibraryRepository>((ref) => PrefsLibraryRepository());
