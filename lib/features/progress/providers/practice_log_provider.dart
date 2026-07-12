import 'dart:async';
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
  // Writes are GATED on the initial load: a record racing the load used to
  // overwrite the on-disk history with just its own entry before the load
  // ever read it (r149 data-loss bug — microtask ordering is not guaranteed
  // in either direction, so the write must wait, not hope).
  final Completer<void> _loaded = Completer<void>();

  @override
  List<PracticeEntry> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => PracticeEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        if (!_dirty) {
          state = list;
        } else {
          // Entries landed before prefs finished loading (cold start → an
          // immediate practice moment): MERGE — disk history in front of the
          // new in-memory entries — then write the union below.
          final merged = [...list, ...state];
          state = merged.length > _cap
              ? merged.sublist(merged.length - _cap)
              : merged;
        }
      }
      if (_dirty) await _write();
    } catch (_) {
      // Prefs unavailable → keep the in-memory default.
    } finally {
      _loaded.complete();
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
    await _loaded.future; // never write over an unread disk blob
    await _write();
  }

  Future<void> _write() async {
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
