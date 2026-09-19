// Per-entity free-text notes over the app's only non-secret persistence
// boundary ([KeyValueStore]).
//
// Re-audit 2026-09-08 M6: `library_item_detail_screen.dart` drew a Notes
// field whose controller was created empty in `initState` and thrown away in
// `dispose` — the learner typed a note about a session, left the screen, and
// the note was gone with no warning. The UI-side twin of this repo's own
// "silent no-op" trap.
//
// The store is feature-agnostic on purpose. A surface binds it to its own
// [StorageKeys] entry — `noteStoreProvider(StorageKeys.libraryItemNotes)` —
// so no feature has to open storage of its own to keep a note; that is what
// keeps the E13-R28 §5.4 rule ("the surface is an entry point, the actual
// operation is a use case") machine-checkable for the library tree.
//
// A note is USER-AUTHORED content, so nothing here repairs a document by
// guessing: an unreadable document surfaces as `Failure(storage.read)` (the
// caller logs it and starts the field empty) rather than as an innocent
// empty note.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../foundation/app_failure.dart';
import '../foundation/app_result.dart';
import 'key_value_store.dart';
import 'storage_providers.dart';

/// The learner's free-text notes about one kind of entity, keyed by id and
/// stored as one versioned document under [storageKey].
final class KeyValueNoteStore {
  const KeyValueNoteStore({
    required this.keyValueStore,
    required this.storageKey,
  });

  /// Envelope version of the stored document.
  static const int schemaVersion = 1;

  /// Documented storage bound (SDD Ch2 §7.5). A note is short prose about
  /// one session; anything longer than this is truncated on write rather
  /// than silently refused, so the learner keeps what they can see.
  static const int maxNoteLength = 2000;

  final KeyValueStore keyValueStore;

  /// The [StorageKeys] entry this store's document lives under. One key per
  /// note-keeping surface, so two surfaces can never overwrite each other.
  final String storageKey;

  /// The stored note for [entityId] — `''` when the learner never wrote one.
  ///
  /// Synchronous on purpose: [KeyValueStore] reads are already loaded before
  /// the first frame, so a screen can restore the note in `initState`
  /// without an async gap that could clobber typing.
  AppResult<String> readNote(String entityId) {
    final Map<String, String> stored;
    try {
      stored = _readAll();
    } on FormatException catch (e, stackTrace) {
      return Failure<String>(
        StorageFailure(
          code: FailureCode.storageRead,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
    return Success<String>(stored[entityId] ?? '');
  }

  /// Stores [note] for [entityId]; an empty note removes the entry.
  Future<AppResult<void>> updateNote({
    required String entityId,
    required String note,
  }) async {
    final next = <String, String>{};
    try {
      next.addAll(_readAll());
    } on FormatException {
      // A document this build cannot read must not block a NEW note. The
      // unreadable bytes are replaced below — the note the learner is
      // typing right now is the one thing here that is certainly still
      // wanted.
    }
    final trimmed = note.length > maxNoteLength
        ? note.substring(0, maxNoteLength)
        : note;
    if (trimmed.isEmpty) {
      next.remove(entityId);
    } else {
      next[entityId] = trimmed;
    }
    final payload = <String, Object?>{
      'schemaVersion': schemaVersion,
      'notes': next,
    };
    try {
      await keyValueStore.writeString(storageKey, jsonEncode(payload));
      return const Success<void>(null);
    } on StorageException catch (e, stackTrace) {
      return Failure<void>(
        StorageFailure(
          code: FailureCode.storageWrite,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Every stored note keyed by entity id.
  ///
  /// Throws [FormatException] — and nothing else — when the document cannot
  /// be read, so every caller has exactly one failure shape to handle.
  Map<String, String> _readAll() {
    final raw = keyValueStore.readString(storageKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Notes document is not a JSON object.');
    }
    if (decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException('Notes document has an unknown version.');
    }
    final body = decoded['notes'];
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Notes document has no notes map.');
    }
    final result = <String, String>{};
    for (final entry in body.entries) {
      final value = entry.value;
      if (value is! String) {
        throw const FormatException('Notes entry is not a string.');
      }
      result[entry.key] = value;
    }
    return result;
  }
}

/// The note store for one [StorageKeys] document. A surface binds this
/// family to its own key instead of opening a store of its own.
final noteStoreProvider = Provider.family<KeyValueNoteStore, String>(
  (ref, storageKey) => KeyValueNoteStore(
    keyValueStore: ref.watch(keyValueStoreProvider),
    storageKey: storageKey,
  ),
);
