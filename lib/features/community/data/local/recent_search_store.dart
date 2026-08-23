/// Local-only recent-search history for Community profile search
/// (E09-R09, brief §3).
///
/// **Privacy boundary (A5 / §3):** the store lives in the
/// SharedPreferences-backed ``KeyValueStore`` — local to the
/// device, never uploaded, never synced. A future cross-device
/// feature would be a NEW store with a NEW key, not an
/// extension of this one.
///
/// **Scope:** at most [maxEntries] queries, most-recent-first.
/// The list deduplicates on push — adding the same query twice
/// moves it to the front instead of creating a second row.
///
/// **API shape:** the store is async on write, sync on read.
/// Reads are synchronous because the ``KeyValueStore`` is loaded
/// at boot, so the search screen can build its initial recent
/// list without an async gap (the same rationale as
/// ``key_value_store.dart``).
///
/// **No DTO / no Flutter binding import** — the store deals in
/// ``List<String>`` and ``String`` only. The presentation layer
/// maps the list to widgets, the data layer maps it to the wire
/// (the brief §5.1 invariant: the search key is a handle prefix
/// only).
library;

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/storage/key_value_store.dart';

/// Stable preference key for the recent-search list. Versioned
/// in the name so a future shape change lives next to the old
/// one instead of overwriting it (the migration precedent
/// ``song_migration_version_store.dart`` follows).
const String _recentSearchesPreferenceKey = 'community.search.recent.v1';

/// Maximum number of recent searches kept on the device.
/// Larger than 10 would crowd the screen; smaller than 5 would
/// feel arbitrary. The exact value is a UX choice — the brief
/// only requires "user-clearable" + "local-only" (A5).
const int _maxEntries = 8;

/// Async-only local store for the recent-search history. The
/// write methods return ``Future<void>`` because the underlying
/// ``KeyValueStore`` is async; reads are synchronous.
class RecentSearchStore {
  /// Internal constructor — use [RecentSearchStore.open] to get
  /// the production singleton bound to the platform's
  /// ``KeyValueStore``.
  RecentSearchStore._(this._prefs);

  /// The injected key-value store. Production wires
  /// ``SharedPreferencesStore.open()``; tests can substitute an
  /// in-memory implementation.
  final KeyValueStore _prefs;

  /// Open a [RecentSearchStore] against an existing
  /// [KeyValueStore]. The factory takes the dependency as an
  /// argument so production and tests share the same code path.
  factory RecentSearchStore.open(KeyValueStore prefs) =>
      RecentSearchStore._(prefs);

  /// Return the recent-search list, most-recent-first.
  ///
  /// A malformed list (e.g. a single entry that exceeds the
  /// length cap because a future version bumped it) is
  /// silently re-trimmed — the user-visible invariant is
  /// "at most [_maxEntries]", and a corrupt list cannot
  /// crash the search screen.
  List<String> read() {
    final raw = _prefs.readStringList(_recentSearchesPreferenceKey);
    if (raw == null) return const <String>[];
    final trimmed = <String>[];
    for (final value in raw) {
      if (value.isEmpty) continue;
      if (value.length > 64) continue;
      if (trimmed.length >= _maxEntries) break;
      trimmed.add(value);
    }
    return List<String>.unmodifiable(trimmed);
  }

  /// Push [query] to the front of the list. If [query] is
  /// already present, it is moved (not duplicated). Empty /
  /// whitespace-only queries are ignored — they would only
  /// pollute the list and the backend's minimum-length gate
  /// would reject them anyway.
  ///
  /// Throws [StorageException] when the platform refuses the
  /// write (the [KeyValueStore] contract); the caller
  /// (:class:`CommunitySearchScreen`) catches it and surfaces a
  /// non-fatal snackbar so the user can retry.
  Future<void> push(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final existing = List<String>.from(read());
    existing.removeWhere((value) => value == trimmed);
    existing.insert(0, trimmed);
    final next = existing.length > _maxEntries
        ? existing.sublist(0, _maxEntries)
        : existing;
    await _prefs.writeStringList(_recentSearchesPreferenceKey, next);
  }

  /// Remove a single entry. Idempotent — a no-op if the value
  /// is not in the list. Throws [StorageException] on write
  /// failure (same contract as [push]).
  Future<void> remove(String query) async {
    final existing = List<String>.from(read());
    final next = existing.where((value) => value != query).toList();
    if (next.length == existing.length) return;
    await _prefs.writeStringList(_recentSearchesPreferenceKey, next);
  }

  /// Clear the entire list. Throws [StorageException] on
  /// write failure.
  Future<void> clear() async {
    await _prefs.writeStringList(
      _recentSearchesPreferenceKey,
      const <String>[],
    );
  }
}

/// Storage-error → AppFailure mapping. Lives next to the store
/// so the screen has a single import for both the I/O surface
/// and the failure translation.
StorageFailure mapRecentSearchStorageException(StorageException exception) {
  return StorageFailure(code: exception.code, cause: exception.cause);
}
