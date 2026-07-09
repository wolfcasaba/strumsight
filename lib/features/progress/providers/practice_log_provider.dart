import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/practice_entry.dart';

/// The raw practice-history log, persisted locally (like the streak — per-device
/// habit state, not synced). Append a [PracticeEntry] from any real practice
/// moment (Live/Analyze/Learn) via [record]; the Progress dashboard reads the
/// list and rolls it up through `PracticeStats`.
///
/// The list is kept newest-last and capped at [_cap] entries so a heavy user's
/// blob stays bounded; the dashboard only ever needs recent history + totals,
/// and the oldest entries are the least interesting.
class PracticeLogController extends Notifier<List<PracticeEntry>> {
  static const _key = 'practice_log_v1';
  static const _cap = 400;

  SharedPreferences? _prefs;
  bool _dirty = false; // an entry landed before prefs finished loading

  @override
  List<PracticeEntry> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      // Don't clobber an entry recorded before prefs finished loading.
      if (raw != null && !_dirty) {
        final list = (jsonDecode(raw) as List)
            .map((e) => PracticeEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        state = list;
      }
    } catch (_) {
      // Prefs unavailable → keep the in-memory default.
    }
  }

  /// Append one practice moment and persist. Best-effort: an entry is never lost
  /// from this session's in-memory state even if the disk write fails.
  Future<void> record(PracticeEntry entry) async {
    _dirty = true;
    final next = [...state, entry];
    // Bound the blob — drop the oldest once over the cap.
    state = next.length > _cap
        ? next.sublist(next.length - _cap)
        : next;
    await _persist();
  }

  Future<void> _persist() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(
        _key,
        jsonEncode(state.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Best-effort; state stays correct in memory for this session.
    }
  }
}

final practiceLogProvider =
    NotifierProvider<PracticeLogController, List<PracticeEntry>>(
        PracticeLogController.new);
