// Persisted per-item notes for the unified library.
//
// Re-audit 2026-09-08 M6: `library_item_detail_screen.dart` drew a Notes
// field whose controller was created empty in `initState` and thrown away in
// `dispose` — the learner typed a note about a session, left the screen, and
// the note was gone with no warning. The UI-side twin of this repo's own
// "silent no-op" trap.
//
// The store sits on the app's only non-secret persistence boundary
// ([KeyValueStore]), the way `KeyValueSongResumeRepository` does for the
// trainer's resume checkpoints: a feature-owned key, a versioned envelope,
// and no direct plugin dependency.
//
// A note is USER-AUTHORED content, so nothing here repairs a document by
// guessing: an unreadable document surfaces as `Failure(storage.read)` (the
// caller logs it and starts the field empty) rather than as an innocent
// empty note.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';

/// The learner's free-text notes on library items, keyed by item id.
final class KeyValueLibraryNoteRepository {
  const KeyValueLibraryNoteRepository({required this.keyValueStore});

  /// Envelope version of the stored document.
  static const int schemaVersion = 1;

  /// Documented storage bound (SDD Ch2 §7.5). A note is short prose about
  /// one session; anything longer than this is truncated on write rather
  /// than silently refused, so the learner keeps what they can see.
  static const int maxNoteLength = 2000;

  final KeyValueStore keyValueStore;

  /// The stored note for [itemId] — `''` when the learner never wrote one.
  ///
  /// Synchronous on purpose: [KeyValueStore] reads are already loaded before
  /// the first frame, so the detail screen can restore the note in
  /// `initState` without an async gap that could clobber typing.
  AppResult<String> read(String itemId) {
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
    return Success<String>(stored[itemId] ?? '');
  }

  /// Stores [note] for [itemId]; an empty note removes the entry.
  Future<AppResult<void>> write({
    required String itemId,
    required String note,
  }) async {
    final next = <String, String>{};
    try {
      next.addAll(_readAll());
    } on FormatException {
      // A document this build cannot read must not block a NEW note. The
      // unreadable bytes are replaced by the write below — the note the
      // learner is typing right now is the one thing here that is certainly
      // still wanted.
    }
    final trimmed = note.length > maxNoteLength
        ? note.substring(0, maxNoteLength)
        : note;
    if (trimmed.isEmpty) {
      next.remove(itemId);
    } else {
      next[itemId] = trimmed;
    }
    final payload = <String, Object?>{
      'schemaVersion': schemaVersion,
      'notes': next,
    };
    try {
      await keyValueStore.writeString(
        StorageKeys.libraryItemNotes,
        jsonEncode(payload),
      );
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

  /// Every stored note keyed by item id.
  ///
  /// Throws [FormatException] — and nothing else — when the document cannot
  /// be read, so every caller has exactly one failure shape to handle.
  Map<String, String> _readAll() {
    final raw = keyValueStore.readString(StorageKeys.libraryItemNotes);
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

/// The note store the library detail screen reads and writes.
final libraryNoteRepositoryProvider = Provider<KeyValueLibraryNoteRepository>(
  (ref) => KeyValueLibraryNoteRepository(
    keyValueStore: ref.watch(keyValueStoreProvider),
  ),
);
